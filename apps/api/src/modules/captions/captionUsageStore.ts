import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';

export type RealClipCaptionUsageRecord = {
  id?: string;
  userId: string;
  monthKey: string;
  createdAt: string;
  usesAddonCredit?: boolean;
};

export type RealClipCaptionUsageReservation =
  | {
      ok: true;
      usedThisMonth: number;
      record: RealClipCaptionUsageRecord;
    }
  | {
      ok: false;
      usedThisMonth: number;
    };

export type RealClipCaptionUsageStore = {
  countForMonth: (input: { userId: string; monthKey: string }) => Promise<number>;
  countAddonUsages: (input: { userId: string }) => Promise<number>;
  record: (input: { userId: string; monthKey: string }) => Promise<RealClipCaptionUsageRecord>;
  reserve: (input: {
    userId: string;
    monthKey: string;
    limit: number;
    includeMonthlyAddons?: boolean;
    now?: string;
  }) => Promise<RealClipCaptionUsageReservation>;
  // Removes only this reservation, never another concurrent request's usage.
  release?: (record: RealClipCaptionUsageRecord) => Promise<boolean>;
  // Hard-deletes every usage record owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const readCurrentRealClipCaptionMonthKey = (date = new Date()) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const createInMemoryRealClipCaptionUsageStore = ({
  now = () => new Date().toISOString(),
  monthlyAddonStore,
  runWithActiveOwner = async (_ownerId, operation) => operation()
}: {
  now?: () => string;
  monthlyAddonStore?: Pick<MonthlyAddonStore, 'readCredits'>;
  runWithActiveOwner?: RunWithActiveOwner;
} = {}): RealClipCaptionUsageStore => {
  const records: RealClipCaptionUsageRecord[] = [];
  const createRecord = ({ userId, monthKey }: { userId: string; monthKey: string }, usesAddonCredit = false) => {
    const record: RealClipCaptionUsageRecord = {
      userId,
      monthKey,
      createdAt: now(),
      ...(usesAddonCredit ? { usesAddonCredit: true } : {})
    };

    records.push(record);
    return record;
  };

  return {
    countForMonth: async ({ userId, monthKey }) =>
      records.filter((record) => record.userId === userId && record.monthKey === monthKey && !record.usesAddonCredit).length,
    countAddonUsages: async ({ userId }) => records.filter(record => record.userId === userId && record.usesAddonCredit).length,
    record: ({ userId, monthKey }) => runWithActiveOwner(userId, async () => {
      return createRecord({ userId, monthKey });
    }),
    reserve: input => runWithActiveOwner(input.userId, async () => {
      const { userId, monthKey, limit, includeMonthlyAddons, now: reservationNow } = input;
      let addonAiCaptions = 0;
      if (includeMonthlyAddons) {
        const creditNow = reservationNow ?? now();
        if (readCurrentRealClipCaptionMonthKey(new Date(creditNow)) !== monthKey) {
          throw new Error('Caption reservation month does not match addon window');
        }
        addonAiCaptions = (await monthlyAddonStore?.readCredits({ userId, now: creditNow }))?.aiCaptions ?? 0;
      }
      const usedThisMonth = records.filter(
        (record) => record.userId === userId && record.monthKey === monthKey && !record.usesAddonCredit
      ).length;
      const usesAddonCredit = usedThisMonth >= limit;
      const addonUsed = records.filter(record => record.userId === userId && record.usesAddonCredit).length;
      if (usesAddonCredit && addonUsed >= addonAiCaptions) {
        return {
          ok: false,
          usedThisMonth
        };
      }

      return {
        ok: true,
        usedThisMonth: usedThisMonth + (usesAddonCredit ? 0 : 1),
        record: createRecord({ userId, monthKey }, usesAddonCredit)
      };
    }),
    release: async (record) => {
      const index = records.indexOf(record);
      if (index < 0) return false;
      records.splice(index, 1);
      return true;
    },
    deleteAllForUser: async (userId) => {
      for (let index = records.length - 1; index >= 0; index -= 1) {
        if (records[index].userId === userId) {
          records.splice(index, 1);
        }
      }
    }
  };
};
