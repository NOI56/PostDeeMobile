import type { Platform } from '../posts/postStore.js';

export type PlatformMetric = {
  platform: Platform;
  label: string;
  views: number;
  likes: number;
};

export type PlatformMetricInput = {
  platform: Platform;
  views: number;
  likes: number;
  occurredAt?: Date;
};

export const analyticsRanges = ['today', '7d', '30d', '90d', 'year'] as const;
export type AnalyticsRange = (typeof analyticsRanges)[number];

export type DailyAnalyticsMetric = {
  date: string;
  views: number;
  likes: number;
};

export type AnalyticsSummary = {
  range: AnalyticsRange;
  totalViews: number;
  totalLikes: number;
  platforms: PlatformMetric[];
  daily: DailyAnalyticsMetric[];
};

const zeroStatePlatforms: PlatformMetric[] = [
  { platform: 'TIKTOK', label: 'TikTok', views: 0, likes: 0 },
  { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 0, likes: 0 },
  { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
  { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
];

const startOfUtcDay = (date: Date): Date =>
  new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));

export const analyticsRangeStart = (range: AnalyticsRange, now = new Date()): Date => {
  const today = startOfUtcDay(now);

  if (range === 'today') return today;
  if (range === 'year') return new Date(Date.UTC(now.getUTCFullYear(), 0, 1));

  const days = range === '7d' ? 7 : range === '30d' ? 30 : 90;
  return new Date(today.getTime() - (days - 1) * 24 * 60 * 60 * 1000);
};

export const summarizePlatformMetrics = (
  metrics: PlatformMetricInput[],
  { range = '30d', now = new Date() }: { range?: AnalyticsRange; now?: Date } = {}
): AnalyticsSummary => {
  const rangeStart = analyticsRangeStart(range, now);
  const rangeEnd = now;
  const filteredMetrics = metrics.filter((metric) => {
    if (!metric.occurredAt) return true;
    return metric.occurredAt >= rangeStart && metric.occurredAt <= rangeEnd;
  });
  const platforms = zeroStatePlatforms.map((platform) => ({ ...platform }));
  const dailyByDate = new Map<string, DailyAnalyticsMetric>();

  for (const metric of filteredMetrics) {
    const platform = platforms.find((item) => item.platform === metric.platform);

    if (platform) {
      platform.views += metric.views;
      platform.likes += metric.likes;
    }

    if (metric.occurredAt) {
      const date = metric.occurredAt.toISOString().slice(0, 10);
      const daily = dailyByDate.get(date) ?? { date, views: 0, likes: 0 };
      daily.views += metric.views;
      daily.likes += metric.likes;
      dailyByDate.set(date, daily);
    }
  }

  return {
    range,
    totalViews: platforms.reduce((sum, platform) => sum + platform.views, 0),
    totalLikes: platforms.reduce((sum, platform) => sum + platform.likes, 0),
    platforms,
    daily: [...dailyByDate.values()].sort((a, b) => a.date.localeCompare(b.date))
  };
};

export const getZeroStateAnalyticsSummary = (): AnalyticsSummary => summarizePlatformMetrics([]);
