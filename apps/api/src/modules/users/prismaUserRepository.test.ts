import { describe, expect, it, vi } from 'vitest';

import { createPrismaUserRepository } from './prismaUserRepository.js';

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
    const repository = createPrismaUserRepository({ prisma });

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
    const repository = createPrismaUserRepository({ prisma });

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
    const repository = createPrismaUserRepository({ prisma });

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
});
