import { describe, expect, it, vi } from 'vitest';
import type { RunWithActiveOwner } from '../modules/account/ownerOperationQueue.js';

import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore } from '../modules/posts/postStore.js';
import { createPublishScheduler } from './publishScheduler.js';
import { PublishOutcomeUnknownError, type PlatformPublishInput } from './publishWorker.js';

describe('createPublishScheduler', () => {
  it('publishes due posts concurrently up to the configured limit', async () => {
    const postStore = createPostStore();
    const releases = new Map<string, () => void>();
    const started: string[] = [];
    const publisher = {
      publish: vi.fn(async ({ postId, platform }: PlatformPublishInput) => {
        started.push(postId);
        await new Promise<void>((resolve) => releases.set(postId, resolve));
        return {
          platform, status: 'PUBLISHED' as const, deliveryOutcome: 'LIVE' as const,
          publishedAt: '2026-10-27T00:00:00.000Z'
        };
      })
    };
    for (const caption of ['one', 'two', 'three']) {
      await postStore.create({
        userId: `seller-concurrent-${caption}`, caption,
        videoS3Key: `uploads/seller-concurrent/${caption}.mp4`, platforms: ['TIKTOK']
      });
    }
    const flush = async () => {
      for (let index = 0; index < 50; index += 1) await Promise.resolve();
    };

    const run = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher,
      maxConcurrentPublishes: 2
    }).runOnce();
    await flush();

    expect(started).toHaveLength(2);
    releases.get(started[0])?.();
    await flush();
    expect(started).toHaveLength(3);
    for (const postId of started) releases.get(postId)?.();
    await run;

    const statuses = (await postStore.listDue({ now: '2099-01-01T00:00:00.000Z' }));
    expect(statuses).toEqual([]);
  });

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

  it('reports a post settled once pre-publish retries end in FAILED', async () => {
    const postStore = createPostStore();
    const post = await postStore.create({
      userId: 'seller-settled-failed', caption: 'fails', videoS3Key: 'uploads/x/a.mp4',
      platforms: ['TIKTOK']
    });
    const onPostSettled = vi.fn(async () => undefined);

    await createPublishScheduler({
      postStore,
      platformPublishStore: createInMemoryPlatformPublishStore(),
      assertOwnerActive: async () => { throw new Error('preflight unavailable'); },
      maxPrePublishAttempts: 1,
      onPostSettled
    }).runOnce();

    expect(onPostSettled.mock.calls).toEqual([[post.id]]);
  });

  it('keeps owner admission through the fallback failure notification', async () => {
    const postStore = createPostStore();
    const post = await postStore.create({
      userId: 'seller-fallback-lifetime', caption: 'fixture', videoS3Key: 'fixture.mp4', platforms: ['TIKTOK']
    });
    let notificationEntered!: () => void;
    let finishNotification!: () => void;
    const started = new Promise<void>((resolve) => { notificationEntered = resolve; });
    const notificationPending = new Promise<void>((resolve) => { finishNotification = resolve; });
    let depth = 0;
    const owners: string[] = [];
    const runWithActiveOwner: RunWithActiveOwner = async (ownerId, operation) => {
      owners.push(ownerId); depth += 1;
      try { return await operation(); } finally { depth -= 1; }
    };
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), runWithActiveOwner,
      assertOwnerActive: async () => { throw new Error('preflight unavailable'); },
      maxPrePublishAttempts: 1,
      notifier: { notifyPublishResult: async () => { notificationEntered(); await notificationPending; } }
    });
    const running = scheduler.runOnce();
    await started;
    expect(post.status).toBe('FAILED');
    expect(depth).toBeGreaterThan(0);
    expect(owners.every((ownerId) => ownerId === post.userId)).toBe(true);
    finishNotification();
    await running;
    expect(depth).toBe(0);
  });

  it('leaves a due post untouched when shared owner admission rejects', async () => {
    const postStore = createPostStore();
    const post = await postStore.create({
      userId: 'seller-denied-lifetime', caption: 'fixture', videoS3Key: 'fixture.mp4', platforms: ['TIKTOK']
    });
    const publish = vi.fn();
    const notifyPublishResult = vi.fn(async () => undefined);
    const runWithActiveOwner: RunWithActiveOwner = async () => { throw new Error('owner deleting'); };
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish },
      notifier: { notifyPublishResult }, runWithActiveOwner
    });
    await scheduler.runOnce();
    expect(post.status).toBe('QUEUED');
    expect(publish).not.toHaveBeenCalled();
    expect(notifyPublishResult).not.toHaveBeenCalled();
  });

  it('keeps scheduler readiness unavailable after a resolved unknown provider result', async () => {
    const postStore = createPostStore();
    const post = await postStore.create({
      userId: 'seller-unknown-lifetime', caption: 'fixture', videoS3Key: 'fixture.mp4', platforms: ['TIKTOK']
    });
    const publish = vi.fn(async () => { throw new PublishOutcomeUnknownError('provider may still be processing'); });
    const logging = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish }
    });
    await scheduler.start();
    try {
      await scheduler.runOnce();
      expect(post.status).toBe('FAILED');
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
      await scheduler.runOnce();
      expect(publish).toHaveBeenCalledOnce();
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
    } finally {
      scheduler.stop(); logging.mockRestore();
    }
  });

  it('detects unknown interrupted publishes at startup without sending them again', async () => {
    const postStore = createPostStore();
    const post = await postStore.create({ userId: 'seller-interrupted', caption: 'private', videoS3Key: 'private.mp4', platforms: ['TIKTOK'] });
    await postStore.claimForPublish({ postId: post.id, expectedRunAt: post.createdAt });
    const publisher = { publish: vi.fn() };
    const warn = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const scheduler = createPublishScheduler({ postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher });
    try {
      await scheduler.start();
      await scheduler.runOnce();
      expect(post.status).toBe('PUBLISHING');
      expect(publisher.publish).not.toHaveBeenCalled();
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
      expect(warn).toHaveBeenCalledWith('Interrupted publishing requires operator reconciliation', { code: 'PUBLISH_RECONCILIATION_REQUIRED', count: 1 });
    } finally {
      scheduler.stop();
      warn.mockRestore();
    }
  });

  it('fails startup safely when recovery inspection cannot reach the store', async () => {
    const postStore = createPostStore();
    vi.spyOn(postStore, 'listPublishing').mockRejectedValue(new Error('secret database URL'));
    const scheduler = createPublishScheduler({ postStore, platformPublishStore: createInMemoryPlatformPublishStore() });
    await expect(scheduler.start()).rejects.toThrow('Interrupted publish inspection failed');
  });

  it('stops claiming new posts and drains the active publish before shutdown', async () => {
    const postStore = createPostStore();
    const first = await postStore.create({ userId: 'seller-drain', caption: 'first', videoS3Key: 'first.mp4', platforms: ['TIKTOK'] });
    const second = await postStore.create({ userId: 'seller-drain', caption: 'second', videoS3Key: 'second.mp4', platforms: ['TIKTOK'] });
    let finishPublish!: () => void;
    let publishStarted!: () => void;
    const started = new Promise<void>((resolve) => { publishStarted = resolve; });
    const publishing = new Promise<void>((resolve) => { finishPublish = resolve; });
    const publisher = { publish: vi.fn(async ({ platform }: PlatformPublishInput) => {
      publishStarted();
      await publishing;
      return { platform, status: 'PUBLISHED' as const, deliveryOutcome: 'LIVE' as const, publishedAt: '2026-10-05T00:00:00.000Z' };
    }) };
    // One publish in flight; the concurrent case is covered separately below.
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher,
      maxConcurrentPublishes: 1
    });
    const run = scheduler.runOnce();
    await started;
    let drained = false;
    const drain = scheduler.drain!().then(() => { drained = true; });
    await Promise.resolve();
    expect(drained).toBe(false);
    finishPublish();
    await Promise.all([run, drain]);
    expect(first.status).toBe('PUBLISHED');
    expect(second.status).toBe('QUEUED');
    await scheduler.runOnce();
    expect(publisher.publish).toHaveBeenCalledOnce();
  });

  it('drains concurrent publishes without claiming the rest of the batch', async () => {
    const postStore = createPostStore();
    const posts = [];
    for (const caption of ['first', 'second', 'third']) {
      posts.push(await postStore.create({
        userId: `seller-drain-${caption}`, caption, videoS3Key: `${caption}.mp4`, platforms: ['TIKTOK']
      }));
    }
    let finishPublish!: () => void;
    const publishing = new Promise<void>((resolve) => { finishPublish = resolve; });
    let startedCount = 0;
    let bothStarted!: () => void;
    const started = new Promise<void>((resolve) => { bothStarted = resolve; });
    const publisher = { publish: vi.fn(async ({ platform }: PlatformPublishInput) => {
      startedCount += 1;
      if (startedCount === 2) bothStarted();
      await publishing;
      return { platform, status: 'PUBLISHED' as const, deliveryOutcome: 'LIVE' as const, publishedAt: '2026-10-05T00:00:00.000Z' };
    }) };
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher,
      maxConcurrentPublishes: 2
    });

    const run = scheduler.runOnce();
    await started;
    const drain = scheduler.drain!();
    finishPublish();
    await Promise.all([run, drain]);

    expect(posts.map((post) => post.status)).toEqual(['PUBLISHED', 'PUBLISHED', 'QUEUED']);
    expect(publisher.publish).toHaveBeenCalledTimes(2);
  });

  it('marks polling failures unavailable and recovers on a successful poll', async () => {
    const postStore = createPostStore();
    const scheduler = createPublishScheduler({ postStore, platformPublishStore: createInMemoryPlatformPublishStore() });
    await scheduler.start();
    try {
      vi.spyOn(postStore, 'listDue').mockRejectedValueOnce(new Error('private database detail'));
      await expect(scheduler.runOnce()).rejects.toThrow();
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
      await scheduler.runOnce();
      await expect(scheduler.checkReady!()).resolves.toBeUndefined();
    } finally {
      scheduler.stop();
    }
  });

  it('fails readiness after a post-provider persistence failure and never sends the post again', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const post = await postStore.create({
      userId: 'seller-persist', caption: 'private', videoS3Key: 'private.mp4', platforms: ['TIKTOK']
    });
    const publisher = { publish: vi.fn(async ({ platform }: PlatformPublishInput) => ({
      platform, status: 'PUBLISHED' as const, externalPostId: 'saved-provider-receipt',
      deliveryOutcome: 'LIVE' as const, publishedAt: '2026-10-05T00:00:00.000Z'
    })) };
    const scheduler = createPublishScheduler({ postStore, platformPublishStore, publisher });
    await scheduler.start();
    const updateStatus = vi.spyOn(postStore, 'updateStatus')
      .mockRejectedValue(new Error('private database connection detail'));
    try {
      await scheduler.runOnce();
      expect(post.status).toBe('PUBLISHING');
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
      updateStatus.mockRestore();
      await scheduler.runOnce();
      expect(publisher.publish).toHaveBeenCalledOnce();
      await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
    } finally {
      updateStatus.mockRestore();
      scheduler.stop();
    }
    const restart = createPublishScheduler({ postStore, platformPublishStore, publisher });
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    try {
      await restart.start();
      expect(post.status).toBe('PUBLISHED');
      await expect(restart.checkReady!()).resolves.toBeUndefined();
      await restart.runOnce();
      expect(publisher.publish).toHaveBeenCalledOnce();
    } finally {
      restart.stop();
      log.mockRestore();
    }
  });

  it('checks the complete global backlog before starting an opted-in scheduler', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const countPublishBacklog = vi.spyOn(postStore, 'countPublishBacklog');
    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      requireEmptyBacklogOnStart: true
    });

    await scheduler.start();
    scheduler.stop();

    expect(countPublishBacklog).toHaveBeenCalledOnce();
  });

  it('refuses to start when any queued post exists, including future work', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    await postStore.create({
      userId: 'seller-future',
      caption: 'future',
      videoS3Key: 'uploads/future.mp4',
      platforms: ['YOUTUBE_SHORTS'],
      scheduledAt: '2030-01-01T00:00:00.000Z'
    });
    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      requireEmptyBacklogOnStart: true
    });

    await expect(scheduler.start()).rejects.toThrow(
      'Social publishing activation blocked: 1 queued or publishing posts exist'
    );
  });

  it('refuses to start when a publishing post exists', async () => {
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const post = await postStore.create({
      userId: 'seller-publishing',
      caption: 'publishing',
      videoS3Key: 'uploads/publishing.mp4',
      platforms: ['YOUTUBE_SHORTS']
    });
    await postStore.claimForPublish({
      postId: post.id,
      expectedRunAt: post.createdAt
    });
    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      requireEmptyBacklogOnStart: true
    });

    await expect(scheduler.start()).rejects.toThrow(
      'Social publishing activation blocked: 1 queued or publishing posts exist'
    );
  });

  it('fails closed without exposing a database error when backlog inspection fails', async () => {
    const postStore = createPostStore();
    vi.spyOn(postStore, 'countPublishBacklog').mockRejectedValue(
      new Error('sensitive database detail that must not reach logs')
    );
    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore: createInMemoryPlatformPublishStore(),
      requireEmptyBacklogOnStart: true
    });

    const start = scheduler.start();
    await expect(start).rejects.toThrow(
      'Social publishing activation blocked: backlog inspection failed'
    );
    await expect(start).rejects.not.toThrow('sensitive database detail');
  });

  it('does not inspect global backlog unless the activation guard is opted in', async () => {
    const postStore = createPostStore();
    const countPublishBacklog = vi
      .spyOn(postStore, 'countPublishBacklog')
      .mockRejectedValue(new Error('must not be called'));
    const scheduler = createPublishScheduler({
      postStore,
      platformPublishStore: createInMemoryPlatformPublishStore()
    });

    await scheduler.start();
    scheduler.stop();

    expect(countPublishBacklog).not.toHaveBeenCalled();
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
      publish: vi.fn(async ({ postId, platform }: PlatformPublishInput) => ({
        platform,
        status: 'PUBLISHED' as const,
        deliveryOutcome: 'LIVE' as const,
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
      }: PlatformPublishInput) => {
        if (platform === 'YOUTUBE_SHORTS') {
          throw new Error('youtube down');
        }

        return {
          platform,
          status: 'PUBLISHED' as const,
          deliveryOutcome: 'LIVE' as const,
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
      publish: vi.fn(async ({ postId, platform }: PlatformPublishInput) => ({
        platform,
        status: 'PUBLISHED' as const,
        deliveryOutcome: 'LIVE' as const,
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
    // The first two attempts fail during the pre-claim guard. The successful
    // attempt rechecks the owner after claiming and immediately before the
    // provider call, closing the deletion race window.
    expect(assertOwnerActive).toHaveBeenCalledTimes(4);
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
      publish: vi.fn(async ({ postId, platform }: PlatformPublishInput) => ({
        platform,
        status: 'PUBLISHED' as const,
        deliveryOutcome: 'LIVE' as const,
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
