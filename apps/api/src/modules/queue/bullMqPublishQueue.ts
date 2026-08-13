import { Queue, type JobType } from 'bullmq';

import type { PlatformSettings } from '../posts/platformSettings.js';
import type { PlatformTargets } from '../posts/platformTargets.js';
import type { Platform, QueuedPost } from '../posts/postStore.js';
import {
  buildPublishJobId,
  readPublishRunAt,
  type PublishJob,
  type PublishQueue
} from './publishQueue.js';

export const publishQueueName = 'publish-posts';
const jobName = 'publish-post';
const listableJobStatuses: JobType[] = ['waiting', 'delayed', 'active', 'completed', 'failed'];

export type BullMqPublishJobData = {
  userId?: string;
  postId: string;
  caption?: string;
  videoS3Key?: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  platformSettings?: PlatformSettings | null;
  // Internal target evidence; never map this onto public PublishJob responses.
  platformTargets?: PlatformTargets | null;
  runAt: string;
  status: PublishJob['status'];
};

type BullMqAddOptions = {
  jobId: string;
  delay: number;
  attempts: number;
  backoff: {
    type: 'exponential';
    delay: number;
  };
  removeOnComplete: boolean;
  removeOnFail: boolean;
};

const publishJobMaxAttempts = 3;
const publishJobRetryBackoffMs = 5_000;

export type BullMqQueueClient = {
  add: (
    name: string,
    data: BullMqPublishJobData,
    options: BullMqAddOptions
  ) => Promise<{ id?: string | number; timestamp?: number }>;
  getJobs: (statuses: JobType[]) => Promise<BullMqJobSnapshot[]>;
};

type BullMqJobSnapshot = {
  id?: string | number;
  timestamp?: number;
  data: BullMqPublishJobData;
  getState?: () => Promise<string>;
  remove?: () => Promise<void>;
};

const healthyBullMqStates = new Set([
  'active',
  'delayed',
  'prioritized',
  'waiting',
  'waiting-children'
]);

const mapBullMqJob = (job: BullMqJobSnapshot, now: () => number): PublishJob => ({
  id: String(job.id),
  queueName: publishQueueName,
  userId: job.data.userId,
  postId: job.data.postId,
  ...(job.data.coverImageS3Key ? { coverImageS3Key: job.data.coverImageS3Key } : {}),
  ...(job.data.coverFrameTimeMs !== undefined
    ? { coverFrameTimeMs: job.data.coverFrameTimeMs }
    : {}),
  platforms: [...job.data.platforms],
  ...(job.data.platformSettings ? { platformSettings: job.data.platformSettings } : {}),
  runAt: job.data.runAt,
  status: job.data.status,
  createdAt: new Date(job.timestamp ?? now()).toISOString()
});

export const parseRedisConnection = (redisUrl: string) => {
  const parsed = new URL(redisUrl);
  const port = parsed.port ? Number(parsed.port) : 6379;
  const db = parsed.pathname.length > 1 ? Number(parsed.pathname.slice(1)) : undefined;

  if (parsed.protocol !== 'redis:' && parsed.protocol !== 'rediss:') {
    throw new Error('REDIS_URL must use redis:// or rediss://');
  }

  return {
    host: parsed.hostname,
    port,
    username: parsed.username ? decodeURIComponent(parsed.username) : undefined,
    password: parsed.password ? decodeURIComponent(parsed.password) : undefined,
    db: Number.isInteger(db) ? db : undefined,
    tls: parsed.protocol === 'rediss:' ? {} : undefined
  };
};

