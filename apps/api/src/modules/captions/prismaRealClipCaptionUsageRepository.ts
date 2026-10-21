import type {
  RealClipCaptionUsageReservation,
  RealClipCaptionUsageRecord,
  RealClipCaptionUsageStore
} from './captionUsageStore.js';
import { readCurrentRealClipCaptionMonthKey } from './captionUsageStore.js';
import { readPrismaMonthlyAddonCredits, type PrismaMonthlyAddonReadTransaction } from '../billing/prismaMonthlyAddonRepository.js';
import { lockActiveOwner, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';

type PrismaRealClipCaptionUsage = {
  id?: string;
  userId: string;
  monthKey: string;
  createdAt: Date;
  usesAddonCredit?: boolean;
};

type RealClipCaptionUsageDelegate = {
  count: (args: {
    where: {
      userId: string;
      monthKey?: string;
      usesAddonCredit?: boolean;
    };
  }) => Promise<number>;
  create: (args: {
    data: {
      userId: string;
      monthKey: string;
      usesAddonCredit?: boolean;
    };
    select: {
      id: true;
      userId: true;
      monthKey: true;
      createdAt: true;
      usesAddonCredit?: true;
    };
  }) => Promise<PrismaRealClipCaptionUsage>;
  deleteMany?: (args: { where: { id: string; userId: string; monthKey: string } }) => Promise<{ count: number }>;
};

type CaptionUsageTransaction = Partial<PrismaMonthlyAddonReadTransaction> & Partial<PrismaOwnerLifecycleTransaction> & {
  realClipCaptionUsage: RealClipCaptionUsageDelegate;
};

export type PrismaRealClipCaptionUsageClient = CaptionUsageTransaction & {
  $transaction?: <T>(
    callback: (client: CaptionUsageTransaction) => Promise<T>,
    options?: { isolationLevel: 'Serializable' }
  ) => Promise<T>;
};

const mapUsageRecord = (
  record: PrismaRealClipCaptionUsage
): RealClipCaptionUsageRecord => ({
  ...(record.id ? { id: record.id } : {}),
  userId: record.userId,
  monthKey: record.monthKey,
  createdAt: record.createdAt.toISOString(),
  ...(record.usesAddonCredit ? { usesAddonCredit: true } : {})
});

export const createPrismaRealClipCaptionUsageRepository = ({
  prisma
}: {
  prisma: PrismaRealClipCaptionUsageClient;
}): RealClipCaptionUsageStore => {
  const usageSelect = {
    id: true,
    userId: true,
    monthKey: true,
    createdAt: true,
    usesAddonCredit: true
  } as const;
  const reserveWithClient = async (
    client: CaptionUsageTransaction,
    {
      userId,
      monthKey,
      limit,
      includeMonthlyAddons,
      now
    }: {
      userId: string;
      monthKey: string;
      limit: number;
      includeMonthlyAddons?: boolean;
      now?: string;
    }
  ): Promise<RealClipCaptionUsageReservation> => {
    let addonAiCaptions = 0;
    if (includeMonthlyAddons) {
      if (!client.monthlyAddonPurchase) throw new Error('Monthly addon transaction delegate is required');
      if (!client.managedUploadOwner) throw new Error('Caption addon owner transaction delegate is required');
      await lockActiveOwner({ managedUploadOwner: client.managedUploadOwner }, userId);
      const creditNow = now ?? new Date().toISOString();
      if (readCurrentRealClipCaptionMonthKey(new Date(creditNow)) !== monthKey) {
        throw new Error('Caption reservation month does not match addon window');
      }
      addonAiCaptions = (await readPrismaMonthlyAddonCredits(
        { monthlyAddonPurchase: client.monthlyAddonPurchase }, userId, creditNow
      )).aiCaptions;
    }
    const usedThisMonth = await client.realClipCaptionUsage.count({
      where: {
        userId,
        monthKey,
        usesAddonCredit: false
      }
    });

    const usesAddonCredit = usedThisMonth >= limit;
    const usedAddon = includeMonthlyAddons ? await client.realClipCaptionUsage.count({
      where: { userId, usesAddonCredit: true }
    }) : 0;
    if (usesAddonCredit && usedAddon >= addonAiCaptions) {
      return {
        ok: false,
        usedThisMonth
      };
    }

    const record = await client.realClipCaptionUsage.create({
      data: {
        userId,
        monthKey,
        ...(usesAddonCredit ? { usesAddonCredit: true } : {})
      },
      select: usageSelect
    });

    return {
      ok: true,
      usedThisMonth: usedThisMonth + (usesAddonCredit ? 0 : 1),
      record: mapUsageRecord(record)
    };
  };

  return {
    countForMonth: async ({ userId, monthKey }) =>
      prisma.realClipCaptionUsage.count({
        where: {
          userId,
          monthKey,
          usesAddonCredit: false
        }
      }),
    countAddonUsages: async ({ userId }) => prisma.realClipCaptionUsage.count({ where: { userId, usesAddonCredit: true } }),
    record: async ({ userId, monthKey }) => {
      const record = await prisma.realClipCaptionUsage.create({
        data: {
          userId,
          monthKey
        },
        select: usageSelect
      });

      return mapUsageRecord(record);
    },
    release: async (record) => {
      if (!record.id || !prisma.realClipCaptionUsage.deleteMany) return false;
      const result = await prisma.realClipCaptionUsage.deleteMany({
        where: { id: record.id, userId: record.userId, monthKey: record.monthKey }
      });
      return result.count === 1;
    },
    reserve: async (input) => {
      if (prisma.$transaction) {
        for (let attempt = 1; attempt <= 3; attempt += 1) {
          try {
            return await prisma.$transaction((client) => reserveWithClient(client, input), {
              isolationLevel: 'Serializable'
            });
          } catch (error) {
            if (attempt === 3 || !error || typeof error !== 'object' ||
                !('code' in error) || error.code !== 'P2034') throw error;
          }
        }
        throw new Error('Caption quota transaction retry exhausted');
      }

      if (input.includeMonthlyAddons) throw new Error('Monthly addons require transaction support');
      return reserveWithClient(prisma, input);
    }
  };
};
