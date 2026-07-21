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
  processPublishJobForPost
} from './publishWorker.js';

export type PublishScheduler = {
  start: () => void;
  stop: () => void;
  runOnce: () => Promise<void>;
};

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
  sleep?: (delayMs: number) => Promise<void>;
}): PublishScheduler => {
  let timer: ReturnType<typeof setInterval> | undefined;
  let isRunning = false;
  const attemptLimit = Math.max(1, Math.floor(maxPrePublishAttempts));
  const retryBackoffMs = Math.max(0, prePublishRetryBackoffMs);

  const publishDuePost = async (post: Awaited<ReturnType<PostStore['listDue']>>[number]) => {
    let externalPublishStarted = false;
    const trackedPublisher: PlatformPublisher = {
      publish: async (input) => {
        externalPublishStarted = true;
        return publisher.publish(input);
      }
    };

    for (let attempt = 1; attempt <= attemptLimit; attempt += 1) {
      try {
        await processPublishJobForPost({
          jobData: {
            userId: post.userId,
            postId: post.id,
            caption: post.caption,
            videoS3Key: post.videoS3Key,
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
        return;
      } catch {
        // Once a provider call starts, its outcome can be ambiguous. The worker
        // already fails the post closed; never create another provider post.
        if (externalPublishStarted) {
          return;
        }

        if (attempt === attemptLimit) {
          await postStore.updateStatus({ postId: post.id, status: 'FAILED' });

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

  const runOnce = async () => {
    if (isRunning) {
      return;
    }

    isRunning = true;

    try {
      const duePosts = await postStore.listDue({ now: now() });

      for (const post of duePosts) {
        try {
          await publishDuePost(post);
        } catch {
          // A store outage can also prevent persisting FAILED. The next tick
          // may safely retry while the post remains QUEUED.
        }
      }
    } finally {
      isRunning = false;
    }
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
