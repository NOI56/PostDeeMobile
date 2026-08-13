import { UnrecoverableError } from 'bullmq';

import type { PublishWorkerResult } from './publishWorker.js';

export const buildPublishWorkerCompletedLog = ({
  result
}: {
  result: PublishWorkerResult;
}) => ({
  postId: result.postId,
  status: result.status,
  platforms: result.platformResults.map((platformResult) => ({
    platform: platformResult.platform,
    status: platformResult.status,
    ...(platformResult.status === 'PUBLISHED'
      ? { deliveryOutcome: platformResult.deliveryOutcome }
      : {})
  }))
});

export const buildPublishWorkerFailedLog = ({
  postId,
  platforms,
  error
}: {
  postId?: string;
  platforms?: Array<{ platform: string }>;
  error: unknown;
}) => ({
  postId: postId ?? 'unknown',
  status: 'FAILED' as const,
  platforms: (platforms ?? []).map(({ platform }) => ({
    platform,
    status: 'FAILED' as const
  })),
  errorName:
    error instanceof UnrecoverableError
      ? 'UnrecoverableError'
      : error instanceof Error
        ? 'Error'
        : 'UnknownError',
  message:
    'Publish worker job failed; inspect sanitized platform results and provider dashboards'
});

/**
 * A retry that finds the post already claimed cannot know whether a previous
 * worker reached the provider. Keep the BullMQ job in the failed set for
 * operator/provider reconciliation instead of completing and deleting it.
 */
export const enforceRetriedPublishRecoveryPolicy = ({
  attemptsStarted,
  result
}: {
  attemptsStarted?: number;
  result: PublishWorkerResult;
}): PublishWorkerResult => {
  if ((attemptsStarted ?? 1) > 1 && result.status === 'SKIPPED') {
    throw new UnrecoverableError(
      `Retried publish job for ${result.postId} requires manual provider reconciliation`
    );
  }

  return result;
};
