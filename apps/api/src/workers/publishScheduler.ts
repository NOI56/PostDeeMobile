import type { PlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import {
  type PublishNotifier,
  createNoopPublishNotifier
} from '../modules/notifications/publishNotifier.js';
import type { PostStore } from '../modules/posts/postStore.js';
import { reconcileInterruptedPublishes } from './interruptedPublishRecovery.js';
import {
  type PlatformPublisher,
  type VideoStorageCleaner,
  createMockPlatformPublisher,
  createMockVideoStorageCleaner,
  processPublishJobForPost
} from './publishWorker.js';

export type PublishScheduler = {
  start: () => Promise<void>;
  stop: () => void;
  runOnce: () => Promise<void>;
  drain?: () => Promise<void>;
  checkReady?: () => Promise<void>;
};

const activationBacklogInspectionFailedMessage =
  'Social publishing activation blocked: backlog inspection failed';

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
  requireEmptyBacklogOnStart = false,
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
  requireEmptyBacklogOnStart?: boolean;
  intervalMs?: number;
  now?: () => string;
  maxPrePublishAttempts?: number;
  prePublishRetryBackoffMs?: number;
  sleep?: (delayMs: number) => Promise<void>;
}): PublishScheduler => {
  let timer: ReturnType<typeof setInterval> | undefined;
  let activeRun: Promise<void> | undefined;
  let stopped = false;
  let pollHealthy = true;
  let requiresReconciliation = false;
  let starting: Promise<void> | undefined;
  let generation = 0;
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
            ...(post.coverImageS3Key
              ? { coverImageS3Key: post.coverImageS3Key }
              : {}),
            ...(post.coverFrameTimeMs !== undefined
              ? { coverFrameTimeMs: post.coverFrameTimeMs }
              : {}),
            platforms: post.platforms,
            ...(post.platformSettings
              ? { platformSettings: post.platformSettings }
              : {}),
            ...(post.platformTargets ? { platformTargets: post.platformTargets } : {}),
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
          // Persistence may have failed after provider acceptance. Keep readiness
          // unavailable until restart/reconciliation examines the saved receipts.
          requiresReconciliation = true;
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

        await postStore.updateStatus({ postId: post.id, status: 'QUEUED' });
        await sleep(retryBackoffMs * 2 ** (attempt - 1));
      }
    }
  };

  const runOnce = (): Promise<void> => {
    if (stopped) return Promise.resolve();
    if (activeRun) return activeRun;
    activeRun = Promise.resolve().then(async () => {
      try {
        const duePosts = await postStore.listDue({ now: now() });
        let persistenceFailed = false;
        for (const post of duePosts) {
          if (stopped) break;
          try {
            await publishDuePost(post);
          } catch {
            // Preserve an uncertain provider outcome. A later healthy poll can
            // retry only rows that remain safely QUEUED before provider intake.
            persistenceFailed = true;
          }
        }
        pollHealthy = !persistenceFailed;
      } catch (error) {
        pollHealthy = false;
        throw error;
      }
    }).finally(() => { activeRun = undefined; });
    return activeRun;
  };

  const stop = () => {
    generation += 1;
    stopped = true;
    if (timer) {
      clearInterval(timer);
      timer = undefined;
    }
  };

  return {
    start: () => {
      if (starting) return starting;
      if (timer) return Promise.resolve();
      const startGeneration = generation;
      starting = (async () => {
        if (activeRun) throw new Error('Publish scheduler is still draining');
        if (requireEmptyBacklogOnStart) {
          let pendingPostCount: Awaited<ReturnType<PostStore['countPublishBacklog']>>;

          try {
            pendingPostCount = await postStore.countPublishBacklog();
          } catch {
            // Do not leak database connection details through deployment logs.
            throw new Error(activationBacklogInspectionFailedMessage);
          }

          if (pendingPostCount > 0) {
            throw new Error(
              `Social publishing activation blocked: ${pendingPostCount} queued or publishing posts exist`
            );
          }
        }

        try {
          const recovery = await reconcileInterruptedPublishes({ postStore, platformPublishStore });
          requiresReconciliation = recovery.requiresReconciliation > 0;
          if (recovery.recovered > 0) {
            console.log('Interrupted publishing statuses recovered', { count: recovery.recovered });
          }
          if (requiresReconciliation) {
            console.error('Interrupted publishing requires operator reconciliation', {
              code: 'PUBLISH_RECONCILIATION_REQUIRED', count: recovery.requiresReconciliation
            });
          }
        } catch {
          throw new Error('Interrupted publish inspection failed');
        }
        if (startGeneration !== generation) return;
        timer = setInterval(() => {
          void runOnce().catch(() => {
            console.error('Publish scheduler poll failed', { code: 'PUBLISH_POLL_FAILED' });
          });
        }, intervalMs);
        stopped = false;
      })().finally(() => { starting = undefined; });
      return starting;
    },
    stop,
    drain: async () => {
      stop();
      await starting;
      await activeRun;
    },
    checkReady: async () => {
      if (!timer || stopped || !pollHealthy || requiresReconciliation) {
        throw new Error('Publish scheduler unavailable');
      }
    },
    runOnce
  };
};
