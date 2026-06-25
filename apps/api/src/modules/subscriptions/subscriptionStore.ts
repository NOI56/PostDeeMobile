import type { AuthUser } from '../auth/authTypes.js';

export type SubscriptionPlan = 'BASIC' | 'STARTER' | 'PRO';
export type PaidSubscriptionPlan = Exclude<SubscriptionPlan, 'BASIC'>;
export type SubscriptionStatus = 'ACTIVE' | 'PAST_DUE' | 'CANCELED' | 'INCOMPLETE';

export type UserSubscription = {
  userId: string;
  plan: SubscriptionPlan;
  status: SubscriptionStatus;
  billingSubscriptionId?: string;
  currentPeriodEnd?: string;
  updatedAt: string;
};

export type ActivatePlanOptions = {
  billingSubscriptionId?: string;
  currentPeriodEnd?: string;
};

export type UpdateSubscriptionStatusByBillingIdInput = {
  billingSubscriptionId: string;
  status: SubscriptionStatus;
};

export type SubscriptionStore = {
  getPlan: (authUser: AuthUser) => Promise<SubscriptionPlan>;
  activatePlan: (
    authUser: AuthUser,
    plan: PaidSubscriptionPlan,
    options?: ActivatePlanOptions
  ) => Promise<UserSubscription>;
  activatePro: (authUser: AuthUser, options?: ActivatePlanOptions) => Promise<UserSubscription>;
  updateStatusByBillingSubscriptionId: (
    input: UpdateSubscriptionStatusByBillingIdInput
  ) => Promise<UserSubscription | null>;
  // Hard-deletes the subscription owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

/**
 * True when a subscription's paid period has already ended. A safety net for
 * missed renewal/cancel webhooks: even if the stored status is still ACTIVE, an
 * elapsed `currentPeriodEnd` means the user should drop to BASIC. Subscriptions
 * with no known period end (e.g. mock activations) are treated as active.
 */
export const isSubscriptionExpired = (
  currentPeriodEnd: string | undefined,
  nowIso: string
): boolean => {
  if (!currentPeriodEnd) {
    return false;
  }

  const end = Date.parse(currentPeriodEnd);
  const now = Date.parse(nowIso);

  if (Number.isNaN(end) || Number.isNaN(now)) {
    return false;
  }

  return end <= now;
};

export const createSubscriptionStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): SubscriptionStore => {
  const subscriptions = new Map<string, UserSubscription>();
  const subscriptionUserIdsByBillingId = new Map<string, string>();
  const activatePaidPlan = async (
    authUser: AuthUser,
    plan: PaidSubscriptionPlan,
    options: ActivatePlanOptions = {}
  ) => {
    const previousSubscription = subscriptions.get(authUser.id);

    if (previousSubscription?.billingSubscriptionId) {
      subscriptionUserIdsByBillingId.delete(previousSubscription.billingSubscriptionId);
    }

    const subscription: UserSubscription = {
      userId: authUser.id,
      plan,
      status: 'ACTIVE',
      billingSubscriptionId: options.billingSubscriptionId,
      currentPeriodEnd: options.currentPeriodEnd,
      updatedAt: now()
    };

    subscriptions.set(authUser.id, subscription);
    if (subscription.billingSubscriptionId) {
      subscriptionUserIdsByBillingId.set(subscription.billingSubscriptionId, authUser.id);
    }

    return subscription;
  };

  return {
    getPlan: async (authUser) => {
      const storedSubscription = subscriptions.get(authUser.id);

      if (authUser.subscriptionPlan) {
        return authUser.subscriptionPlan;
      }

      if (
        storedSubscription?.status === 'ACTIVE' &&
        !isSubscriptionExpired(storedSubscription.currentPeriodEnd, now())
      ) {
        return storedSubscription.plan;
      }

      return 'BASIC';
    },
    activatePlan: activatePaidPlan,
    activatePro: async (authUser, options = {}) => activatePaidPlan(authUser, 'PRO', options),
    updateStatusByBillingSubscriptionId: async ({ billingSubscriptionId, status }) => {
      const userId = subscriptionUserIdsByBillingId.get(billingSubscriptionId);

      if (!userId) {
        return null;
      }

      const existingSubscription = subscriptions.get(userId);

      if (!existingSubscription) {
        return null;
      }

      const subscription: UserSubscription = {
        ...existingSubscription,
        status,
        updatedAt: now()
      };

      subscriptions.set(userId, subscription);
      return subscription;
    },
    deleteAllForUser: async (userId) => {
      const existingSubscription = subscriptions.get(userId);

      if (existingSubscription?.billingSubscriptionId) {
        subscriptionUserIdsByBillingId.delete(existingSubscription.billingSubscriptionId);
      }

      subscriptions.delete(userId);
    }
  };
};
