import { UnrecoverableError } from 'bullmq';
import { describe, expect, it } from 'vitest';

import type { PublishWorkerResult } from './publishWorker.js';
import {
  buildPublishWorkerCompletedLog,
  buildPublishWorkerFailedLog,
  enforceRetriedPublishRecoveryPolicy
} from './publishWorkerRunnerPolicy.js';

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

  it('redacts provider identifiers and raw errors from operational logs', () => {
    const providerPostId = 'sentinel-provider-post-id';
    const externalPostId = 'sentinel-external-post-id';
    const providerSecret = 'sentinel-provider-secret-payload';
    const completed = buildPublishWorkerCompletedLog({
      result: {
        postId: 'post-1',
        status: 'PUBLISHED',
        platformResults: [
          {
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            providerPostId,
            externalPostId,
            deliveryOutcome: 'DRAFT',
            publishedAt: '2026-08-13T00:00:00.000Z'
          }
        ],
        cleanup: { status: 'SKIPPED' }
      }
    });
    const failed = buildPublishWorkerFailedLog({
      postId: 'post-2',
      platforms: [{ platform: 'YOUTUBE_SHORTS' }],
      error: new Error(providerSecret)
    });
    const serialized = JSON.stringify({ completed, failed });

    expect(completed).toEqual({
      postId: 'post-1',
      status: 'PUBLISHED',
      platforms: [
        { platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'DRAFT' }
      ]
    });
    expect(failed).toEqual({
      postId: 'post-2',
      status: 'FAILED',
      platforms: [{ platform: 'YOUTUBE_SHORTS', status: 'FAILED' }],
      errorName: 'Error',
      message: 'Publish worker job failed; inspect sanitized platform results and provider dashboards'
    });
    expect(serialized).not.toContain(providerPostId);
    expect(serialized).not.toContain(externalPostId);
    expect(serialized).not.toContain(providerSecret);
  });
});
