import { describe, expect, it, vi } from 'vitest';

import { createPrismaAiEditUsageRepository } from './prismaAiEditUsageRepository.js';

describe('createPrismaAiEditUsageRepository', () => {
  it('counts AI edit minutes for a user and month', async () => {
    const prisma = {
      aiEditUsage: {
        aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: 12 } }),
        create: vi.fn()
      }
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.sumMinutesForMonth({
        userId: 'seller-1',
        monthKey: '2026-06'
      })
    ).resolves.toBe(12);
    expect(prisma.aiEditUsage.aggregate).toHaveBeenCalledWith({
      where: {
        userId: 'seller-1',
        monthKey: '2026-06'
      },
      _sum: { minutes: true }
    });
  });

  it('records AI edit minutes in Prisma', async () => {
    const createdAt = new Date('2026-06-14T00:00:00.000Z');
    const prisma = {
      aiEditUsage: {
        aggregate: vi.fn(),
        create: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          monthKey: '2026-06',
          minutes: 3,
          createdAt
        })
      }
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.record({
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 3
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      monthKey: '2026-06',
      minutes: 3,
      createdAt: '2026-06-14T00:00:00.000Z'
    });
    expect(prisma.aiEditUsage.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 3
      },
      select: {
        userId: true,
        monthKey: true,
        minutes: true,
        createdAt: true
      }
    });
  });

  it('reserves minutes in a serializable Prisma transaction when under limit', async () => {
    const createdAt = new Date('2026-06-14T00:00:00.000Z');
    const transactionClient = {
      aiEditUsage: {
        aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: 198 } }),
        create: vi.fn().mockResolvedValue({
          userId: 'seller-1',
          monthKey: '2026-06',
          minutes: 2,
          createdAt
        })
      }
    };
    const prisma = {
      aiEditUsage: {
        aggregate: vi.fn(),
        create: vi.fn()
      },
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.reserve({
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 2,
        limit: 200
      })
    ).resolves.toEqual({
      ok: true,
      usedMinutes: 200,
      record: {
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 2,
        createdAt: '2026-06-14T00:00:00.000Z'
      }
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable'
    });
    expect(transactionClient.aiEditUsage.create).toHaveBeenCalledWith({
      data: {
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 2
      },
      select: {
        userId: true,
        monthKey: true,
        minutes: true,
        createdAt: true
      }
    });
  });

  it('does not reserve minutes when the Prisma monthly limit is exhausted', async () => {
    const transactionClient = {
      aiEditUsage: {
        aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: 199 } }),
        create: vi.fn()
      }
    };
    const prisma = {
      aiEditUsage: {
        aggregate: vi.fn(),
        create: vi.fn()
      },
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.reserve({
        userId: 'seller-1',
        monthKey: '2026-06',
        minutes: 2,
        limit: 200
      })
    ).resolves.toEqual({
      ok: false,
      usedMinutes: 199
    });
    expect(transactionClient.aiEditUsage.create).not.toHaveBeenCalled();
  });
});