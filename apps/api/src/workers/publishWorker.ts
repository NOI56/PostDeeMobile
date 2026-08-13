import type { Platform, PostStatus, PostStore } from '../modules/posts/postStore.js';
import {
  type PublishNotifier,
  createNoopPublishNotifier
} from '../modules/notifications/publishNotifier.js';
import {
  type DeliveryOutcome,
  type PlatformPublishStore,
  createInMemoryPlatformPublishStore
} from '../modules/platformPublishes/platformPublishStore.js';
import type { PlatformSettings } from '../modules/posts/platformSettings.js';
import type { PlatformTargets } from '../modules/posts/platformTargets.js';
import type { BullMqPublishJobData } from '../modules/queue/bullMqPublishQueue.js';
import { readRequestedDeliveryOutcome } from './platformDeliveryOutcome.js';

export type PlatformPublishInput = {
  userId?: string;
  postId: string;
  caption?: string;
  videoS3Key?: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platform: Platform;
  platformSettings?: PlatformSettings | null;
  platformTargets?: PlatformTargets | null;
};

export type PlatformPublishSuccess = {
  platform: Platform;
  status: 'PUBLISHED';
  externalPostId?: string;
  providerPostId?: string;
  deliveryOutcome: DeliveryOutcome;
  publishedAt: string;
};

export type PlatformPublishFailure = {
  platform: Platform;
  status: 'FAILED';
  errorMessage: string;
};

export type PlatformPublishResult = PlatformPublishSuccess | PlatformPublishFailure;

export type PlatformPublisher = {
  publish: (input: PlatformPublishInput) => Promise<PlatformPublishSuccess>;
};

/**
 * A publisher may use this error only when it knows the provider did not
 * accept/create a post. Generic network and timeout errors are intentionally
 * not retryable because their provider outcome can be ambiguous.
 */
export class RetryablePublishError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RetryablePublishError';
  }
}

/**
 * The provider may already have accepted the publish request, but its final
 * outcome could not be read. Retrying this error could create a duplicate.
 */
export class PublishOutcomeUnknownError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PublishOutcomeUnknownError';
  }
}

export type VideoStorageCleaner = {
  deleteVideo: (videoS3Key: string) => Promise<void>;
};

export type PublishWorkerResult = {
  postId: string;
  status: 'PUBLISHED' | 'PARTIAL_FAILED' | 'FAILED' | 'SKIPPED';
  platformResults: PlatformPublishResult[];
  cleanup: {
    status: 'DELETED' | 'SKIPPED' | 'FAILED';
    videoS3Key?: string;
    coverImageS3Key?: string;
    errorMessage?: string;
  };
};

const publicPlatformPublishErrorMessage =
  'Publishing to this platform failed. Please try again later.';
const publicPublishOutcomeUnknownErrorMessage =
  'Publishing result could not be confirmed. Check the platform before trying again.';
const publicCleanupErrorMessage = 'Video cleanup failed. Please try again later.';

const readSafeWorkerErrorName = (error: unknown) => {
  if (error instanceof RetryablePublishError) {
    return 'RetryablePublishError';
  }

  if (error instanceof PublishOutcomeUnknownError) {
    return 'PublishOutcomeUnknownError';
  }

  return error instanceof Error ? 'Error' : 'UnknownError';
};

const logWorkerError = (
  input:
    | {
        category: 'PLATFORM_PUBLISH';
        code: 'PLATFORM_PUBLISH_FAILED';
        platform: Platform;
        error: unknown;
      }
    | {
        category: 'MEDIA_CLEANUP';
        code: 'MEDIA_CLEANUP_FAILED';
        error: unknown;
      }
) => {
  const { error, ...safeFields } = input;
  console.error('Publish worker operation failed', {
    ...safeFields,
    errorName: readSafeWorkerErrorName(error)
  });
};

const wait = async (delayMs: number) =>
  new Promise<void>((resolve) => {
    setTimeout(resolve, delayMs);
  });

const getWorkerStatus = (platformResults: PlatformPublishResult[]): PublishWorkerResult['status'] => {
  const publishedCount = platformResults.filter((result) => result.status === 'PUBLISHED').length;

  if (publishedCount === platformResults.length) {
    return 'PUBLISHED';
  }

  return publishedCount > 0 ? 'PARTIAL_FAILED' : 'FAILED';
};

