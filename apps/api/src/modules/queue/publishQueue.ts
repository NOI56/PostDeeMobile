import { randomUUID } from 'node:crypto';

import type { Platform, QueuedPost } from '../posts/postStore.js';

export type PublishJob = {
  id: string;
  queueName: 'publish-posts';
  userId?: string;
  postId: string;
  platforms: Platform[];
  runAt: string;
  status: 'READY' | 'SCHEDULED';
  createdAt: string;
};

export type PublishQueue = {
  enqueue: (post: QueuedPost) => Promise<PublishJob>;
  list: (filter?: { userId?: string }) => Promise<PublishJob[]>;
  reschedule: (post: QueuedPost) => Promise<PublishJob>;
  remove: (postId: string) => Promise<void>;
};

export const createInMemoryPublishQueue = (): PublishQueue => {
  const jobs: PublishJob[] = [];
  const enqueue = async (post: QueuedPost) => {
    const runAt = post.scheduledAt ?? new Date().toISOString();
    const job = {
      id: randomUUID(),
      queueName: 'publish-posts' as const,
      userId: post.userId,
      postId: post.id,
      platforms: [...post.platforms],
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
