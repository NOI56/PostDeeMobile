import { randomUUID } from 'node:crypto';

export type AiEditUsageRecord = {
  id: string;
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
  // Re-prices a reservation to the real billed minutes when the month still has
  // room; otherwise leaves it unchanged and returns ok: false.
  settle: (input: {
    id: string;
    userId: string;
    monthKey: string;
    minutes: number;
    limit: number;
  }) => Promise<AiEditUsageReservation>;
  // Deletes a reservation whose AI call failed, so it costs no minutes.
  release: (input: { id: string; userId: string }) => Promise<void>;
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
      id: randomUUID(),
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
    settle: async ({ id, userId, monthKey, minutes, limit }) => {
      const usedMinutes = sumMinutes({ userId, monthKey });
      const record = records.find(
        (candidate) =>
          candidate.id === id && candidate.userId === userId && candidate.monthKey === monthKey
      );

      if (!record || usedMinutes - record.minutes + minutes > limit) {
        return { ok: false, usedMinutes };
      }

      record.minutes = minutes;
      return { ok: true, usedMinutes: sumMinutes({ userId, monthKey }), record };
    },
    release: async ({ id, userId }) => {
      const index = records.findIndex(
        (candidate) => candidate.id === id && candidate.userId === userId
      );

      if (index !== -1) {
        records.splice(index, 1);
      }
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
