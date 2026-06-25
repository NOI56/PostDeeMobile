import { describe, expect, it, vi } from 'vitest';

import { createPrismaPostRepository } from './prismaPostRepository.js';

describe('createPrismaPostRepository', () => {
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
        platforms: ['INSTAGRAM_REELS'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
    ).toMatchObject({
      id: 'post-1',
      userId: 'seller-1',
      platforms: ['INSTAGRAM_REELS'],
      scheduledAt: '2026-06-02T10:00:00.000Z',
      status: 'QUEUED'
    });
    expect(prisma.post.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        caption: 'Stored caption',
        videoS3Key: 'uploads/video.mp4',
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
});
