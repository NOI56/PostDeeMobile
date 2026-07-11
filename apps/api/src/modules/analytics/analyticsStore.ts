import type { Platform } from '../posts/postStore.js';
import {
  type AnalyticsRange,
  type AnalyticsSummary,
  type PlatformMetricInput,
  summarizePlatformMetrics
} from './analyticsService.js';

export type UserPlatformMetric = PlatformMetricInput & {
  userId: string;
};

export type AnalyticsStore = {
  summaryForUser: (userId: string, range?: AnalyticsRange) => Promise<AnalyticsSummary>;
  // Hard-deletes every metric owned by userId. Used by account deletion.
  // Optional because the Prisma store derives metrics from cascaded posts.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const createInMemoryAnalyticsStore = ({
  initialMetrics = []
}: {
  initialMetrics?: UserPlatformMetric[];
} = {}): AnalyticsStore => {
  const metrics = [...initialMetrics];

  return {
    summaryForUser: async (userId, range = '30d') =>
      summarizePlatformMetrics(
        metrics
          .filter((metric) => metric.userId === userId)
          .map(({ platform, views, likes, occurredAt }) => ({
            platform: platform as Platform,
            views,
            likes,
            occurredAt
          })),
        { range }
      ),
    deleteAllForUser: async (userId) => {
      for (let index = metrics.length - 1; index >= 0; index -= 1) {
        if (metrics[index].userId === userId) {
          metrics.splice(index, 1);
        }
      }
    }
  };
};
