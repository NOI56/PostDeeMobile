import { describe, expect, it, vi } from 'vitest';

import { createPrismaRealClipCaptionUsageRepository } from './prismaRealClipCaptionUsageRepository.js';

describe('createPrismaRealClipCaptionUsageRepository', () => {
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
        monthKey: '2026-06'
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
        userId: true,
        monthKey: true,
        createdAt: true
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
        userId: true,
        monthKey: true,
        createdAt: true
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
