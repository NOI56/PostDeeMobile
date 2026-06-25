import { describe, expect, it, vi } from 'vitest';

import { createBullMqPublishQueueFromClient } from './bullMqPublishQueue.js';

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
      caption: 'Publish now',
      videoS3Key: 'uploads/video.mp4',
      platforms: ['FACEBOOK_REELS'],
      status: 'QUEUED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });

    expect(queueClient.add).toHaveBeenCalledWith(
      'publish-post',
      expect.objectContaining({
        postId: 'post-1',
        platforms: ['FACEBOOK_REELS'],
        runAt: expect.any(String),
        status: 'READY'
      }),
      expect.objectContaining({
        delay: 0,
        removeOnComplete: true,
        removeOnFail: false
      })
    );
    expect(job).toMatchObject({
      id: 'bull-job-1',
      queueName: 'publish-posts',
      postId: 'post-1',
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
