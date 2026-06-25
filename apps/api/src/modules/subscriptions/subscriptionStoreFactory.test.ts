import { describe, expect, it, vi } from 'vitest';

import { createSubscriptionStoreFromConfig } from './subscriptionStoreFactory.js';

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
    const prisma = {
      subscription: {
        findUnique: vi.fn().mockResolvedValue({
          plan: 'PRO',
          status: 'ACTIVE'
        })
      }
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
