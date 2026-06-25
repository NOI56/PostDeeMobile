import { describe, expect, it } from 'vitest';

import { summarizePlatformMetrics } from './analyticsService.js';

describe('summarizePlatformMetrics', () => {
  it('aggregates views and likes per platform and fills missing platforms with zero', () => {
    expect(
      summarizePlatformMetrics([
        { platform: 'TIKTOK', views: 100, likes: 10 },
        { platform: 'TIKTOK', views: 25, likes: 3 },
        { platform: 'YOUTUBE_SHORTS', views: 50, likes: 5 }
      ])
    ).toEqual({
      totalViews: 175,
      totalLikes: 18,
      platforms: [
        { platform: 'TIKTOK', label: 'TikTok', views: 125, likes: 13 },
        { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 50, likes: 5 },
        { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
        { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
      ]
    });
  });
});
