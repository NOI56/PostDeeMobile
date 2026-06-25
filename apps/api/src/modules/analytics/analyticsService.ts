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
};

export type AnalyticsSummary = {
  totalViews: number;
  totalLikes: number;
  platforms: PlatformMetric[];
};

const zeroStatePlatforms: PlatformMetric[] = [
  { platform: 'TIKTOK', label: 'TikTok', views: 0, likes: 0 },
  { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 0, likes: 0 },
  { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
  { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
];

export const summarizePlatformMetrics = (metrics: PlatformMetricInput[]): AnalyticsSummary => {
  const platforms = zeroStatePlatforms.map((platform) => ({ ...platform }));

  for (const metric of metrics) {
    const platform = platforms.find((item) => item.platform === metric.platform);

    if (platform) {
      platform.views += metric.views;
      platform.likes += metric.likes;
    }
  }

  return {
    totalViews: platforms.reduce((sum, platform) => sum + platform.views, 0),
    totalLikes: platforms.reduce((sum, platform) => sum + platform.likes, 0),
    platforms
  };
};

export const getZeroStateAnalyticsSummary = (): AnalyticsSummary => summarizePlatformMetrics([]);