export const createMockPlatformPublisher = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): PlatformPublisher => ({
  publish: async ({ postId, platform, platformSettings }) => ({
    platform,
    status: 'PUBLISHED',
    externalPostId: `mock-${platform.toLowerCase()}-${postId}`,
    deliveryOutcome: readRequestedDeliveryOutcome({ platform, platformSettings }),
    publishedAt: now()
  })
});

export const createDisabledPlatformPublisher = (): PlatformPublisher => ({
  publish: async () => {
    throw new Error('Social publishing is disabled for this environment');
  }
});

export const createMockVideoStorageCleaner = (): VideoStorageCleaner => ({
  deleteVideo: async () => undefined
});

export const processPublishJob = async ({
  jobData,
  publisher = createMockPlatformPublisher(),
  storage = createMockVideoStorageCleaner(),
  platformPublishStore = createInMemoryPlatformPublishStore(),
  // Off by default: a unified publisher like PostPeer is given a signed URL and
  // may download the media asynchronously AFTER it accepts the job. Deleting the
  // source immediately can make that fetch 404 and silently fail the post.
  // Prefer an R2/S3 lifecycle rule to expire temporary uploads instead.
  deleteVideoAfterPublish = false,
  maxPublishAttempts = 3,
  publishRetryBackoffMs = 1_000,
  sleep = wait
}: {
  jobData: BullMqPublishJobData;
  publisher?: PlatformPublisher;
  storage?: VideoStorageCleaner;
  platformPublishStore?: PlatformPublishStore;
  deleteVideoAfterPublish?: boolean;
  maxPublishAttempts?: number;
  publishRetryBackoffMs?: number;
  sleep?: (delayMs: number) => Promise<void>;
}): Promise<PublishWorkerResult> => {
  const attemptLimit = Math.max(1, Math.floor(maxPublishAttempts));
  const retryBackoffMs = Math.max(0, publishRetryBackoffMs);
  const uniquePlatforms = [...new Set(jobData.platforms)];
  const platformResults = await Promise.all(
    uniquePlatforms.map(async (platform): Promise<PlatformPublishResult> => {
      for (let attempt = 1; attempt <= attemptLimit; attempt += 1) {
        try {
          return await publisher.publish({
            ...(jobData.userId ? { userId: jobData.userId } : {}),
            postId: jobData.postId,
            caption: jobData.caption,
            videoS3Key: jobData.videoS3Key,
            ...(jobData.coverImageS3Key
              ? { coverImageS3Key: jobData.coverImageS3Key }
              : {}),
            ...(jobData.coverFrameTimeMs !== undefined
              ? { coverFrameTimeMs: jobData.coverFrameTimeMs }
              : {}),
            platform,
            ...(jobData.platformSettings
              ? { platformSettings: jobData.platformSettings }
              : {}),
            ...(jobData.platformTargets
              ? { platformTargets: jobData.platformTargets }
              : {})
          });
        } catch (error) {
          if (error instanceof RetryablePublishError && attempt < attemptLimit) {
            await sleep(retryBackoffMs * 2 ** (attempt - 1));
            continue;
          }

          logWorkerError({
            category: 'PLATFORM_PUBLISH',
            code: 'PLATFORM_PUBLISH_FAILED',
            platform,
            error
          });
          return {
            platform,
            status: 'FAILED',
            errorMessage:
              error instanceof PublishOutcomeUnknownError
                ? publicPublishOutcomeUnknownErrorMessage
                : publicPlatformPublishErrorMessage
          };
        }
      }

      throw new Error('Publish retry loop exited unexpectedly');
    })
  );
  const status = getWorkerStatus(platformResults);

  await platformPublishStore.recordResults({
    postId: jobData.postId,
    results: platformResults
  });

  const cleanupKeys = [...new Set(
    [jobData.videoS3Key, jobData.coverImageS3Key].filter(
      (key): key is string => typeof key === 'string' && key.length > 0
    )
  )];
  const cleanupMedia = {
    ...(jobData.videoS3Key ? { videoS3Key: jobData.videoS3Key } : {}),
    ...(jobData.coverImageS3Key
      ? { coverImageS3Key: jobData.coverImageS3Key }
      : {})
  };

  if (status === 'PUBLISHED' && cleanupKeys.length > 0 && deleteVideoAfterPublish) {
    const cleanupResults = await Promise.all(
      cleanupKeys.map(async (key) => {
        try {
          await storage.deleteVideo(key);
          return true;
        } catch (error) {
          logWorkerError({
            category: 'MEDIA_CLEANUP',
            code: 'MEDIA_CLEANUP_FAILED',
            error
          });
          return false;
        }
      })
    );
    const cleanupFailed = cleanupResults.some((succeeded) => !succeeded);

    return {
      postId: jobData.postId,
      status,
      platformResults,
      cleanup: {
        status: cleanupFailed ? 'FAILED' : 'DELETED',
        ...cleanupMedia,
        ...(cleanupFailed ? { errorMessage: publicCleanupErrorMessage } : {})
      }
    };
  }

  return {
    postId: jobData.postId,
    status,
    platformResults,
    cleanup: {
      status: 'SKIPPED',
      ...cleanupMedia
    }
  };
};

