import { describe, expect, it } from 'vitest';

import { createInMemoryPlatformPublishStore } from './platformPublishStore.js';

describe('createInMemoryPlatformPublishStore', () => {
  it('records platform publish results with zero analytics metrics by default', async () => {
    const store = createInMemoryPlatformPublishStore();

    await expect(
      store.recordResults({
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
      })
    ).resolves.toEqual([
      {
        postId: 'post-1',
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        externalPostId: 'tiktok-post-1',
        publishedAt: '2026-06-02T10:00:00.000Z',
        views: 0,
        likes: 0
      },
      {
        postId: 'post-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'FAILED',
        errorMessage: 'YouTube API unavailable',
        views: 0,
        likes: 0
      }
    ]);
  });
});
