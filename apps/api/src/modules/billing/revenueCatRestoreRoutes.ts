import type { RequestHandler, Router } from 'express';

import type { ServerConfig } from '../../config/env.js';
import { readAuthUser } from '../auth/authTypes.js';
import type { PaidSubscriptionPlan } from '../subscriptions/subscriptionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import {
  RevenueCatSubscriberUnavailableError,
  type RevenueCatActiveEntitlement,
  type RevenueCatSubscriberClient
} from './revenueCatSubscriberClient.js';

type RevenueCatRestoreConfig = Pick<
  ServerConfig,
  | 'billingProvider'
  | 'revenueCatStarterEntitlementId'
  | 'revenueCatProEntitlementId'
  | 'revenueCatStarterProductId'
  | 'revenueCatProProductId'
>;

const revenueCatBillingSubscriptionId = (appUserId: string) =>
  `revenuecat:${appUserId}`;

const buildRevenueCatResyncEventId = ({
  appUserId,
  observedAtMs,
  outcome
}: {
  appUserId: string;
  observedAtMs: number;
  outcome: string;
}) =>
  `revenuecat-resync:${encodeURIComponent(appUserId)}:${observedAtMs}:${outcome}`;

const findMappedEntitlement = (
  entitlements: RevenueCatActiveEntitlement[],
  entitlementId: string,
  productId: string
) =>
  entitlements.find(
    (entitlement) =>
      entitlement.id === entitlementId || entitlement.productId === productId
  );

const readPaidPlan = (
  entitlements: RevenueCatActiveEntitlement[],
  config: RevenueCatRestoreConfig
): { plan: PaidSubscriptionPlan; entitlement: RevenueCatActiveEntitlement } | undefined => {
  const pro = findMappedEntitlement(
    entitlements,
    config.revenueCatProEntitlementId,
    config.revenueCatProProductId
  );

  if (pro) {
    return { plan: 'PRO', entitlement: pro };
  }

  const starter = findMappedEntitlement(
    entitlements,
    config.revenueCatStarterEntitlementId,
    config.revenueCatStarterProductId
  );

  return starter ? { plan: 'STARTER', entitlement: starter } : undefined;
};

export const registerRevenueCatRestoreRoutes = ({
  router,
  authMiddleware,
  config,
  subscriberClient,
  userStore,
  subscriptionStore
}: {
  router: Router;
  authMiddleware: RequestHandler;
  config: RevenueCatRestoreConfig;
  subscriberClient: RevenueCatSubscriberClient;
  userStore: UserStore;
  subscriptionStore: SubscriptionStore;
}) => {
  if (config.billingProvider !== 'revenuecat') {
    return;
  }

  router.post(
    '/billing/revenuecat/resync',
    authMiddleware,
    async (_request, response) => {
      const authUser = readAuthUser(response.locals);

      if (!authUser) {
        response.status(401).json({
          status: 'error',
          message: 'Authenticated user is required'
        });
        return;
      }

      let activeEntitlements: RevenueCatActiveEntitlement[];
      let observedAtMs: number;

      try {
        ({ activeEntitlements, observedAtMs } =
          await subscriberClient.loadSubscriber(authUser.id));
      } catch (error) {
        if (error instanceof RevenueCatSubscriberUnavailableError) {
          response.status(501).json({
            status: 'error',
            code: 'REVENUECAT_RESYNC_NOT_CONFIGURED',
            message: 'RevenueCat subscription resync is not configured'
          });
          return;
        }

        response.status(502).json({
          status: 'error',
          code: 'REVENUECAT_RESYNC_FAILED',
          message: 'RevenueCat subscription resync failed'
        });
        return;
      }

      const paidPlan = readPaidPlan(activeEntitlements, config);

      if (!paidPlan) {
        if (activeEntitlements.length > 0) {
          response.status(409).json({
            status: 'error',
            code: 'REVENUECAT_ENTITLEMENT_NOT_MAPPED',
            message: 'RevenueCat subscription entitlement is not mapped'
          });
          return;
        }

        await userStore.ensure(authUser);
        const eventResult = await subscriptionStore.applyRevenueCatEvent({
          authUser,
          billingSubscriptionId: revenueCatBillingSubscriptionId(authUser.id),
          status: 'CANCELED',
          eventId: buildRevenueCatResyncEventId({
            appUserId: authUser.id,
            observedAtMs,
            outcome: 'BASIC'
          }),
          eventTimestampMs: observedAtMs
        });
        const effectivePlan = await subscriptionStore.getPlan(authUser);
        response.json({
          status: 'ok',
          plan: eventResult.applied ? 'BASIC' : effectivePlan,
          effectivePlan,
          subscription: eventResult.subscription
        });
        return;
      }

      await userStore.ensure(authUser);
      const currentPeriodEnd = paidPlan.entitlement.expiresAt ?? null;
      const eventResult = await subscriptionStore.applyRevenueCatEvent({
        authUser,
        billingSubscriptionId: revenueCatBillingSubscriptionId(authUser.id),
        plan: paidPlan.plan,
        status: 'ACTIVE',
        eventId: buildRevenueCatResyncEventId({
          appUserId: authUser.id,
          observedAtMs,
          outcome: `${paidPlan.plan}:${currentPeriodEnd ?? 'lifetime'}`
        }),
        eventTimestampMs: observedAtMs,
        currentPeriodEnd
      });
      const effectivePlan = await subscriptionStore.getPlan(authUser);

      response.json({
        status: 'ok',
        plan: eventResult.applied ? paidPlan.plan : effectivePlan,
        subscription: eventResult.subscription
      });
    }
  );
};