/** Maps a worker result to the post-level status stored on the Post row. */
export const mapWorkerStatusToPostStatus = (
  status: PublishWorkerResult['status']
): PostStatus => {
  if (status === 'PUBLISHED') {
    return 'PUBLISHED';
  }

  if (status === 'PARTIAL_FAILED') {
    return 'PARTIAL_PUBLISHED';
  }

  if (status === 'SKIPPED') {
    throw new Error('Skipped publish jobs do not map to post status');
  }

  return 'FAILED';
};

const createSkippedPublishResult = (jobData: BullMqPublishJobData): PublishWorkerResult => ({
  postId: jobData.postId,
  status: 'SKIPPED',
  platformResults: [],
  cleanup: {
    status: 'SKIPPED',
    ...(jobData.videoS3Key ? { videoS3Key: jobData.videoS3Key } : {}),
    ...(jobData.coverImageS3Key
      ? { coverImageS3Key: jobData.coverImageS3Key }
      : {})
  }
});

/**
 * Publishes a job AND advances the post status (QUEUED -> PUBLISHING ->
 * PUBLISHED/PARTIAL_PUBLISHED/FAILED). Shared by the in-process scheduler and
 * the BullMQ worker so both keep the post status in sync; previously only the
 * scheduler did, leaving BullMQ-published posts stuck at QUEUED forever.
 */
export const processPublishJobForPost = async ({
  jobData,
  postStore,
  publisher = createMockPlatformPublisher(),
  storage = createMockVideoStorageCleaner(),
  platformPublishStore = createInMemoryPlatformPublishStore(),
  notifier = createNoopPublishNotifier(),
  assertOwnerActive,
  deleteVideoAfterPublish = false,
  now = () => new Date().toISOString()
}: {
  jobData: BullMqPublishJobData;
  postStore: PostStore;
  publisher?: PlatformPublisher;
  storage?: VideoStorageCleaner;
  platformPublishStore?: PlatformPublishStore;
  notifier?: PublishNotifier;
  assertOwnerActive?: (ownerId: string) => Promise<void>;
  deleteVideoAfterPublish?: boolean;
  now?: () => string;
}): Promise<PublishWorkerResult> => {
  if (assertOwnerActive && jobData.userId) {
    await assertOwnerActive(jobData.userId);
  }

  const claimed = await postStore.claimForPublish({
    postId: jobData.postId,
    expectedRunAt: jobData.runAt
  });

  if (!claimed) {
    return createSkippedPublishResult(jobData);
  }

  // Best-effort push: never let a notification failure affect publishing.
  const notify = async (outcome: PostStatus) => {
    try {
      await notifier.notifyPublishResult({
        userId: jobData.userId,
        postId: jobData.postId,
        outcome: outcome as 'PUBLISHED' | 'PARTIAL_PUBLISHED' | 'FAILED'
      });
    } catch {
      // Swallow: the post status is already persisted; push is non-critical.
    }
  };

  try {
    if (assertOwnerActive && jobData.userId) {
      await assertOwnerActive(jobData.userId);
    }

    const result = await processPublishJob({
      jobData,
      publisher,
      storage,
      platformPublishStore,
      deleteVideoAfterPublish
    });
    const postStatus = mapWorkerStatusToPostStatus(result.status);

    await postStore.updateStatus({
      postId: jobData.postId,
      status: postStatus,
      // Only stamp a publish time when something actually went live.
      publishedAt: postStatus === 'FAILED' ? undefined : now()
    });

    await notify(postStatus);

    return result;
  } catch (error) {
    await postStore.updateStatus({ postId: jobData.postId, status: 'FAILED' });
    await notify('FAILED');
    throw error;
  }
};
