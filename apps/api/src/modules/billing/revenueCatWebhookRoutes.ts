import type { Request, Response, Router } from 'express';

import type { ServerConfig } from '../../config/env.js';
import {
  createOwnerMutationLock,
  type OwnerMutationCoordinator
} from '../account/ownerMutationLock.js';
import type { PaidSubscriptionPlan, SubscriptionStatus } from '../subscriptions/subscriptionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { isSameSecret } from '../security/secretCompare.js';
import type { UserStore } from '../users/userStore.js';
import { UploadSessionConflictError } from '../uploads/uploadSessionStore.js';
import { MonthlyAddonPurchaseConflictError, allowMonthlyAddonStore, type MonthlyAddonStore } from './monthlyAddonStore.js';
import { addonGrantSnapshot, readAddonProductDefinition } from './addonProductCatalog.js';
import { normalizeRevenueCatAddonStore } from './revenueCatAddonPurchaseClient.js';
import { isRevenueCatSubscriptionEntitlementAllowed, isRevenueCatSubscriptionStoreAllowed,
  selectRevenueCatPaidEntitlement } from './revenueCatSubscriptionPolicy.js';
import type { RevenueCatSubscriberClient } from './revenueCatSubscriberClient.js';
import { handleRevenueCatTransfer } from './revenueCatTransfer.js';

type RevenueCatWebhookConfig = Pick<
  ServerConfig,
  | 'billingProvider'
  | 'revenueCatWebhookAuthToken'
  | 'revenueCatSubscriptionEnvironment'
  | 'revenueCatStarterEntitlementId'
  | 'revenueCatProEntitlementId'
  | 'revenueCatBusinessEntitlementId'
  | 'revenueCatStarterProductId'
  | 'revenueCatProProductId'
  | 'revenueCatBusinessProductId'
  | 'billingAddonsEnabled'
  | 'revenueCatAddonProductId'
  | 'revenueCatAddonEnvironment'
>;

type RevenueCatEvent = {
  type: string;
  appUserId: string;
  eventId?: string;
  productId?: string;
  entitlementIds: string[];
  eventTimestampMs?: number;
  expirationAtMs?: number | null;
  environment?: string;
  store?: string;
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

const readExpiration = (value: unknown) => {
  if (value === null) {
    return null;
  }

  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? new Date(value).toISOString()
    : undefined;
};

const readEventTimestamp = (value: unknown) =>
  typeof value === 'number' && Number.isSafeInteger(value) && value > 0
    ? value
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
  const eventTimestampMs = readEventTimestamp(event.event_timestamp_ms);

  if (!type || !appUserId) {
    return undefined;
  }

  return {
    type,
    appUserId,
    eventId: readString(event.id),
    productId: readString(event.product_id),
    entitlementIds: readStringList(event.entitlement_ids),
    environment: readString(event.environment),
    store: readString(event.store)?.toUpperCase(),
    eventTimestampMs,
    expirationAtMs:
      event.expiration_at_ms === null
        ? null
        : typeof event.expiration_at_ms === 'number' &&
            Number.isFinite(event.expiration_at_ms)
          ? event.expiration_at_ms
          : undefined
  };
};

