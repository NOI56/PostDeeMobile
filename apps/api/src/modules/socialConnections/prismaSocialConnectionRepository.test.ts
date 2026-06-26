import { describe, expect, it, vi } from 'vitest';

import { createPrismaSocialConnectionRepository } from './prismaSocialConnectionRepository.js';

describe('createPrismaSocialConnectionRepository', () => {
  it('lists connected social accounts with disconnected defaults', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = {
      socialConnection: {
        findMany: vi.fn().mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'postpeer-tiktok-1',
            displayName: 'Seller TikTok',
            externalAccountId: '@seller-1',
            connectedAt
          }
        ])
      }
    };
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
        userId: 'seller-1'
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

  it('upserts a social connection by user and platform', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const prisma = {
      socialConnection: {
        upsert: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: 'Seller TikTok',
          externalAccountId: '@seller-1',
          connectedAt
        })
      }
    };
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
});
