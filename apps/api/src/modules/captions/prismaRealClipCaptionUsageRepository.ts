import type {
  RealClipCaptionUsageReservation,
  RealClipCaptionUsageRecord,
  RealClipCaptionUsageStore
} from './captionUsageStore.js';
import { readCurrentRealClipCaptionMonthKey, readRealClipCaptionReservationUnits } from './captionUsageStore.js';
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

class CaptionBatchReleaseMismatchError extends Error {}

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
      units = 1,
      includeMonthlyAddons,
      now
    }: {
      userId: string;
      monthKey: string;
      limit: number;
      units?: number;
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

    const usedAddon = includeMonthlyAddons ? await client.realClipCaptionUsage.count({
      where: { userId, usesAddonCredit: true }
    }) : 0;
    const monthlyUnits = Math.min(units, Math.max(0, limit - usedThisMonth));
    const addonUnits = units - monthlyUnits;
    if (addonUnits > Math.max(0, addonAiCaptions - usedAddon)) {
      return {
        ok: false,
        usedThisMonth
      };
    }

    const records: RealClipCaptionUsageRecord[] = [];
    for (let index = 0; index < units; index += 1) {
      const record = await client.realClipCaptionUsage.create({
        data: {
          userId,
          monthKey,
          ...(index >= monthlyUnits ? { usesAddonCredit: true } : {})
        },
        select: usageSelect
      });
      records.push(mapUsageRecord(record));
    }

    return {
      ok: true,
      usedThisMonth: usedThisMonth + monthlyUnits,
      record: records[0],
      ...(units > 1 ? { records } : {})
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
    releaseMany: async (records) => {
      const batch = records.map(record => ({ ...record }));
      const first = batch[0];
      if (!prisma.$transaction || !first || new Set(batch.map(record => record.id)).size !== batch.length ||
          batch.some(record => !record.id || record.userId !== first.userId || record.monthKey !== first.monthKey)) return false;
      for (let attempt = 1; attempt <= 3; attempt += 1) {
        try {
          return await prisma.$transaction(async client => {
            if (!client.realClipCaptionUsage.deleteMany) throw new CaptionBatchReleaseMismatchError();
            for (const record of batch) {
              const deleted = await client.realClipCaptionUsage.deleteMany({
                where: { id: record.id!, userId: record.userId, monthKey: record.monthKey }
              });
              if (deleted.count !== 1) throw new CaptionBatchReleaseMismatchError();
            }
            return true;
          }, { isolationLevel: 'Serializable' });
        } catch (error) {
          if (error instanceof CaptionBatchReleaseMismatchError) return false;
          if (attempt === 3 || !error || typeof error !== 'object' ||
              !('code' in error) || error.code !== 'P2034') throw error;
        }
      }
      return false;
    },
    reserve: async (input) => {
      const units = readRealClipCaptionReservationUnits(input.units);
      if (units > 1 && !prisma.$transaction) throw new Error('Caption credit batches require transaction support');
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
