import { describe, expect, it, vi } from 'vitest';

import type { PostStore } from '../modules/posts/postStore.js';
import type { BullMqPublishJobData } from '../modules/queue/bullMqPublishQueue.js';
import { processPublishJobForPost } from './publishWorker.js';

const baseJob = {
  userId: 'u1',
  postId: 'p1',
  platforms: ['TIKTOK'],
  runAt: '2026-06-26T00:00:00.000Z',
  status: 'READY'
} as unknown as BullMqPublishJobData;

const createPostStoreStub = () =>
  ({
    claimForPublish: vi.fn(async () => true),
    updateStatus: vi.fn(async () => undefined)
  }) as unknown as PostStore;

describe('processPublishJobForPost notifications', () => {
  it('notifies the post owner with the publish outcome', async () => {
    const notifyPublishResult = vi.fn(async () => undefined);

    await processPublishJobForPost({
      jobData: baseJob,
      postStore: createPostStoreStub(),
      notifier: { notifyPublishResult }
    });

    expect(notifyPublishResult).toHaveBeenCalledWith({
      userId: 'u1',
      postId: 'p1',
      outcome: 'PUBLISHED'
    });
  });

  it('does not let a notification failure break publishing', async () => {
    const notifyPublishResult = vi.fn(async () => {
      throw new Error('push provider down');
    });

    const result = await processPublishJobForPost({
      jobData: baseJob,
      postStore: createPostStoreStub(),
      notifier: { notifyPublishResult }
    });

    expect(result.status).toBe('PUBLISHED');
  });
});
