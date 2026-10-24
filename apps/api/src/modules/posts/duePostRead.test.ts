import { describe, expect, it, vi } from 'vitest';
import { withPostRepositoryFixture } from '../../../test/repositoryFixtures.js';
import { createPostStore, maxDuePostsPerPoll } from './postStore.js';
import { createPrismaPostRepository } from './prismaPostRepository.js';

const dueRow = (id: string) => ({
  id, userId: 'owner', caption: 'Due post', videoS3Key: `uploads/owner/${id}.mp4`,
  coverImageS3Key: null, coverFrameTimeMs: null, selectedPlatforms: ['TIKTOK'],
  platformSettings: null, platformTargets: null, scheduledAt: new Date('2026-10-24T00:00:00.000Z'),
  status: 'QUEUED', publishedAt: null, createdAt: new Date('2026-10-23T00:00:00.000Z')
});

describe('due post read for the publish scheduler', () => {
  it('reads a bounded batch with only the publish fields', async () => {
    const findMany = vi.fn().mockResolvedValue([dueRow('due-1')]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });

    const due = await repository.listDue({ now: '2026-10-24T01:00:00.000Z' });

    expect(due).toEqual([expect.objectContaining({ id: 'due-1', platforms: ['TIKTOK'], status: 'QUEUED' })]);
    expect(findMany).toHaveBeenCalledExactlyOnceWith({
      where: {
        status: 'QUEUED',
        OR: [{ scheduledAt: null }, { scheduledAt: { lte: new Date('2026-10-24T01:00:00.000Z') } }]
      },
      orderBy: { id: 'asc' },
      take: maxDuePostsPerPoll,
      select: {
        id: true, userId: true, caption: true, videoS3Key: true, coverImageS3Key: true,
        coverFrameTimeMs: true, selectedPlatforms: true, platformSettings: true,
        platformTargets: true, scheduledAt: true, status: true, publishedAt: true, createdAt: true
      }
    });
  });

  it('honours a smaller explicit batch size', async () => {
    const findMany = vi.fn().mockResolvedValue([]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });

    await repository.listDue({ now: '2026-10-24T01:00:00.000Z', limit: 5 });

    expect(findMany).toHaveBeenCalledWith(expect.objectContaining({ take: 5 }));
  });

  it('resumes after the last post the scheduler tried', async () => {
    const findMany = vi.fn().mockResolvedValue([]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });

    await repository.listDue({ now: '2026-10-24T01:00:00.000Z', afterId: 'tried-2' });

    expect(findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ id: { gt: 'tried-2' }, status: 'QUEUED' }),
      orderBy: { id: 'asc' }
    }));
  });

  it('claims an ended-plan post only while it is still scheduled at its run time', async () => {
    const updateMany = vi.fn().mockResolvedValue({ count: 0 });
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { updateMany } }) });

    await expect(repository.claimForPublish({
      postId: 'post-1', expectedRunAt: '2026-10-24T00:00:00.000Z', requireSchedule: true
    })).resolves.toBe(false);

    expect(updateMany).toHaveBeenCalledExactlyOnceWith({
      where: { id: 'post-1', status: 'QUEUED', scheduledAt: new Date('2026-10-24T00:00:00.000Z') },
      data: { status: 'PUBLISHING' }
    });
  });

  it('bounds the in-memory store the same way', async () => {
    const store = createPostStore();
    for (let index = 0; index < maxDuePostsPerPoll + 3; index += 1) {
      await store.create({
        userId: `owner-${index}`, caption: `Post ${index}`, videoS3Key: `uploads/owner-${index}/v.mp4`,
        platforms: ['TIKTOK']
      });
    }

    expect(await store.listDue({ now: '2099-01-01T00:00:00.000Z' })).toHaveLength(maxDuePostsPerPoll);
    expect(await store.listDue({ now: '2099-01-01T00:00:00.000Z', limit: 2 })).toHaveLength(2);
  });
});
