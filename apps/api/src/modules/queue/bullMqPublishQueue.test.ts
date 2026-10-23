import { describe, expect, it, vi } from 'vitest';

import type { QueuedPost } from '../posts/postStore.js';
import { createBullMqPublishQueueFromClient } from './bullMqPublishQueue.js';
import { buildPublishJobId } from './publishQueue.js';

describe('createBullMqPublishQueueFromClient', () => {
  it('keeps all caption overrides when replacing a rescheduled BullMQ snapshot', async () => {
    const platformSettings = {
      TIKTOK: { publishMode: 'INBOX_DRAFT' as const, caption: 'TikTok' },
      YOUTUBE_SHORTS: { visibility: 'private' as const, caption: 'YouTube' },
      INSTAGRAM_REELS: { shareToFeed: true, caption: 'Instagram' },
      FACEBOOK_REELS: { publishMode: 'PUBLISH' as const, caption: 'Facebook' }
    };
    const timestamp = Date.parse('2026-06-01T00:00:00.000Z');
    const queueClient = { add: vi.fn().mockResolvedValue({ id: 'new-job', timestamp }), getJobs: vi.fn().mockResolvedValue([]) };
    const queue = createBullMqPublishQueueFromClient({ queue: queueClient, now: () => timestamp });
    const job = await queue.reschedule({ id: 'four-captions', userId: 'owner', caption: 'Representative',
      videoS3Key: 'uploads/owner/v.mp4', platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'],
      platformSettings, scheduledAt: '2026-06-03T10:00:00.000Z', status: 'QUEUED', createdAt: '2026-06-01T00:00:00.000Z' });
    expect(queueClient.add.mock.calls[0][1]).toMatchObject({ platformSettings, caption: 'Representative', runAt: '2026-06-03T10:00:00.000Z' });
    expect(job.platformSettings).toEqual(platformSettings);
  });

  it.each([undefined, true, false])('retains historical and explicit Meta AI declarations in BullMQ snapshots (%s)', async (isAiGenerated) => {
    const aiSetting = isAiGenerated === undefined ? {} : { isAiGenerated };
    const platformSettings = {
      INSTAGRAM_REELS: { shareToFeed: false, ...aiSetting },
      FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' as const, ...aiSetting }
    };
    const timestamp = Date.parse('2026-06-01T00:00:00.000Z');
    const queueClient = {
      add: vi.fn().mockResolvedValue({ id: 'meta-job', timestamp }),
      getJobs: vi.fn().mockResolvedValue([])
    };
    const queue = createBullMqPublishQueueFromClient({ queue: queueClient, now: () => timestamp });
    const job = await queue.enqueue({
      id: 'meta-post', userId: 'owner', caption: 'Meta media', videoS3Key: 'uploads/video.mp4',
      platforms: ['INSTAGRAM_REELS', 'FACEBOOK_REELS'], platformSettings,
      status: 'QUEUED', createdAt: '2026-06-01T00:00:00.000Z'
    });
    const data = queueClient.add.mock.calls[0][1];
    expect(data.platformSettings).toEqual(platformSettings);
    expect(job.platformSettings).toEqual(platformSettings);
    queueClient.getJobs.mockResolvedValue([{ id: 'meta-job', timestamp, data }]);
    expect((await queue.list())[0].platformSettings).toEqual(platformSettings);
  });

  it('probes Redis without loading jobs and closes the owned connection', async () => {
    const queueClient = {
      add: vi.fn(), getJobs: vi.fn(),
      checkReady: vi.fn(async () => undefined), close: vi.fn(async () => undefined)
    };
    const queue = createBullMqPublishQueueFromClient({ queue: queueClient });
    await queue.checkReady();
    await queue.close();
    expect(queueClient.checkReady).toHaveBeenCalledOnce();
    expect(queueClient.close).toHaveBeenCalledOnce();
    expect(queueClient.getJobs).not.toHaveBeenCalled();
  });

  it('does not claim Redis is ready without a configured connection probe', async () => {
    const queue = createBullMqPublishQueueFromClient({ queue: { add: vi.fn(), getJobs: vi.fn() } });
    await expect(queue.checkReady()).rejects.toThrow('Publish queue readiness probe unavailable');
  });

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
    const post: QueuedPost = {
      id: 'post-idempotent-repair',
      userId: 'seller-repair',
      caption: 'Repair queue',
      videoS3Key: 'uploads/repair.mp4',
      platforms: ['TIKTOK'],
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
