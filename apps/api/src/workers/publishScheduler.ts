import type { PlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import {
  type PublishNotifier,
  createNoopPublishNotifier
} from '../modules/notifications/publishNotifier.js';
import type { PostStore } from '../modules/posts/postStore.js';
import {
  type PlatformPublisher,
  type VideoStorageCleaner,
  createMockPlatformPublisher,
  createMockVideoStorageCleaner,
  processPublishJobForPost,
  publicPublishOutcomeUnknownErrorMessage
} from './publishWorker.js';

export type PublishScheduler = {
  start: () => void;
  stop: () => void;
  runOnce: () => Promise<void>;
};

type DuePost = Awaited<ReturnType<PostStore['listDue']>>[number];

const wait = async (delayMs: number) =>
  new Promise<void>((resolve) => {
    setTimeout(resolve, delayMs);
  });

/**
 * In-process publish scheduler for the in-memory queue (PUBLISH_QUEUE=memory).
 *
 * Polls the post store for posts whose time has come (post-now or scheduledAt
 * in the past), then runs them through {@link processPublishJob} and advances
 * the post status QUEUED -> PUBLISHING -> PUBLISHED/FAILED. The publisher is a
 * mock for now; real platform posting (PostPeer) plugs in via `publisher`.
 */
export const createPublishScheduler = ({
  postStore,
  platformPublishStore,
  publisher = createMockPlatformPublisher(),
  storage = createMockVideoStorageCleaner(),
  notifier = createNoopPublishNotifier(),
  assertOwnerActive,
  intervalMs = 5000,
  now = () => new Date().toISOString(),
  maxPrePublishAttempts = 3,
  prePublishRetryBackoffMs = 1_000,
  stalePublishingMs = 30 * 60_000,
  stalePublishingSweepIntervalMs = 60_000,
  maxConcurrentPublishes = 4,
  onPostSettled,
  sleep = wait
}: {
  postStore: PostStore;
  platformPublishStore: PlatformPublishStore;
  publisher?: PlatformPublisher;
  storage?: VideoStorageCleaner;
  notifier?: PublishNotifier;
  assertOwnerActive?: (ownerId: string) => Promise<void>;
  intervalMs?: number;
  now?: () => string;
  maxPrePublishAttempts?: number;
  prePublishRetryBackoffMs?: number;
  // A claim older than this is treated as orphaned. It must exceed the longest
  // legitimate publish (provider polling can take minutes per platform).
  stalePublishingMs?: number;
  stalePublishingSweepIntervalMs?: number;
  // Posts published at once. Each claim is atomic, so this only bounds load on
  // the provider and the single API instance.
  maxConcurrentPublishes?: number;
  // Called once a post leaves the queue for good (published or failed), so the
  // in-memory publish queue can drop its job instead of growing forever.
  onPostSettled?: (postId: string) => Promise<void>;
  sleep?: (delayMs: number) => Promise<void>;
}): PublishScheduler => {
  let timer: ReturnType<typeof setInterval> | undefined;
  let isListing = false;
  let lastStaleSweepAtMs: number | undefined;
  const inFlightPostIds = new Set<string>();
  const concurrencyLimit = Math.max(1, Math.floor(maxConcurrentPublishes));

  const reportSettled = async (postId: string) => {
    try {
      await onPostSettled?.(postId);
    } catch {
      // Queue bookkeeping must not affect the stored publish outcome.
    }
  };
  const attemptLimit = Math.max(1, Math.floor(maxPrePublishAttempts));
  const retryBackoffMs = Math.max(0, prePublishRetryBackoffMs);

  // A restart (e.g. a deploy) mid-publish leaves posts PUBLISHING forever, where
  // users can neither retry nor delete them. Fail them closed instead: the
  // provider outcome is unknown, so never publish them again automatically.
  const failStalePublishingPosts = async () => {
    if (!postStore.recoverStalePublishing) {
      return;
    }

    const currentMs = Date.parse(now());

    if (
      lastStaleSweepAtMs !== undefined &&
      currentMs - lastStaleSweepAtMs < stalePublishingSweepIntervalMs
    ) {
      return;
    }

    lastStaleSweepAtMs = currentMs;
    const stalePosts = await postStore.recoverStalePublishing({
      startedBefore: new Date(currentMs - stalePublishingMs).toISOString()
    });

    for (const post of stalePosts) {
      try {
        const savedResults = platformPublishStore.listForPostIds
          ? await platformPublishStore.listForPostIds([post.id])
          : [];
        const savedPlatforms = new Set(savedResults.map((result) => result.platform));
        const unknownPlatforms = post.platforms.filter(
          (platform) => !savedPlatforms.has(platform)
        );

        if (unknownPlatforms.length > 0) {
          await platformPublishStore.recordResults({
            postId: post.id,
            results: unknownPlatforms.map((platform) => ({
              platform,
              status: 'FAILED' as const,
              errorMessage: publicPublishOutcomeUnknownErrorMessage
            }))
          });
        }
      } catch {
        // The FAILED post status is already stored; results are best-effort.
      }

      try {
        await notifier.notifyPublishResult({
          userId: post.userId,
          postId: post.id,
          outcome: 'FAILED'
        });
      } catch {
        // Best-effort notification.
      }

      await reportSettled(post.id);
    }
  };

  const publishDuePost = async (post: DuePost) => {
    let externalPublishStarted = false;
    const trackedPublisher: PlatformPublisher = {
      publish: async (input) => {
        externalPublishStarted = true;
        return publisher.publish(input);
      }
    };

    for (let attempt = 1; attempt <= attemptLimit; attempt += 1) {
      try {
        const result = await processPublishJobForPost({
          jobData: {
            userId: post.userId,
            postId: post.id,
            caption: post.caption,
            ...(post.youtubeTitle ? { youtubeTitle: post.youtubeTitle } : {}),
            videoS3Key: post.videoS3Key,
            ...(post.coverImageS3Key
              ? { coverImageS3Key: post.coverImageS3Key }
              : {}),
            ...(post.coverFrameTimeMs !== undefined
              ? { coverFrameTimeMs: post.coverFrameTimeMs }
              : {}),
            platforms: post.platforms,
            runAt: post.scheduledAt ?? now(),
            status: post.scheduledAt ? 'SCHEDULED' : 'READY'
          },
          postStore,
          publisher: trackedPublisher,
          storage,
          platformPublishStore,
          notifier,
          assertOwnerActive,
          now
        });

        // A skipped post lost its claim (e.g. it was rescheduled) and is still queued.
        if (result.status !== 'SKIPPED') {
          await reportSettled(post.id);
        }
        return;
      } catch {
        // Once a provider call starts, its outcome can be ambiguous. The worker
        // already fails the post closed; never create another provider post.
        if (externalPublishStarted) {
          await reportSettled(post.id);
          return;
        }

        if (attempt === attemptLimit) {
          await postStore.updateStatus({ postId: post.id, status: 'FAILED' });
          await reportSettled(post.id);

          try {
            await notifier.notifyPublishResult({
              userId: post.userId,
              postId: post.id,
              outcome: 'FAILED'
            });
          } catch {
            // Best-effort notification; the terminal status is already stored.
          }

          return;
        }

        await sleep(retryBackoffMs * 2 ** (attempt - 1));
      }
    }
  };

  const publishDuePosts = async (pending: DuePost[]) => {
    // Takes a slot synchronously, so overlapping ticks never start a post twice
    // and the process never runs more than concurrencyLimit publishes.
    const takeNext = () => {
      while (pending.length > 0 && inFlightPostIds.size < concurrencyLimit) {
        const post = pending.shift();

        if (post && !inFlightPostIds.has(post.id)) {
          inFlightPostIds.add(post.id);
          return post;
        }
      }

      return undefined;
    };
    const work = async () => {
      for (let post = takeNext(); post; post = takeNext()) {
        try {
          await publishDuePost(post);
        } catch {
          // A store outage can also prevent persisting FAILED. The next tick
          // may safely retry while the post remains QUEUED.
        } finally {
          inFlightPostIds.delete(post.id);
        }
      }
    };

    await Promise.all(Array.from({ length: concurrencyLimit }, work));
  };

  // Ticks may overlap so one slow publish (provider polling can take minutes)
  // does not hold back posts that become due later. Only listing is serialized;
  // posts left over at full capacity stay QUEUED for the next tick.
  const runOnce = async () => {
    if (isListing || inFlightPostIds.size >= concurrencyLimit) {
      return;
    }

    isListing = true;
    let duePosts: DuePost[];

    try {
      try {
        await failStalePublishingPosts();
      } catch {
        // A failed sweep retries next interval; due posts must still publish.
      }

      duePosts = await postStore.listDue({ now: now() });
    } finally {
      isListing = false;
    }

    await publishDuePosts(duePosts);
  };

  return {
    start: () => {
      if (!timer) {
        timer = setInterval(() => {
          void runOnce();
        }, intervalMs);
      }
    },
    stop: () => {
      if (timer) {
        clearInterval(timer);
        timer = undefined;
      }
    },
    runOnce
  };
};
