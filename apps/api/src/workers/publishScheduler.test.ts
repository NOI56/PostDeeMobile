import { describe, expect, it, vi } from 'vitest';

import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore } from '../modules/posts/postStore.js';
import { createPublishScheduler } from './publishScheduler.js';
import type { PlatformPublishInput, PlatformPublisher } from './publishWorker.js';

const createBlockingPublisher = () => {
  const releases = new Map<string, () => void>();
  const started: string[] = [];
  const publisher: PlatformPublisher = {
    publish: vi.fn(async ({ postId, platform }: PlatformPublishInput) => {
      started.push(postId);
      await new Promise<void>((resolve) => releases.set(postId, resolve));
      return {
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `tiktok-${postId}`,
        publishedAt: '2026-10-26T01:00:00.000Z'
      };
    })
  };
  const release = (postId: string) => releases.get(postId)?.();
  return { publisher, started, release };
};

const flushAsync = async () => {
  for (let index = 0; index < 20; index += 1) {
    await Promise.resolve();
  }
};

describe('createPublishScheduler', () => {
  it('reports finished posts as settled but not posts skipped by a lost claim', async () => {
    const postStore = createPostStore();
    const published = await postStore.create({
      userId: 'seller-settled', caption: 'published', videoS3Key: 'uploads/seller-settled/a.mp4',
      platforms: ['TIKTOK']
    });
    const skipped = await postStore.create({
      userId: 'seller-settled', caption: 'rescheduled meanwhile',
      videoS3Key: 'uploads/seller-settled/b.mp4', platforms: ['TIKTOK']
    });
    const onPostSettled = vi.fn(async () => undefined);

    await createPublishScheduler({
      postStore: {
        ...postStore,
        claimForPublish: async (input) =>
          input.postId === skipped.id ? false : postStore.claimForPublish(input)
      },
      platformPublishStore: createInMemoryPlatformPublishStore(),
      onPostSettled
    }).runOnce();

    expect(onPostSettled.mock.calls).toEqual([[published.id]]);
  });

  it('publishes due posts concurrently up to the configured limit', async () => {
    const postStore = createPostStore();
    const { publisher, started, release } = createBlockingPublisher();
    const posts = [];
    for (const caption of ['one', 'two', 'three']) {
      posts.push(await postStore.create({
        userId: 'seller-concurrent', caption, videoS3Key: `uploads/seller-concurrent/${caption}.mp4`,
        platforms: ['TIKTOK']
      }));
    }

    const run = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher,
      maxConcurrentPublishes: 2
    }).runOnce();
    await flushAsync();

    expect(started).toHaveLength(2);
    release(started[0]);
    await flushAsync();
    expect(started).toHaveLength(3);
    for (const postId of started) release(postId);
    await run;

    const statuses = (await postStore.list({ userId: 'seller-concurrent' })).map((post) => post.status);
    expect(statuses).toEqual(['PUBLISHED', 'PUBLISHED', 'PUBLISHED']);
  });

  it('does not let a slow publish block posts that become due on a later tick', async () => {
    const postStore = createPostStore();
    const { publisher, started, release } = createBlockingPublisher();
    const slow = await postStore.create({
      userId: 'seller-slow', caption: 'slow', videoS3Key: 'uploads/seller-slow/slow.mp4',
      platforms: ['TIKTOK']
    });
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher
    });

    const firstTick = scheduler.runOnce();
    await flushAsync();
    const later = await postStore.create({
      userId: 'seller-slow', caption: 'later', videoS3Key: 'uploads/seller-slow/later.mp4',
      platforms: ['TIKTOK']
    });
    const secondTick = scheduler.runOnce();
    await flushAsync();

    expect(started).toEqual([slow.id, later.id]);
    release(later.id);
    await secondTick;
    const statuses = Object.fromEntries(
      (await postStore.list({ userId: 'seller-slow' })).map((post) => [post.id, post.status])
    );
    expect(statuses).toEqual({ [slow.id]: 'PUBLISHING', [later.id]: 'PUBLISHED' });

    release(slow.id);
    await firstTick;
  });

  it('never starts the same post twice from overlapping ticks', async () => {
    const postStore = createPostStore();
    const { publisher, started, release } = createBlockingPublisher();
    const post = await postStore.create({
      userId: 'seller-overlap', caption: 'once', videoS3Key: 'uploads/seller-overlap/once.mp4',
      platforms: ['TIKTOK']
    });
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher
    });

    const ticks = [scheduler.runOnce(), scheduler.runOnce(), scheduler.runOnce()];
    await flushAsync();
    release(post.id);
    await Promise.all(ticks);

    expect(started).toEqual([post.id]);
  });

  it('fails posts left in PUBLISHING by a crashed run and notifies the owner', async () => {
    const claimedAt = new Date('2026-10-26T01:00:00.000Z');
    const postStore = createPostStore({ now: () => claimedAt });
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const publisher = { publish: vi.fn() };
    const notifier = { notifyPublishResult: vi.fn(async () => undefined) };
    const post = await postStore.create({
      userId: 'seller-crashed', caption: 'crashed mid publish',
      videoS3Key: 'uploads/seller-crashed/clip.mp4', platforms: ['TIKTOK', 'INSTAGRAM_REELS']
    });
    await postStore.claimForPublish({ postId: post.id, expectedRunAt: claimedAt.toISOString() });

    await createPublishScheduler({
      postStore, platformPublishStore, publisher, notifier,
      now: () => '2026-10-26T01:31:00.000Z'
    }).runOnce();

    const [stored] = await postStore.list({ userId: 'seller-crashed' });
    expect(stored.status).toBe('FAILED');
    expect(publisher.publish).not.toHaveBeenCalled();
    expect(await platformPublishStore.listForPostIds([post.id])).toEqual([
      expect.objectContaining({
        platform: 'TIKTOK', status: 'FAILED',
        errorMessage: 'Publishing result could not be confirmed. Check the platform before trying again.'
      }),
      expect.objectContaining({ platform: 'INSTAGRAM_REELS', status: 'FAILED' })
    ]);
    expect(notifier.notifyPublishResult).toHaveBeenCalledWith({
      userId: 'seller-crashed', postId: post.id, outcome: 'FAILED'
    });
  });

  it('keeps platform results that were saved before the crash', async () => {
    const claimedAt = new Date('2026-10-26T01:00:00.000Z');
    const postStore = createPostStore({ now: () => claimedAt });
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const post = await postStore.create({
      userId: 'seller-partial-crash', caption: 'saved one result',
      videoS3Key: 'uploads/seller-partial-crash/clip.mp4', platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
    });
    await postStore.claimForPublish({ postId: post.id, expectedRunAt: claimedAt.toISOString() });
    await platformPublishStore.recordResults({
      postId: post.id,
      results: [{
        platform: 'TIKTOK', status: 'PUBLISHED', externalPostId: 'tiktok-1',
        publishedAt: '2026-10-26T01:02:00.000Z'
      }]
    });

    await createPublishScheduler({
      postStore, platformPublishStore, now: () => '2026-10-26T01:31:00.000Z'
    }).runOnce();

    expect(await platformPublishStore.listForPostIds([post.id])).toEqual([
      expect.objectContaining({ platform: 'TIKTOK', status: 'PUBLISHED', externalPostId: 'tiktok-1' }),
      expect.objectContaining({ platform: 'YOUTUBE_SHORTS', status: 'FAILED' })
    ]);
  });

  it('leaves a recently claimed PUBLISHING post to its running worker', async () => {
    const claimedAt = new Date('2026-10-26T01:00:00.000Z');
    const postStore = createPostStore({ now: () => claimedAt });
    const notifier = { notifyPublishResult: vi.fn(async () => undefined) };
    const post = await postStore.create({
      userId: 'seller-in-flight', caption: 'still publishing',
      videoS3Key: 'uploads/seller-in-flight/clip.mp4', platforms: ['TIKTOK']
    });
    await postStore.claimForPublish({ postId: post.id, expectedRunAt: claimedAt.toISOString() });

    await createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), notifier,
      now: () => '2026-10-26T01:05:00.000Z'
    }).runOnce();

    const [stored] = await postStore.list({ userId: 'seller-in-flight' });
    expect(stored.status).toBe('PUBLISHING');
    expect(notifier.notifyPublishResult).not.toHaveBeenCalled();
  });

  it('sweeps stale PUBLISHING posts at most once per sweep interval', async () => {
    let currentTime = '2026-10-26T01:00:00.000Z';
    const postStore = createPostStore();
    const recoverStalePublishing = vi.fn(async () => []);
    const scheduler = createPublishScheduler({
      postStore: { ...postStore, recoverStalePublishing },
      platformPublishStore: createInMemoryPlatformPublishStore(),
      now: () => currentTime
    });

    await scheduler.runOnce();
    currentTime = '2026-10-26T01:00:30.000Z';
    await scheduler.runOnce();
    currentTime = '2026-10-26T01:01:00.000Z';
    await scheduler.runOnce();

    expect(recoverStalePublishing.mock.calls).toEqual([
      [{ startedBefore: '2026-10-26T00:30:00.000Z' }],
      [{ startedBefore: '2026-10-26T00:31:00.000Z' }]
    ]);
  });

  it('keeps publishing due posts when the stale sweep fails', async () => {
    const postStore = createPostStore();
    await postStore.create({
      userId: 'seller-sweep-down', caption: 'publish anyway',
      videoS3Key: 'uploads/seller-sweep-down/clip.mp4', platforms: ['TIKTOK']
    });

    await createPublishScheduler({
      postStore: {
        ...postStore,
        recoverStalePublishing: async () => {
          throw new Error('database unavailable');
        }
      },
      platformPublishStore: createInMemoryPlatformPublishStore()
    }).runOnce();

    const [stored] = await postStore.list({ userId: 'seller-sweep-down' });
    expect(stored.status).toBe('PUBLISHED');
  });

  it('passes a scheduled YouTube title separately from its caption', async () => {
    const postStore = createPostStore();
    const publisher = { publish: vi.fn(async ({ platform }) => ({
      platform, status: 'PUBLISHED' as const, externalPostId: 'youtube-1',
      publishedAt: '2026-10-18T00:00:00.000Z'
    })) };
    await postStore.create({
      userId: 'seller-youtube', caption: 'Full description', youtubeTitle: 'Short title',
      videoS3Key: 'uploads/clip.mp4', platforms: ['YOUTUBE_SHORTS'],
      scheduledAt: '2026-10-17T00:00:00.000Z'
    });
    await createPublishScheduler({
      postStore, publisher, platformPublishStore: createInMemoryPlatformPublishStore()
    }).runOnce();

    expect(publisher.publish).toHaveBeenCalledWith(expect.objectContaining({
      caption: 'Full description', youtubeTitle: 'Short title', platform: 'YOUTUBE_SHORTS'
    }));
  });

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

  it('passes cover metadata from memory-scheduled posts to the publisher', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const publisher = {
      publish: vi.fn(async ({ postId, platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `${platform}-${postId}`,
        publishedAt: '2026-07-16T00:00:00.000Z'
      }))
    };

    await postStore.create({
      userId: 'seller-cover-memory',
      caption: 'Memory cover',
      videoS3Key: 'uploads/seller-cover-memory/video/clip.mp4',
      coverImageS3Key: 'uploads/seller-cover-memory/cover/cover.jpg',
      coverFrameTimeMs: 0,
      platforms: ['INSTAGRAM_REELS']
    });

    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      publisher
    });
    await scheduler.runOnce();

    expect(publisher.publish).toHaveBeenCalledWith(
      expect.objectContaining({
        coverImageS3Key: 'uploads/seller-cover-memory/cover/cover.jpg',
        coverFrameTimeMs: 0,
        platform: 'INSTAGRAM_REELS'
      })
    );
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
