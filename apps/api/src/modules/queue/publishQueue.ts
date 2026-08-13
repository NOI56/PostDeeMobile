import { createHash } from 'node:crypto';

import type { PlatformSettings } from '../posts/platformSettings.js';
import type { Platform, QueuedPost } from '../posts/postStore.js';

export type PublishJob = {
  id: string;
  queueName: 'publish-posts';
  userId?: string;
  postId: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  platformSettings?: PlatformSettings;
  runAt: string;
  status: 'READY' | 'SCHEDULED';
  createdAt: string;
};

export type PublishQueue = {
  enqueue: (post: QueuedPost) => Promise<PublishJob>;
  ensureEnqueued: (post: QueuedPost) => Promise<PublishJob>;
  list: (filter?: { userId?: string }) => Promise<PublishJob[]>;
  reschedule: (post: QueuedPost) => Promise<PublishJob>;
  remove: (postId: string) => Promise<void>;
};

export const readPublishRunAt = (post: QueuedPost) =>
  post.scheduledAt ?? post.createdAt;

export const buildPublishJobId = (post: QueuedPost) =>
  `publish_${createHash('sha256')
    .update(post.id)
    .update('\0')
    .update(readPublishRunAt(post))
    .digest('hex')}`;

export const createInMemoryPublishQueue = (): PublishQueue => {
  const jobs: PublishJob[] = [];
  const enqueue = async (post: QueuedPost) => {
    const runAt = readPublishRunAt(post);
    const id = buildPublishJobId(post);
    const existing = jobs.find((candidate) => candidate.id === id);
    if (existing) {
      return existing;
    }
    const job = {
      id,
      queueName: 'publish-posts' as const,
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
      status: post.scheduledAt ? ('SCHEDULED' as const) : ('READY' as const),
      createdAt: new Date().toISOString()
    };

    jobs.push(job);
    return job;
  };

  const remove = async (postId: string, exceptJobId?: string) => {
    const remainingJobs = jobs.filter(
      (job) => job.postId !== postId || job.id === exceptJobId
    );
    jobs.splice(0, jobs.length, ...remainingJobs);
  };

  return {
    enqueue,
    ensureEnqueued: enqueue,
    list: async (filter) =>
      jobs.filter((job) => (filter?.userId ? job.userId === filter.userId : true)),
    reschedule: async (post) => {
      const replacementJob = await enqueue(post);
      await remove(post.id, replacementJob.id);
      return replacementJob;
    },
    remove: async (postId) => {
      await remove(postId);
    }
  };
};
