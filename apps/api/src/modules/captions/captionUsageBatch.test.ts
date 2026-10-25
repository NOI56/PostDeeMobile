import { describe, expect, it, vi } from 'vitest';

import { createInMemoryRealClipCaptionUsageStore, type RealClipCaptionUsageRecord,
  type RealClipCaptionUsageReservation } from './captionUsageStore.js';
import { createPrismaRealClipCaptionUsageRepository,
  type PrismaRealClipCaptionUsageClient } from './prismaRealClipCaptionUsageRepository.js';
import { withOwnerLifecycleFixture } from '../../../test/ownerLifecycleFixture.js';

const instant = '2026-10-25T00:00:00.000Z';
const input = { userId: 'batch-owner', monthKey: '2026-10', limit: 2,
  includeMonthlyAddons: true, now: instant, units: 4 };
const batchRecords = (reservation: RealClipCaptionUsageReservation) => {
  if (!reservation.ok || !reservation.records) throw new Error('Expected a batch reservation');
  return reservation.records;
};

describe('in-memory caption credit batches', () => {
  it('keeps the default and explicit single-credit response shape unchanged', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ now: () => instant });
    const expectedRecord = { userId: input.userId, monthKey: input.monthKey, createdAt: instant };
    expect(await store.reserve({ userId: input.userId, monthKey: input.monthKey, limit: 4 }))
      .toEqual({ ok: true, usedThisMonth: 1, record: expectedRecord });
    expect(await store.reserve({ userId: input.userId, monthKey: input.monthKey, limit: 4, units: 1 }))
      .toEqual({ ok: true, usedThisMonth: 2, record: expectedRecord });
  });

  it('uses monthly credits before the retained addon bank in one batch', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ now: () => instant,
      monthlyAddonStore: { readCredits: async () => ({ postUnits: 0, aiCaptions: 2 }) } });
    const reservation = await store.reserve(input);
    const records = batchRecords(reservation);
    expect(reservation).toMatchObject({ ok: true, usedThisMonth: 2, record: records[0] });
    expect(records.map(record => Boolean(record.usesAddonCredit))).toEqual([false, false, true, true]);
    expect(await store.countForMonth(input)).toBe(2);
    expect(await store.countAddonUsages(input)).toBe(2);
  });

  it('does not reserve any credits when the whole batch cannot be funded', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore: {
      readCredits: async () => ({ postUnits: 0, aiCaptions: 1 }) } });
    expect(await store.reserve(input)).toEqual({ ok: false, usedThisMonth: 0 });
    expect(await store.countForMonth(input)).toBe(0);
    expect(await store.countAddonUsages(input)).toBe(0);
  });

  it('leaves no partial reservation if preparing a batch record fails', async () => {
    let clockReads = 0;
    const store = createInMemoryRealClipCaptionUsageStore({ now: () => {
      if (++clockReads === 2) throw new Error('clock failed');
      return instant;
    } });
    await expect(store.reserve({ ...input, includeMonthlyAddons: false, limit: 4 })).rejects.toThrow('clock failed');
    expect(await store.countForMonth(input)).toBe(0);
  });

  it('lets only one concurrent batch reserve the last four credits after an async lookup', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore: {
      readCredits: async () => { await Promise.resolve(); return { postUnits: 0, aiCaptions: 4 }; } } });
    const results = await Promise.all([store.reserve({ ...input, limit: 0 }), store.reserve({ ...input, limit: 0 })]);
    expect(results.filter(result => result.ok)).toHaveLength(1);
    expect(await store.countAddonUsages(input)).toBe(4);
  });

  it('refunds the whole exact batch and preserves another same-timestamp reservation', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ now: () => instant });
    const first = batchRecords(await store.reserve({ ...input, includeMonthlyAddons: false, limit: 12 }));
    const second = batchRecords(await store.reserve({ ...input, includeMonthlyAddons: false, limit: 12 }));
    expect(await store.releaseMany!([first[0], { ...first[1] }, first[2], first[3]])).toBe(false);
    expect(await store.countForMonth(input)).toBe(8);
    expect(await store.releaseMany!(first)).toBe(true);
    expect(await store.releaseMany!(first)).toBe(false);
    expect(await store.countForMonth(input)).toBe(4);
    expect(await store.releaseMany!([second[0], second[0]])).toBe(false);
    expect(await store.releaseMany!(second)).toBe(true);
  });

  it.each([0, 5, -1, 1.5, Number.NaN])('rejects invalid unit count %s before creating rows', async units => {
    const store = createInMemoryRealClipCaptionUsageStore();
    await expect(store.reserve({ ...input, units })).rejects.toThrow('units');
    expect(await store.countForMonth(input)).toBe(0);
    expect(await store.countAddonUsages(input)).toBe(0);
  });
});

