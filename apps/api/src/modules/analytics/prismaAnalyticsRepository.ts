import type { Platform } from '../posts/postStore.js';
import type { AnalyticsRange } from './analyticsService.js';
import { summarizePlatformMetrics } from './analyticsService.js';
import type { AnalyticsStore } from './analyticsStore.js';

type PrismaPlatformMetric = {
  platform: Platform;
  views: number;
  likes: number;
  publishedAt: Date | null;
  createdAt: Date;
};

type PlatformPublishDelegate = {
  findMany: (args: {
    where: {
      post: {
        userId: string;
      };
    };
    select: {
      platform: true;
      views: true;
      likes: true;
      publishedAt: true;
      createdAt: true;
    };
  }) => Promise<PrismaPlatformMetric[]>;
};

export type PrismaAnalyticsClient = {
  platformPublish: PlatformPublishDelegate;
};

export const createPrismaAnalyticsRepository = ({
  prisma
}: {
  prisma: PrismaAnalyticsClient;
}): AnalyticsStore => ({
  summaryForUser: async (userId, range: AnalyticsRange = '30d') => {
    const metrics = await prisma.platformPublish.findMany({
      where: {
        post: {
          userId
        }
      },
      select: {
        platform: true,
        views: true,
        likes: true,
        publishedAt: true,
        createdAt: true
      }
    });

    return summarizePlatformMetrics(
      metrics.map(({ publishedAt, createdAt, ...metric }) => ({
        ...metric,
        occurredAt: publishedAt ?? createdAt
      })),
      { range }
    );
  }
});
