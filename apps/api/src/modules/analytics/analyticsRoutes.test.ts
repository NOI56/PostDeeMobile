import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';

describe('analytics routes', () => {
  it('rejects analytics for Basic users', async () => {
    const app = createApp();

    const response = await request(app).get('/analytics/summary').expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PRO_REQUIRED',
      message: 'Unified Analytics requires the Pro plan'
    });
  });

  it('returns a unified zero-state analytics summary for Pro users', async () => {
    const app = createApp();

    const response = await request(app)
      .get('/analytics/summary')
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      summary: {
        range: '30d',
        totalViews: 0,
        totalLikes: 0,
        platforms: [
          { platform: 'TIKTOK', label: 'TikTok', views: 0, likes: 0 },
          { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 0, likes: 0 },
          { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
          { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
        ],
        daily: []
      }
    });
  });

  it('rejects an unsupported analytics range', async () => {
    const app = createApp();

    const response = await request(app)
      .get('/analytics/summary?range=forever')
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(400);

    expect(response.body.code).toBe('INVALID_ANALYTICS_RANGE');
  });

  it('reads aggregated analytics for the authenticated Pro user', async () => {
    const analyticsStore = {
      summaryForUser: vi.fn().mockResolvedValue({
        range: '7d',
        totalViews: 150,
        totalLikes: 15,
        platforms: [
          { platform: 'TIKTOK', label: 'TikTok', views: 100, likes: 10 },
          { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 50, likes: 5 },
          { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
          { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
        ],
        daily: [{ date: '2026-07-10', views: 150, likes: 15 }]
      })
    };
    const app = createApp({ analyticsStore });

    const response = await request(app)
      .get('/analytics/summary?range=7d')
      .set('x-postdee-user-id', 'seller-analytics')
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(200);

    expect(analyticsStore.summaryForUser).toHaveBeenCalledWith('seller-analytics', '7d');
    expect(response.body.summary).toMatchObject({
      totalViews: 150,
      totalLikes: 15
    });
  });
});
