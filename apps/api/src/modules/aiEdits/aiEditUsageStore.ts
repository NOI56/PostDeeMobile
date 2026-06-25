export type AiEditUsageRecord = {
  userId: string;
  monthKey: string;
  minutes: number;
  createdAt: string;
};

export type AiEditUsageStore = {
  sumMinutesForMonth: (input: {
    userId: string;
    monthKey: string;
  }) => Promise<number>;
  record: (input: {
    userId: string;
    monthKey: string;
    minutes: number;
  }) => Promise<AiEditUsageRecord>;
  // Hard-deletes every usage record owned by userId. Used by account deletion.
  // Optional because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

/** Pro AI auto-editing minutes per month. Top-ups add to this elsewhere. */
export const aiEditMonthlyMinuteLimit = 200;

export const readCurrentAiEditMonthKey = (date = new Date()) =>
  `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

export const createInMemoryAiEditUsageStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): AiEditUsageStore => {
  const records: AiEditUsageRecord[] = [];

  return {
    sumMinutesForMonth: async ({ userId, monthKey }) =>
      records
        .filter((record) => record.userId === userId && record.monthKey === monthKey)
        .reduce((sum, record) => sum + record.minutes, 0),
    record: async ({ userId, monthKey, minutes }) => {
      const record: AiEditUsageRecord = {
        userId,
        monthKey,
        minutes,
        createdAt: now()
      };

      records.push(record);
      return record;
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
