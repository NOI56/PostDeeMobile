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

      try {
        ({ activeEntitlements } = await subscriberClient.loadSubscriber(authUser.id));
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

        const subscription =
          await subscriptionStore.updateStatusByBillingSubscriptionId({
            billingSubscriptionId: revenueCatBillingSubscriptionId(authUser.id),
            status: 'CANCELED'
          });
        const plan = await subscriptionStore.getPlan(authUser);
        response.json({
          status: 'ok',
          plan: 'BASIC',
          effectivePlan: plan,
          subscription
        });
        return;
      }

      await userStore.ensure(authUser);
      const subscription = await subscriptionStore.activatePlan(
        authUser,
        paidPlan.plan,
        {
          billingSubscriptionId: revenueCatBillingSubscriptionId(authUser.id),
          currentPeriodEnd: paidPlan.entitlement.expiresAt ?? null
        }
      );

      response.json({
        status: 'ok',
        plan: paidPlan.plan,
        subscription
      });
    }
  );
};