type UsageRow = Required<Pick<RealClipCaptionUsageRecord, 'id' | 'userId' | 'monthKey'>> & {
  createdAt: Date; usesAddonCredit?: boolean;
};
type CreateArgs = Parameters<PrismaRealClipCaptionUsageClient['realClipCaptionUsage']['create']>[0];
type CountArgs = Parameters<PrismaRealClipCaptionUsageClient['realClipCaptionUsage']['count']>[0];
type DeleteArgs = Parameters<NonNullable<PrismaRealClipCaptionUsageClient['realClipCaptionUsage']['deleteMany']>>[0];

// Copy-on-write transactions model commit/rollback, including a conflict after
// a partial batch has been written inside the transaction.
const prismaLedger = ({ addonUsed = 48, failCreate, failDelete }: {
  addonUsed?: number; failCreate?: 'P2034' | 'failure'; failDelete?: 'P2034' | 'failure';
} = {}) => {
  let rows: UsageRow[] = Array.from({ length: addonUsed }, (_, index) => ({
    id: `existing-${index}`, userId: input.userId, monthKey: '2026-09', createdAt: new Date(instant), usesAddonCredit: true
  }));
  let sequence = 0;
  let tail = Promise.resolve();
  let attempts = 0;
  let deleteConflictRaised = false;
  const create = vi.fn();
  const deleteMany = vi.fn();
  const transaction: NonNullable<PrismaRealClipCaptionUsageClient['$transaction']> = async (operation) => {
    const result = tail.then(async () => {
      attempts += 1;
      const attempt = attempts;
      let draft = rows.map(row => ({ ...row }));
      let creates = 0;
      let deletes = 0;
      const value = await operation({
        monthlyAddonPurchase: { findMany: async () => [{ id: 'grant' }] },
        realClipCaptionUsage: {
          count: async ({ where }: CountArgs) => draft.filter(row => row.userId === where.userId &&
            (where.monthKey === undefined || row.monthKey === where.monthKey) &&
            (where.usesAddonCredit === undefined || Boolean(row.usesAddonCredit) === where.usesAddonCredit)).length,
          create: async (args: CreateArgs) => {
            create(args);
            creates += 1;
            if (attempt === 1 && creates === 2 && failCreate) {
              throw Object.assign(new Error('create failed'), { code: failCreate });
            }
            const row = { id: `new-${++sequence}`, ...args.data, createdAt: new Date(instant) };
            draft.push(row);
            return row;
          },
          deleteMany: async (args: DeleteArgs) => {
            deleteMany(args);
            deletes += 1;
            if (deletes === 2 && (failDelete === 'failure' || (failDelete === 'P2034' && !deleteConflictRaised))) {
              deleteConflictRaised = true;
              throw Object.assign(new Error('delete failed'), { code: failDelete });
            }
            const remaining = draft.filter(row => row.id !== args.where.id || row.userId !== args.where.userId ||
              row.monthKey !== args.where.monthKey);
            const count = draft.length - remaining.length;
            draft = remaining;
            return { count };
          }
        }
      });
      rows = draft;
      return value;
    });
    tail = result.then(() => undefined, () => undefined);
    return result;
  };
  const prisma = withOwnerLifecycleFixture({
    realClipCaptionUsage: { count: vi.fn(), create: vi.fn(), deleteMany: vi.fn() },
    $transaction: vi.fn(transaction)
  });
  return { prisma, rows: () => rows, create, deleteMany };
};

