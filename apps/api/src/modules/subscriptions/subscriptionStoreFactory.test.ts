import { describe, expect, it, vi } from 'vitest';

import { createSubscriptionStoreFromConfig } from './subscriptionStoreFactory.js';
import type { PrismaSubscriptionClient } from './prismaSubscriptionRepository.js';

describe('createSubscriptionStoreFromConfig', () => {
  it('uses the in-memory subscription store by default', async () => {
    const store = createSubscriptionStoreFromConfig({
      config: {
        subscriptionStore: 'memory'
      }
    });

    await expect(store.getPlan({ id: 'seller-1', provider: 'mock' })).resolves.toBe('BASIC');
    await expect(
      store.getPlan({
        id: 'seller-1',
        provider: 'mock',
        subscriptionPlan: 'PRO'
      })
    ).resolves.toBe('PRO');
  });

  it('uses the Prisma subscription repository when configured', async () => {
    const transaction: Omit<PrismaSubscriptionClient, '$transaction'> = {
      managedUploadOwner: {
        upsert: vi.fn<PrismaSubscriptionClient['managedUploadOwner']['upsert']>(),
        updateMany: vi.fn<PrismaSubscriptionClient['managedUploadOwner']['updateMany']>()
      },
      user: {
        findUnique: vi.fn<PrismaSubscriptionClient['user']['findUnique']>(),
        update: vi.fn<PrismaSubscriptionClient['user']['update']>()
      },
      subscription: {
        findUnique: vi.fn<PrismaSubscriptionClient['subscription']['findUnique']>().mockResolvedValue({
          plan: 'PRO',
          status: 'ACTIVE'
        }),
        upsert: vi.fn<PrismaSubscriptionClient['subscription']['upsert']>(),
        update: vi.fn<PrismaSubscriptionClient['subscription']['update']>()
      }
    };
    const prisma: PrismaSubscriptionClient = {
      ...transaction,
      $transaction: async (operation) => operation(transaction)
    };
    const store = createSubscriptionStoreFromConfig({
      config: {
        subscriptionStore: 'prisma'
      },
      prisma
    });

    await expect(store.getPlan({ id: 'seller-1', provider: 'mock' })).resolves.toBe('PRO');
  });

  it('requires a Prisma client when Prisma subscriptions are configured', () => {
    expect(() =>
      createSubscriptionStoreFromConfig({
        config: {
          subscriptionStore: 'prisma'
        }
      })
    ).toThrow('Prisma subscription store requires a Prisma client');
  });
});
