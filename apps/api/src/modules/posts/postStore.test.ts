import { describe, expect, it } from 'vitest';

import {
  PostIdempotencyKeyReusedError,
  createPostStore
} from './postStore.js';

describe('createPostStore', () => {
  it('counts monthly platform units through the dedicated bounded usage API', async () => {
    const store = createPostStore();
    await store.createWithinMonthlyLimit({
      userId: 'seller-monthly-usage',
      caption: 'June units',
      videoS3Key: 'uploads/seller-monthly-usage/june.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      monthlyPostUnitLimit: 10,
      now: '2026-06-30T23:59:59.000Z'
    });
    await store.createWithinMonthlyLimit({
      userId: 'seller-monthly-usage',
      caption: 'July units',
      videoS3Key: 'uploads/seller-monthly-usage/july.mp4',
      platforms: ['INSTAGRAM_REELS'],
      monthlyPostUnitLimit: 10,
      now: '2026-07-01T00:00:00.000Z'
    });

    await expect(
      store.countMonthlyPostUnits({
        userId: 'seller-monthly-usage',
        now: '2026-06-15T10:00:00.000Z'
      })
    ).resolves.toBe(2);
  });

  it('checks monthly units and creates atomically for concurrent requests', async () => {
    const store = createPostStore();
    const createPost = (suffix: string) =>
      store.createWithinMonthlyLimit({
        userId: 'seller-concurrent',
        caption: `Concurrent ${suffix}`,
        videoS3Key: `uploads/seller-concurrent/${suffix}.mp4`,
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        monthlyPostUnitLimit: 3,
        now: '2026-06-15T10:00:00.000Z'
      });

    const results = await Promise.all([createPost('a'), createPost('b')]);

    expect(results.filter((result) => result.ok)).toHaveLength(1);
    expect(results.filter((result) => !result.ok)).toHaveLength(1);
    await expect(store.list({ userId: 'seller-concurrent' })).resolves.toHaveLength(1);
  });

  it('replays the same client request inside the atomic quota operation without charging twice', async () => {
    const store = createPostStore();
    const input = {
      userId: 'seller-idempotent',
      clientRequestId: 'draft-123',
      caption: 'โพสต์ครั้งเดียว',
      videoS3Key: 'uploads/seller-idempotent/video.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'] as const,
      monthlyPostUnitLimit: 2,
      now: '2026-06-15T10:00:00.000Z'
    };

    const first = await store.createWithinMonthlyLimit(input);
    const replay = await store.createWithinMonthlyLimit({
      ...input,
      videoS3Key: 'uploads/seller-idempotent/retry-upload.mp4',
      monthlyPostUnitLimit: 0
    });

    expect(first).toMatchObject({ ok: true, created: true });
    expect(replay).toMatchObject({
      ok: true,
      created: false,
      post: { id: first.ok ? first.post.id : '' }
    });
    await expect(store.list({ userId: input.userId })).resolves.toHaveLength(1);
  });

  it('rejects reusing a client request id for a different publishing intent', async () => {
    const store = createPostStore();
    const input = {
      userId: 'seller-intent-conflict',
      clientRequestId: 'draft-conflict',
      caption: 'Original caption',
      videoS3Key: 'uploads/seller-intent-conflict/video.mp4',
      platforms: ['TIKTOK'] as const,
      monthlyPostUnitLimit: 3,
      now: '2026-06-15T10:00:00.000Z'
    };

    await store.createWithinMonthlyLimit(input);
    await expect(
      store.createWithinMonthlyLimit({ ...input, caption: 'Changed caption' })
    ).rejects.toBeInstanceOf(PostIdempotencyKeyReusedError);
  });

  it('reports one aggregate queued-or-publishing backlog total', async () => {
    const store = createPostStore();
    const queued = await store.create({
      userId: 'seller-queued',
      caption: 'queued',
      videoS3Key: 'uploads/queued.mp4',
      platforms: ['YOUTUBE_SHORTS']
    });
    const publishing = await store.create({
      userId: 'seller-publishing',
      caption: 'publishing',
      videoS3Key: 'uploads/publishing.mp4',
      platforms: ['YOUTUBE_SHORTS']
    });

    await store.claimForPublish({
      postId: publishing.id,
      expectedRunAt: publishing.scheduledAt ?? publishing.createdAt
    });
    await store.updateStatus({ postId: queued.id, status: 'FAILED' });
    await store.create({
      userId: 'seller-still-queued',
      caption: 'future queued',
      videoS3Key: 'uploads/future.mp4',
      platforms: ['YOUTUBE_SHORTS'],
      scheduledAt: '2030-01-01T00:00:00.000Z'
    });

    expect(await store.countPublishBacklog()).toBe(2);
  });

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
      expectedScheduledAt: oldRunAt,
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

  it('uses compare-and-set schedule transitions for compensation and publish-now', async () => {
    const store = createPostStore();
    const originalRunAt = '2026-06-02T10:00:00.000Z';
    const replacementRunAt = '2026-06-03T10:00:00.000Z';
    const post = await store.create({
      userId: 'seller-transition',
      caption: 'Race-safe transition',
      videoS3Key: 'uploads/seller-transition/video.mp4',
      platforms: ['TIKTOK'],
      scheduledAt: originalRunAt
    });

    await expect(
      store.reschedule({
        postId: post.id,
        userId: post.userId,
        expectedScheduledAt: originalRunAt,
        scheduledAt: replacementRunAt
      })
    ).resolves.toMatchObject({ scheduledAt: replacementRunAt });
    await expect(
      store.reschedule({
        postId: post.id,
        userId: post.userId,
        expectedScheduledAt: originalRunAt,
        scheduledAt: '2026-06-04T10:00:00.000Z'
      })
    ).resolves.toBeUndefined();

    const readyPost = await store.publishNow({
      postId: post.id,
      userId: post.userId,
      expectedScheduledAt: replacementRunAt
    });
    expect(readyPost).toMatchObject({ id: post.id });
    expect(readyPost?.scheduledAt).toBeUndefined();
  });
});
