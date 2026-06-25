import { describe, expect, it } from 'vitest';

import { createPublishQueueFromConfig } from './publishQueueFactory.js';

const baseConfig = {
  publishQueue: 'memory' as const,
  redisUrl: 'redis://localhost:6379'
};

describe('createPublishQueueFromConfig', () => {
  it('uses the in-memory queue by default', async () => {
    const queue = createPublishQueueFromConfig({
      config: baseConfig
    });

    const job = await queue.enqueue({
      id: 'post-1',
      caption: 'Ready now',
      videoS3Key: 'uploads/video.mp4',
      platforms: ['TIKTOK'],
      status: 'QUEUED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });

    expect(await queue.list()).toEqual([job]);
  });

  it('uses a BullMQ-backed queue when configured', async () => {
    const addedJobs: unknown[] = [];
    const queue = createPublishQueueFromConfig({
      config: {
        publishQueue: 'bullmq',
        redisUrl: 'redis://localhost:6379'
      },
      bullMqQueue: {
        add: async (_name, data, options) => {
          addedJobs.push({ data, options });
          return {
            id: options.jobId,
            timestamp: Date.parse('2026-06-01T00:00:00.000Z')
          };
        },
        getJobs: async () => []
      },
      now: () => Date.parse('2026-06-01T00:00:00.000Z')
    });

    const job = await queue.enqueue({
      id: 'post-2',
      caption: 'Schedule later',
      videoS3Key: 'uploads/video.mp4',
      platforms: ['YOUTUBE_SHORTS'],
      scheduledAt: '2026-06-01T01:00:00.000Z',
      status: 'QUEUED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });

    expect(job).toMatchObject({
      queueName: 'publish-posts',
      postId: 'post-2',
      platforms: ['YOUTUBE_SHORTS'],
      runAt: '2026-06-01T01:00:00.000Z',
      status: 'SCHEDULED',
      createdAt: '2026-06-01T00:00:00.000Z'
    });
    expect(addedJobs).toEqual([
      {
        data: expect.objectContaining({
          postId: 'post-2',
          runAt: '2026-06-01T01:00:00.000Z',
          status: 'SCHEDULED'
        }),
        options: expect.objectContaining({
          delay: 3_600_000,
          removeOnComplete: true,
          removeOnFail: false
        })
      }
    ]);
  });
});