const planForRevenueCatEvent = (
  event: RevenueCatEvent,
  config: RevenueCatWebhookConfig
): PaidSubscriptionPlan | undefined => {
  // A renewal/expiration belongs to its product. A shared entitlement list can
  // include another still-active plan and must not relabel an old receipt.
  if (event.productId === (config.revenueCatBusinessProductId ?? 'postdee_business_monthly')) return 'BUSINESS';
  if (event.productId === config.revenueCatProProductId) return 'PRO';
  if (event.productId === config.revenueCatStarterProductId) return 'STARTER';
  if (event.entitlementIds.includes(config.revenueCatBusinessEntitlementId ?? 'business')) return 'BUSINESS';
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
    message:
      'RevenueCat webhook payload must include event.type, event.app_user_id, and ordering metadata for actionable events'
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
  subscriptionStore,
  ownerMutationLock = createOwnerMutationLock(),
  monthlyAddonStore,
  subscriberClient
}: {
  router: Router;
  config: RevenueCatWebhookConfig;
  userStore: UserStore;
  subscriptionStore: SubscriptionStore;
  ownerMutationLock?: OwnerMutationCoordinator;
  monthlyAddonStore?: MonthlyAddonStore;
  subscriberClient?: RevenueCatSubscriberClient;
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

    if (!isSameSecret(readAuthorizationToken(request), config.revenueCatWebhookAuthToken)) {
      sendUnauthorized(response);
      return;
    }

    if (isRecord(request.body) && isRecord(request.body.event) && request.body.event.type === 'TRANSFER') {
      await handleRevenueCatTransfer({ event: request.body.event, response, config, subscriberClient,
        userStore, subscriptionStore, ownerMutationLock });
      return;
    }

    const event = readRevenueCatEvent(request.body);

    if (!event) {
      sendInvalidPayload(response);
      return;
    }

    const addonProduct = event.productId ? readAddonProductDefinition(event.productId, config.revenueCatAddonProductId) : undefined;
    const raw = isRecord(request.body) && isRecord(request.body.event) ? request.body.event : {};
    const isPurchase = event.type === 'NON_RENEWING_PURCHASE';
    // RevenueCat non-subscription cancellations represent refund/revocation,
    // not subscription auto-renewal cancellation. Keep them sticky.
    const isRevoke = event.type === 'CANCELLATION' || event.type === 'REFUND';
    const historicalStore = normalizeRevenueCatAddonStore(raw.store);
    const historicalTransactionId = readString(raw.transaction_id);
    // Retired configured aliases may disappear from the current registry.
    // An authenticated exact ledger match can still be revoked, never newly
    // fulfilled. Exact receipt identity takes priority over incidental
    // entitlement tags; unmatched subscription events retain their routing.
    const historicalAddon = !addonProduct && monthlyAddonStore &&
      event.productId && isRevoke && event.eventId && event.eventTimestampMs !== undefined &&
      historicalStore && historicalTransactionId && readEventTimestamp(raw.purchased_at_ms) &&
      raw.environment === config.revenueCatAddonEnvironment
      ? await monthlyAddonStore.findPurchaseConfirmation({ userId: event.appUserId, productId: event.productId,
        transactionId: historicalTransactionId, store: historicalStore, environment: config.revenueCatAddonEnvironment })
      : null;
    if (addonProduct || historicalAddon) {
      if (!monthlyAddonStore || (!isPurchase && !isRevoke)) {
        response.status(202).json({ status: 'ok', ignored: true, code: 'REVENUECAT_EVENT_NOT_ACTIONABLE' }); return;
      }
      const store = normalizeRevenueCatAddonStore(raw.store);
      const transactionId = readString(raw.transaction_id);
      const purchasedAtMs = readEventTimestamp(raw.purchased_at_ms);
      if (!event.eventId || event.eventTimestampMs === undefined || !store || !transactionId || !purchasedAtMs ||
        !['SANDBOX', 'PRODUCTION'].includes(String(raw.environment))) {
        sendInvalidPayload(response); return;
      }
      if (raw.environment !== config.revenueCatAddonEnvironment) {
        response.status(202).json({ status: 'ok', ignored: true, code: 'REVENUECAT_ADDON_ENVIRONMENT_MISMATCH' }); return;
      }
      if (isPurchase && !allowMonthlyAddonStore(store, String(raw.environment))) {
        response.status(202).json({ status: 'ok', ignored: true, code: 'ADDON_STORE_UNSUPPORTED' }); return;
      }
      const release = await ownerMutationLock.acquireMutation(event.appUserId);
      try {
        if (!ownerMutationLock.isActive(event.appUserId) || !(await userStore.exists(event.appUserId))) {
          response.status(202).json({ status: 'ok', ignored: true, code: 'REVENUECAT_USER_NOT_FOUND' }); return;
        }
        const purchase = { userId: event.appUserId, productId: addonProduct?.productId ?? event.productId!,
          transactionId, store, environment: raw.environment as string, purchasedAt: new Date(purchasedAtMs).toISOString(),
          ...(addonProduct ? addonGrantSnapshot(addonProduct) : {
            postUnitsGranted: historicalAddon!.postUnits, aiCaptionsGranted: historicalAddon!.aiCaptions }) };
        if (isRevoke) {
          await monthlyAddonStore.revokePurchase(purchase);
          response.json({ status: 'ok', eventType: event.type, revoked: true }); return;
        }
        const result = await monthlyAddonStore.applyPurchase(purchase);
        response.json({ status: 'ok', eventType: event.type, ignored: !result.applied, revoked: result.revoked });
      } catch (error) {
        if (error instanceof MonthlyAddonPurchaseConflictError) {
          response.status(409).json({ status: 'error', code: 'PURCHASE_ALREADY_LINKED', message: error.message }); return;
        }
        if (!(error instanceof UploadSessionConflictError) || error.code !== 'ACCOUNT_DELETION_IN_PROGRESS') throw error;
        response.status(202).json({ status: 'ok', ignored: true, code: 'REVENUECAT_USER_NOT_FOUND' });
      } finally { release(); }
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

    const inactiveStatus = inactiveStatusByEventType[event.type];
    const isBusinessRevocation = plan === 'BUSINESS' && ['CANCELLATION', 'REFUND'].includes(event.type);
    const isActionable = activeEventTypes.has(event.type) || Boolean(inactiveStatus) || isBusinessRevocation;

    if (isActionable && (!event.eventId || event.eventTimestampMs === undefined)) {
      sendInvalidPayload(response);
      return;
    }

    if (!isActionable) {
      response.status(202).json({
        status: 'ok',
        ignored: true,
        code: 'REVENUECAT_EVENT_NOT_ACTIONABLE',
        message: 'RevenueCat event does not change PostDee entitlements'
      });
      return;
    }

    if (event.environment !== config.revenueCatSubscriptionEnvironment) {
      response.status(202).json({
        status: 'ok', ignored: true, code: 'REVENUECAT_SUBSCRIPTION_ENVIRONMENT_MISMATCH'
      });
      return;
    }
    if (!isRevenueCatSubscriptionStoreAllowed(event.store, config.revenueCatSubscriptionEnvironment)) {
      response.status(202).json({
        status: 'ok', ignored: true, code: 'REVENUECAT_SUBSCRIPTION_STORE_UNSUPPORTED'
      });
      return;
    }

    const authUser = {
      id: event.appUserId,
      provider: 'firebase' as const
    };
    const billingSubscriptionId = revenueCatBillingSubscriptionId(event.appUserId);
    const releaseOwner = await (ownerMutationLock.acquireMutation?.(event.appUserId) ??
      ownerMutationLock.acquire(event.appUserId));

    try {
      if (!ownerMutationLock.isActive(event.appUserId)) {
        response.status(202).json({
          status: 'ok',
          ignored: true,
          code: 'REVENUECAT_USER_NOT_FOUND',
          message: 'RevenueCat event belongs to a PostDee user that no longer exists'
        });
        return;
      }

      const currentPlan = await (subscriptionStore.getPurchasedPlan?.(authUser) ?? subscriptionStore.getPlan(authUser));
      const requiresBusinessReconciliation =
        (currentPlan === 'BUSINESS' && plan !== 'BUSINESS') ||
        (plan === 'BUSINESS' && (Boolean(inactiveStatus) || isBusinessRevocation));
      if (requiresBusinessReconciliation && event.eventId && event.eventTimestampMs !== undefined) {
        if (!(await userStore.exists(event.appUserId))) {
          response.status(202).json({ status: 'ok', ignored: true, code: 'REVENUECAT_USER_NOT_FOUND' });
          return;
        }
        // All RevenueCat plans share one owner subscription row. Before an old
        // lower-tier event or Business expiry changes it, resolve the strongest
        // remaining provider entitlement. A failed/stale lookup is retryable.
        try {
          if (!subscriberClient) throw new Error('Subscriber lookup is not configured');
          const snapshot = await subscriberClient.loadSubscriber(event.appUserId);
          if (!Number.isSafeInteger(snapshot.observedAtMs) || snapshot.observedAtMs < event.eventTimestampMs) {
            throw new Error('Subscriber lookup predates this event');
          }
          const paid = selectRevenueCatPaidEntitlement(snapshot.activeEntitlements, config);
          if (!paid && snapshot.activeEntitlements.some(entitlement =>
            isRevenueCatSubscriptionEntitlementAllowed(entitlement, config))) {
            throw new Error('Remaining entitlement is not mapped');
          }
          const common = { authUser, billingSubscriptionId, eventId: `revenuecat-reconcile:${event.eventId}`,
            eventTimestampMs: snapshot.observedAtMs };
          const result = await subscriptionStore.applyRevenueCatEvent(paid ? {
            ...common, plan: paid.plan, status: 'ACTIVE', currentPeriodEnd: paid.entitlement.expiresAt ?? null
          } : { ...common, status: 'CANCELED' });
          response.json({ status: 'ok', ignored: !result.applied || result.subscription === null,
            eventType: event.type, subscription: result.subscription });
        } catch (error) {
          if (error instanceof UploadSessionConflictError) throw error;
          response.status(502).json({ status: 'error', code: 'REVENUECAT_SUBSCRIPTION_RECONCILIATION_FAILED',
            message: 'RevenueCat subscription reconciliation failed. Retry this webhook.' });
        }
        return;
      }

      if (
        activeEventTypes.has(event.type) &&
        event.eventId &&
        event.eventTimestampMs !== undefined
      ) {
        if (!(await userStore.exists(event.appUserId))) {
          response.status(202).json({
            status: 'ok',
            ignored: true,
            code: 'REVENUECAT_USER_NOT_FOUND',
            message: 'RevenueCat event belongs to a PostDee user that no longer exists'
          });
          return;
        }

        const currentPeriodEnd = readExpiration(event.expirationAtMs);
        const eventResult = await subscriptionStore.applyRevenueCatEvent({
          authUser,
          billingSubscriptionId,
          plan,
          status: 'ACTIVE',
          eventId: event.eventId,
          eventTimestampMs: event.eventTimestampMs,
          ...(currentPeriodEnd !== undefined ? { currentPeriodEnd } : {})
        });

        response.json({
          status: 'ok',
          ignored: !eventResult.applied,
          eventType: event.type,
          subscription: eventResult.subscription
        });
        return;
      }

      if (inactiveStatus && event.eventId && event.eventTimestampMs !== undefined) {
        const eventResult = await subscriptionStore.applyRevenueCatEvent({
          authUser,
          billingSubscriptionId,
          plan,
          status: inactiveStatus,
          eventId: event.eventId,
          eventTimestampMs: event.eventTimestampMs
        });

        response.json({
          status: 'ok',
          ignored: !eventResult.applied || eventResult.subscription === null,
          eventType: event.type,
          subscription: eventResult.subscription
        });
        return;
      }
    } catch (error) {
      if (!(error instanceof UploadSessionConflictError) || error.code !== 'ACCOUNT_DELETION_IN_PROGRESS') throw error;
      response.status(202).json({
        status: 'ok', ignored: true, code: 'REVENUECAT_USER_NOT_FOUND',
        message: 'RevenueCat event belongs to a PostDee user that no longer exists'
      });
    } finally {
      releaseOwner();
    }
  });
};
