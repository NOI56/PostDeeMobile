import { describe, expect, it } from 'vitest';

import { createPostStore } from './postStore.js';

describe('createPostStore', () => {
  it('keeps optional cover metadata with a queued post', async () => {
    const store = createPostStore();

    const post = await store.create({
      userId: 'seller-cover',
      caption: 'Post with a cover',
      videoS3Key: 'uploads/seller-cover/video/clip.mp4',
      coverImageS3Key: 'uploads/seller-cover/cover/cover.jpg',
      coverFrameTimeMs: 2_500,
      platforms: ['INSTAGRAM_REELS']
    });

    expect(post).toMatchObject({
      coverImageS3Key: 'uploads/seller-cover/cover/cover.jpg',
      coverFrameTimeMs: 2_500
    });
    await expect(store.list({ userId: 'seller-cover' })).resolves.toEqual([post]);
  });

  it('claims a queued post for publish only once', async () => {
    const store = createPostStore();
    const post = await store.create({
      userId: 'seller-1',
      caption: 'Queued post',
      videoS3Key: 'uploads/video.mp4',
      platforms: ['TIKTOK']
    });

    expect(
      await store.claimForPublish({
        postId: post.id,
        expectedRunAt: '2026-06-01T00:00:00.000Z'
      })
    ).toBe(true);

    const [claimedPost] = await store.list({ userId: 'seller-1' });
    expect(claimedPost.status).toBe('PUBLISHING');
    expect(
      await store.claimForPublish({
        postId: post.id,
        expectedRunAt: '2026-06-01T00:00:00.000Z'
      })
    ).toBe(false);
  });

  it('does not claim a rescheduled post from a stale queue job', async () => {
    const store = createPostStore();
    const oldRunAt = '2026-06-01T01:00:00.000Z';
    const newRunAt = '2026-06-01T02:00:00.000Z';
    const post = await store.create({
      userId: 'seller-1',
      caption: 'Scheduled post',
      videoS3Key: 'uploads/scheduled.mp4',
      platforms: ['TIKTOK'],
      scheduledAt: oldRunAt
    });

    await store.reschedule({
      postId: post.id,
      userId: 'seller-1',
      scheduledAt: newRunAt
    });

    expect(
      await store.claimForPublish({
        postId: post.id,
        expectedRunAt: oldRunAt
      })
    ).toBe(false);

    const [queuedPost] = await store.list({ userId: 'seller-1' });
    expect(queuedPost.status).toBe('QUEUED');
    expect(
      await store.claimForPublish({
        postId: post.id,
        expectedRunAt: newRunAt
      })
    ).toBe(true);
  });
});
