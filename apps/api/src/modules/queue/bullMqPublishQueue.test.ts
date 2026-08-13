import { describe, expect, it, vi } from 'vitest';

import { createBullMqPublishQueueFromClient } from './bullMqPublishQueue.js';
import { buildPublishJobId } from './publishQueue.js';

describe('createBullMqPublishQueueFromClient', () => {
  it('adds immediate posts to BullMQ with no delay', async () => {
    const queueClient = {
      add: vi.fn().mockResolvedValue({
        id: 'bull-job-1',
        timestamp: Date.parse('2026-06-01T00:00:00.000Z')
      }),
      getJobs: vi.fn().mockResolvedValue([])
    };
    const queue = createBullMqPublishQueueFromClient({
      queue: queueClient,
      now: () => Date.parse('2026-06-01T00:00:00.000Z')
    });

    const job = await queue.enqueue({
      id: 'post-1',
      userId: 'seller-cover',
      caption: 'Publish now',
      videoS3Key: 'uploads/video.mp4',
      coverImageS3Key: 'uploads/cover.jpg',
      coverFrameTimeMs: 2_000,
      platforms: ['FACEBOOK_REELS'],
      status: 'QUEUED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });

    expect(queueClient.add).toHaveBeenCalledWith(
      'publish-post',
      expect.objectContaining({
        postId: 'post-1',
        userId: 'seller-cover',
        coverImageS3Key: 'uploads/cover.jpg',
        coverFrameTimeMs: 2_000,
        platforms: ['FACEBOOK_REELS'],
        runAt: expect.any(String),
        status: 'READY'
      }),
      expect.objectContaining({
        attempts: 3,
        backoff: {
          type: 'exponential',
          delay: 5_000
        },
        delay: 0,
        removeOnComplete: true,
        removeOnFail: false
      })
    );
    expect(job).toMatchObject({
      id: 'bull-job-1',
      queueName: 'publish-posts',
      postId: 'post-1',
      userId: 'seller-cover',
      coverImageS3Key: 'uploads/cover.jpg',
      coverFrameTimeMs: 2_000,
      platforms: ['FACEBOOK_REELS'],
      status: 'READY'
    });
  });

  it('maps existing BullMQ jobs back to publish queue snapshots', async () => {
    const queueClient = {
      add: vi.fn(),
      getJobs: vi.fn().mockResolvedValue([
        {
          id: 'bull-job-2',
          timestamp: Date.parse('2026-06-01T00:00:00.000Z'),
          data: {
            postId: 'post-2',
            platforms: ['TIKTOK'],
            runAt: '2026-06-01T01:00:00.000Z',
            status: 'SCHEDULED'
          }
        }
      ])
    };
    const queue = createBullMqPublishQueueFromClient({
      queue: queueClient,
      now: () => Date.parse('2026-06-01T00:00:00.000Z')
    });

    expect(await queue.list()).toEqual([
      {
        id: 'bull-job-2',
        queueName: 'publish-posts',
        postId: 'post-2',
        platforms: ['TIKTOK'],
        runAt: '2026-06-01T01:00:00.000Z',
        status: 'SCHEDULED',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
    expect(queueClient.getJobs).toHaveBeenCalledWith([
      'waiting',
      'delayed',
      'active',
      'completed',
      'failed'
    ]);
  });

  it('repairs a failed deterministic job and leaves a healthy retry alone', async () => {
    const post = {
      id: 'post-idempotent-repair',
      userId: 'seller-repair',
      caption: 'Repair queue',
      videoS3Key: 'uploads/repair.mp4',
      platforms: ['TIKTOK'] as const,
      status: 'QUEUED' as const,
      createdAt: '2026-06-01T00:00:00.000Z'
    };
    const jobId = buildPublishJobId(post);
    const remove = vi.fn().mockResolvedValue(undefined);
    const job = {
      id: jobId,
      timestamp: Date.parse(post.createdAt),
      data: {
        userId: post.userId,
        postId: post.id,
        caption: post.caption,
        videoS3Key: post.videoS3Key,
        platforms: [...post.platforms],
        runAt: post.createdAt,
        status: 'READY' as const
      },
      getState: vi.fn().mockResolvedValueOnce('failed').mockResolvedValue('waiting'),
      remove
    };
    const queueClient = {
      add: vi.fn().mockResolvedValue({ id: jobId, timestamp: Date.parse(post.createdAt) }),
      getJobs: vi.fn().mockResolvedValue([job])
    };
    const queue = createBullMqPublishQueueFromClient({ queue: queueClient });

    await queue.ensureEnqueued(post);
    expect(remove).toHaveBeenCalledOnce();
    expect(queueClient.add).toHaveBeenCalledOnce();

    queueClient.add.mockClear();
    remove.mockClear();
    await queue.ensureEnqueued(post);
    expect(remove).not.toHaveBeenCalled();
    expect(queueClient.add).not.toHaveBeenCalled();
  });

  it('removes BullMQ jobs for a canceled post', async () => {
    const removeMatchingJob = vi.fn().mockResolvedValue(undefined);
    const removeOtherJob = vi.fn().mockResolvedValue(undefined);
    const queueClient = {
      add: vi.fn(),
      getJobs: vi.fn().mockResolvedValue([
        {
          id: 'bull-job-canceled',
          timestamp: Date.parse('2026-06-01T00:00:00.000Z'),
          data: {
            postId: 'post-canceled',
            platforms: ['TIKTOK'],
            runAt: '2026-06-01T01:00:00.000Z',
            status: 'SCHEDULED'
          },
          remove: removeMatchingJob
        },
        {
          id: 'bull-job-other',
          timestamp: Date.parse('2026-06-01T00:00:00.000Z'),
          data: {
            postId: 'post-other',
            platforms: ['YOUTUBE_SHORTS'],
            runAt: '2026-06-01T01:00:00.000Z',
            status: 'SCHEDULED'
          },
          remove: removeOtherJob
        }
      ])
    };
    const queue = createBullMqPublishQueueFromClient({
      queue: queueClient,
      now: () => Date.parse('2026-06-01T00:00:00.000Z')
    });

    await queue.remove('post-canceled');

    expect(removeMatchingJob).toHaveBeenCalledTimes(1);
    expect(removeOtherJob).not.toHaveBeenCalled();
  });

  it('replaces BullMQ jobs when a scheduled post is rescheduled', async () => {
    const removeOldJob = vi.fn().mockResolvedValue(undefined);
    const queueClient = {
      add: vi.fn().mockResolvedValue({
        id: 'bull-job-replacement',
        timestamp: Date.parse('2026-06-01T00:00:00.000Z')
      }),
      getJobs: vi.fn().mockResolvedValue([
        {
          id: 'bull-job-old',
          timestamp: Date.parse('2026-06-01T00:00:00.000Z'),
          data: {
            postId: 'post-rescheduled',
            platforms: ['INSTAGRAM_REELS'],
            runAt: '2026-06-01T01:00:00.000Z',
            status: 'SCHEDULED'
          },
          remove: removeOldJob
        }
      ])
    };
    const queue = createBullMqPublishQueueFromClient({
      queue: queueClient,
      now: () => Date.parse('2026-06-01T00:00:00.000Z')
    });

    const job = await queue.reschedule({
      id: 'post-rescheduled',
      userId: 'seller-rescheduled',
      caption: 'Updated time',
      videoS3Key: 'uploads/rescheduled.mp4',
      coverImageS3Key: 'uploads/rescheduled-cover.jpg',
      coverFrameTimeMs: 3_000,
      platforms: ['INSTAGRAM_REELS'],
      scheduledAt: '2026-06-01T02:00:00.000Z',
      status: 'QUEUED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });

    expect(removeOldJob).toHaveBeenCalledTimes(1);
    expect(queueClient.add.mock.invocationCallOrder[0]).toBeLessThan(
      removeOldJob.mock.invocationCallOrder[0]
    );
    expect(queueClient.add).toHaveBeenCalledWith(
      'publish-post',
      expect.objectContaining({
        postId: 'post-rescheduled',
        userId: 'seller-rescheduled',
        coverImageS3Key: 'uploads/rescheduled-cover.jpg',
        coverFrameTimeMs: 3_000,
        runAt: '2026-06-01T02:00:00.000Z',
        status: 'SCHEDULED'
      }),
      expect.objectContaining({
        delay: 7_200_000
      })
    );
    expect(job).toMatchObject({
      id: 'bull-job-replacement',
      postId: 'post-rescheduled',
      runAt: '2026-06-01T02:00:00.000Z'
    });
  });
});
