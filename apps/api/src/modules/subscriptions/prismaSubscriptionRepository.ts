import type { AuthUser } from '../auth/authTypes.js';
import {
  type ApplyRevenueCatEventInput,
  type ApplyRevenueCatEventResult,
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
  currentPeriodEnd?: Date | null;
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

type PrismaRevenueCatUserState = {
  lastRevenueCatEventTimestampMs: bigint | null;
  lastRevenueCatEventId: string | null;
};

type RevenueCatUserDelegate = {
  findUnique: (args: {
    where: { id: string };
    select: {
      lastRevenueCatEventTimestampMs: true;
      lastRevenueCatEventId: true;
    };
  }) => Promise<PrismaRevenueCatUserState | null>;
  update: (args: {
    where: { id: string };
    data: {
      lastRevenueCatEventTimestampMs: bigint;
      lastRevenueCatEventId: string;
    };
    select: { id: true };
  }) => Promise<{ id: string }>;
};

type PrismaSubscriptionTransaction = {
  subscription: SubscriptionDelegate;
  user: RevenueCatUserDelegate;
};

export type PrismaSubscriptionClient = PrismaSubscriptionTransaction & {
  $transaction: <T>(
    action: (transaction: PrismaSubscriptionTransaction) => Promise<T>,
    options: {
      isolationLevel: 'Serializable';
      maxWait: number;
      timeout: number;
    }
  ) => Promise<T>;
};

const readErrorCode = (error: unknown) =>
  error && typeof error === 'object' && 'code' in error && typeof error.code === 'string'
    ? error.code
    : undefined;

const runSerializable = async <T>(
  prisma: PrismaSubscriptionClient,
  action: (transaction: PrismaSubscriptionTransaction) => Promise<T>
) => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await prisma.$transaction(action, {
        isolationLevel: 'Serializable',
        maxWait: 5_000,
        timeout: 10_000
      });
    } catch (error) {
      if (readErrorCode(error) !== 'P2034' || attempt === 2) {
        throw error;
      }
    }
  }

  throw new Error('Serializable RevenueCat transaction retry was exhausted');
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
    currentPeriodEnd?: string | null;
  }): PrismaSubscriptionWriteData => {
    const data: PrismaSubscriptionWriteData = {
      plan,
      status: 'ACTIVE'
    };

    if (billingSubscriptionId) {
      data.billingSubscriptionId = billingSubscriptionId;
    }

    if (currentPeriodEnd !== undefined) {
      data.currentPeriodEnd = currentPeriodEnd ? new Date(currentPeriodEnd) : null;
    }

    return data;
  };

  const applyRevenueCatEvent = (
    input: ApplyRevenueCatEventInput
  ): Promise<ApplyRevenueCatEventResult> =>
    runSerializable(prisma, async (transaction) => {
      const storedCursor = await transaction.user.findUnique({
        where: { id: input.authUser.id },
        select: {
          lastRevenueCatEventTimestampMs: true,
          lastRevenueCatEventId: true
        }
      });

      if (!storedCursor) {
        return {
          applied: false,
          subscription: null
        };
      }

      const eventTimestampMs = BigInt(input.eventTimestampMs);

      if (
        storedCursor.lastRevenueCatEventId === input.eventId ||
        (storedCursor.lastRevenueCatEventTimestampMs !== null &&
          eventTimestampMs <= storedCursor.lastRevenueCatEventTimestampMs)
      ) {
        return {
          applied: false,
          subscription: null
        };
      }

      await transaction.user.update({
        where: { id: input.authUser.id },
        data: {
          lastRevenueCatEventTimestampMs: eventTimestampMs,
          lastRevenueCatEventId: input.eventId
        },
        select: { id: true }
      });

      if (input.status === 'ACTIVE') {
        const activationData = buildActivationData({
          plan: input.plan,
          billingSubscriptionId: input.billingSubscriptionId,
          ...(Object.prototype.hasOwnProperty.call(input, 'currentPeriodEnd')
            ? { currentPeriodEnd: input.currentPeriodEnd }
            : {})
        });
        const subscription = await transaction.subscription.upsert({
          where: { userId: input.authUser.id },
          update: activationData,
          create: {
            userId: input.authUser.id,
            ...activationData
          },
          select: subscriptionSelect
        });

        return {
          applied: true,
          subscription: mapSubscription(subscription)
        };
      }

      try {
        const subscription = await transaction.subscription.update({
          where: {
            billingSubscriptionId: input.billingSubscriptionId
          },
          data: {
            status: input.status
          },
          select: subscriptionSelect
        });

        return {
          applied: true,
          subscription: mapSubscription(subscription)
        };
      } catch (error) {
        if (readErrorCode(error) === 'P2025') {
          return {
            applied: true,
            subscription: null
          };
        }

        throw error;
      }
    });

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
    },
    applyRevenueCatEvent
  };
};
