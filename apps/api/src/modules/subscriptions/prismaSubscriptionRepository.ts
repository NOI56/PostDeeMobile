import type { AuthUser } from '../auth/authTypes.js';
import {
  isSubscriptionExpired,
  type PaidSubscriptionPlan,
  type SubscriptionPlan,
  type SubscriptionStatus,
  type SubscriptionStore,
  type UserSubscription
} from './subscriptionStore.js';

type PrismaSubscription = {
  userId?: string;
  plan: SubscriptionPlan;
  status: SubscriptionStatus;
  billingSubscriptionId?: string | null;
  currentPeriodEnd?: Date | null;
  updatedAt?: Date;
};

type PrismaSubscriptionSelection = Required<
  Pick<PrismaSubscription, 'userId' | 'plan' | 'status' | 'updatedAt'>
> &
  Pick<PrismaSubscription, 'billingSubscriptionId' | 'currentPeriodEnd'>;

type PrismaSubscriptionWriteData = {
  plan: PaidSubscriptionPlan;
  status: 'ACTIVE';
  billingSubscriptionId?: string;
  currentPeriodEnd?: Date;
};

type PrismaSubscriptionSelect = {
  userId: true;
  plan: true;
  status: true;
  billingSubscriptionId: true;
  currentPeriodEnd: true;
  updatedAt: true;
};

type SubscriptionDelegate = {
  findUnique: (args: {
    where: { userId: string };
    select: {
      plan: true;
      status: true;
      currentPeriodEnd: true;
    };
  }) => Promise<PrismaSubscription | null>;
  upsert: (args: {
    where: { userId: string };
    update: PrismaSubscriptionWriteData;
    create: PrismaSubscriptionWriteData & {
      userId: string;
    };
    select: PrismaSubscriptionSelect;
  }) => Promise<PrismaSubscriptionSelection>;
  update: (args: {
    where: { billingSubscriptionId: string };
    data: {
      status: SubscriptionStatus;
    };
    select: PrismaSubscriptionSelect;
  }) => Promise<PrismaSubscriptionSelection>;
};

export type PrismaSubscriptionClient = {
  subscription: SubscriptionDelegate;
};

export const createPrismaSubscriptionRepository = ({
  prisma
}: {
  prisma: PrismaSubscriptionClient;
}): SubscriptionStore => {
  const subscriptionSelect = {
    userId: true,
    plan: true,
    status: true,
    billingSubscriptionId: true,
    currentPeriodEnd: true,
    updatedAt: true
  } satisfies PrismaSubscriptionSelect;

  const mapSubscription = (subscription: PrismaSubscriptionSelection): UserSubscription => {
    const mappedSubscription: UserSubscription = {
      userId: subscription.userId,
      plan: subscription.plan,
      status: subscription.status,
      updatedAt: subscription.updatedAt.toISOString()
    };

    if (subscription.billingSubscriptionId) {
      mappedSubscription.billingSubscriptionId = subscription.billingSubscriptionId;
    }

    if (subscription.currentPeriodEnd) {
      mappedSubscription.currentPeriodEnd = subscription.currentPeriodEnd.toISOString();
    }

    return mappedSubscription;
  };

  const buildActivationData = ({
    plan,
    billingSubscriptionId,
    currentPeriodEnd
  }: {
    plan: PaidSubscriptionPlan;
    billingSubscriptionId?: string;
    currentPeriodEnd?: string;
  }): PrismaSubscriptionWriteData => {
    const data: PrismaSubscriptionWriteData = {
      plan,
      status: 'ACTIVE'
    };

    if (billingSubscriptionId) {
      data.billingSubscriptionId = billingSubscriptionId;
    }

    if (currentPeriodEnd) {
      data.currentPeriodEnd = new Date(currentPeriodEnd);
    }

    return data;
  };

  return {
    getPlan: async (authUser: AuthUser) => {
      // Honor the dev subscription-plan override header (mock auth only; the
      // mobile app sends it via POSTDEE_MOCK_SUBSCRIPTION_PLAN). Production
      // Firebase auth never sends it, so the DB lookup below is used instead.
      if (authUser.subscriptionPlan) {
        return authUser.subscriptionPlan;
      }

      const subscription = await prisma.subscription.findUnique({
        where: { userId: authUser.id },
        select: {
          plan: true,
          status: true,
          currentPeriodEnd: true
        }
      });

      if (
        subscription?.status === 'ACTIVE' &&
        !isSubscriptionExpired(
          subscription.currentPeriodEnd?.toISOString(),
          new Date().toISOString()
        )
      ) {
        return subscription.plan;
      }

      return 'BASIC';
    },
    activatePlan: async (authUser: AuthUser, plan, options = {}) => {
      const activationData = buildActivationData({
        plan,
        ...options
      });
      const subscription = await prisma.subscription.upsert({
        where: { userId: authUser.id },
        update: activationData,
        create: {
          userId: authUser.id,
          ...activationData
        },
        select: subscriptionSelect
      });

      return mapSubscription(subscription);
    },
    activatePro: async (authUser: AuthUser, options = {}) => {
      const activationData = buildActivationData({
        plan: 'PRO',
        ...options
      });
      const subscription = await prisma.subscription.upsert({
        where: { userId: authUser.id },
        update: activationData,
        create: {
          userId: authUser.id,
          ...activationData
        },
        select: subscriptionSelect
      });

      return mapSubscription(subscription);
    },
    updateStatusByBillingSubscriptionId: async ({ billingSubscriptionId, status }) => {
      try {
        const subscription = await prisma.subscription.update({
          where: {
            billingSubscriptionId
          },
          data: {
            status
          },
          select: subscriptionSelect
        });

        return mapSubscription(subscription);
      } catch (error) {
        if (error && typeof error === 'object' && 'code' in error && error.code === 'P2025') {
          return null;
        }

        throw error;
      }
    }
  };
};
