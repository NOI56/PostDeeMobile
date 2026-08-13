import { describe, expect, it, vi } from 'vitest';

import { createPrismaPostRepository } from './prismaPostRepository.js';

describe('createPrismaPostRepository', () => {
  it('counts monthly units with UTC bounds and a minimal Prisma projection', async () => {
    const findMany = vi.fn().mockResolvedValue([
      {
        createdAt: new Date('2026-06-15T10:00:00.000Z'),
        selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS']
      }
    ]);
    const repository = createPrismaPostRepository({ prisma: { post: { findMany } } });

    await expect(
      repository.countMonthlyPostUnits({
        userId: 'seller-usage-query',
        now: '2026-06-30T23:59:59.000Z'
      })
    ).resolves.toBe(2);
    expect(findMany).toHaveBeenCalledWith({
      where: {
        userId: 'seller-usage-query',
        createdAt: {
          gte: new Date('2026-06-01T00:00:00.000Z'),
          lt: new Date('2026-07-01T00:00:00.000Z')
        }
      },
      select: { createdAt: true, selectedPlatforms: true }
    });
  });

  it('counts the global queued and publishing backlog in one atomic aggregate statement', async () => {
    const count = vi.fn().mockResolvedValue(5);
    const repository = createPrismaPostRepository({
      prisma: {
        post: {
          count
        }
      }
    });

    expect(await repository.countPublishBacklog()).toBe(5);
    expect(count).toHaveBeenCalledOnce();
    expect(count).toHaveBeenCalledWith({
      where: {
        status: { in: ['QUEUED', 'PUBLISHING'] }
      }
    });
  });

  it('lists posts for a user from Prisma', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const scheduledAt = new Date('2026-06-02T10:00:00.000Z');
    const prisma = {
      post: {
        findMany: vi.fn().mockResolvedValue([
          {
            id: 'post-1',
            userId: 'seller-1',
            caption: 'Stored caption',
            videoS3Key: 'uploads/video.mp4',
            selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
            scheduledAt,
            status: 'QUEUED',
            createdAt
          }
        ]),
        create: vi.fn()
      }
    };
    const repository = createPrismaPostRepository({ prisma });

    expect(await repository.list({ userId: 'seller-1' })).toEqual([
      {
        id: 'post-1',
        userId: 'seller-1',
        caption: 'Stored caption',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        scheduledAt: '2026-06-02T10:00:00.000Z',
        status: 'QUEUED',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
    expect(prisma.post.findMany).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      orderBy: { createdAt: 'desc' }
    });
  });

  it('lists scheduled posts ordered by publish time for the calendar', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const scheduledAt = new Date('2026-06-07T11:30:00.000Z');
    const prisma = {
      post: {
        findMany: vi.fn().mockResolvedValue([
          {
            id: 'post-scheduled',
            userId: 'seller-1',
            caption: 'Scheduled caption',
            videoS3Key: 'uploads/scheduled-video.mp4',
            selectedPlatforms: ['TIKTOK'],
            scheduledAt,
            status: 'QUEUED',
            createdAt
          }
        ]),
        create: vi.fn()
      }
    };
    const repository = createPrismaPostRepository({ prisma });

    expect(await repository.list({ userId: 'seller-1', scheduledOnly: true })).toEqual([
      {
        id: 'post-scheduled',
        userId: 'seller-1',
        caption: 'Scheduled caption',
        videoS3Key: 'uploads/scheduled-video.mp4',
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-07T11:30:00.000Z',
        status: 'QUEUED',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
    expect(prisma.post.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'seller-1',
        scheduledAt: {
          not: null
        }
      },
      orderBy: { scheduledAt: 'asc' }
    });
  });

  it('creates queued posts in Prisma', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const scheduledAt = new Date('2026-06-02T10:00:00.000Z');
    const prisma = {
      post: {
        findMany: vi.fn(),
        create: vi.fn().mockResolvedValue({
          id: 'post-1',
          userId: 'seller-1',
          caption: 'Stored caption',
          videoS3Key: 'uploads/video.mp4',
          coverImageS3Key: 'uploads/cover.jpg',
          coverFrameTimeMs: 1_750,
          selectedPlatforms: ['INSTAGRAM_REELS'],
          scheduledAt,
          status: 'QUEUED',
          createdAt
        })
      }
    };
    const repository = createPrismaPostRepository({ prisma });

    expect(
      await repository.create({
        userId: 'seller-1',
        caption: 'Stored caption',
        videoS3Key: 'uploads/video.mp4',
        coverImageS3Key: 'uploads/cover.jpg',
        coverFrameTimeMs: 1_750,
        platforms: ['INSTAGRAM_REELS'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
    ).toMatchObject({
      id: 'post-1',
      userId: 'seller-1',
      platforms: ['INSTAGRAM_REELS'],
      coverImageS3Key: 'uploads/cover.jpg',
      coverFrameTimeMs: 1_750,
      scheduledAt: '2026-06-02T10:00:00.000Z',
      status: 'QUEUED'
    });
    expect(prisma.post.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        caption: 'Stored caption',
        videoS3Key: 'uploads/video.mp4',
        coverImageS3Key: 'uploads/cover.jpg',
        coverFrameTimeMs: 1_750,
        selectedPlatforms: ['INSTAGRAM_REELS'],
        scheduledAt,
        status: 'QUEUED'
      }
    });
  });

  it('claims queued posts with a conditional Prisma update', async () => {
    const prisma = {
      post: {
        findMany: vi.fn(),
        create: vi.fn(),
        updateMany: vi.fn().mockResolvedValue({ count: 1 })
      }
    };
    const repository = createPrismaPostRepository({ prisma });

    expect(
      await repository.claimForPublish({
        postId: 'post-1',
        expectedRunAt: '2026-06-01T01:00:00.000Z'
      })
    ).toBe(true);
    expect(prisma.post.updateMany).toHaveBeenCalledWith({
      where: {
        id: 'post-1',
        status: 'QUEUED',
        OR: [
          { scheduledAt: null },
          { scheduledAt: new Date('2026-06-01T01:00:00.000Z') }
        ]
      },
      data: { status: 'PUBLISHING' }
    });
  });

  it('does not claim posts that are no longer queued', async () => {
    const prisma = {
      post: {
        findMany: vi.fn(),
        create: vi.fn(),
        updateMany: vi.fn().mockResolvedValue({ count: 0 })
      }
    };
    const repository = createPrismaPostRepository({ prisma });

    expect(
      await repository.claimForPublish({
        postId: 'post-1',
        expectedRunAt: '2026-06-01T01:00:00.000Z'
      })
    ).toBe(false);
  });

  it('checks monthly units and creates inside a serializable transaction', async () => {
    const createdAt = new Date('2026-06-15T10:00:00.000Z');
    const createdPost = {
      id: 'post-atomic',
      userId: 'seller-atomic',
      caption: 'Atomic post',
      videoS3Key: 'uploads/seller-atomic/atomic.mp4',
      selectedPlatforms: ['TIKTOK'] as const,
      scheduledAt: null,
      status: 'QUEUED' as const,
      publishedAt: null,
      createdAt
    };
    const transactionPost = {
      findFirst: vi.fn().mockResolvedValue(null),
      findMany: vi.fn().mockResolvedValue([]),
      create: vi.fn().mockResolvedValue(createdPost)
    };
    const prisma = {
      post: transactionPost,
      $transaction: vi.fn(async (operation: (client: unknown) => Promise<unknown>) =>
        operation({ post: transactionPost })
      )
    };
    const repository = createPrismaPostRepository({ prisma });

    await expect(
      repository.createWithinMonthlyLimit({
        userId: 'seller-atomic',
        clientRequestId: 'atomic-request',
        caption: 'Atomic post',
        videoS3Key: 'uploads/seller-atomic/atomic.mp4',
        platforms: ['TIKTOK'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toEqual({
      ok: true,
      created: true,
      post: expect.objectContaining({ id: 'post-atomic', platforms: ['TIKTOK'] })
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable'
    });
    expect(transactionPost.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'seller-atomic',
        createdAt: {
          gte: new Date('2026-06-01T00:00:00.000Z'),
          lt: new Date('2026-07-01T00:00:00.000Z')
        }
      },
      select: { createdAt: true, selectedPlatforms: true }
    });
  });

  it('returns an idempotent replay before quota counting in the same serializable transaction', async () => {
    const persisted = {
      id: 'post_idem_existing',
      userId: 'seller-replay',
      caption: 'Original intent',
      videoS3Key: 'uploads/seller-replay/original.mp4',
      selectedPlatforms: ['TIKTOK'] as const,
      scheduledAt: null,
      status: 'QUEUED' as const,
      publishedAt: null,
      createdAt: new Date('2026-06-15T09:00:00.000Z')
    };
    const transactionPost = {
      findFirst: vi.fn().mockResolvedValue(persisted),
      findMany: vi.fn(),
      create: vi.fn()
    };
    const prisma = {
      post: transactionPost,
      $transaction: vi.fn(async (operation: (client: unknown) => Promise<unknown>) =>
        operation({ post: transactionPost })
      )
    };
    const repository = createPrismaPostRepository({ prisma });

    await expect(
      repository.createWithinMonthlyLimit({
        userId: persisted.userId,
        clientRequestId: 'same-request',
        caption: persisted.caption,
        videoS3Key: 'uploads/seller-replay/retry-upload.mp4',
        platforms: ['TIKTOK'],
        monthlyPostUnitLimit: 0,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toMatchObject({
      ok: true,
      created: false,
      post: {
        id: persisted.id,
        userId: persisted.userId,
        caption: persisted.caption,
        platforms: ['TIKTOK'],
        createdAt: persisted.createdAt.toISOString()
      }
    });
    expect(transactionPost.findMany).not.toHaveBeenCalled();
    expect(transactionPost.create).not.toHaveBeenCalled();
  });

  it('retries a duplicate-key race and then returns the committed idempotent post', async () => {
    const persisted = {
      id: 'post_idem_race_winner',
      userId: 'seller-idempotent-race',
      caption: 'One durable post',
      videoS3Key: 'uploads/seller-idempotent-race/original.mp4',
      selectedPlatforms: ['TIKTOK'] as const,
      scheduledAt: null,
      status: 'QUEUED' as const,
      publishedAt: null,
      createdAt: new Date('2026-06-15T09:00:00.000Z')
    };
    const firstPost = {
      findFirst: vi.fn().mockResolvedValue(null),
      findMany: vi.fn().mockResolvedValue([]),
      create: vi.fn().mockRejectedValue(Object.assign(new Error('duplicate'), { code: 'P2002' }))
    };
    const secondPost = {
      findFirst: vi.fn().mockResolvedValue(persisted),
      findMany: vi.fn(),
      create: vi.fn()
    };
    const prisma = {
      post: firstPost,
      $transaction: vi
        .fn()
        .mockImplementationOnce((operation: (client: unknown) => Promise<unknown>) =>
          operation({ post: firstPost })
        )
        .mockImplementationOnce((operation: (client: unknown) => Promise<unknown>) =>
          operation({ post: secondPost })
        )
    };
    const repository = createPrismaPostRepository({ prisma });

    await expect(
      repository.createWithinMonthlyLimit({
        userId: persisted.userId,
        clientRequestId: 'same-race',
        caption: persisted.caption,
        videoS3Key: 'uploads/seller-idempotent-race/retry.mp4',
        platforms: ['TIKTOK'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toMatchObject({ ok: true, created: false });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(secondPost.findMany).not.toHaveBeenCalled();
  });

  it('retries a Prisma write conflict before rechecking quota', async () => {
    const transactionPost = {
      findFirst: vi.fn().mockResolvedValue(null),
      findMany: vi.fn().mockResolvedValue([
        {
          id: 'existing',
          userId: 'seller-race',
          caption: 'Existing',
          videoS3Key: 'uploads/existing.mp4',
          selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
          scheduledAt: null,
          status: 'QUEUED',
          publishedAt: null,
          createdAt: new Date('2026-06-15T09:00:00.000Z')
        }
      ]),
      create: vi.fn()
    };
    const conflict = Object.assign(new Error('write conflict'), { code: 'P2034' });
    const prisma = {
      post: transactionPost,
      $transaction: vi
        .fn()
        .mockRejectedValueOnce(conflict)
        .mockImplementationOnce((operation: (client: unknown) => Promise<unknown>) =>
          operation({ post: transactionPost })
        )
    };
    const repository = createPrismaPostRepository({ prisma });

    await expect(
      repository.createWithinMonthlyLimit({
        userId: 'seller-race',
        clientRequestId: 'race-request',
        caption: 'Lost race',
        videoS3Key: 'uploads/lost.mp4',
        platforms: ['INSTAGRAM_REELS', 'FACEBOOK_REELS'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toEqual({ ok: false });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(transactionPost.create).not.toHaveBeenCalled();
  });
});
