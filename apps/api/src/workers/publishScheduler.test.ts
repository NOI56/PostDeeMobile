import { describe, expect, it, vi } from 'vitest';

import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore } from '../modules/posts/postStore.js';
import { createPublishScheduler } from './publishScheduler.js';

describe('createPublishScheduler', () => {
  it('publishes due scheduled posts and leaves future ones QUEUED', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();

    const duePost = await postStore.create({
      userId: 'seller-1',
      caption: 'due',
      videoS3Key: 'uploads/due.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      scheduledAt: new Date(Date.now() - 60_000).toISOString()
    });
    const futurePost = await postStore.create({
      userId: 'seller-1',
      caption: 'future',
      videoS3Key: 'uploads/future.mp4',
      platforms: ['TIKTOK'],
      scheduledAt: new Date(Date.now() + 3_600_000).toISOString()
    });

    const scheduler = createPublishScheduler({ postStore, platformPublishStore });
    await scheduler.runOnce();

    const posts = await postStore.list({ userId: 'seller-1' });
    const due = posts.find((post) => post.id === duePost.id);
    const future = posts.find((post) => post.id === futurePost.id);

    expect(due?.status).toBe('PUBLISHED');
    expect(due?.publishedAt).toBeDefined();
    expect(future?.status).toBe('QUEUED');
  });

  it('publishes immediate (post-now) posts on the next tick', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();

    await postStore.create({
      userId: 'seller-2',
      caption: 'now',
      videoS3Key: 'uploads/now.mp4',
      platforms: ['TIKTOK']
    });

    const scheduler = createPublishScheduler({ postStore, platformPublishStore });
    await scheduler.runOnce();

    const [post] = await postStore.list({ userId: 'seller-2' });
    expect(post.status).toBe('PUBLISHED');
  });

  it('marks a partial publish (some platforms failed) as PARTIAL_PUBLISHED, not FAILED', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();

    await postStore.create({
      userId: 'seller-partial',
      caption: 'partial',
      videoS3Key: 'uploads/partial.mp4',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
    });

    // Publisher that fails YouTube but succeeds TikTok.
    const publisher = {
      publish: async ({
        postId,
        platform
      }: {
        postId: string;
        platform: string;
      }) => {
        if (platform === 'YOUTUBE_SHORTS') {
          throw new Error('youtube down');
        }

        return {
          platform: platform as 'TIKTOK',
          status: 'PUBLISHED' as const,
          externalPostId: `tiktok-${postId}`,
          publishedAt: new Date().toISOString()
        };
      }
    };

    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      publisher
    });
    await scheduler.runOnce();

    const [post] = await postStore.list({ userId: 'seller-partial' });
    expect(post.status).toBe('PARTIAL_PUBLISHED');
    expect(post.publishedAt).toBeDefined();
  });

  it('records per-platform publish results for due posts', async () => {
    const postStore = createPostStore();
    const recorded: string[] = [];
    const platformPublishStore = {
      recordResults: async ({
        results
      }: {
        postId: string;
        results: { platform: string }[];
      }) => {
        for (const result of results) {
          recorded.push(result.platform);
        }
        return [];
      }
    };

    await postStore.create({
      userId: 'seller-3',
      caption: 'now',
      videoS3Key: 'uploads/now.mp4',
      platforms: ['TIKTOK', 'INSTAGRAM_REELS']
    });

    const scheduler = createPublishScheduler({
      postStore,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      platformPublishStore: platformPublishStore as any
    });
    await scheduler.runOnce();

    expect(recorded).toContain('TIKTOK');
    expect(recorded).toContain('INSTAGRAM_REELS');
  });

  it('retries failures before the external publisher starts with exponential backoff', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const sleep = vi.fn(async () => undefined);
    const assertOwnerActive = vi
      .fn<() => Promise<void>>()
      .mockRejectedValueOnce(new Error('database temporarily unavailable'))
      .mockRejectedValueOnce(new Error('database temporarily unavailable'))
      .mockResolvedValue(undefined);
    const publisher = {
      publish: vi.fn(async ({ postId, platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `${platform}-${postId}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };

    await postStore.create({
      userId: 'seller-preflight-retry',
      caption: 'retry safely',
      videoS3Key: 'uploads/retry.mp4',
      platforms: ['TIKTOK']
    });

    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      publisher,
      assertOwnerActive,
      maxPrePublishAttempts: 3,
      prePublishRetryBackoffMs: 100,
      sleep
    });
    await scheduler.runOnce();

    const [post] = await postStore.list({ userId: 'seller-preflight-retry' });
    expect(assertOwnerActive).toHaveBeenCalledTimes(3);
    expect(publisher.publish).toHaveBeenCalledTimes(1);
    expect(sleep).toHaveBeenNthCalledWith(1, 100);
    expect(sleep).toHaveBeenNthCalledWith(2, 200);
    expect(post.status).toBe('PUBLISHED');
  });

  it('fails a memory-scheduled post after the pre-publish retry budget is exhausted', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const sleep = vi.fn(async () => undefined);
    const assertOwnerActive = vi.fn(async () => {
      throw new Error('database unavailable');
    });
    const publisher = { publish: vi.fn() };

    await postStore.create({
      userId: 'seller-preflight-exhausted',
      caption: 'fail closed',
      videoS3Key: 'uploads/fail-closed.mp4',
      platforms: ['TIKTOK']
    });

    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      publisher: publisher as any,
      assertOwnerActive,
      maxPrePublishAttempts: 3,
      prePublishRetryBackoffMs: 100,
      sleep
    });
    await scheduler.runOnce();

    const [post] = await postStore.list({ userId: 'seller-preflight-exhausted' });
    expect(assertOwnerActive).toHaveBeenCalledTimes(3);
    expect(publisher.publish).not.toHaveBeenCalled();
    expect(sleep).toHaveBeenCalledTimes(2);
    expect(post.status).toBe('FAILED');
  });

  it('does not retry scheduler failures after an external publish call has started', async () => {
    const postStore = createPostStore();
    const sleep = vi.fn(async () => undefined);
    const publisher = {
      publish: vi.fn(async ({ postId, platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `${platform}-${postId}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };

    await postStore.create({
      userId: 'seller-no-duplicate',
      caption: 'do not duplicate',
      videoS3Key: 'uploads/no-duplicate.mp4',
      platforms: ['TIKTOK']
    });

    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore: {
        recordResults: async () => {
          throw new Error('result database unavailable');
        }
      },
      publisher,
      maxPrePublishAttempts: 3,
      prePublishRetryBackoffMs: 100,
      sleep
    });
    await scheduler.runOnce();

    const [post] = await postStore.list({ userId: 'seller-no-duplicate' });
    expect(publisher.publish).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
    expect(post.status).toBe('FAILED');
  });
});
