import { describe, expect, it, vi } from 'vitest';

import {
  PublishOutcomeUnknownError,
  RetryablePublishError,
  processPublishJob,
  processPublishJobForPost
} from './publishWorker.js';

const makeFakePostStore = ({ status = 'QUEUED' }: { status?: string } = {}) => {
  const statuses: string[] = [];

  return {
    statuses,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    store: {
      claimForPublish: async () => {
        if (status !== 'QUEUED') {
          return false;
        }

        statuses.push('PUBLISHING');
        return true;
      },
      updateStatus: async ({ status }: { status: string }) => {
        statuses.push(status);
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any
  };
};

const publishedResult = (platform: string) => ({
  platform,
  status: 'PUBLISHED' as const,
  externalPostId: `mock-${platform}`,
  publishedAt: '2026-06-01T00:00:00.000Z'
});

describe('processPublishJobForPost', () => {
  const jobData = {
    userId: 'seller-1',
    postId: 'post-1',
    caption: 'Caption',
    videoS3Key: 'uploads/video.mp4',
    platforms: ['TIKTOK', 'YOUTUBE_SHORTS'] as const,
    runAt: '2026-06-01T00:00:00.000Z',
    status: 'READY' as const
  };

  it('does not claim or publish a post after account deletion starts', async () => {
    const { store, statuses } = makeFakePostStore();
    const publisher = { publish: vi.fn(async ({ platform }) => publishedResult(platform)) };

    await expect(
      processPublishJobForPost({
        jobData,
        postStore: store,
        publisher,
        storage: { deleteVideo: async () => undefined },
        platformPublishStore: { recordResults: async () => [] },
        assertOwnerActive: async () => {
          throw new Error('account deletion in progress');
        }
      })
    ).rejects.toThrow('account deletion in progress');

    expect(statuses).toEqual([]);
    expect(publisher.publish).not.toHaveBeenCalled();
  });

  it('advances the post to PUBLISHED when every platform succeeds', async () => {
    const { store, statuses } = makeFakePostStore();

    await processPublishJobForPost({
      jobData,
      postStore: store,
      publisher: { publish: async ({ platform }) => publishedResult(platform) },
      storage: { deleteVideo: async () => undefined },
      platformPublishStore: { recordResults: async () => [] }
    });

    expect(statuses).toEqual(['PUBLISHING', 'PUBLISHED']);
  });

  it('advances the post to PARTIAL_PUBLISHED when some platforms fail', async () => {
    const { store, statuses } = makeFakePostStore();

    await processPublishJobForPost({
      jobData,
      postStore: store,
      publisher: {
        publish: async ({ platform }) => {
          if (platform === 'YOUTUBE_SHORTS') {
            throw new Error('youtube down');
          }

          return publishedResult(platform);
        }
      },
      storage: { deleteVideo: async () => undefined },
      platformPublishStore: { recordResults: async () => [] }
    });

    expect(statuses).toEqual(['PUBLISHING', 'PARTIAL_PUBLISHED']);
  });

  it('marks the post FAILED when the job throws', async () => {
    const { store, statuses } = makeFakePostStore();

    await expect(
      processPublishJobForPost({
        jobData,
        postStore: store,
        publisher: { publish: async ({ platform }) => publishedResult(platform) },
        storage: { deleteVideo: async () => undefined },
        platformPublishStore: {
          recordResults: async () => {
            throw new Error('db down');
          }
        }
      })
    ).rejects.toThrow();

    expect(statuses).toEqual(['PUBLISHING', 'FAILED']);
  });

  it('keeps a published post successful when video cleanup fails', async () => {
    const { store, statuses } = makeFakePostStore();

    const result = await processPublishJobForPost({
      jobData,
      postStore: store,
      publisher: { publish: async ({ platform }) => publishedResult(platform) },
      storage: {
        deleteVideo: async () => {
          throw new Error('r2 cleanup down');
        }
      },
      platformPublishStore: { recordResults: async () => [] },
      deleteVideoAfterPublish: true
    });

    expect(statuses).toEqual(['PUBLISHING', 'PUBLISHED']);
    expect(result.status).toBe('PUBLISHED');
    expect(result.cleanup).toEqual({
      status: 'FAILED',
      videoS3Key: 'uploads/video.mp4',
      errorMessage: 'Video cleanup failed. Please try again later.'
    });
  });

  it('skips already finished posts so retry jobs do not publish twice', async () => {
    const { store, statuses } = makeFakePostStore({ status: 'PUBLISHED' });
    const publisher = {
      publish: vi.fn(async ({ platform }) => publishedResult(platform))
    };

    const result = await processPublishJobForPost({
      jobData,
      postStore: store,
      publisher,
      storage: { deleteVideo: async () => undefined },
      platformPublishStore: { recordResults: async () => [] }
    });

    expect(publisher.publish).not.toHaveBeenCalled();
    expect(statuses).toEqual([]);
    expect(result).toEqual({
      postId: 'post-1',
      status: 'SKIPPED',
      platformResults: [],
      cleanup: {
        status: 'SKIPPED',
        videoS3Key: 'uploads/video.mp4'
      }
    });
  });

  it('skips a post already being published so a recovery attempt does not create duplicates', async () => {
    const { store, statuses } = makeFakePostStore({ status: 'PUBLISHING' });
    const publisher = {
      publish: vi.fn(async ({ platform }) => publishedResult(platform))
    };

    const result = await processPublishJobForPost({
      jobData,
      postStore: store,
      publisher,
      storage: { deleteVideo: async () => undefined },
      platformPublishStore: { recordResults: async () => [] }
    });

    expect(publisher.publish).not.toHaveBeenCalled();
    expect(statuses).toEqual([]);
    expect(result.status).toBe('SKIPPED');
  });
});

const baseJobData = {
  postId: 'post-1',
  caption: 'Caption',
  videoS3Key: 'uploads/video.mp4',
  platforms: ['TIKTOK', 'YOUTUBE_SHORTS'] as const,
  runAt: '2026-06-01T00:00:00.000Z',
  status: 'READY' as const
};

describe('processPublishJob', () => {
  it('retries an explicitly safe provider rejection with exponential backoff', async () => {
    const sleep = vi.fn(async () => undefined);
    const publisher = {
      publish: vi.fn(async ({ platform }) => {
        if (publisher.publish.mock.calls.length < 3) {
          throw new RetryablePublishError('provider explicitly rejected before accepting');
        }

        return publishedResult(platform);
      })
    };

    const result = await processPublishJob({
      jobData: {
        ...baseJobData,
        platforms: ['TIKTOK']
      },
      publisher,
      platformPublishStore: { recordResults: vi.fn(async () => []) },
      maxPublishAttempts: 3,
      publishRetryBackoffMs: 100,
      sleep
    });

    expect(publisher.publish).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenNthCalledWith(1, 100);
    expect(sleep).toHaveBeenNthCalledWith(2, 200);
    expect(result.status).toBe('PUBLISHED');
  });

  it('stops retrying an explicitly safe provider rejection at the configured limit', async () => {
    const sleep = vi.fn(async () => undefined);
    const publisher = {
      publish: vi.fn(async () => {
        throw new RetryablePublishError('provider still unavailable');
      })
    };

    const result = await processPublishJob({
      jobData: {
        ...baseJobData,
        platforms: ['TIKTOK']
      },
      publisher,
      platformPublishStore: { recordResults: vi.fn(async () => []) },
      maxPublishAttempts: 3,
      publishRetryBackoffMs: 100,
      sleep
    });

    expect(publisher.publish).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenCalledTimes(2);
    expect(result.status).toBe('FAILED');
  });

  it('does not retry an ambiguous provider error that could already have created a post', async () => {
    const sleep = vi.fn(async () => undefined);
    const publisher = {
      publish: vi.fn(async () => {
        throw new Error('publish outcome unknown after request was sent');
      })
    };

    const result = await processPublishJob({
      jobData: {
        ...baseJobData,
        platforms: ['TIKTOK']
      },
      publisher,
      platformPublishStore: { recordResults: vi.fn(async () => []) },
      maxPublishAttempts: 3,
      publishRetryBackoffMs: 100,
      sleep
    });

    expect(publisher.publish).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
    expect(result.status).toBe('FAILED');
  });

  it('surfaces an unconfirmed provider outcome without retrying the publish call', async () => {
    const sleep = vi.fn(async () => undefined);
    const publisher = {
      publish: vi.fn(async () => {
        throw new PublishOutcomeUnknownError('provider accepted the request but polling timed out');
      })
    };

    const result = await processPublishJob({
      jobData: {
        ...baseJobData,
        platforms: ['TIKTOK']
      },
      publisher,
      platformPublishStore: { recordResults: vi.fn(async () => []) },
      maxPublishAttempts: 3,
      publishRetryBackoffMs: 100,
      sleep
    });

    expect(publisher.publish).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      status: 'FAILED',
      platformResults: [
        {
          platform: 'TIKTOK',
          status: 'FAILED',
          errorMessage:
            'Publishing result could not be confirmed. Check the platform before trying again.'
        }
      ]
    });
  });

  it('passes the post owner id to the platform publisher', async () => {
    const publisher = {
      publish: vi.fn(async ({ platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `mock-${platform}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };

    await processPublishJob({
      jobData: {
        ...baseJobData,
        userId: 'seller-owner'
      },
      publisher,
      platformPublishStore: { recordResults: vi.fn(async () => []) }
    });

    expect(publisher.publish).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 'seller-owner',
        platform: 'TIKTOK'
      })
    );
    expect(publisher.publish).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 'seller-owner',
        platform: 'YOUTUBE_SHORTS'
      })
    );
  });
  it('publishes to every selected platform and cleans up the uploaded video after all succeed', async () => {
    const publisher = {
      publish: vi.fn(async ({ platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `mock-${platform}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };
    const storage = {
      deleteVideo: vi.fn(async () => undefined)
    };
    const platformPublishStore = {
      recordResults: vi.fn(async () => [])
    };

    const result = await processPublishJob({
      jobData: baseJobData,
      publisher,
      storage,
      platformPublishStore,
      deleteVideoAfterPublish: true
    });

    expect(publisher.publish).toHaveBeenCalledTimes(2);
    expect(publisher.publish).toHaveBeenCalledWith({
      postId: 'post-1',
      caption: 'Caption',
      videoS3Key: 'uploads/video.mp4',
      platform: 'TIKTOK'
    });
    expect(publisher.publish).toHaveBeenCalledWith({
      postId: 'post-1',
      caption: 'Caption',
      videoS3Key: 'uploads/video.mp4',
      platform: 'YOUTUBE_SHORTS'
    });
    expect(storage.deleteVideo).toHaveBeenCalledWith('uploads/video.mp4');
    expect(platformPublishStore.recordResults).toHaveBeenCalledWith({
      postId: 'post-1',
      results: [
        {
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          externalPostId: 'mock-TIKTOK',
          publishedAt: '2026-06-01T00:00:00.000Z'
        },
        {
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          externalPostId: 'mock-YOUTUBE_SHORTS',
          publishedAt: '2026-06-01T00:00:00.000Z'
        }
      ]
    });
    expect(result).toEqual({
      postId: 'post-1',
      status: 'PUBLISHED',
      platformResults: [
        {
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          externalPostId: 'mock-TIKTOK',
          publishedAt: '2026-06-01T00:00:00.000Z'
        },
        {
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          externalPostId: 'mock-YOUTUBE_SHORTS',
          publishedAt: '2026-06-01T00:00:00.000Z'
        }
      ],
      cleanup: {
        status: 'DELETED',
        videoS3Key: 'uploads/video.mp4'
      }
    });
  });

  it('does NOT delete the video by default, even when all platforms succeed', async () => {
    const publisher = {
      publish: vi.fn(async ({ platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `mock-${platform}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };
    const storage = { deleteVideo: vi.fn(async () => undefined) };
    const platformPublishStore = { recordResults: vi.fn(async () => []) };

    const result = await processPublishJob({
      jobData: baseJobData,
      publisher,
      storage,
      platformPublishStore
      // deleteVideoAfterPublish omitted -> defaults to false (safe for async
      // PostPeer media fetch).
    });

    expect(storage.deleteVideo).not.toHaveBeenCalled();
    expect(result.cleanup.status).toBe('SKIPPED');
  });

  it('skips cleanup and reports failed platform results when a platform publish fails', async () => {
    const publisher = {
      publish: vi.fn(async ({ platform }) => {
        if (platform === 'YOUTUBE_SHORTS') {
          throw new Error('YouTube API unavailable');
        }

        return {
          platform,
          status: 'PUBLISHED' as const,
          externalPostId: `mock-${platform}`,
          publishedAt: '2026-06-01T00:00:00.000Z'
        };
      })
    };
    const storage = {
      deleteVideo: vi.fn(async () => undefined)
    };

    const result = await processPublishJob({
      jobData: baseJobData,
      publisher,
      storage
    });

    expect(storage.deleteVideo).not.toHaveBeenCalled();
    expect(result).toEqual({
      postId: 'post-1',
      status: 'PARTIAL_FAILED',
      platformResults: [
        {
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          externalPostId: 'mock-TIKTOK',
          publishedAt: '2026-06-01T00:00:00.000Z'
        },
        {
          platform: 'YOUTUBE_SHORTS',
          status: 'FAILED',
          errorMessage: 'Publishing to this platform failed. Please try again later.'
        }
      ],
      cleanup: {
        status: 'SKIPPED',
        videoS3Key: 'uploads/video.mp4'
      }
    });
  });

  it('reports cleanup failure without failing an already published job', async () => {
    const publisher = {
      publish: vi.fn(async ({ platform }) => ({
        platform,
        status: 'PUBLISHED' as const,
        externalPostId: `mock-${platform}`,
        publishedAt: '2026-06-01T00:00:00.000Z'
      }))
    };
    const storage = {
      deleteVideo: vi.fn(async () => {
        throw new Error('r2 cleanup down');
      })
    };

    const result = await processPublishJob({
      jobData: baseJobData,
      publisher,
      storage,
      deleteVideoAfterPublish: true
    });

    expect(storage.deleteVideo).toHaveBeenCalledWith('uploads/video.mp4');
    expect(result).toMatchObject({
      postId: 'post-1',
      status: 'PUBLISHED',
      cleanup: {
        status: 'FAILED',
        videoS3Key: 'uploads/video.mp4',
        errorMessage: 'Video cleanup failed. Please try again later.'
      }
    });
  });
});
