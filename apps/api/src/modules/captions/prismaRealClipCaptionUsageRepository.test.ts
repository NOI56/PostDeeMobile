import { describe, expect, it, vi } from 'vitest';

import { createPrismaRealClipCaptionUsageRepository } from './prismaRealClipCaptionUsageRepository.js';
import { withOwnerLifecycleFixture } from '../../../test/ownerLifecycleFixture.js';

describe('createPrismaRealClipCaptionUsageRepository', () => {
  it('retries caption quota with the latest transactional addon grants after a concurrent refund', async () => {
    const transactionGrants = { findMany: vi.fn().mockResolvedValueOnce([{ id: 'grant' }]).mockResolvedValue([]) };
    const transactionUsage = { count: vi.fn(async ({ where }) => where.usesAddonCredit ? 0 : 50),
      create: vi.fn().mockRejectedValue(Object.assign(new Error('serialization conflict'), { code: 'P2034' })) };
    const prisma = { monthlyAddonPurchase: { findMany: vi.fn() },
      realClipCaptionUsage: { count: vi.fn(), create: vi.fn() },
      $transaction: vi.fn(async callback => callback({ realClipCaptionUsage: transactionUsage,
        monthlyAddonPurchase: transactionGrants })) };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: withOwnerLifecycleFixture(prisma) });
    expect(await repository.reserve({ userId: 'addon-refund', monthKey: '2026-10', limit: 50,
      includeMonthlyAddons: true, now: '2026-10-21T00:00:00.000Z' }))
      .toEqual({ ok: false, usedThisMonth: 50 });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), { isolationLevel: 'Serializable' });
    expect(transactionGrants.findMany).toHaveBeenCalledTimes(2);
    expect(prisma.monthlyAddonPurchase.findMany).not.toHaveBeenCalled();
    expect(transactionUsage.create).toHaveBeenCalledTimes(1);
  });

  it('fails closed if addon quota cannot be read in a transaction', async () => {
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: {
      realClipCaptionUsage: { count: vi.fn(), create: vi.fn() }
    } });
    await expect(repository.reserve({ userId: 'owner', monthKey: '2026-10', limit: 50,
      includeMonthlyAddons: true, now: '2026-10-21T00:00:00.000Z' })).rejects.toThrow('transaction support');
  });

  it('releases only the exact reserved row owned by the caller', async () => {
    const prisma = { realClipCaptionUsage: {
      count: vi.fn(), create: vi.fn(), deleteMany: vi.fn().mockResolvedValue({ count: 1 })
    }};
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    expect(await repository.release!({ id: 'reservation-1', userId: 'owner',
      monthKey: '2026-10', createdAt: '2026-10-09T00:00:00.000Z' })).toBe(true);
    expect(prisma.realClipCaptionUsage.deleteMany).toHaveBeenCalledWith({
      where: { id: 'reservation-1', userId: 'owner', monthKey: '2026-10' }
    });
  });
  it('counts real-clip caption usage for a user and month', async () => {
    const prisma = {
      realClipCaptionUsage: {
        count: vi.fn().mockResolvedValue(7),
        create: vi.fn()
      }
    };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });

    await expect(
      repository.countForMonth({
        userId: 'seller-1',
        monthKey: '2026-06'
      })
    ).resolves.toBe(7);
    expect(prisma.realClipCaptionUsage.count).toHaveBeenCalledWith({
      where: {
        userId: 'seller-1',
        monthKey: '2026-06',
        usesAddonCredit: false
      }
    });
  });

  it('records a real-clip caption generation in Prisma', async () => {
    const createdAt = new Date('2026-06-14T00:00:00.000Z');
    const prisma = {
      realClipCaptionUsage: {
        count: vi.fn(),
        create: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          monthKey: '2026-06',
          createdAt
        })
      }
    };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });

    await expect(
      repository.record({
        userId: 'seller-1',
        monthKey: '2026-06'
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      monthKey: '2026-06',
      createdAt: '2026-06-14T00:00:00.000Z'
    });
    expect(prisma.realClipCaptionUsage.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        monthKey: '2026-06'
      },
      select: {
        id: true,
        userId: true,
        monthKey: true,
        createdAt: true,
        usesAddonCredit: true
      }
    });
  });

  it('reserves usage in a serializable Prisma transaction when under limit', async () => {
    const createdAt = new Date('2026-06-14T00:00:00.000Z');
    const transactionClient = {
      realClipCaptionUsage: {
        count: vi.fn().mockResolvedValue(2),
        create: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          monthKey: '2026-06',
          createdAt
        })
      }
    };
    const prisma = {
      realClipCaptionUsage: {
        count: vi.fn(),
        create: vi.fn()
      },
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });

    await expect(
      repository.reserve({
        userId: 'seller-1',
        monthKey: '2026-06',
        limit: 3
      })
    ).resolves.toEqual({
      ok: true,
      usedThisMonth: 3,
      record: {
        userId: 'seller-1',
        monthKey: '2026-06',
        createdAt: '2026-06-14T00:00:00.000Z'
      }
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable'
    });
    expect(transactionClient.realClipCaptionUsage.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        monthKey: '2026-06'
      },
      select: {
        id: true,
        userId: true,
        monthKey: true,
        createdAt: true,
        usesAddonCredit: true
      }
    });
  });

  it('does not reserve usage when the Prisma monthly limit is exhausted', async () => {
    const transactionClient = {
      realClipCaptionUsage: {
        count: vi.fn().mockResolvedValue(3),
        create: vi.fn()
      }
    };
    const prisma = {
      realClipCaptionUsage: {
        count: vi.fn(),
        create: vi.fn()
      },
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });

    await expect(
      repository.reserve({
        userId: 'seller-1',
        monthKey: '2026-06',
        limit: 3
      })
    ).resolves.toEqual({
      ok: false,
      usedThisMonth: 3
    });
    expect(transactionClient.realClipCaptionUsage.create).not.toHaveBeenCalled();
  });
});
