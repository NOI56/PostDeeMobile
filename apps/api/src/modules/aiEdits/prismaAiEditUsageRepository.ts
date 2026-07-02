import type {
  AiEditUsageRecord,
  AiEditUsageReservation,
  AiEditUsageStore
} from './aiEditUsageStore.js';

type PrismaAiEditUsage = {
  userId: string;
  monthKey: string;
  minutes: number;
  createdAt: Date;
};

type AiEditUsageDelegate = {
  aggregate: (args: {
    where: { userId: string; monthKey: string };
    _sum: { minutes: true };
  }) => Promise<{ _sum: { minutes: number | null } }>;
  create: (args: {
    data: { userId: string; monthKey: string; minutes: number };
    select: { userId: true; monthKey: true; minutes: true; createdAt: true };
  }) => Promise<PrismaAiEditUsage>;
};

export type PrismaAiEditUsageClient = {
  aiEditUsage: AiEditUsageDelegate;
  $transaction?: <T>(
    callback: (client: { aiEditUsage: AiEditUsageDelegate }) => Promise<T>,
    options?: { isolationLevel: 'Serializable' }
  ) => Promise<T>;
};

const mapUsageRecord = (record: PrismaAiEditUsage): AiEditUsageRecord => ({
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
    reserve: async (input) => {
      if (prisma.$transaction) {
        return prisma.$transaction((client) => reserveWithClient(client, input), {
          isolationLevel: 'Serializable'
        });
      }

      return reserveWithClient(prisma, input);
    }
  };
};
