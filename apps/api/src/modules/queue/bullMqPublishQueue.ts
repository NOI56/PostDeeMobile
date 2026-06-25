import { randomUUID } from 'node:crypto';

import { Queue, type JobType } from 'bullmq';

import type { Platform, QueuedPost } from '../posts/postStore.js';
import type { PublishJob, PublishQueue } from './publishQueue.js';

export const publishQueueName = 'publish-posts';
const jobName = 'publish-post';
const listableJobStatuses: JobType[] = ['waiting', 'delayed', 'active', 'completed', 'failed'];

export type BullMqPublishJobData = {
  userId?: string;
  postId: string;
  caption?: string;
  videoS3Key?: string;
  platforms: Platform[];
  runAt: string;
  status: PublishJob['status'];
};

type BullMqAddOptions = {
  jobId: string;
  delay: number;
  removeOnComplete: boolean;
  removeOnFail: boolean;
};

export type BullMqQueueClient = {
  add: (
    name: string,
    data: BullMqPublishJobData,
    options: BullMqAddOptions
  ) => Promise<{ id?: string | number; timestamp?: number }>;
  getJobs: (
    statuses: JobType[]
  ) => Promise<
    Array<{
      id?: string | number;
      timestamp?: number;
      data: BullMqPublishJobData;
      remove?: () => Promise<void>;
    }>
  >;
};

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
    const runAt = post.scheduledAt ?? new Date(now()).toISOString();
    const status: PublishJob['status'] = post.scheduledAt ? 'SCHEDULED' : 'READY';
    const delay = Math.max(0, Date.parse(runAt) - now());
    const jobId = randomUUID();
    const data = {
      userId: post.userId,
      postId: post.id,
      caption: post.caption,
      videoS3Key: post.videoS3Key,
      platforms: [...post.platforms],
      runAt,
      status
    };
    const addedJob = await queue.add(jobName, data, {
      jobId,
      delay,
      removeOnComplete: true,
      removeOnFail: false
    });

    return {
      id: String(addedJob.id ?? jobId),
      queueName: publishQueueName,
      userId: post.userId,
      postId: post.id,
      platforms: [...post.platforms],
      runAt,
      status,
      createdAt: new Date(addedJob.timestamp ?? now()).toISOString()
    };
  },
  list: async (filter) => {
    const jobs = await queue.getJobs(listableJobStatuses);

    return jobs
      .filter((job) => (filter?.userId ? job.data.userId === filter.userId : true))
      .map((job) => ({
        id: String(job.id),
        queueName: publishQueueName,
        userId: job.data.userId,
        postId: job.data.postId,
        platforms: [...job.data.platforms],
        runAt: job.data.runAt,
        status: job.data.status,
        createdAt: new Date(job.timestamp ?? now()).toISOString()
      }));
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
