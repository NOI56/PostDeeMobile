import type { Platform } from '../posts/postStore.js';
import { summarizePlatformMetrics } from './analyticsService.js';
import type { AnalyticsStore } from './analyticsStore.js';

type PrismaPlatformMetric = {
  platform: Platform;
  views: number;
  likes: number;
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
  summaryForUser: async (userId) => {
    const metrics = await prisma.platformPublish.findMany({
      where: {
        post: {
          userId
        }
      },
      select: {
        platform: true,
        views: true,
        likes: true
      }
    });

    return summarizePlatformMetrics(metrics);
  }
});
