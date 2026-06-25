import { describe, expect, it, vi } from 'vitest';

import { createUserStoreForPostStore } from './userStoreFactory.js';

describe('createUserStoreForPostStore', () => {
  it('uses the in-memory user store when posts are stored in memory', async () => {
    const store = createUserStoreForPostStore({
      config: {
        postStore: 'memory'
      }
    });

    const user = await store.ensure({
      id: 'seller-1',
      provider: 'mock',
      email: 'seller@example.com'
    });

    expect(user).toMatchObject({
      id: 'seller-1',
      firebaseUid: 'mock:seller-1',
      email: 'seller@example.com'
    });
  });

  it('uses the Prisma user repository when posts are stored in Prisma', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      user: {
        upsert: vi.fn().mockResolvedValue({
          id: 'seller-1',
          firebaseUid: 'mock:seller-1',
          email: 'seller@example.com',
          displayName: undefined,
          createdAt: now,
          updatedAt: now
        })
      }
    };
    const store = createUserStoreForPostStore({
      config: {
        postStore: 'prisma'
      },
      prisma
    });

    expect(
      await store.ensure({
        id: 'seller-1',
        provider: 'mock',
        email: 'seller@example.com'
      })
    ).toMatchObject({
      id: 'seller-1',
      email: 'seller@example.com'
    });
    expect(prisma.user.upsert).toHaveBeenCalledOnce();
  });

  it('requires a Prisma client when posts are stored in Prisma', () => {
    expect(() =>
      createUserStoreForPostStore({
        config: {
          postStore: 'prisma'
        }
      })
    ).toThrow('Prisma user store requires a Prisma client');
  });
});
