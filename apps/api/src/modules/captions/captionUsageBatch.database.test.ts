import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { monthlyAddonOwnerHash } from '../billing/monthlyAddonStore.js';
import { createPrismaRealClipCaptionUsageRepository,
  type PrismaRealClipCaptionUsageClient } from './prismaRealClipCaptionUsageRepository.js';
import type { RealClipCaptionUsageReservation } from './captionUsageStore.js';

// Opt in only after migrating a disposable loopback database and isolated schema.
// Neither DATABASE_URL nor any hosted database is used implicitly by this suite.
const databaseUrl = process.env.POSTDEE_CAPTION_BATCH_DB_TEST_URL;
describe.skipIf(!databaseUrl)('caption credit batches in PostgreSQL', () => {
  let prisma: PrismaClient;
  const owners: string[] = [];
  const now = '2026-10-25T00:00:00.000Z';
  const monthKey = '2026-10';

  beforeAll(async () => {
    const url = new URL(databaseUrl!);
    if (!['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
        !/^\/postdee_caption_test(?:$|_)/.test(url.pathname) ||
        !/^caption_batch_[a-z0-9_]+$/.test(url.searchParams.get('schema') ?? '')) {
      throw new Error('Caption batch DB tests require a disposable local postdee_caption_test database and caption_batch_ schema');
    }
    prisma = new PrismaClient({ datasourceUrl: databaseUrl });
    await prisma.$connect();
  });

  afterAll(async () => {
    if (!prisma) return;
    try {
      await prisma.user.deleteMany({ where: { id: { in: owners } } });
      await prisma.monthlyAddonPurchase.deleteMany({ where: { ownerHash: { in: owners.map(monthlyAddonOwnerHash) } } });
      await prisma.managedUploadOwner.deleteMany({ where: { ownerId: { in: owners } } });
      expect(await prisma.realClipCaptionUsage.count({ where: { userId: { in: owners } } })).toBe(0);
      expect(await prisma.monthlyAddonPurchase.count({ where: { ownerHash: { in: owners.map(monthlyAddonOwnerHash) } } })).toBe(0);
      expect(await prisma.managedUploadOwner.count({ where: { ownerId: { in: owners } } })).toBe(0);
    } finally { await prisma.$disconnect(); }
  });

  const owner = async (addonUsed = 0) => {
    const userId = `caption-batch-db-${randomUUID()}`;
    owners.push(userId);
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    await prisma.managedUploadOwner.create({ data: { ownerId: userId, status: 'ACTIVE' } });
    await prisma.monthlyAddonPurchase.create({ data: { id: randomUUID(), userId, ownerHash: monthlyAddonOwnerHash(userId),
      productId: 'postdee_post_ai_49', store: 'PLAY_STORE', environment: 'SANDBOX', transactionId: randomUUID(),
      purchasedAt: new Date('2026-09-01T00:00:00.000Z') } });
    if (addonUsed) await prisma.realClipCaptionUsage.createMany({ data: Array.from({ length: addonUsed }, () => ({
      userId, monthKey: '2026-09', usesAddonCredit: true
    })) });
    return { userId, monthKey, limit: 2, units: 4, includeMonthlyAddons: true, now };
  };

  const records = (reservation: RealClipCaptionUsageReservation) => {
    if (!reservation.ok || !reservation.records) throw new Error('Expected a committed caption batch');
    return reservation.records;
  };

  const instrumentedRepository = ({ failCreate = false, failDelete = false, synchronizeOwner }: {
    failCreate?: boolean; failDelete?: boolean; synchronizeOwner?: string;
  } = {}) => {
    const conflicts: string[] = [];
    let transactionsStarted = 0;
    let snapshotsRead = 0;
    let releaseSnapshots!: () => void;
    const snapshotsReady = new Promise<void>(resolve => { releaseSnapshots = resolve; });
    const client: PrismaRealClipCaptionUsageClient = {
      realClipCaptionUsage: prisma.realClipCaptionUsage,
      monthlyAddonPurchase: prisma.monthlyAddonPurchase,
      managedUploadOwner: prisma.managedUploadOwner,
      $transaction: async (operation, options) => {
        try {
          return await prisma.$transaction(async transaction => {
            if (synchronizeOwner && ++transactionsStarted <= 2) {
              // Establish both serializable snapshots before either writer
              // locks the owner marker. The loser must retry against new rows.
              await transaction.managedUploadOwner.findUnique({ where: { ownerId: synchronizeOwner } });
              if (++snapshotsRead === 2) releaseSnapshots();
              await snapshotsReady;
            }
            let creates = 0;
            let deletes = 0;
            return operation({
              monthlyAddonPurchase: transaction.monthlyAddonPurchase,
              managedUploadOwner: transaction.managedUploadOwner,
              realClipCaptionUsage: {
                count: args => transaction.realClipCaptionUsage.count(args),
                create: async args => {
                  const row = await transaction.realClipCaptionUsage.create(args);
                  if (failCreate && ++creates === 2) throw new Error('Injected failure after second real insert');
                  return row;
                },
                deleteMany: async args => {
                  const result = await transaction.realClipCaptionUsage.deleteMany(args);
                  if (failDelete && ++deletes === 2) throw new Error('Injected failure after second real delete');
                  return result;
                }
              }
            });
          }, options);
        } catch (error) {
          if (error && typeof error === 'object' && 'code' in error) conflicts.push(String(error.code));
          throw error;
        }
      }
    };
    return { repository: createPrismaRealClipCaptionUsageRepository({ prisma: client }), conflicts };
  };

  it('supports the generated Prisma client and keeps a one-credit response unchanged', async () => {
    const input = await owner();
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    const result = await repository.reserve({ ...input, units: undefined });
    expect(result).toMatchObject({ ok: true, usedThisMonth: 1 });
    expect(result).not.toHaveProperty('records');
    expect(await prisma.realClipCaptionUsage.count({ where: { userId: input.userId } })).toBe(1);
  });

  it('atomically funds one of two competing mixed batches with the final four credits', async () => {
    const input = await owner(48);
    const { repository, conflicts } = instrumentedRepository({ synchronizeOwner: input.userId });
    const results = await Promise.all([repository.reserve(input), repository.reserve(input)]);
    expect(results.filter(result => result.ok)).toHaveLength(1);
    expect(results.filter(result => !result.ok)).toHaveLength(1);
    const winner = results.find(result => result.ok)!;
    expect(records(winner).map(record => Boolean(record.usesAddonCredit))).toEqual([false, false, true, true]);
    expect(await repository.countForMonth(input)).toBe(2);
    expect(await repository.countAddonUsages(input)).toBe(50);
    expect(conflicts).toContain('P2034');
    expect(conflicts.every(code => code === 'P2034')).toBe(true);
    expect(await repository.releaseMany!(records(winner))).toBe(true);
    expect(await repository.countForMonth(input)).toBe(0);
    expect(await repository.countAddonUsages(input)).toBe(48);
  });

  it('does not insert any rows if three credits remain for a four-credit request', async () => {
    const input = await owner(49);
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    expect(await repository.reserve(input)).toEqual({ ok: false, usedThisMonth: 0 });
    expect(await prisma.realClipCaptionUsage.count({ where: { userId: input.userId } })).toBe(49);
  });

  it('rolls back real inserts if the second insert fails before commit', async () => {
    const input = await owner(48);
    const { repository } = instrumentedRepository({ failCreate: true });
    await expect(repository.reserve(input)).rejects.toThrow('Injected failure after second real insert');
    expect(await repository.countForMonth(input)).toBe(0);
    expect(await repository.countAddonUsages(input)).toBe(48);
  });

  it('preserves concurrent rows and rolls back an incomplete exact-owner refund', async () => {
    const input = await owner();
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    const first = records(await repository.reserve({ ...input, limit: 8 }));
    const second = records(await repository.reserve({ ...input, limit: 8 }));
    expect(await repository.releaseMany!([first[0], { ...first[1], id: 'nonexistent-row' }])).toBe(false);
    expect(await repository.countForMonth(input)).toBe(8);
    expect(await repository.releaseMany!(first)).toBe(true);
    expect(await prisma.realClipCaptionUsage.findMany({ where: { userId: input.userId }, select: { id: true } }))
      .toEqual(expect.arrayContaining(second.map(record => ({ id: record.id }))));
    expect(await repository.countForMonth(input)).toBe(4);
  });

  it('rolls back real deletes if refund fails after deleting the second row', async () => {
    const input = await owner();
    const { repository } = instrumentedRepository({ failDelete: true });
    const batch = records(await repository.reserve({ ...input, limit: 4 }));
    await expect(repository.releaseMany!(batch)).rejects.toThrow('Injected failure after second real delete');
    expect(await repository.countForMonth(input)).toBe(4);
  });

  it('rejects a complete batch for an owner whose deletion has started', async () => {
    const input = await owner();
    await prisma.managedUploadOwner.update({ where: { ownerId: input.userId }, data: { status: 'DELETING' } });
    const repository = createPrismaRealClipCaptionUsageRepository({ prisma });
    await expect(repository.reserve(input)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(await repository.countForMonth(input)).toBe(0);
    expect(await repository.countAddonUsages(input)).toBe(0);
  });
});
