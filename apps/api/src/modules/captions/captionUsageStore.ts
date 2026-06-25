export type RealClipCaptionUsageRecord = {
  userId: string;
  monthKey: string;
  createdAt: string;
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
  record: (input: { userId: string; monthKey: string }) => Promise<RealClipCaptionUsageRecord>;
  reserve: (input: {
    userId: string;
    monthKey: string;
    limit: number;
  }) => Promise<RealClipCaptionUsageReservation>;
  // Hard-deletes every usage record owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const readCurrentRealClipCaptionMonthKey = (date = new Date()) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const createInMemoryRealClipCaptionUsageStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): RealClipCaptionUsageStore => {
  const records: RealClipCaptionUsageRecord[] = [];
  const createRecord = ({ userId, monthKey }: { userId: string; monthKey: string }) => {
    const record: RealClipCaptionUsageRecord = {
      userId,
      monthKey,
      createdAt: now()
    };

    records.push(record);
    return record;
  };

  return {
    countForMonth: async ({ userId, monthKey }) =>
      records.filter((record) => record.userId === userId && record.monthKey === monthKey).length,
    record: async ({ userId, monthKey }) => {
      return createRecord({ userId, monthKey });
    },
    reserve: async ({ userId, monthKey, limit }) => {
      const usedThisMonth = records.filter(
        (record) => record.userId === userId && record.monthKey === monthKey
      ).length;

      if (usedThisMonth >= limit) {
        return {
          ok: false,
          usedThisMonth
        };
      }

      return {
        ok: true,
        usedThisMonth: usedThisMonth + 1,
        record: createRecord({ userId, monthKey })
      };
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
