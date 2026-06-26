import { describe, expect, it, vi } from 'vitest';

import {
  createPrismaSocialConnectionRepository,
  type PrismaSocialConnectionClient
} from './prismaSocialConnectionRepository.js';
import { supportedSocialConnectionPlatforms } from './socialConnectionStore.js';

const createPrisma = (
  delegate: Partial<PrismaSocialConnectionClient['socialConnection']>
): PrismaSocialConnectionClient => ({
  socialConnection: {
    findMany: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
      .mockResolvedValue([]),
    findUnique: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['findUnique']>()
      .mockResolvedValue(null),
    upsert: vi.fn<PrismaSocialConnectionClient['socialConnection']['upsert']>(),
    deleteMany: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['deleteMany']>()
      .mockResolvedValue({ count: 0 }),
    ...delegate
  }
});

describe('createPrismaSocialConnectionRepository', () => {
  it('lists connected social accounts with disconnected defaults', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'postpeer-tiktok-1',
            displayName: 'Seller TikTok',
            externalAccountId: '@seller-1',
            connectedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        userId: 'seller-1',
        platform: 'TIKTOK',
        status: 'CONNECTED',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1',
        connectedAt: '2026-06-26T02:00:00.000Z'
      },
      {
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
      }
    ]);
    expect(prisma.socialConnection.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'seller-1',
        platform: {
          in: supportedSocialConnectionPlatforms
        }
      },
      select: {
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true
      }
    });
  });

  it('does not map unsupported Prisma platform rows into domain connections', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'SHOPEE_VIDEO',
            postPeerAccountId: 'postpeer-shopee-1',
            displayName: 'Seller Shopee',
            externalAccountId: 'seller-shopee',
            connectedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        userId: 'seller-1',
        platform: 'TIKTOK',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
      }
    ]);
  });

  it('upserts a social connection by user and platform', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: 'Seller TikTok',
          externalAccountId: '@seller-1',
          connectedAt
        })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.upsert({
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      platform: 'TIKTOK',
      status: 'CONNECTED',
      postPeerAccountId: 'postpeer-tiktok-1',
      displayName: 'Seller TikTok',
      externalAccountId: '@seller-1',
      connectedAt: '2026-06-26T02:00:00.000Z'
    });
    expect(prisma.socialConnection.upsert).toHaveBeenCalledWith({
      where: {
        userId_platform: {
          userId: 'seller-1',
          platform: 'TIKTOK'
        }
      },
      update: {
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      },
      create: {
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      },
      select: {
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true
      }
    });
  });

  it('normalizes empty optional metadata to null before upserting', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: null,
          externalAccountId: null,
          connectedAt
        })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.upsert({
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: '',
        externalAccountId: '   '
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      platform: 'TIKTOK',
      status: 'CONNECTED',
      postPeerAccountId: 'postpeer-tiktok-1',
      connectedAt: '2026-06-26T02:00:00.000Z'
    });
    expect(prisma.socialConnection.upsert).toHaveBeenCalledWith({
      where: {
        userId_platform: {
          userId: 'seller-1',
          platform: 'TIKTOK'
        }
      },
      update: {
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: null,
        externalAccountId: null
      },
      create: {
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: null,
        externalAccountId: null
      },
      select: {
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true
      }
    });
  });

  it('omits null optional metadata returned from Prisma', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'postpeer-tiktok-1',
            displayName: null,
            externalAccountId: null,
            connectedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        userId: 'seller-1',
        platform: 'TIKTOK',
        status: 'CONNECTED',
        postPeerAccountId: 'postpeer-tiktok-1',
        connectedAt: '2026-06-26T02:00:00.000Z'
      },
      {
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
      }
    ]);
  });
});
