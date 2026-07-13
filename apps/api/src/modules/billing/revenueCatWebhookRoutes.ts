import type { Request, Response, Router } from 'express';

import type { ServerConfig } from '../../config/env.js';
import type { PaidSubscriptionPlan, SubscriptionStatus } from '../subscriptions/subscriptionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';

type RevenueCatWebhookConfig = Pick<
  ServerConfig,
  | 'billingProvider'
  | 'revenueCatWebhookAuthToken'
  | 'revenueCatStarterEntitlementId'
  | 'revenueCatProEntitlementId'
  | 'revenueCatStarterProductId'
  | 'revenueCatProProductId'
>;

type RevenueCatEvent = {
  type: string;
  appUserId: string;
  productId?: string;
  entitlementIds: string[];
  expirationAtMs?: number;
};

const activeEventTypes = new Set([
  'INITIAL_PURCHASE',
  'NON_RENEWING_PURCHASE',
  'PRODUCT_CHANGE',
  'RENEWAL',
  'UNCANCELLATION'
]);

// RevenueCat cancellation, pause, and billing issue events can arrive before paid access expires.
const inactiveStatusByEventType: Record<string, SubscriptionStatus | undefined> = {
  EXPIRATION: 'CANCELED'
};

const revenueCatBillingSubscriptionId = (appUserId: string) => `revenuecat:${appUserId}`;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const readString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readStringList = (value: unknown) =>
  Array.isArray(value) ? value.map(readString).filter((item): item is string => Boolean(item)) : [];

const readExpiration = (value: unknown) =>
  typeof value === 'number' && Number.isFinite(value) && value > 0
    ? new Date(value).toISOString()
    : undefined;

const readAuthorizationToken = (request: Request) => {
  const authorization = readString(request.headers.authorization);

  if (!authorization?.startsWith('Bearer ')) {
    return undefined;
  }

  return authorization.slice('Bearer '.length).trim();
};

const readRevenueCatEvent = (body: unknown): RevenueCatEvent | undefined => {
  if (!isRecord(body) || !isRecord(body.event)) {
    return undefined;
  }

  const event = body.event;
  const type = readString(event.type);
  const appUserId = readString(event.app_user_id);

  if (!type || !appUserId) {
    return undefined;
  }

  return {
    type,
    appUserId,
    productId: readString(event.product_id),
    entitlementIds: readStringList(event.entitlement_ids),
    expirationAtMs:
      typeof event.expiration_at_ms === 'number' && Number.isFinite(event.expiration_at_ms)
        ? event.expiration_at_ms
        : undefined
  };
};

const planForRevenueCatEvent = (
  event: RevenueCatEvent,
  config: RevenueCatWebhookConfig
): PaidSubscriptionPlan | undefined => {
  if (
    event.entitlementIds.includes(config.revenueCatProEntitlementId) ||
    event.productId === config.revenueCatProProductId
  ) {
    return 'PRO';
  }

  if (
    event.entitlementIds.includes(config.revenueCatStarterEntitlementId) ||
    event.productId === config.revenueCatStarterProductId
  ) {
    return 'STARTER';
  }

  return undefined;
};

const sendInvalidPayload = (response: Response) =>
  response.status(400).json({
    status: 'error',
    code: 'REVENUECAT_WEBHOOK_INVALID',
    message: 'RevenueCat webhook payload must include event.type and event.app_user_id'
  });

const sendUnauthorized = (response: Response) =>
  response.status(401).json({
    status: 'error',
    code: 'REVENUECAT_WEBHOOK_UNAUTHORIZED',
    message: 'RevenueCat webhook authorization is invalid'
  });

export const registerRevenueCatWebhookRoutes = ({
  router,
  config,
  userStore,
  subscriptionStore
}: {
  router: Router;
  config: RevenueCatWebhookConfig;
  userStore: UserStore;
  subscriptionStore: SubscriptionStore;
}) => {
  if (config.billingProvider !== 'revenuecat') {
    return;
  }

  router.post('/billing/revenuecat/webhooks', async (request, response) => {
    if (!config.revenueCatWebhookAuthToken) {
      response.status(501).json({
        status: 'error',
        code: 'REVENUECAT_WEBHOOK_NOT_CONFIGURED',
        message: 'RevenueCat webhook authorization token is not configured'
      });
      return;
    }

    if (readAuthorizationToken(request) !== config.revenueCatWebhookAuthToken) {
      sendUnauthorized(response);
      return;
    }

    const event = readRevenueCatEvent(request.body);

    if (!event) {
      sendInvalidPayload(response);
      return;
    }

    const plan = planForRevenueCatEvent(event, config);

    if (!plan) {
      response.status(202).json({
        status: 'ok',
        ignored: true,
        code: 'REVENUECAT_PRODUCT_NOT_MAPPED',
        message: 'RevenueCat product or entitlement is not mapped to a PostDee plan'
      });
      return;
    }

    const authUser = {
      id: event.appUserId,
      provider: 'firebase' as const
    };
    const billingSubscriptionId = revenueCatBillingSubscriptionId(event.appUserId);

    if (activeEventTypes.has(event.type)) {
      if (!(await userStore.exists(event.appUserId))) {
        response.status(202).json({
          status: 'ok',
          ignored: true,
          code: 'REVENUECAT_USER_NOT_FOUND',
          message: 'RevenueCat event belongs to a PostDee user that no longer exists'
        });
        return;
      }

      const subscription = await subscriptionStore.activatePlan(authUser, plan, {
        billingSubscriptionId,
        currentPeriodEnd: readExpiration(event.expirationAtMs)
      });

      response.json({
        status: 'ok',
        ignored: false,
        eventType: event.type,
        subscription
      });
      return;
    }

    const inactiveStatus = inactiveStatusByEventType[event.type];

    if (inactiveStatus) {
      const subscription = await subscriptionStore.updateStatusByBillingSubscriptionId({
        billingSubscriptionId,
        status: inactiveStatus
      });

      response.json({
        status: 'ok',
        ignored: subscription === null,
        eventType: event.type,
        subscription
      });
      return;
    }

    response.status(202).json({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_EVENT_NOT_ACTIONABLE',
      message: 'RevenueCat event does not change PostDee entitlements'
    });
  });
};
