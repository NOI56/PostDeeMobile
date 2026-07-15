import { describe, expect, it, vi } from 'vitest';

import {
  createPrismaSocialConnectionRepository,
  type PrismaSocialConnectionClient
} from './prismaSocialConnectionRepository.js';
import {
  PostPeerProfileOwnershipConflictError,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

const createPrisma = (
  delegate: Partial<PrismaSocialConnectionClient['socialConnection']>,
  profileDelegate: Partial<PrismaSocialConnectionClient['postPeerProfile']> = {}
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
  },
  postPeerProfile: {
    findUnique: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
      .mockResolvedValue(null),
    create: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
      .mockResolvedValue({ profileId: 'profile-1' }),
    deleteMany: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['deleteMany']>()
      .mockResolvedValue({ count: 0 }),
    ...profileDelegate
  }
});

describe('createPrismaSocialConnectionRepository', () => {
  it('lists connected social accounts with disconnected defaults', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
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
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        platform: 'TIKTOK',
        connected: true,
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1',
        connectedAt: '2026-06-26T02:00:00.000Z'
      },
      {
        platform: 'YOUTUBE_SHORTS',
        connected: false
      },
      {
        platform: 'INSTAGRAM_REELS',
        connected: false
      },
      {
        platform: 'FACEBOOK_REELS',
        connected: false
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
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('does not map unsupported Prisma platform rows into domain connections', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
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
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual(
      supportedSocialConnectionPlatforms.map((platform) => ({
        platform,
        connected: false
      }))
    );
  });

  it('upserts a social connection by user and platform', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: 'Seller TikTok',
          externalAccountId: '@seller-1',
          connectedAt,
          updatedAt
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
      postPeerAccountId: 'postpeer-tiktok-1',
      displayName: 'Seller TikTok',
      externalAccountId: '@seller-1',
      connectedAt: '2026-06-26T02:00:00.000Z',
      updatedAt: '2026-06-26T03:00:00.000Z'
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
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('normalizes empty optional metadata to null before upserting', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: null,
          externalAccountId: null,
          connectedAt,
          updatedAt
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
      postPeerAccountId: 'postpeer-tiktok-1',
      connectedAt: '2026-06-26T02:00:00.000Z',
      updatedAt: '2026-06-26T03:00:00.000Z'
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
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('omits null optional metadata returned from Prisma', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
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
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        platform: 'TIKTOK',
        connected: true,
        connectedAt: '2026-06-26T02:00:00.000Z'
      },
      {
        platform: 'YOUTUBE_SHORTS',
        connected: false
      },
      {
        platform: 'INSTAGRAM_REELS',
        connected: false
      },
      {
        platform: 'FACEBOOK_REELS',
        connected: false
      }
    ]);
  });

  it('returns whether disconnect removed a connection', async () => {
    const prisma = createPrisma({
      deleteMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['deleteMany']>()
        .mockResolvedValue({ count: 1 })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.disconnect({
        userId: 'seller-1',
        platform: 'TIKTOK'
      })
    ).resolves.toBe(true);
  });

  it('reads the stored PostPeer profile id for a user', async () => {
    const prisma = createPrisma(
      {},
      {
        findUnique: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
          .mockResolvedValue({ profileId: 'profile-1' })
      }
    );
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.getProfileId('seller-1')).resolves.toBe('profile-1');
    expect(prisma.postPeerProfile.findUnique).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: { profileId: true }
    });
  });

  it('claims the PostPeer profile id for a user', async () => {
    const prisma = createPrisma({});
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-1' })
    ).resolves.toBe('profile-1');

    expect(prisma.postPeerProfile.create).toHaveBeenCalledWith({
      data: { userId: 'seller-1', profileId: 'profile-1' },
      select: { profileId: true }
    });
  });

  it('preserves same-user PostPeer profile assignment idempotence', async () => {
    const prismaError = Object.assign(new Error('Unique constraint failed'), {
      code: 'P2002'
    });
    const create = vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
      .mockResolvedValueOnce({ profileId: 'profile-1' })
      .mockRejectedValueOnce(prismaError);
    const findUnique = vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
      .mockResolvedValue({ profileId: 'profile-1' });
    const prisma = createPrisma({}, { create, findUnique });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-1' })
    ).resolves.toBe('profile-1');
    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-race-loser' })
    ).resolves.toBe('profile-1');
    expect(create).toHaveBeenCalledTimes(2);
    expect(findUnique).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: { profileId: true }
    });
  });

  it('maps Prisma profileId unique conflicts to an ownership domain error', async () => {
    const prismaError = Object.assign(new Error('Unique constraint failed'), {
      code: 'P2002',
      meta: { target: ['profileId'] }
    });
    const prisma = createPrisma(
      {},
      {
        create: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
          .mockRejectedValue(prismaError),
        findUnique: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
          .mockResolvedValue(null)
      }
    );
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-2', profileId: 'profile-owned' })
    ).rejects.toBeInstanceOf(PostPeerProfileOwnershipConflictError);
  });
});
