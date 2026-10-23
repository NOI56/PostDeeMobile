import type { ServerConfig } from '../../config/env.js';
import type { PaidSubscriptionPlan } from '../subscriptions/subscriptionStore.js';
import type { RevenueCatActiveEntitlement } from './revenueCatSubscriberClient.js';

export type RevenueCatSubscriptionPolicyConfig = Pick<ServerConfig,
  | 'revenueCatSubscriptionEnvironment'
  | 'revenueCatStarterEntitlementId'
  | 'revenueCatProEntitlementId'
  | 'revenueCatStarterProductId'
  | 'revenueCatProProductId'
>;

export const isRevenueCatSubscriptionStoreAllowed = (store: unknown, environment: 'SANDBOX' | 'PRODUCTION') => {
  if (typeof store !== 'string') return false;
  const normalized = store.toUpperCase();
  return normalized === 'APP_STORE' || normalized === 'PLAY_STORE' ||
    (environment === 'SANDBOX' && normalized === 'TEST_STORE');
};

export const isRevenueCatSubscriptionEntitlementAllowed = (
  entitlement: RevenueCatActiveEntitlement,
  config: RevenueCatSubscriptionPolicyConfig
) => {
  if (typeof entitlement.isSandbox !== 'boolean') return false;
  const environment = entitlement.isSandbox ? 'SANDBOX' : 'PRODUCTION';
  return environment === config.revenueCatSubscriptionEnvironment &&
    isRevenueCatSubscriptionStoreAllowed(entitlement.store, environment);
};

export const selectRevenueCatPaidEntitlement = (
  entitlements: RevenueCatActiveEntitlement[],
  config: RevenueCatSubscriptionPolicyConfig
): { plan: PaidSubscriptionPlan; entitlement: RevenueCatActiveEntitlement } | undefined => {
  const eligible = entitlements.filter(entitlement => isRevenueCatSubscriptionEntitlementAllowed(entitlement, config));
  const pro = eligible.find(entitlement => entitlement.id === config.revenueCatProEntitlementId ||
    entitlement.productId === config.revenueCatProProductId);
  if (pro) return { plan: 'PRO', entitlement: pro };
  const starter = eligible.find(entitlement => entitlement.id === config.revenueCatStarterEntitlementId ||
    entitlement.productId === config.revenueCatStarterProductId);
  return starter ? { plan: 'STARTER', entitlement: starter } : undefined;
};
