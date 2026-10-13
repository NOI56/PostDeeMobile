import { describe, expect, it, vi } from 'vitest';

import { createPrismaUserRepository } from '../users/prismaUserRepository.js';
import { createPrismaPostRepository } from '../posts/prismaPostRepository.js';
import { createPrismaSubscriptionRepository } from '../subscriptions/prismaSubscriptionRepository.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createUserStore } from '../users/userStore.js';
import { createPostStore } from '../posts/postStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';

const authUser = { id: 'owner-a', provider: 'mock' as const };
const postInput = { userId: authUser.id, caption: 'Private', videoS3Key: 'uploads/owner-a/a.mp4', platforms: ['TIKTOK' as const] };

describe('final owner write boundaries', () => {
  const entryPoints = ['user ensure', 'post create', 'post quota', 'post reschedule', 'post publish-now', 'subscription activate', 'subscription Pro', 'RevenueCat event'] as const;
  it.each(entryPoints)('rejects %s on a deleted owner without touching durable entities', async (entryPoint) => {
    const write = vi.fn();
    const transaction = {
      managedUploadOwner: { upsert: vi.fn(async () => ({ status: 'DELETED' })), updateMany: vi.fn() },
      user: { upsert: write, findUnique: write, update: write },
      post: { create: write, findMany: write, findFirst: write, updateMany: write },
      subscription: { upsert: write, update: write }
    };
    const prisma = { ...transaction, $transaction: vi.fn(async (action) => action(transaction)) };
    const user = createPrismaUserRepository({ prisma: prisma as never });
    const posts = createPrismaPostRepository({ prisma: prisma as never });
    const subscription = createPrismaSubscriptionRepository({ prisma: prisma as never });
    const operations = {
      'user ensure': () => user.ensure(authUser),
      'post create': () => posts.create(postInput),
      'post quota': () => posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'replay', now: '2026-10-13T00:00:00.000Z', monthlyPostUnitLimit: 3 }),
      'post reschedule': () => posts.reschedule({ userId: authUser.id, postId: 'p1', scheduledAt: '2026-10-14T00:00:00.000Z' }),
      'post publish-now': () => posts.publishNow({ userId: authUser.id, postId: 'p1' }),
      'subscription activate': () => subscription.activatePlan(authUser, 'STARTER'),
      'subscription Pro': () => subscription.activatePro(authUser),
      'RevenueCat event': () => subscription.applyRevenueCatEvent({ authUser, plan: 'PRO', status: 'ACTIVE', billingSubscriptionId: 'revenuecat:owner-a', eventId: 'e1', eventTimestampMs: 1 })
    };
    await expect(operations[entryPoint]()).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(write).not.toHaveBeenCalled();
  });

  it('holds deletion behind an admitted memory write and then rejects later work', async () => {
    const owners = createInMemoryUploadSessionStore();
    let entered!: () => void;
    let release!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const writing = owners.runWithActiveOwner(authUser.id, async () => { entered(); await gate; });
    await started;
    let deleted = false;
    const deleting = owners.beginOwnerDeletion(authUser.id).then(() => { deleted = true; });
    await Promise.resolve();
    expect(deleted).toBe(false);
    release();
    await writing;
    await deleting;
    await expect(owners.runWithActiveOwner(authUser.id, async () => undefined))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('shares the memory tombstone across User, Post, Subscription and another owner remains usable', async () => {
    const owners = createInMemoryUploadSessionStore();
    const runWithActiveOwner = owners.runWithActiveOwner;
    const users = createUserStore({ runWithActiveOwner });
    const posts = createPostStore({ runWithActiveOwner });
    const subscriptions = createSubscriptionStore({ runWithActiveOwner });
    await owners.beginOwnerDeletion(authUser.id);
    await owners.finishOwnerDeletion(authUser.id);
    await expect(users.ensure(authUser)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(posts.create(postInput)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(subscriptions.activatePro(authUser)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(users.ensure({ id: 'owner-b', provider: 'mock' })).resolves.toMatchObject({ id: 'owner-b' });
  });
});
