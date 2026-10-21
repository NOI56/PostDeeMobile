import { describe, expect, it, vi } from 'vitest';
import { withPostRepositoryFixture } from '../../../test/repositoryFixtures.js';
import { createPrismaPostRepository } from './prismaPostRepository.js';

describe('single owned Prisma post read', () => {
  it('looks up the exact owner and id without scanning history', async () => {
    const row = { id: 'owned-id', userId: 'owner', caption: 'One post', videoS3Key: 'uploads/owner/v.mp4',
      selectedPlatforms: ['TIKTOK'], scheduledAt: null, publishedAt: null, status: 'PUBLISHING',
      createdAt: new Date('2026-10-21T00:00:00.000Z') };
    const findFirst = vi.fn().mockResolvedValue(row);
    const findMany = vi.fn();
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findFirst, findMany } }) });
    expect(await repository.findOwned({ postId: 'owned-id', userId: 'owner' })).toMatchObject({
      id: 'owned-id', userId: 'owner', status: 'PUBLISHING', platforms: ['TIKTOK']
    });
    expect(findFirst).toHaveBeenCalledExactlyOnceWith({ where: { id: 'owned-id', userId: 'owner' } });
    expect(findMany).not.toHaveBeenCalled();
  });

  it('returns undefined for an unavailable owned id', async () => {
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findFirst: vi.fn().mockResolvedValue(null) } }) });
    expect(await repository.findOwned({ postId: 'foreign-id', userId: 'owner' })).toBeUndefined();
  });
});
