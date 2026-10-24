import { describe, expect, it, vi } from 'vitest';

import { readServerConfig } from '../config/env.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore } from '../modules/posts/postStore.js';
import type { SubscriptionPlan, SubscriptionStore } from '../modules/subscriptions/subscriptionStore.js';
import { createPublishScheduler } from './publishScheduler.js';
import { processPublishJobForPost, type PlatformPublisher } from './publishWorker.js';
import {
  createScheduledPublishPlanReader,
  paidPlanRequiredPublishError
} from './scheduledPublishPlan.js';

const published: PlatformPublisher['publish'] = async ({ platform }) => ({
  platform, status: 'PUBLISHED', externalPostId: `https://example.test/${platform}`,
  deliveryOutcome: 'LIVE', publishedAt: '2026-10-24T00:00:00.000Z'
});

const createFixture = async ({ scheduled = true } = {}) => {
  const postStore = createPostStore();
  const platformPublishStore = createInMemoryPlatformPublishStore();
  const post = await postStore.create({
    userId: 'seller-plan', caption: 'Scheduled clip', videoS3Key: 'uploads/seller-plan/v.mp4',
    platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
    ...(scheduled ? { scheduledAt: new Date(Date.now() - 60_000).toISOString() } : {})
  });
  const publish = vi.fn(published);
  const notifyPublishResult = vi.fn(async () => undefined);
  return { postStore, platformPublishStore, post, publish, notifyPublishResult };
};

describe('scheduled posts after a paid plan ends', () => {
  it('fails a due scheduled post without sending it when the owner is now on Basic', async () => {
    const { postStore, platformPublishStore, post, publish, notifyPublishResult } = await createFixture();
    const readOwnerPlan = vi.fn(async (): Promise<SubscriptionPlan> => 'BASIC');
    const scheduler = createPublishScheduler({
      postStore, platformPublishStore, publisher: { publish }, notifier: { notifyPublishResult }, readOwnerPlan
    });

    await scheduler.runOnce();

    expect(readOwnerPlan).toHaveBeenCalledWith('seller-plan');
    expect(publish).not.toHaveBeenCalled();
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('FAILED');
    expect(await platformPublishStore.listForPostIds([post.id])).toEqual([
      expect.objectContaining({ platform: 'TIKTOK', status: 'FAILED', errorMessage: 'PAID_PLAN_REQUIRED' }),
      expect.objectContaining({ platform: 'YOUTUBE_SHORTS', status: 'FAILED', errorMessage: 'PAID_PLAN_REQUIRED' })
    ]);
    expect(paidPlanRequiredPublishError).toBe('PAID_PLAN_REQUIRED');
    expect(notifyPublishResult).toHaveBeenCalledExactlyOnceWith({
      userId: 'seller-plan', postId: post.id, outcome: 'FAILED'
    });
  });

  it('keeps the post units used: a failed post still counts for its month', async () => {
    const { postStore, platformPublishStore, publish } = await createFixture();
    const before = await postStore.countMonthlyPostUnits({ userId: 'seller-plan', now: new Date().toISOString() });
    await createPublishScheduler({
      postStore, platformPublishStore, publisher: { publish }, readOwnerPlan: async () => 'BASIC'
    }).runOnce();
    expect(before).toBe(2);
    expect(await postStore.countMonthlyPostUnits({ userId: 'seller-plan', now: new Date().toISOString() })).toBe(2);
  });

  it.each(['STARTER', 'PRO'] as const)('publishes a due scheduled post while the owner is on %s', async (plan) => {
    const { postStore, platformPublishStore, post, publish } = await createFixture();
    await createPublishScheduler({
      postStore, platformPublishStore, publisher: { publish }, readOwnerPlan: async () => plan
    }).runOnce();
    expect(publish).toHaveBeenCalledTimes(2);
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('PUBLISHED');
  });

  it('does not re-check the plan for a post-now post', async () => {
    const { postStore, platformPublishStore, post, publish } = await createFixture({ scheduled: false });
    const readOwnerPlan = vi.fn(async (): Promise<SubscriptionPlan> => 'BASIC');
    await createPublishScheduler({ postStore, platformPublishStore, publisher: { publish }, readOwnerPlan }).runOnce();
    expect(readOwnerPlan).not.toHaveBeenCalled();
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('PUBLISHED');
  });

  it('sends nothing while the plan cannot be read and retries before provider work', async () => {
    const { postStore, platformPublishStore, post, publish, notifyPublishResult } = await createFixture();
    const readOwnerPlan = vi.fn<() => Promise<SubscriptionPlan>>()
      .mockRejectedValueOnce(new Error('database unavailable'))
      .mockResolvedValue('PRO');
    await createPublishScheduler({
      postStore, platformPublishStore, publisher: { publish }, notifier: { notifyPublishResult },
      readOwnerPlan, maxPrePublishAttempts: 2, prePublishRetryBackoffMs: 0
    }).runOnce();
    expect(readOwnerPlan).toHaveBeenCalledTimes(2);
    expect(publish).toHaveBeenCalledTimes(2);
    expect((await postStore.findOwned({ postId: post.id, userId: 'seller-plan' }))?.status).toBe('PUBLISHED');
    expect(notifyPublishResult).toHaveBeenCalledExactlyOnceWith({
      userId: 'seller-plan', postId: post.id, outcome: 'PUBLISHED'
    });
  });

  it('applies the same rule in the shared worker used by BullMQ', async () => {
    const { postStore, platformPublishStore, post, publish } = await createFixture();
    const result = await processPublishJobForPost({
      jobData: {
        userId: 'seller-plan', postId: post.id, caption: post.caption, videoS3Key: post.videoS3Key,
        platforms: post.platforms, runAt: post.scheduledAt!, status: 'SCHEDULED'
      },
      postStore, platformPublishStore, publisher: { publish }, readOwnerPlan: async () => 'BASIC'
    });
    expect(result).toMatchObject({ status: 'FAILED', cleanup: { status: 'SKIPPED' } });
    expect(result.platformResults.every((entry) => entry.status === 'FAILED' &&
      entry.errorMessage === 'PAID_PLAN_REQUIRED')).toBe(true);
    expect(publish).not.toHaveBeenCalled();
  });
});

describe('scheduled publish plan reader wiring', () => {
  const subscriptionStore = (plan: SubscriptionPlan) => ({
    getPlan: vi.fn<SubscriptionStore['getPlan']>(async () => plan)
  });

  it('reads the stored plan by owner id when per-request plan overrides are disabled', async () => {
    const store = subscriptionStore('STARTER');
    const reader = createScheduledPublishPlanReader({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'test-project' }),
      subscriptionStore: store
    });
    await expect(reader?.('seller-plan')).resolves.toBe('STARTER');
    expect(store.getPlan).toHaveBeenCalledWith({ id: 'seller-plan', provider: 'firebase' });
  });

  it('is off in local mock development, where the plan came from a request header', () => {
    expect(createScheduledPublishPlanReader({
      config: readServerConfig({ AUTH_PROVIDER: 'mock' }),
      subscriptionStore: subscriptionStore('BASIC')
    })).toBeUndefined();
  });
});
