import { describe, expect, it, vi } from 'vitest';

import { createAnalyticsStoreFromConfig } from './analyticsStoreFactory.js';

describe('createAnalyticsStoreFromConfig', () => {
  it('uses the in-memory analytics store by default', async () => {
    const store = createAnalyticsStoreFromConfig({
      config: {
        analyticsStore: 'memory'
      }
    });

    await expect(store.summaryForUser('seller-1')).resolves.toMatchObject({
      totalViews: 0,
      totalLikes: 0
    });
  });

  it('uses the Prisma analytics repository when configured', async () => {
    const prisma = {
      platformPublish: {
        findMany: vi.fn().mockResolvedValue([
          { platform: 'TIKTOK', views: 100, likes: 10 },
          { platform: 'YOUTUBE_SHORTS', views: 50, likes: 5 }
        ])
      }
    };
    const store = createAnalyticsStoreFromConfig({
      config: {
        analyticsStore: 'prisma'
      },
      prisma
    });

    await expect(store.summaryForUser('seller-1')).resolves.toMatchObject({
      totalViews: 150,
      totalLikes: 15
    });
  });

  it('requires a Prisma client when Prisma analytics is configured', () => {
    expect(() =>
      createAnalyticsStoreFromConfig({
        config: {
          analyticsStore: 'prisma'
        }
      })
    ).toThrow('Prisma analytics store requires a Prisma client');
  });
});
