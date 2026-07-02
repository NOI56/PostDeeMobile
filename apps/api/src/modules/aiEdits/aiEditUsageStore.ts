export type AiEditUsageRecord = {
  userId: string;
  monthKey: string;
  minutes: number;
  createdAt: string;
};

export type AiEditUsageReservation =
  | {
      ok: true;
      usedMinutes: number;
      record: AiEditUsageRecord;
    }
  | {
      ok: false;
      usedMinutes: number;
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
  reserve: (input: {
    userId: string;
    monthKey: string;
    minutes: number;
    limit: number;
  }) => Promise<AiEditUsageReservation>;
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
  const sumMinutes = ({ userId, monthKey }: { userId: string; monthKey: string }) =>
    records
      .filter((record) => record.userId === userId && record.monthKey === monthKey)
      .reduce((sum, record) => sum + record.minutes, 0);
  const createRecord = ({
    userId,
    monthKey,
    minutes
  }: {
    userId: string;
    monthKey: string;
    minutes: number;
  }) => {
    const record: AiEditUsageRecord = {
      userId,
      monthKey,
      minutes,
      createdAt: now()
    };

    records.push(record);
    return record;
  };

  return {
    sumMinutesForMonth: async (input) => sumMinutes(input),
    record: async ({ userId, monthKey, minutes }) => createRecord({ userId, monthKey, minutes }),
    reserve: async ({ userId, monthKey, minutes, limit }) => {
      const usedMinutes = sumMinutes({ userId, monthKey });

      if (usedMinutes + minutes > limit) {
        return {
          ok: false,
          usedMinutes
        };
      }

      return {
        ok: true,
        usedMinutes: usedMinutes + minutes,
        record: createRecord({ userId, monthKey, minutes })
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
