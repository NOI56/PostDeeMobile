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
  now = () => new Date().toISOString()
}: {
  postStore: PostStore;
  platformPublishStore: PlatformPublishStore;
  publisher?: PlatformPublisher;
  storage?: VideoStorageCleaner;
  notifier?: PublishNotifier;
  assertOwnerActive?: (ownerId: string) => Promise<void>;
  intervalMs?: number;
  now?: () => string;
}): PublishScheduler => {
  let timer: ReturnType<typeof setInterval> | undefined;
  let isRunning = false;

  const runOnce = async () => {
    if (isRunning) {
      return;
    }

    isRunning = true;

    try {
      const duePosts = await postStore.listDue({ now: now() });

      for (const post of duePosts) {
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
            publisher,
            storage,
            platformPublishStore,
            notifier,
            assertOwnerActive,
            now
          });
        } catch {
          // processPublishJobForPost already marked the post FAILED.
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
