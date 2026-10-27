import { describe, expect, it, vi } from 'vitest';

import { createPrismaAiEditUsageRepository } from './prismaAiEditUsageRepository.js';

describe('createPrismaAiEditUsageRepository', () => {
  it('counts AI edit minutes for a user and month', async () => {
    const prisma = {
      aiEditUsage: {
        aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: 12 } }),
        findFirst: vi.fn(),
        update: vi.fn(),
        deleteMany: vi.fn(),
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
        findFirst: vi.fn(),
        update: vi.fn(),
        deleteMany: vi.fn(),
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
        id: true,
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
        findFirst: vi.fn(),
        update: vi.fn(),
        deleteMany: vi.fn(),
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
        id: true,
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
        findFirst: vi.fn(),
        update: vi.fn(),
        deleteMany: vi.fn(),
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

  const reservedRecord = {
    id: 'usage-1',
    userId: 'seller-1',
    monthKey: '2026-06',
    minutes: 1,
    createdAt: new Date('2026-06-14T00:00:00.000Z')
  };

  const createSettleClient = (totalMinutes: number) => ({
    aiEditUsage: {
      aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: totalMinutes } }),
      create: vi.fn(),
      findFirst: vi.fn().mockResolvedValue(reservedRecord),
      update: vi.fn(async ({ data }: { data: { minutes: number } }) => ({
        ...reservedRecord,
        minutes: data.minutes
      })),
      deleteMany: vi.fn()
    }
  });

  it('settles a reservation to the billed minutes when the month has room', async () => {
    const transactionClient = createSettleClient(150);
    const prisma = {
      ...createSettleClient(0),
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.settle({
        id: 'usage-1', userId: 'seller-1', monthKey: '2026-06', minutes: 3, limit: 200
      })
    ).resolves.toMatchObject({ ok: true, usedMinutes: 152, record: { id: 'usage-1', minutes: 3 } });
    expect(transactionClient.aiEditUsage.findFirst).toHaveBeenCalledWith({
      where: { id: 'usage-1', userId: 'seller-1', monthKey: '2026-06' },
      select: { id: true, userId: true, monthKey: true, minutes: true, createdAt: true }
    });
    expect(transactionClient.aiEditUsage.update).toHaveBeenCalledWith({
      where: { id: 'usage-1' },
      data: { minutes: 3 },
      select: { id: true, userId: true, monthKey: true, minutes: true, createdAt: true }
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable'
    });
  });

  it('keeps a reservation unchanged when the billed minutes do not fit', async () => {
    const transactionClient = createSettleClient(200);
    const prisma = {
      ...createSettleClient(0),
      $transaction: vi.fn(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.settle({
        id: 'usage-1', userId: 'seller-1', monthKey: '2026-06', minutes: 5, limit: 200
      })
    ).resolves.toEqual({ ok: false, usedMinutes: 200 });
    expect(transactionClient.aiEditUsage.update).not.toHaveBeenCalled();
  });

  const writeConflict = () => Object.assign(new Error('write conflict'), { code: 'P2034' });

  it('retries a reservation after a serializable write conflict', async () => {
    const transactionClient = createSettleClient(10);
    transactionClient.aiEditUsage.create.mockResolvedValue({ ...reservedRecord, minutes: 2 });
    const prisma = {
      ...createSettleClient(0),
      $transaction: vi
        .fn()
        .mockRejectedValueOnce(writeConflict())
        .mockImplementationOnce(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.reserve({ userId: 'seller-1', monthKey: '2026-06', minutes: 2, limit: 200 })
    ).resolves.toMatchObject({ ok: true, usedMinutes: 12 });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('retries a settle after a serializable write conflict', async () => {
    const transactionClient = createSettleClient(150);
    const prisma = {
      ...createSettleClient(0),
      $transaction: vi
        .fn()
        .mockRejectedValueOnce(writeConflict())
        .mockImplementationOnce(async (callback) => callback(transactionClient))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.settle({
        id: 'usage-1', userId: 'seller-1', monthKey: '2026-06', minutes: 3, limit: 200
      })
    ).resolves.toMatchObject({ ok: true, usedMinutes: 152 });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('does not retry errors other than write conflicts', async () => {
    const prisma = {
      ...createSettleClient(0),
      $transaction: vi.fn().mockRejectedValue(new Error('database down'))
    };
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await expect(
      repository.reserve({ userId: 'seller-1', monthKey: '2026-06', minutes: 2, limit: 200 })
    ).rejects.toThrow('database down');
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('releases a failed reservation only for its owner', async () => {
    const prisma = createSettleClient(0);
    const repository = createPrismaAiEditUsageRepository({ prisma });

    await repository.release({ id: 'usage-1', userId: 'seller-1' });

    expect(prisma.aiEditUsage.deleteMany).toHaveBeenCalledWith({
      where: { id: 'usage-1', userId: 'seller-1' }
    });
  });
});