export const createBullMqPublishQueueFromClient = ({
  queue,
  now = Date.now
}: {
  queue: BullMqQueueClient;
  now?: () => number;
}): PublishQueue => ({
  enqueue: async (post: QueuedPost) => {
    const runAt = readPublishRunAt(post);
    const status: PublishJob['status'] = post.scheduledAt ? 'SCHEDULED' : 'READY';
    const delay = Math.max(0, Date.parse(runAt) - now());
    const jobId = buildPublishJobId(post);
    const data = {
      userId: post.userId,
      postId: post.id,
      caption: post.caption,
      videoS3Key: post.videoS3Key,
      ...(post.coverImageS3Key
        ? { coverImageS3Key: post.coverImageS3Key }
        : {}),
      ...(post.coverFrameTimeMs !== undefined
        ? { coverFrameTimeMs: post.coverFrameTimeMs }
        : {}),
      platforms: [...post.platforms],
      ...(post.platformSettings ? { platformSettings: post.platformSettings } : {}),
      ...(post.platformTargets ? { platformTargets: post.platformTargets } : {}),
      runAt,
      status
    };
    const addedJob = await queue.add(jobName, data, {
      jobId,
      delay,
      attempts: publishJobMaxAttempts,
      backoff: {
        type: 'exponential',
        delay: publishJobRetryBackoffMs
      },
      removeOnComplete: true,
      removeOnFail: false
    });

    return {
      id: String(addedJob.id ?? jobId),
      queueName: publishQueueName,
      userId: post.userId,
      postId: post.id,
      ...(post.coverImageS3Key
        ? { coverImageS3Key: post.coverImageS3Key }
        : {}),
      ...(post.coverFrameTimeMs !== undefined
        ? { coverFrameTimeMs: post.coverFrameTimeMs }
        : {}),
      platforms: [...post.platforms],
      ...(post.platformSettings ? { platformSettings: post.platformSettings } : {}),
      runAt,
      status,
      createdAt: new Date(addedJob.timestamp ?? now()).toISOString()
    };
  },
  ensureEnqueued: async (post) => {
    const expectedJobId = buildPublishJobId(post);
    const jobs = await queue.getJobs(listableJobStatuses);
    const expectedJob = jobs.find((job) => String(job.id) === expectedJobId);

    if (expectedJob) {
      const state = await expectedJob.getState?.();
      if (state && healthyBullMqStates.has(state)) {
        return mapBullMqJob(expectedJob, now);
      }
    }

    const staleJobs = jobs.filter((job) => job.data.postId === post.id);
    await Promise.all(
      staleJobs.map(async (job) => {
        if (!job.remove) {
          throw new Error('Publish queue cannot remove an unhealthy job');
        }
        await job.remove();
      })
    );

    return createBullMqPublishQueueFromClient({ queue, now }).enqueue(post);
  },
  list: async (filter) => {
    const jobs = await queue.getJobs(listableJobStatuses);

    return jobs
      .filter((job) => (filter?.userId ? job.data.userId === filter.userId : true))
      .map((job) => mapBullMqJob(job, now));
  },
  reschedule: async (post) => {
    const replacementJob = await createBullMqPublishQueueFromClient({ queue, now }).enqueue(post);
    await removeJobsForPost(queue, post.id, replacementJob.id);
    return replacementJob;
  },
  remove: async (postId) => {
    await removeJobsForPost(queue, postId);
  }
});

const removeJobsForPost = async (
  queue: BullMqQueueClient,
  postId: string,
  exceptJobId?: string
) => {
  const jobs = await queue.getJobs(listableJobStatuses);
  const matchingJobs = jobs.filter(
    (job) => job.data.postId === postId && String(job.id) !== exceptJobId
  );

  await Promise.all(
    matchingJobs.map(async (job) => {
      await job.remove?.();
    })
  );
};

export const createBullMqPublishQueue = ({
  redisUrl,
  now
}: {
  redisUrl: string;
  now?: () => number;
}): PublishQueue => {
  const queue = new Queue<BullMqPublishJobData>(publishQueueName, {
    connection: parseRedisConnection(redisUrl)
  });

  return createBullMqPublishQueueFromClient({
    queue: {
      add: async (name, data, options) => {
        const job = await queue.add(name, data, options);

        return {
          id: job.id,
          timestamp: job.timestamp
        };
      },
      getJobs: async (statuses) => queue.getJobs(statuses)
    },
    now
  });
};
