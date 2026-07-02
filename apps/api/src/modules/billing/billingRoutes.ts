import type { RequestHandler, Response, Router } from 'express';

import type { ServerConfig } from '../../config/env.js';
import { readAuthUser } from '../auth/authTypes.js';
import type { PostStore } from '../posts/postStore.js';
import { countCurrentMonthPostUnits } from '../posts/postUsage.js';
import {
  canSchedulePosts,
  monthlyPostUnitLimits
} from '../subscriptions/subscriptionEntitlements.js';
import type {
  PaidSubscriptionPlan,
  SubscriptionPlan,
  SubscriptionStore
} from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import { readPaidPlanRequest } from './billingService.js';
import {
  StorePurchaseVerificationError,
  buildBillingSubscriptionId,
  createMockStorePurchaseVerifier,
  type StorePurchaseRequest,
  type StorePurchaseVerifier
} from './storePurchaseService.js';
import {
  type AppleSignedNotificationDecoder,
  registerStoreNotificationRoutes
} from './storeNotificationRoutes.js';
import { createStoreNotificationSubscriptionHandler } from './storeNotificationSubscriptionHandler.js';

const buildSubscriptionStatus = ({
  userId,
  plan,
  phoneVerified,
  usedPostsThisMonth
}: {
  userId: string;
  plan: SubscriptionPlan;
  phoneVerified: boolean;
  usedPostsThisMonth: number;
}) => {
  const monthlyPostLimit = monthlyPostUnitLimits[plan];
  const requiresPhoneVerification = plan === 'BASIC' && !phoneVerified;
  const canUseFreePostQuota = plan === 'BASIC' && phoneVerified;
  const remainingPostsThisMonth =
    requiresPhoneVerification
        ? 0
        : Math.max(monthlyPostLimit - usedPostsThisMonth, 0);

  return {
    userId,
    plan,
    status: plan === 'BASIC' ? 'INACTIVE' : 'ACTIVE',
    monthlyPostLimit,
    usedPostsThisMonth,
    remainingPostsThisMonth,
    phoneVerified,
    requiresPhoneVerification,
    canUseFreePostQuota,
    canSchedule: canSchedulePosts(plan),
    canUseAiCaptions: plan !== 'BASIC',
    canUseAnalytics: plan === 'PRO',
    canUseAiAudioReview: false,
    canUseAiVideoReview: false
  };
};

type BillingRoutesConfig = Pick<
  ServerConfig,
  | 'nodeEnv'
  | 'billingProvider'
  | 'storeStarterMonthlyProductId'
  | 'storeProMonthlyProductId'
  | 'googlePlayNotificationAuthToken'
>;

const defaultBillingRoutesConfig: BillingRoutesConfig = {
  nodeEnv: 'development',
  billingProvider: 'mock',
  storeStarterMonthlyProductId: 'postdee_starter_monthly',
  storeProMonthlyProductId: 'postdee_pro_monthly',
  googlePlayNotificationAuthToken: undefined
};

type StorePurchaseRequestResult =
  | {
      ok: true;
      purchase: StorePurchaseRequest;
    }
  | {
      ok: false;
      message: string;
    };

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readStorePurchaseRequest = (body: unknown): StorePurchaseRequestResult => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const platform = payload.platform;
  const productId = readRequiredString(payload.productId);

  if (platform !== 'IOS' && platform !== 'ANDROID') {
    return {
      ok: false,
      message: 'platform must be IOS or ANDROID'
    };
  }

  if (!productId) {
    return {
      ok: false,
      message: 'productId is required'
    };
  }

  if (platform === 'ANDROID') {
    const purchaseToken = readRequiredString(payload.purchaseToken);

    if (!purchaseToken) {
      return {
        ok: false,
        message: 'purchaseToken is required for Android purchases'
      };
    }

    return {
      ok: true,
      purchase: {
        platform,
        productId,
        purchaseToken
      }
    };
  }

  const transactionId = readRequiredString(payload.transactionId);

  if (!transactionId) {
    return {
      ok: false,
      message: 'transactionId is required for iOS purchases'
    };
  }

  return {
    ok: true,
    purchase: {
      platform,
      productId,
      transactionId
    }
  };
};

const readPlanForProductId = (
  config: BillingRoutesConfig,
  productId: string
): PaidSubscriptionPlan | undefined => {
  if (productId === config.storeStarterMonthlyProductId) {
    return 'STARTER' as const;
  }

  if (productId === config.storeProMonthlyProductId) {
    return 'PRO' as const;
  }

  return undefined;
};

