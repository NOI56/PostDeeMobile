import { describe, expect, it, vi } from 'vitest';

import { createPrismaPostRepository as createRepository, type PrismaPostClient } from './prismaPostRepository.js';

const createPrismaPostRepository = ({ prisma }: { prisma: Record<string, unknown> }) => {
  const managedUploadOwner = {
    upsert: vi.fn(async () => ({ status: 'ACTIVE' as const })),
    updateMany: vi.fn(async () => ({ count: 1 }))
  };
  const transaction = { ...prisma, managedUploadOwner };
  return createRepository({ prisma: {
    ...transaction,
    $transaction: async (operation: (client: unknown) => Promise<unknown>, options: unknown) =>
      typeof prisma.$transaction === 'function'
        ? Reflect.apply(prisma.$transaction, prisma, [
            (client: Record<string, unknown>) => operation({ ...client, managedUploadOwner }), options
          ])
        : operation(transaction)
  } as unknown as PrismaPostClient });
};

describe('createPrismaPostRepository', () => {
  it('persists and reloads a separate YouTube title, omitting null legacy titles', async () => {
    const stored = {
      id: 'youtube-post', userId: 'seller-youtube', caption: 'Full description',
      youtubeTitle: 'Short title', videoS3Key: 'uploads/clip.mp4',
      selectedPlatforms: ['YOUTUBE_SHORTS'], scheduledAt: null, status: 'QUEUED',
      createdAt: new Date('2026-10-18T00:00:00.000Z')
    };
    const prisma = { post: {
      create: vi.fn().mockResolvedValue(stored),
      findMany: vi.fn().mockResolvedValue([stored, { ...stored, id: 'legacy', youtubeTitle: null }])
    } };
    const repository = createPrismaPostRepository({ prisma });

    await expect(repository.create({
      userId: stored.userId, caption: stored.caption, youtubeTitle: stored.youtubeTitle,
      videoS3Key: stored.videoS3Key, platforms: ['YOUTUBE_SHORTS']
    })).resolves.toMatchObject({ caption: 'Full description', youtubeTitle: 'Short title' });
    expect(prisma.post.create).toHaveBeenCalledWith({ data: expect.objectContaining({
      caption: 'Full description', youtubeTitle: 'Short title'
    }) });
    await expect(repository.createWithinMonthlyLimit({
      userId: stored.userId, caption: stored.caption, youtubeTitle: stored.youtubeTitle,
      videoS3Key: stored.videoS3Key, platforms: ['YOUTUBE_SHORTS'],
      monthlyPostUnitLimit: 100, now: '2026-10-18T00:00:00.000Z'
    })).resolves.toMatchObject({
      ok: true, post: { caption: 'Full description', youtubeTitle: 'Short title' }
    });
    const posts = await repository.list();
    expect(posts[0]).toMatchObject({ youtubeTitle: 'Short title' });
    expect(posts[1]).not.toHaveProperty('youtubeTitle');
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
      data: { status: 'PUBLISHING', updatedAt: expect.any(Date) }
    });
  });

  it('fails PUBLISHING posts whose claim is older than the cutoff', async () => {
    const stale = {
      id: 'stale-post', userId: 'seller-stuck', caption: 'stuck',
      videoS3Key: 'uploads/seller-stuck/a.mp4', selectedPlatforms: ['TIKTOK'],
      scheduledAt: null, status: 'PUBLISHING', publishedAt: null,
      createdAt: new Date('2026-10-26T00:00:00.000Z')
    };
    const finishedMeanwhile = { ...stale, id: 'finished-meanwhile' };
    const prisma = {
      post: {
        findMany: vi.fn().mockResolvedValue([stale, finishedMeanwhile]),
        create: vi.fn(),
        updateMany: vi.fn()
          .mockResolvedValueOnce({ count: 1 })
          .mockResolvedValueOnce({ count: 0 })
      }
    };
    const repository = createPrismaPostRepository({ prisma });
    const cutoff = new Date('2026-10-26T01:00:00.000Z');

    const recovered = await repository.recoverStalePublishing?.({
      startedBefore: cutoff.toISOString()
    });

    expect(prisma.post.findMany).toHaveBeenCalledWith({
      where: { status: 'PUBLISHING', updatedAt: { lt: cutoff } },
      orderBy: { updatedAt: 'asc' }
    });
    expect(prisma.post.updateMany).toHaveBeenCalledWith({
      where: { id: 'stale-post', status: 'PUBLISHING', updatedAt: { lt: cutoff } },
      data: { status: 'FAILED' }
    });
    expect(recovered).toEqual([
      expect.objectContaining({ id: 'stale-post', status: 'FAILED' })
    ]);
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
        caption: 'Atomic post',
        videoS3Key: 'uploads/seller-atomic/atomic.mp4',
        platforms: ['TIKTOK'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toEqual({
      ok: true,
      post: expect.objectContaining({ id: 'post-atomic', platforms: ['TIKTOK'] })
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000
    });
    expect(transactionPost.findMany).toHaveBeenCalledWith({
      where: { userId: 'seller-atomic' },
      orderBy: { createdAt: 'desc' }
    });
    expect(transactionPost.create).toHaveBeenCalledOnce();
  });

  it('retries a Prisma write conflict and returns the updated quota result', async () => {
    const existingPost = {
      id: 'post-existing',
      userId: 'seller-race',
      caption: 'Won the race',
      videoS3Key: 'uploads/seller-race/existing.mp4',
      selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'] as const,
      scheduledAt: null,
      status: 'QUEUED' as const,
      publishedAt: null,
      createdAt: new Date('2026-06-15T09:59:59.000Z')
    };
    const transactionPost = {
      findMany: vi.fn().mockResolvedValue([existingPost]),
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
        caption: 'Lost the race',
        videoS3Key: 'uploads/seller-race/loser.mp4',
        platforms: ['INSTAGRAM_REELS', 'FACEBOOK_REELS'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toEqual({ ok: false });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(transactionPost.create).not.toHaveBeenCalled();
  });
});
