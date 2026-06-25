import { describe, expect, it } from 'vitest';

import { createRealClipCaptionUsageStoreFromConfig } from './captionUsageStoreFactory.js';

describe('createRealClipCaptionUsageStoreFromConfig', () => {
  it('uses the in-memory store by default', async () => {
    const store = createRealClipCaptionUsageStoreFromConfig({
      config: {
        captionUsageStore: 'memory'
      }
    });

    await store.record({
      userId: 'seller-memory',
      monthKey: '2026-06'
    });

    await expect(
      store.countForMonth({
        userId: 'seller-memory',
        monthKey: '2026-06'
      })
    ).resolves.toBe(1);
  });

  it('reserves in-memory usage only when the monthly limit has room', async () => {
    const store = createRealClipCaptionUsageStoreFromConfig({
      config: {
        captionUsageStore: 'memory'
      }
    });

    await expect(
      store.reserve({
        userId: 'seller-memory',
        monthKey: '2026-06',
        limit: 1
      })
    ).resolves.toMatchObject({
      ok: true,
      usedThisMonth: 1
    });
    await expect(
      store.reserve({
        userId: 'seller-memory',
        monthKey: '2026-06',
        limit: 1
      })
    ).resolves.toEqual({
      ok: false,
      usedThisMonth: 1
    });
  });

  it('uses Prisma when configured', async () => {
    const prisma = {
      realClipCaptionUsage: {
        count: async () => 4,
        create: async () => ({
          userId: 'seller-prisma',
          monthKey: '2026-06',
          createdAt: new Date('2026-06-14T00:00:00.000Z')
        })
      }
    };
    const store = createRealClipCaptionUsageStoreFromConfig({
      config: {
        captionUsageStore: 'prisma'
      },
      prisma
    });

    await expect(
      store.countForMonth({
        userId: 'seller-prisma',
        monthKey: '2026-06'
      })
    ).resolves.toBe(4);
  });

  it('requires a Prisma client when Prisma usage is configured', () => {
    expect(() =>
      createRealClipCaptionUsageStoreFromConfig({
        config: {
          captionUsageStore: 'prisma'
        }
      })
    ).toThrow('Prisma real-clip caption usage store requires a Prisma client');
  });
});
