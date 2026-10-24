import { describe, expect, it, vi } from 'vitest';

import type { RunWithActiveOwner } from '../modules/account/ownerOperationQueue.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore, maxDuePostsPerPoll } from '../modules/posts/postStore.js';
import type { SubscriptionPlan } from '../modules/subscriptions/subscriptionStore.js';
import { createInMemoryUploadSessionStore } from '../modules/uploads/uploadSessionStore.js';
import { createPublishScheduler, maxDueBatchesPerPoll } from './publishScheduler.js';
import type { PlatformPublisher } from './publishWorker.js';

const published: PlatformPublisher['publish'] = async ({ platform }) => ({
  platform, status: 'PUBLISHED', externalPostId: `https://example.test/${platform}`,
  deliveryOutcome: 'LIVE', publishedAt: '2026-10-25T00:00:00.000Z'
});
const past = () => new Date(Date.now() - 60_000).toISOString();

const createScheduledPost = async (postStore: ReturnType<typeof createPostStore>, userId: string, caption = 'Scheduled clip') =>
  postStore.create({
    userId, caption, videoS3Key: `uploads/${userId}/v.mp4`, platforms: ['TIKTOK'], scheduledAt: past()
  });

describe('scheduler review fixes (Codex review 2026-10-25)', () => {
  it('keeps publishing other owners when the oldest due batch belongs to an owner it cannot start', async () => {
    const postStore = createPostStore();
    for (let index = 0; index < maxDuePostsPerPoll; index += 1) {
      await createScheduledPost(postStore, 'deleting-owner', `stuck ${index}`);
    }
    const healthy = await createScheduledPost(postStore, 'healthy-owner');
    const publish = vi.fn(published);
    const runWithActiveOwner: RunWithActiveOwner = async (ownerId, operation) => {
      if (ownerId === 'deleting-owner') throw new Error('Account deletion is in progress');
      return operation();
    };

    await createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish }, runWithActiveOwner
    }).runOnce();

    expect((await postStore.findOwned({ postId: healthy.id, userId: 'healthy-owner' }))?.status).toBe('PUBLISHED');
    expect(publish).toHaveBeenCalledTimes(1);
    expect((await postStore.list({ userId: 'deleting-owner' })).every((post) => post.status === 'QUEUED')).toBe(true);
  });

  it('reaches posts behind a full poll of posts it cannot start on a later poll', async () => {
    const postStore = createPostStore();
    for (let index = 0; index < maxDuePostsPerPoll * maxDueBatchesPerPoll; index += 1) {
      await createScheduledPost(postStore, 'deleting-owner', `stuck ${index}`);
    }
    const healthy = await createScheduledPost(postStore, 'healthy-owner');
    const publish = vi.fn(published);
    const runWithActiveOwner: RunWithActiveOwner = async (ownerId, operation) => {
      if (ownerId === 'deleting-owner') throw new Error('Account deletion is in progress');
      return operation();
    };
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish }, runWithActiveOwner
    });

    await scheduler.runOnce();
    await scheduler.runOnce();

    expect((await postStore.findOwned({ postId: healthy.id, userId: 'healthy-owner' }))?.status).toBe('PUBLISHED');
    expect(publish).toHaveBeenCalledTimes(1);
  });

  it('still bounds one poll to a fixed number of due-post batches', async () => {
    const postStore = createPostStore();
    for (let index = 0; index < maxDuePostsPerPoll * (maxDueBatchesPerPoll + 1); index += 1) {
      await createScheduledPost(postStore, 'deleting-owner', `stuck ${index}`);
    }
    const listDue = vi.spyOn(postStore, 'listDue');
    const runWithActiveOwner: RunWithActiveOwner = async () => { throw new Error('Account deletion is in progress'); };

    await createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), runWithActiveOwner
    }).runOnce();

    expect(listDue).toHaveBeenCalledTimes(maxDueBatchesPerPoll);
    expect(maxDueBatchesPerPoll).toBe(10);
  });

  it('does not hold account deletion after a plan read fails and the retry publishes', async () => {
    const postStore = createPostStore();
    const uploadSessions = createInMemoryUploadSessionStore({ ownerOperationOptions: { maxWaitMs: 50, pollIntervalMs: 5 } });
    const post = await createScheduledPost(postStore, 'seller-plan');
    const readOwnerPlan = vi.fn<() => Promise<SubscriptionPlan>>()
      .mockRejectedValueOnce(new Error('database unavailable'))
      .mockResolvedValue('PRO');

    await createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish: vi.fn(published) },
      readOwnerPlan, runWithActiveOwner: uploadSessions.runWithOwnerLifetime,
      maxPrePublishAttempts: 2, prePublishRetryBackoffMs: 0
    }).runOnce();

    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('PUBLISHED');
    await uploadSessions.beginOwnerDeletion('seller-plan');
    await expect(uploadSessions.acquireOwnerDeletion('seller-plan')).resolves.toBeTypeOf('function');
  });

  it('publishes a post the owner switched to post-now while the plan was being read', async () => {
    const postStore = createPostStore();
    const post = await createScheduledPost(postStore, 'seller-plan');
    const publish = vi.fn(published);
    const readOwnerPlan = vi.fn(async (): Promise<SubscriptionPlan> => {
      await postStore.publishNow({ postId: post.id, userId: 'seller-plan', expectedScheduledAt: post.scheduledAt });
      return 'BASIC';
    });
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish }, readOwnerPlan
    });

    // The stale scheduled job cannot claim the post-now row; the next poll
    // reads it as post-now, which is not plan-checked.
    await scheduler.runOnce();
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).not.toBe('FAILED');
    await scheduler.runOnce();

    expect(publish).toHaveBeenCalledTimes(1);
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('PUBLISHED');
  });

  it('fails an expired-plan scheduled post without extra reads that could hold account deletion', async () => {
    const postStore = createPostStore();
    const uploadSessions = createInMemoryUploadSessionStore({ ownerOperationOptions: { maxWaitMs: 50, pollIntervalMs: 5 } });
    const post = await createScheduledPost(postStore, 'seller-plan');
    const findOwned = vi.spyOn(postStore, 'findOwned').mockRejectedValue(new Error('database unavailable'));

    await createPublishScheduler({
      postStore, platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish: vi.fn(published) },
      readOwnerPlan: async () => 'BASIC', runWithActiveOwner: uploadSessions.runWithOwnerLifetime,
      maxPrePublishAttempts: 2, prePublishRetryBackoffMs: 0
    }).runOnce();
    findOwned.mockRestore();

    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('FAILED');
    await uploadSessions.beginOwnerDeletion('seller-plan');
    await expect(uploadSessions.acquireOwnerDeletion('seller-plan')).resolves.toBeTypeOf('function');
  });
});
