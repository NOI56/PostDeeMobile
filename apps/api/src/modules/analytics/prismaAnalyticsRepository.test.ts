import { describe, expect, it, vi } from 'vitest';

import { createPrismaAnalyticsRepository } from './prismaAnalyticsRepository.js';

describe('createPrismaAnalyticsRepository', () => {
  it('summarizes platform publish metrics for one user', async () => {
    const prisma = {
      platformPublish: {
        findMany: vi.fn().mockResolvedValue([
          { platform: 'TIKTOK', views: 100, likes: 10 },
          { platform: 'TIKTOK', views: 20, likes: 2 },
          { platform: 'INSTAGRAM_REELS', views: 80, likes: 8 }
        ])
      }
    };
    const repository = createPrismaAnalyticsRepository({ prisma });

    await expect(repository.summaryForUser('seller-analytics')).resolves.toEqual({
      totalViews: 200,
      totalLikes: 20,
      platforms: [
        { platform: 'TIKTOK', label: 'TikTok', views: 120, likes: 12 },
        { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 0, likes: 0 },
        { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 80, likes: 8 },
        { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
      ]
    });
    expect(prisma.platformPublish.findMany).toHaveBeenCalledWith({
      where: {
        post: {
          userId: 'seller-analytics'
        }
      },
      select: {
        platform: true,
        views: true,
        likes: true
      }
    });
  });
});
