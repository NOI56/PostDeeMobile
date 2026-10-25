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
      // Present only for multi-credit reservations, including every allocated row.
      records?: RealClipCaptionUsageRecord[];
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
    units?: number;
    includeMonthlyAddons?: boolean;
    now?: string;
  }) => Promise<RealClipCaptionUsageReservation>;
  // Removes only this reservation, never another concurrent request's usage.
  release?: (record: RealClipCaptionUsageRecord) => Promise<boolean>;
  // Removes the whole exact batch or leaves every row untouched.
  releaseMany?: (records: RealClipCaptionUsageRecord[]) => Promise<boolean>;
  // Hard-deletes every usage record owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const readCurrentRealClipCaptionMonthKey = (date = new Date()) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const readRealClipCaptionReservationUnits = (units = 1) => {
  if (!Number.isInteger(units) || units < 1 || units > 4) {
    throw new RangeError('Caption reservation units must be an integer from 1 to 4');
  }
  return units;
};

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
  const buildRecord = ({ userId, monthKey }: { userId: string; monthKey: string }, usesAddonCredit = false): RealClipCaptionUsageRecord => {
    return {
      userId,
      monthKey,
      createdAt: now(),
      ...(usesAddonCredit ? { usesAddonCredit: true } : {})
    };
  };

  return {
    countForMonth: async ({ userId, monthKey }) =>
      records.filter((record) => record.userId === userId && record.monthKey === monthKey && !record.usesAddonCredit).length,
    countAddonUsages: async ({ userId }) => records.filter(record => record.userId === userId && record.usesAddonCredit).length,
    record: ({ userId, monthKey }) => runWithActiveOwner(userId, async () => {
      const record = buildRecord({ userId, monthKey });
      records.push(record);
      return record;
    }),
    reserve: input => runWithActiveOwner(input.userId, async () => {
      const { userId, monthKey, limit, includeMonthlyAddons, now: reservationNow } = input;
      const units = readRealClipCaptionReservationUnits(input.units);
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
      const addonUsed = records.filter(record => record.userId === userId && record.usesAddonCredit).length;
      const monthlyUnits = Math.min(units, Math.max(0, limit - usedThisMonth));
      const addonUnits = units - monthlyUnits;
      if (addonUnits > Math.max(0, addonAiCaptions - addonUsed)) {
        return {
          ok: false,
          usedThisMonth
        };
      }

      // Do not await between checking the balance and creating every row.
      const reservedRecords = Array.from({ length: units }, (_, index) =>
        buildRecord({ userId, monthKey }, index >= monthlyUnits));
      records.push(...reservedRecords);
      return {
        ok: true,
        usedThisMonth: usedThisMonth + monthlyUnits,
        record: reservedRecords[0],
        ...(units > 1 ? { records: reservedRecords } : {})
      };
    }),
    release: async (record) => {
      const index = records.indexOf(record);
      if (index < 0) return false;
      records.splice(index, 1);
      return true;
    },
    releaseMany: async (reservedRecords) => {
      const first = reservedRecords[0];
      if (!first || new Set(reservedRecords).size !== reservedRecords.length || reservedRecords.some(record =>
        record.userId !== first.userId || record.monthKey !== first.monthKey || !records.includes(record))) return false;
      for (const record of reservedRecords) records.splice(records.indexOf(record), 1);
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
