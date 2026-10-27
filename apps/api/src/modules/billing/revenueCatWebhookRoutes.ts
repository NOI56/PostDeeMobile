import type { Request, Response, Router } from 'express';

import type { ServerConfig } from '../../config/env.js';
import type { PaidSubscriptionPlan, SubscriptionStatus } from '../subscriptions/subscriptionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { isSameSecret } from '../security/secretCompare.js';
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
  eventId?: string;
  productId?: string;
  entitlementIds: string[];
  eventTimestampMs?: number;
  expirationAtMs?: number | null;
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

type RevenueCatTransferEvent = {
  eventId: string;
  eventTimestampMs: number;
  transferredFrom: string[];
  transferredTo: string[];
};

// TRANSFER events carry no app_user_id or product; they list the App User IDs
// a store purchase moved from and to (e.g. a restore on another account).
const readRevenueCatTransferEvent = (body: unknown): RevenueCatTransferEvent | undefined => {
  if (!isRecord(body) || !isRecord(body.event)) {
    return undefined;
  }

  const event = body.event;
  const eventId = readString(event.id);
  const eventTimestampMs = readEventTimestamp(event.event_timestamp_ms);
  const transferredFrom = readStringList(event.transferred_from);

  if (!eventId || eventTimestampMs === undefined || transferredFrom.length === 0) {
    return undefined;
  }

  return {
    eventId,
    eventTimestampMs,
    transferredFrom,
    transferredTo: readStringList(event.transferred_to)
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

    if (!isSameSecret(readAuthorizationToken(request), config.revenueCatWebhookAuthToken)) {
      sendUnauthorized(response);
      return;
    }

    if (isRecord(request.body) && isRecord(request.body.event) &&
        request.body.event.type === 'TRANSFER') {
      const transfer = readRevenueCatTransferEvent(request.body);

      if (!transfer) {
        sendInvalidPayload(response);
        return;
      }

      // The source accounts no longer own the purchase. Without this they keep
      // paid access while the receiving account also gets it via restore/resync.
      const revokedUserIds: string[] = [];
      const receivingUserIds = new Set(transfer.transferredTo);

      for (const userId of new Set(transfer.transferredFrom)) {
        if (receivingUserIds.has(userId) || !(await userStore.exists(userId))) {
          continue;
        }

        const eventResult = await subscriptionStore.applyRevenueCatEvent({
          authUser: { id: userId, provider: 'firebase' },
          billingSubscriptionId: revenueCatBillingSubscriptionId(userId),
          status: 'CANCELED',
          eventId: transfer.eventId,
          eventTimestampMs: transfer.eventTimestampMs
        });

        if (eventResult.applied) {
          revokedUserIds.push(userId);
        }
      }

      response.json({
        status: 'ok',
        ignored: revokedUserIds.length === 0,
        eventType: 'TRANSFER',
        revokedUserIds
      });
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

    const inactiveStatus = inactiveStatusByEventType[event.type];
    const isActionable = activeEventTypes.has(event.type) || Boolean(inactiveStatus);

    if (
      isActionable &&
      (!event.eventId || event.eventTimestampMs === undefined)
    ) {
      sendInvalidPayload(response);
      return;
    }

    const authUser = {
      id: event.appUserId,
      provider: 'firebase' as const
    };
    const billingSubscriptionId = revenueCatBillingSubscriptionId(event.appUserId);

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

    response.status(202).json({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_EVENT_NOT_ACTIONABLE',
      message: 'RevenueCat event does not change PostDee entitlements'
    });
  });
};
