import { describe, expect, it, vi } from 'vitest';

import { createPrismaUserRepository } from './prismaUserRepository.js';
import { withOwnerLifecycleFixture } from '../../../test/ownerLifecycleFixture.js';

describe('createPrismaUserRepository', () => {
  it('upserts Firebase users by auth user id', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      user: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          id: 'firebase-user-1',
          firebaseUid: 'firebase-user-1',
          email: 'seller@example.com',
          displayName: 'PostDee Seller',
          createdAt: now,
          updatedAt: now
        })
      }
    };
    const repository = createPrismaUserRepository({ prisma: withOwnerLifecycleFixture(prisma) });

    expect(
      await repository.ensure({
        id: 'firebase-user-1',
        provider: 'firebase',
        email: 'seller@example.com',
        displayName: 'PostDee Seller'
      })
    ).toEqual({
      id: 'firebase-user-1',
      firebaseUid: 'firebase-user-1',
      email: 'seller@example.com',
      displayName: 'PostDee Seller',
      createdAt: '2026-06-01T00:00:00.000Z',
      updatedAt: '2026-06-01T00:00:00.000Z'
    });
    expect(prisma.user.upsert).toHaveBeenCalledWith({
      where: { id: 'firebase-user-1' },
      update: {
        email: 'seller@example.com',
        displayName: 'PostDee Seller'
      },
      create: {
        id: 'firebase-user-1',
        firebaseUid: 'firebase-user-1',
        email: 'seller@example.com',
        displayName: 'PostDee Seller'
      }
    });
  });

  it('creates safe fallback identity fields for mock users', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      user: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          id: 'seller-a',
          firebaseUid: 'mock:seller-a',
          email: 'mock-seller-a@postdee.local',
          displayName: undefined,
          createdAt: now,
          updatedAt: now
        })
      }
    };
    const repository = createPrismaUserRepository({ prisma: withOwnerLifecycleFixture(prisma) });

    await repository.ensure({
      id: 'seller-a',
      provider: 'mock'
    });

    expect(prisma.user.upsert).toHaveBeenCalledWith({
      where: { id: 'seller-a' },
      update: {
        email: 'mock-seller-a@postdee.local',
        displayName: undefined
      },
      create: {
        id: 'seller-a',
        firebaseUid: 'mock:seller-a',
        email: 'mock-seller-a@postdee.local',
        displayName: undefined
      }
    });
  });

  it('checks whether a user exists without creating one', async () => {
    const prisma = {
      user: {
        findUnique: vi
          .fn()
          .mockResolvedValueOnce({ id: 'firebase-user-1' })
          .mockResolvedValueOnce(null),
        upsert: vi.fn()
      }
    };
    const repository = createPrismaUserRepository({ prisma: withOwnerLifecycleFixture(prisma) });

    await expect(repository.exists('firebase-user-1')).resolves.toBe(true);
    await expect(repository.exists('deleted-user')).resolves.toBe(false);
    expect(prisma.user.findUnique).toHaveBeenNthCalledWith(1, {
      where: { id: 'firebase-user-1' },
      select: { id: true }
    });
    expect(prisma.user.findUnique).toHaveBeenNthCalledWith(2, {
      where: { id: 'deleted-user' },
      select: { id: true }
    });
    expect(prisma.user.upsert).not.toHaveBeenCalled();
  });

  // A stale row from another UID can still hold an address Firebase later
  // verifies for a new UID. That must not turn every authenticated route into 500.
  it('stores the fallback email when another user already holds the address', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const uniqueEmailConflict = Object.assign(new Error('Unique constraint failed on the fields: (`email`)'), {
      code: 'P2002',
      meta: { target: ['email'] }
    });
    const prisma = {
      user: {
        findUnique: vi.fn(),
        upsert: vi
          .fn()
          .mockRejectedValueOnce(uniqueEmailConflict)
          .mockImplementationOnce(async ({ create }: { create: { id: string; firebaseUid: string; email: string } }) => ({
            ...create,
            displayName: null,
            createdAt: now,
            updatedAt: now
          }))
      }
    };
    const repository = createPrismaUserRepository({ prisma: withOwnerLifecycleFixture(prisma) });

    const user = await repository.ensure({
      id: 'firebase-user-b',
      provider: 'firebase',
      email: 'shared@example.test'
    });

    expect(user.email).toBe('firebase-firebase-user-b@postdee.local');
    expect(prisma.user.upsert).toHaveBeenCalledTimes(2);
    expect(prisma.user.upsert).toHaveBeenLastCalledWith(expect.objectContaining({
      update: expect.objectContaining({ email: 'firebase-firebase-user-b@postdee.local' })
    }));
  });

  it('does not hide other unique conflicts behind the email fallback', async () => {
    const otherConflict = Object.assign(new Error('Unique constraint failed on the fields: (`firebaseUid`)'), {
      code: 'P2002',
      meta: { target: ['firebaseUid'] }
    });
    const prisma = {
      user: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockRejectedValue(otherConflict)
      }
    };
    const repository = createPrismaUserRepository({ prisma: withOwnerLifecycleFixture(prisma) });

    await expect(repository.ensure({ id: 'firebase-user-c', provider: 'firebase', email: 'c@example.test' }))
      .rejects.toBe(otherConflict);
    expect(prisma.user.upsert).toHaveBeenCalledTimes(1);
  });
});
