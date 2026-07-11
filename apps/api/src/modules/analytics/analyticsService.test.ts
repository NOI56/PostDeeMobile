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
      range: '30d',
      totalViews: 175,
      totalLikes: 18,
      platforms: [
        { platform: 'TIKTOK', label: 'TikTok', views: 125, likes: 13 },
        { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 50, likes: 5 },
        { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
        { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
      ],
      daily: []
    });
  });

  it('filters dated metrics by range and groups them by UTC publish day', () => {
    expect(
      summarizePlatformMetrics(
        [
          {
            platform: 'TIKTOK',
            views: 100,
            likes: 10,
            occurredAt: new Date('2026-07-10T08:00:00.000Z')
          },
          {
            platform: 'YOUTUBE_SHORTS',
            views: 50,
            likes: 5,
            occurredAt: new Date('2026-07-04T08:00:00.000Z')
          },
          {
            platform: 'INSTAGRAM_REELS',
            views: 80,
            likes: 8,
            occurredAt: new Date('2026-06-01T08:00:00.000Z')
          }
        ],
        { range: '7d', now: new Date('2026-07-10T12:00:00.000Z') }
      )
    ).toMatchObject({
      range: '7d',
      totalViews: 150,
      totalLikes: 15,
      daily: [
        { date: '2026-07-04', views: 50, likes: 5 },
        { date: '2026-07-10', views: 100, likes: 10 }
      ]
    });
  });
});