const readStorePurchaseVerifier = ({
  config,
  verifier
}: {
  config: BillingRoutesConfig;
  verifier?: StorePurchaseVerifier;
}) => {
  if (verifier) {
    return verifier;
  }

  if (config.billingProvider === 'mock' && config.nodeEnv !== 'production') {
    return createMockStorePurchaseVerifier();
  }

  return undefined;
};

// Prisma unique-constraint violation: another account already activated this
// exact purchase (billingSubscriptionId is @unique), i.e. a reused receipt.
const isUniqueConstraintViolation = (error: unknown) =>
  typeof error === 'object' &&
  error !== null &&
  'code' in error &&
  (error as { code?: unknown }).code === 'P2002';

const handleStorePurchaseError = (response: Response, error: unknown) => {
  if (error instanceof StorePurchaseVerificationError) {
    response.status(error.statusCode).json({
      status: 'error',
      code: error.code,
      message: error.message
    });
    return;
  }

  if (isUniqueConstraintViolation(error)) {
    response.status(409).json({
      status: 'error',
      code: 'PURCHASE_ALREADY_LINKED',
      message: 'This purchase is already linked to another account.'
    });
    return;
  }

  response.status(502).json({
    status: 'error',
    code: 'STORE_VERIFICATION_FAILED',
    message: 'Store purchase verification failed'
  });
};


export const registerBillingRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  userStore: UserStore,
  subscriptionStore: SubscriptionStore,
  postStore: PostStore,
  options: {
    config?: BillingRoutesConfig;
    storePurchaseVerifier?: StorePurchaseVerifier;
    appleSignedNotificationDecoder?: AppleSignedNotificationDecoder;
  } = {}
) => {
  const config = options.config ?? defaultBillingRoutesConfig;

  router.get('/billing/subscription', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    await userStore.ensure(authUser);
    const plan = await subscriptionStore.getPlan(authUser);
    const posts = await postStore.list({ userId: authUser.id });
    const usedPostsThisMonth = countCurrentMonthPostUnits(posts);

    response.json({
      status: 'ok',
      subscription: buildSubscriptionStatus({
        userId: authUser.id,
        plan,
        phoneVerified: authUser.phoneVerified === true,
        usedPostsThisMonth
      })
    });
  });

  router.post('/billing/mock-success', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const paidPlanRequest = readPaidPlanRequest(request.body);

    if (config.nodeEnv === 'production' || config.billingProvider !== 'mock') {
      response.status(403).json({
        status: 'error',
        code: 'MOCK_BILLING_DISABLED',
        message: 'Mock billing activation is only available in local mock development'
      });
      return;
    }

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!paidPlanRequest.ok) {
      response.status(400).json({
        status: 'error',
        message: paidPlanRequest.message
      });
      return;
    }

    await userStore.ensure(authUser);
    const subscription = await subscriptionStore.activatePlan(authUser, paidPlanRequest.plan);

    response.json({
      status: 'ok',
      subscription
    });
  });

  router.post('/billing/store/verify', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const storePurchaseRequest = readStorePurchaseRequest(request.body);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!storePurchaseRequest.ok) {
      response.status(400).json({
        status: 'error',
        message: storePurchaseRequest.message
      });
      return;
    }

    const plan = readPlanForProductId(config, storePurchaseRequest.purchase.productId);

    if (!plan) {
      response.status(400).json({
        status: 'error',
        message: 'productId must match the configured Starter or Pro store product'
      });
      return;
    }

    const verifier = readStorePurchaseVerifier({
      config,
      verifier: options.storePurchaseVerifier
    });

    if (!verifier) {
      response.status(501).json({
        status: 'error',
        code: 'STORE_VERIFIER_NOT_CONFIGURED',
        message: 'Real Apple App Store / Google Play verification is not configured yet'
      });
      return;
    }

    try {
      const purchase = await verifier.verify(storePurchaseRequest.purchase);
      const billingSubscriptionId = buildBillingSubscriptionId(purchase);

      await userStore.ensure(authUser);
      const activateOptions = billingSubscriptionId ? { billingSubscriptionId } : undefined;
      const subscription = await subscriptionStore.activatePlan(
        authUser,
        plan,
        activateOptions
      );

      response.json({
        status: 'ok',
        purchase,
        subscription
      });
    } catch (error) {
      handleStorePurchaseError(response, error);
    }
  });

  registerStoreNotificationRoutes(
    router,
    createStoreNotificationSubscriptionHandler({ subscriptionStore }),
    {
      appleSignedNotificationDecoder: options.appleSignedNotificationDecoder,
      googlePlayNotificationAuthToken: config.googlePlayNotificationAuthToken
    }
  );
};
