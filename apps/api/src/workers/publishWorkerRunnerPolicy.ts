import { UnrecoverableError } from 'bullmq';

import type { PublishWorkerResult } from './publishWorker.js';

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