describe('Prisma caption credit batches', () => {
  it('reserves monthly and addon rows together in a serializable transaction', async () => {
    const ledger = prismaLedger();
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    const result = await repository.reserve(input);
    expect(batchRecords(result).map(row => Boolean(row.usesAddonCredit))).toEqual([false, false, true, true]);
    expect(result).toMatchObject({ usedThisMonth: 2 });
    expect(ledger.rows()).toHaveLength(52);
    expect(ledger.prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), { isolationLevel: 'Serializable' });
  });

  it('preflights all units without creating any rows when the balance is insufficient', async () => {
    const ledger = prismaLedger({ addonUsed: 49 });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    expect(await repository.reserve(input)).toEqual({ ok: false, usedThisMonth: 0 });
    expect(ledger.create).not.toHaveBeenCalled();
    expect(ledger.rows()).toHaveLength(49);
  });

  it('serializes competing batches so only one can take the final available credits', async () => {
    const ledger = prismaLedger();
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    const results = await Promise.all([repository.reserve(input), repository.reserve(input)]);
    expect(results.filter(result => result.ok)).toHaveLength(1);
    expect(ledger.rows()).toHaveLength(52);
  });

  it('rolls back a partial batch and retries the entire reservation on serialization conflict', async () => {
    const ledger = prismaLedger({ failCreate: 'P2034' });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    expect(batchRecords(await repository.reserve(input))).toHaveLength(4);
    expect(ledger.prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(ledger.rows()).toHaveLength(52);
  });

  it('leaves no partial reservation after an insert failure', async () => {
    const ledger = prismaLedger({ failCreate: 'failure' });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    await expect(repository.reserve(input)).rejects.toThrow('create failed');
    expect(ledger.rows()).toHaveLength(48);
  });

  it('fails closed for multi-credit reservations without transaction support', async () => {
    const prisma = { realClipCaptionUsage: { count: vi.fn(), create: vi.fn() } };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    await expect(repository.reserve({ ...input, includeMonthlyAddons: false })).rejects.toThrow('transaction support');
    expect(prisma.realClipCaptionUsage.create).not.toHaveBeenCalled();
  });

  it('refunds only exact owned batch rows and rolls back when any row does not match', async () => {
    const ledger = prismaLedger({ addonUsed: 0 });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    const first = batchRecords(await repository.reserve({ ...input, limit: 12 }));
    const second = batchRecords(await repository.reserve({ ...input, limit: 12 }));
    expect(await repository.releaseMany!([first[0], { ...first[1], userId: 'other-owner' }])).toBe(false);
    expect(await repository.releaseMany!([first[0], { ...first[1], id: 'missing-row' }])).toBe(false);
    expect(ledger.rows()).toHaveLength(8);
    expect(await repository.releaseMany!([first[0], first[0]])).toBe(false);
    expect(await repository.releaseMany!(first)).toBe(true);
    expect(await repository.releaseMany!(first)).toBe(false);
    expect(ledger.rows().map(row => row.id)).toEqual(second.map(row => row.id));
  });

  it('rolls back the whole refund when a delete fails', async () => {
    const ledger = prismaLedger({ addonUsed: 0, failDelete: 'failure' });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    const records = batchRecords(await repository.reserve({ ...input, limit: 4 }));
    await expect(repository.releaseMany!(records)).rejects.toThrow('delete failed');
    expect(ledger.rows()).toHaveLength(4);
  });

  it('retries the complete refund after a serialization conflict without touching concurrent rows', async () => {
    const ledger = prismaLedger({ addonUsed: 0, failDelete: 'P2034' });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    const first = batchRecords(await repository.reserve({ ...input, limit: 8 }));
    const second = batchRecords(await repository.reserve({ ...input, limit: 8 }));
    expect(await repository.releaseMany!(first)).toBe(true);
    expect(ledger.prisma.$transaction).toHaveBeenCalledTimes(4);
    expect(ledger.rows().map(row => row.id)).toEqual(second.map(row => row.id));
  });

  it('does not attempt a batch refund without transaction support', async () => {
    const prisma = { realClipCaptionUsage: { count: vi.fn(), create: vi.fn(), deleteMany: vi.fn() } };
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    expect(await repository.releaseMany!([{ id: 'first', userId: input.userId, monthKey: input.monthKey, createdAt: instant },
      { id: 'second', userId: input.userId, monthKey: input.monthKey, createdAt: instant }])).toBe(false);
    expect(prisma.realClipCaptionUsage.deleteMany).not.toHaveBeenCalled();
  });

  it.each([0, 5, -1, 1.5, Number.NaN])('rejects invalid unit count %s without opening a transaction', async units => {
    const ledger = prismaLedger();
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma: ledger.prisma });
    await expect(repository.reserve({ ...input, units })).rejects.toThrow('units');
    expect(ledger.prisma.$transaction).not.toHaveBeenCalled();
  });
});
