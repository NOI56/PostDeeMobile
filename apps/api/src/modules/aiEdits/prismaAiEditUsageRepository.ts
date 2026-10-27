import type {
  AiEditUsageRecord,
  AiEditUsageReservation,
  AiEditUsageStore
} from './aiEditUsageStore.js';

type PrismaAiEditUsage = {
  id: string;
  userId: string;
  monthKey: string;
  minutes: number;
  createdAt: Date;
};

type AiEditUsageSelect = {
  id: true;
  userId: true;
  monthKey: true;
  minutes: true;
  createdAt: true;
};

type AiEditUsageDelegate = {
  aggregate: (args: {
    where: { userId: string; monthKey: string };
    _sum: { minutes: true };
  }) => Promise<{ _sum: { minutes: number | null } }>;
  create: (args: {
    data: { userId: string; monthKey: string; minutes: number };
    select: AiEditUsageSelect;
  }) => Promise<PrismaAiEditUsage>;
  findFirst: (args: {
    where: { id: string; userId: string; monthKey: string };
    select: AiEditUsageSelect;
  }) => Promise<PrismaAiEditUsage | null>;
  update: (args: {
    where: { id: string };
    data: { minutes: number };
    select: AiEditUsageSelect;
  }) => Promise<PrismaAiEditUsage>;
  deleteMany: (args: { where: { id: string; userId: string } }) => Promise<{ count: number }>;
};

export type PrismaAiEditUsageClient = {
  aiEditUsage: AiEditUsageDelegate;
  $transaction?: <T>(
    callback: (client: { aiEditUsage: AiEditUsageDelegate }) => Promise<T>,
    options?: { isolationLevel: 'Serializable' }
  ) => Promise<T>;
};

const mapUsageRecord = (record: PrismaAiEditUsage): AiEditUsageRecord => ({
  id: record.id,
  userId: record.userId,
  monthKey: record.monthKey,
  minutes: record.minutes,
  createdAt: record.createdAt.toISOString()
});

export const createPrismaAiEditUsageRepository = ({
  prisma
}: {
  prisma: PrismaAiEditUsageClient;
}): AiEditUsageStore => {
  const usageSelect = {
    id: true,
    userId: true,
    monthKey: true,
    minutes: true,
    createdAt: true
  } as const;
  const reserveWithClient = async (
    client: { aiEditUsage: AiEditUsageDelegate },
    {
      userId,
      monthKey,
      minutes,
      limit
    }: {
      userId: string;
      monthKey: string;
      minutes: number;
      limit: number;
    }
  ): Promise<AiEditUsageReservation> => {
    const result = await client.aiEditUsage.aggregate({
      where: { userId, monthKey },
      _sum: { minutes: true }
    });
    const usedMinutes = result._sum.minutes ?? 0;

    if (usedMinutes + minutes > limit) {
      return {
        ok: false,
        usedMinutes
      };
    }

    const record = await client.aiEditUsage.create({
      data: { userId, monthKey, minutes },
      select: usageSelect
    });

    return {
      ok: true,
      usedMinutes: usedMinutes + minutes,
      record: mapUsageRecord(record)
    };
  };

  // Two requests from one user can conflict under Serializable isolation
  // (Prisma P2034). Retry a few times so the loser gets a real quota answer
  // instead of a 500.
  const runSerializable = async <T>(
    operation: (client: { aiEditUsage: AiEditUsageDelegate }) => Promise<T>
  ): Promise<T> => {
    if (!prisma.$transaction) {
      return operation(prisma);
    }

    for (let attempt = 1; ; attempt += 1) {
      try {
        return await prisma.$transaction(operation, { isolationLevel: 'Serializable' });
      } catch (error) {
        const isWriteConflict =
          typeof error === 'object' && error !== null &&
          'code' in error && error.code === 'P2034';

        if (!isWriteConflict || attempt >= 3) {
          throw error;
        }
      }
    }
  };

  const settleWithClient = async (
    client: { aiEditUsage: AiEditUsageDelegate },
    {
      id,
      userId,
      monthKey,
      minutes,
      limit
    }: { id: string; userId: string; monthKey: string; minutes: number; limit: number }
  ): Promise<AiEditUsageReservation> => {
    const reserved = await client.aiEditUsage.findFirst({
      where: { id, userId, monthKey },
      select: usageSelect
    });
    const result = await client.aiEditUsage.aggregate({
      where: { userId, monthKey },
      _sum: { minutes: true }
    });
    const usedMinutes = result._sum.minutes ?? 0;

    if (!reserved || usedMinutes - reserved.minutes + minutes > limit) {
      return { ok: false, usedMinutes };
    }

    const record = await client.aiEditUsage.update({
      where: { id },
      data: { minutes },
      select: usageSelect
    });

    return {
      ok: true,
      usedMinutes: usedMinutes - reserved.minutes + minutes,
      record: mapUsageRecord(record)
    };
  };

  return {
    sumMinutesForMonth: async ({ userId, monthKey }) => {
      const result = await prisma.aiEditUsage.aggregate({
        where: { userId, monthKey },
        _sum: { minutes: true }
      });

      return result._sum.minutes ?? 0;
    },
    record: async ({ userId, monthKey, minutes }) => {
      const record = await prisma.aiEditUsage.create({
        data: { userId, monthKey, minutes },
        select: usageSelect
      });

      return mapUsageRecord(record);
    },
    reserve: (input) =>
      runSerializable((client) => reserveWithClient(client, input)),
    settle: (input) =>
      runSerializable((client) => settleWithClient(client, input)),
    release: async ({ id, userId }) => {
      await prisma.aiEditUsage.deleteMany({ where: { id, userId } });
    }
  };
};
