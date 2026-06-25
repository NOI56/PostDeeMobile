import { describe, expect, it, vi } from 'vitest';

import { createPrismaPlatformPublishRepository } from './prismaPlatformPublishRepository.js';

describe('createPrismaPlatformPublishRepository', () => {
  it('upserts published and failed platform results for a post', async () => {
    const prisma = {
      platformPublish: {
        upsert: vi.fn().mockResolvedValue({})
      }
    };
    const repository = createPrismaPlatformPublishRepository({ prisma });

    await repository.recordResults({
      postId: 'post-1',
      results: [
        {
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          externalPostId: 'tiktok-post-1',
          publishedAt: '2026-06-02T10:00:00.000Z'
        },
        {
          platform: 'YOUTUBE_SHORTS',
          status: 'FAILED',
          errorMessage: 'YouTube API unavailable'
        }
      ]
    });

    expect(prisma.platformPublish.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.platformPublish.upsert).toHaveBeenCalledWith({
      where: {
        postId_platform: {
          postId: 'post-1',
          platform: 'TIKTOK'
        }
      },
      update: {
        status: 'PUBLISHED',
        externalPostId: 'tiktok-post-1',
        errorMessage: null,
        publishedAt: new Date('2026-06-02T10:00:00.000Z')
      },
      create: {
        postId: 'post-1',
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        externalPostId: 'tiktok-post-1',
        errorMessage: null,
        publishedAt: new Date('2026-06-02T10:00:00.000Z'),
        views: 0,
        likes: 0
      }
    });
    expect(prisma.platformPublish.upsert).toHaveBeenCalledWith({
      where: {
        postId_platform: {
          postId: 'post-1',
          platform: 'YOUTUBE_SHORTS'
        }
      },
      update: {
        status: 'FAILED',
        externalPostId: null,
        errorMessage: 'YouTube API unavailable',
        publishedAt: null
      },
      create: {
        postId: 'post-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'FAILED',
        externalPostId: null,
        errorMessage: 'YouTube API unavailable',
        publishedAt: null,
        views: 0,
        likes: 0
      }
    });
  });
});
