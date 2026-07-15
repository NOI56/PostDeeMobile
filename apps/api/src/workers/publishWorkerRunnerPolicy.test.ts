import { UnrecoverableError } from 'bullmq';
import { describe, expect, it } from 'vitest';

import type { PublishWorkerResult } from './publishWorker.js';
import { enforceRetriedPublishRecoveryPolicy } from './publishWorkerRunnerPolicy.js';

const result = (status: PublishWorkerResult['status']): PublishWorkerResult => ({
  postId: 'post-1',
  status,
  platformResults: [],
  cleanup: { status: 'SKIPPED' }
});

describe('enforceRetriedPublishRecoveryPolicy', () => {
  it('keeps a normal first-attempt skip as a completed no-op', () => {
    expect(
      enforceRetriedPublishRecoveryPolicy({
        attemptsStarted: 1,
        result: result('SKIPPED')
      })
    ).toEqual(result('SKIPPED'));
  });

  it('fails closed when a retried job finds the post already claimed', () => {
    const enforce = () =>
      enforceRetriedPublishRecoveryPolicy({
        attemptsStarted: 2,
        result: result('SKIPPED')
      });

    expect(enforce).toThrow(UnrecoverableError);
    expect(enforce).toThrow('requires manual provider reconciliation');
  });

  it('returns a completed publish result on later attempts', () => {
    expect(
      enforceRetriedPublishRecoveryPolicy({
        attemptsStarted: 2,
        result: result('PUBLISHED')
      })
    ).toEqual(result('PUBLISHED'));
  });
});
