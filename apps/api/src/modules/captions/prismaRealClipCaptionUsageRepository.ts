import type {
  RealClipCaptionUsageReservation,
  RealClipCaptionUsageRecord,
  RealClipCaptionUsageStore
} from './captionUsageStore.js';

type PrismaRealClipCaptionUsage = {
  userId: string;
  monthKey: string;
  createdAt: Date;
};

type RealClipCaptionUsageDelegate = {
  count: (args: {
    where: {
      userId: string;
      monthKey: string;
    };
  }) => Promise<number>;
  create: (args: {
    data: {
      userId: string;
      monthKey: string;
    };
    select: {
      userId: true;
      monthKey: true;
      createdAt: true;
    };
  }) => Promise<PrismaRealClipCaptionUsage>;
};

export type PrismaRealClipCaptionUsageClient = {
  realClipCaptionUsage: RealClipCaptionUsageDelegate;
  $transaction?: <T>(
    callback: (client: { realClipCaptionUsage: RealClipCaptionUsageDelegate }) => Promise<T>,
    options?: { isolationLevel: 'Serializable' }
  ) => Promise<T>;
};

const mapUsageRecord = (
  record: PrismaRealClipCaptionUsage
): RealClipCaptionUsageRecord => ({
  userId: record.userId,
  monthKey: record.monthKey,
  createdAt: record.createdAt.toISOString()
});

export const createPrismaRealClipCaptionUsageRepository = ({
  prisma
}: {
  prisma: PrismaRealClipCaptionUsageClient;
}): RealClipCaptionUsageStore => {
  const usageSelect = {
    userId: true,
    monthKey: true,
    createdAt: true
  } as const;
  const reserveWithClient = async (
    client: { realClipCaptionUsage: RealClipCaptionUsageDelegate },
    {
      userId,
      monthKey,
      limit
    }: {
      userId: string;
      monthKey: string;
      limit: number;
    }
  ): Promise<RealClipCaptionUsageReservation> => {
    const usedThisMonth = await client.realClipCaptionUsage.count({
      where: {
        userId,
        monthKey
      }
    });

    if (usedThisMonth >= limit) {
      return {
        ok: false,
        usedThisMonth
      };
    }

    const record = await client.realClipCaptionUsage.create({
      data: {
        userId,
        monthKey
      },
      select: usageSelect
    });

    return {
      ok: true,
      usedThisMonth: usedThisMonth + 1,
      record: mapUsageRecord(record)
    };
  };

  return {
    countForMonth: async ({ userId, monthKey }) =>
      prisma.realClipCaptionUsage.count({
        where: {
          userId,
          monthKey
        }
      }),
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
