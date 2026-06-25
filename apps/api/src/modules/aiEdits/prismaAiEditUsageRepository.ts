import type { AiEditUsageRecord, AiEditUsageStore } from './aiEditUsageStore.js';

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
};

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

      return {
        userId: record.userId,
        monthKey: record.monthKey,
        minutes: record.minutes,
        createdAt: record.createdAt.toISOString()
      } satisfies AiEditUsageRecord;
    }
  };
};
