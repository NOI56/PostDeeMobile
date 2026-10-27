import { describe, expect, it, vi } from 'vitest';

import { createPrismaUserRepository, type PrismaUserClient } from '../users/prismaUserRepository.js';
import { createPrismaPostRepository, type PrismaPostClient } from '../posts/prismaPostRepository.js';
import { createPrismaSubscriptionRepository, type PrismaSubscriptionClient } from '../subscriptions/prismaSubscriptionRepository.js';

const authUser = { id: 'seller-1', provider: 'firebase' as const };
const timestamp = new Date('2026-10-13T00:00:00.000Z');
const storedUser = { id: authUser.id, firebaseUid: authUser.id, email: 'seller@example.com', createdAt: timestamp, updatedAt: timestamp };
const storedPost = { id: 'post-1', userId: authUser.id, caption: 'Owned post', videoS3Key: 'uploads/seller-1/clip/video.mp4', selectedPlatforms: ['TIKTOK'], scheduledAt: null, status: 'QUEUED', publishedAt: null, createdAt: timestamp };
const storedSubscription = { userId: authUser.id, plan: 'PRO', status: 'ACTIVE', updatedAt: timestamp };
const input = { userId: authUser.id, caption: storedPost.caption, videoS3Key: storedPost.videoS3Key, platforms: ['TIKTOK' as const] };

const createFixture = (status: 'ACTIVE' | 'DELETING' | 'DELETED') => {
  const transaction = {
    managedUploadOwner: {
      upsert: vi.fn(async () => ({ status })),
      updateMany: vi.fn(async () => ({ count: status === 'ACTIVE' ? 1 : 0 }))
    },
    user: {
      upsert: vi.fn(async () => storedUser),
      findUnique: vi.fn(async () => ({ lastRevenueCatEventId: null, lastRevenueCatEventTimestampMs: null })),
      update: vi.fn(async () => ({ id: authUser.id }))
    },
    post: {
      findMany: vi.fn(async () => []),
      create: vi.fn(async () => storedPost),
      updateMany: vi.fn(async () => ({ count: 1 })),
      findFirst: vi.fn(async () => storedPost)
    },
    subscription: {
      upsert: vi.fn(async () => storedSubscription)
    }
  };
  const writeOutsideTransaction = vi.fn(async () => { throw new Error('Write escaped lifecycle transaction'); });
  const prisma = {
    managedUploadOwner: transaction.managedUploadOwner,
    user: { upsert: writeOutsideTransaction },
    post: { create: writeOutsideTransaction, updateMany: writeOutsideTransaction },
    subscription: { upsert: writeOutsideTransaction },
    $transaction: vi.fn(async (action: (client: typeof transaction) => Promise<unknown>) => action(transaction))
  };
  return { prisma, transaction, writeOutsideTransaction };
};

const operations = [
  ['User.ensure', (prisma: unknown) => createPrismaUserRepository({ prisma: prisma as PrismaUserClient }).ensure(authUser)],
  ['Post.create', (prisma: unknown) => createPrismaPostRepository({ prisma: prisma as PrismaPostClient }).create(input)],
  ['Post.createWithinMonthlyLimit', (prisma: unknown) => createPrismaPostRepository({ prisma: prisma as PrismaPostClient }).createWithinMonthlyLimit({ ...input, monthlyPostUnitLimit: 3, now: timestamp.toISOString() })],
  ['Post.reschedule', (prisma: unknown) => createPrismaPostRepository({ prisma: prisma as PrismaPostClient }).reschedule({ postId: storedPost.id, userId: authUser.id, scheduledAt: '2026-10-14T00:00:00.000Z' })],
  ['Subscription.activatePlan', (prisma: unknown) => createPrismaSubscriptionRepository({ prisma: prisma as PrismaSubscriptionClient }).activatePlan(authUser, 'PRO')],
  ['Subscription.activatePro', (prisma: unknown) => createPrismaSubscriptionRepository({ prisma: prisma as PrismaSubscriptionClient }).activatePro(authUser)],
  ['Subscription.applyRevenueCatEvent', (prisma: unknown) => createPrismaSubscriptionRepository({ prisma: prisma as PrismaSubscriptionClient }).applyRevenueCatEvent({ authUser, billingSubscriptionId: 'revenuecat:seller-1', plan: 'PRO', status: 'ACTIVE', eventId: 'event-1', eventTimestampMs: timestamp.getTime() })]
] as const;

describe('repository lifecycle mutation entry points', () => {
  it.each(operations)('%s writes only through the locked transaction', async (_name, operation) => {
    const { prisma, transaction, writeOutsideTransaction } = createFixture('ACTIVE');
    await operation(prisma);
    expect(transaction.managedUploadOwner.updateMany).toHaveBeenCalledOnce();
    expect(writeOutsideTransaction).not.toHaveBeenCalled();
    const writes = [transaction.user.upsert, transaction.user.update, transaction.post.create, transaction.post.updateMany, transaction.subscription.upsert];
    expect(writes.some((write) => write.mock.calls.length > 0)).toBe(true);
  });

  describe.each(['DELETING', 'DELETED'] as const)('%s owner', (status) => {
    it.each(operations)('%s rejects a late mutation without writing', async (_name, operation) => {
      const { prisma, transaction, writeOutsideTransaction } = createFixture(status);
      await expect(operation(prisma)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
      for (const write of [transaction.user.upsert, transaction.user.update, transaction.post.create, transaction.post.updateMany, transaction.subscription.upsert, writeOutsideTransaction]) {
        expect(write).not.toHaveBeenCalled();
      }
    });
  });
});
