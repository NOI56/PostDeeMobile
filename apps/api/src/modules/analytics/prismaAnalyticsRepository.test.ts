import { describe, expect, it, vi } from 'vitest';

import { createPrismaAnalyticsRepository } from './prismaAnalyticsRepository.js';

describe('createPrismaAnalyticsRepository', () => {
  it('summarizes platform publish metrics for one user', async () => {
    const prisma = {
      platformPublish: {
        findMany: vi.fn().mockResolvedValue([
          {
            platform: 'TIKTOK',
            views: 100,
            likes: 10,
            publishedAt: new Date('2026-07-10T08:00:00.000Z'),
            createdAt: new Date('2026-07-10T07:00:00.000Z')
          },
          {
            platform: 'TIKTOK',
            views: 20,
            likes: 2,
            publishedAt: null,
            createdAt: new Date('2026-07-09T08:00:00.000Z')
          },
          {
            platform: 'INSTAGRAM_REELS',
            views: 80,
            likes: 8,
            publishedAt: new Date('2026-07-08T08:00:00.000Z'),
            createdAt: new Date('2026-07-08T07:00:00.000Z')
          }
        ])
      }
    };
    const repository = createPrismaAnalyticsRepository({ prisma });

    await expect(
      repository.summaryForUser('seller-analytics', 'year')
    ).resolves.toMatchObject({
      range: 'year',
      totalViews: 200,
      totalLikes: 20,
      daily: [
        { date: '2026-07-08', views: 80, likes: 8 },
        { date: '2026-07-09', views: 20, likes: 2 },
        { date: '2026-07-10', views: 100, likes: 10 }
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
        likes: true,
        publishedAt: true,
        createdAt: true
      }
    });
  });
});
