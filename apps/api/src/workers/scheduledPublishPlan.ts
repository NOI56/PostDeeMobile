import type { ServerConfig } from '../config/env.js';
import type { SubscriptionPlan, SubscriptionStore } from '../modules/subscriptions/subscriptionStore.js';

// Stored as each platform result's errorMessage when a scheduled post comes
// due after the owner's paid plan ended. The post itself becomes FAILED.
export const paidPlanRequiredPublishError = 'PAID_PLAN_REQUIRED';

export type ReadOwnerPlan = (ownerId: string) => Promise<SubscriptionPlan>;

// Local mock development may take the plan from a per-request header.
export const allowsSubscriptionPlanOverride = (
  config: Pick<ServerConfig, 'nodeEnv' | 'authProvider'>
) => config.nodeEnv !== 'production' && config.authProvider === 'mock';

// Scheduling is a paid feature, so the worker re-reads the owner's plan when a
// scheduled post comes due. Where the plan came from a request header (local
// mock development) it cannot be re-read, so no check applies there.
export const createScheduledPublishPlanReader = ({
  config,
  subscriptionStore
}: {
  config: Pick<ServerConfig, 'nodeEnv' | 'authProvider'>;
  subscriptionStore: Pick<SubscriptionStore, 'getPlan'>;
}): ReadOwnerPlan | undefined =>
  allowsSubscriptionPlanOverride(config)
    ? undefined
    : (ownerId) => subscriptionStore.getPlan({ id: ownerId, provider: config.authProvider });
