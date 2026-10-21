import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createPrismaPostRepository, type PrismaPostClient } from '../posts/prismaPostRepository.js';
import { createPrismaRealClipCaptionUsageRepository,
  type PrismaRealClipCaptionUsageClient } from '../captions/prismaRealClipCaptionUsageRepository.js';
import { createPrismaMonthlyAddonRepository, type PrismaMonthlyAddonClient } from './prismaMonthlyAddonRepository.js';
import { monthlyAddonOwnerHash } from './monthlyAddonStore.js';

// Explicitly opt in to a disposable local database that already has migrations.
// This suite never connects to a hosted service or deletes unrelated fixtures.
const databaseUrl = process.env.POSTDEE_ADDON_DB_TEST_URL;
describe.skipIf(!databaseUrl)('nonexpiring addon PostgreSQL quota concurrency', () => {
  let prisma: PrismaClient;
  const userId = `addon-quota-db-${randomUUID()}`;
  const now = new Date().toISOString();
  const monthKey = now.slice(0, 7);
  const previousMonth = new Date(Date.UTC(new Date(now).getUTCFullYear(), new Date(now).getUTCMonth() - 1, 15));
  const previousMonthKey = previousMonth.toISOString().slice(0, 7);
  const purchase = { userId, productId: 'postdee_post_ai_49', transactionId: randomUUID(),
    store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: previousMonth.toISOString() };

  beforeAll(async () => {
    const url = new URL(databaseUrl!);
    if (!['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
        !/^\/postdee_addon_test(?:$|_)/.test(url.pathname)) {
      throw new Error('Addon DB tests require a disposable local postdee_addon_test database');
    }
    prisma = new PrismaClient({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
  });

  afterAll(async () => {
    if (!prisma) return;
    try {
      await prisma.user.deleteMany({ where: { id: userId } });
      await prisma.monthlyAddonPurchase.deleteMany({ where: { ownerHash: monthlyAddonOwnerHash(userId) } });
      await prisma.managedUploadOwner.deleteMany({ where: { ownerId: userId } });
      expect(await prisma.user.count({ where: { id: userId } })).toBe(0);
      expect(await prisma.post.count({ where: { userId } })).toBe(0);
      expect(await prisma.realClipCaptionUsage.count({ where: { userId } })).toBe(0);
      expect(await prisma.monthlyAddonPurchase.count({ where: { ownerHash: monthlyAddonOwnerHash(userId) } })).toBe(0);
      expect(await prisma.managedUploadOwner.count({ where: { ownerId: userId } })).toBe(0);
    } finally { await prisma.$disconnect(); }
  });

  it('preserves prior-month allocations, serializes final units, handles debt and restores exact bank charges', async () => {
    const addons = createPrismaMonthlyAddonRepository({ prisma: prisma as unknown as PrismaMonthlyAddonClient });
    const posts = createPrismaPostRepository({ prisma: prisma as unknown as PrismaPostClient });
    const captions = createPrismaRealClipCaptionUsageRepository({
      prisma: prisma as unknown as PrismaRealClipCaptionUsageClient
    });
    await addons.applyPurchase(purchase);
    await prisma.post.createMany({ data: Array.from({ length: 219 }, (_, index) => ({
      id: `seed-${userId}-${index}`,
      userId, caption: 'Quota fixture', videoS3Key: `uploads/${userId}/clip/${index}.mp4`,
      selectedPlatforms: ['TIKTOK' as const], status: 'QUEUED' as const,
      addonPostUnits: index >= 120 ? 1 : 0,
      createdAt: index >= 120 ? previousMonth : new Date(now)
    })) });
    await prisma.realClipCaptionUsage.createMany({ data: Array.from({ length: 99 }, (_, index) => ({
      userId, monthKey: index >= 50 ? previousMonthKey : monthKey,
      usesAddonCredit: index >= 50, createdAt: index >= 50 ? previousMonth : new Date(now)
    })) });
    expect(await posts.countAddonPostUnits({ userId })).toBe(99);
    expect(await captions.countAddonUsages({ userId })).toBe(49);
    const postInput = { userId, caption: 'Final addon unit', videoS3Key: `uploads/${userId}/clip/final.mp4`,
      platforms: ['TIKTOK' as const], monthlyPostUnitLimit: 120, includeMonthlyAddons: true, now };
    const postResults = await Promise.all(['last-a', 'last-b'].map(clientRequestId =>
      posts.createWithinMonthlyLimit({ ...postInput, clientRequestId })));
    expect(postResults.filter(result => result.ok && result.created)).toHaveLength(1);
    expect(postResults.filter(result => !result.ok)).toHaveLength(1);
    expect(await posts.countMonthlyPostUnits({ userId, now })).toBe(120);
    expect(await posts.countAddonPostUnits({ userId })).toBe(100);

    const captionInput = { userId, monthKey, limit: 50, includeMonthlyAddons: true, now };
    const captionResults = await Promise.all([captions.reserve(captionInput), captions.reserve(captionInput)]);
    expect(captionResults.filter(result => result.ok)).toHaveLength(1);
    expect(captionResults.filter(result => !result.ok)).toHaveLength(1);
    expect(await captions.countForMonth({ userId, monthKey })).toBe(50);
    expect(await captions.countAddonUsages({ userId })).toBe(50);
    const reservedCaption = captionResults.find(result => result.ok);
    if (!reservedCaption?.ok) throw new Error('Missing committed caption reservation');
    expect(await captions.release!(reservedCaption.record)).toBe(true);
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: true, usedThisMonth: 50 });

    await addons.revokePurchase(purchase);
    expect(await addons.readCredits({ userId, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'after-refund' })).toEqual({ ok: false });
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: false, usedThisMonth: 50 });
    const winnerKey = postResults[0].ok ? 'last-a' : 'last-b';
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: winnerKey }))
      .toMatchObject({ ok: true, created: false });
    expect(await prisma.post.count({ where: { userId } })).toBe(220);

    // A replacement pack covers the existing debt. It does not reset usage.
    await addons.applyPurchase({ ...purchase, transactionId: `${purchase.transactionId}-replacement`, purchasedAt: now });
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'debt-covered' })).toEqual({ ok: false });
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: false, usedThisMonth: 50 });
    // Removing/refunding a previous-month allocation returns its exact bank unit.
    expect(await posts.remove({ userId, postId: `seed-${userId}-120` })).toBe(true);
    expect(await posts.countAddonPostUnits({ userId })).toBe(99);
    const historicalCaption = await prisma.realClipCaptionUsage.findFirstOrThrow({
      where: { userId, monthKey: previousMonthKey, usesAddonCredit: true }
    });
    expect(await captions.release!({ id: historicalCaption.id, userId, monthKey: previousMonthKey,
      createdAt: historicalCaption.createdAt.toISOString(), usesAddonCredit: true })).toBe(true);
    expect(await captions.countAddonUsages({ userId })).toBe(49);
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'returned-bank-unit' }))
      .toMatchObject({ ok: true, created: true });
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: true, usedThisMonth: 50 });

    await addons.applyPurchase({ ...purchase, transactionId: `${purchase.transactionId}-additional`, purchasedAt: now });
    expect(await posts.remove({ userId, postId: `seed-${userId}-0` })).toBe(true);
    expect(await posts.remove({ userId, postId: `seed-${userId}-1` })).toBe(true);
    const mixed = await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'mixed-allocation',
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] });
    if (!mixed.ok) throw new Error('Expected a mixed included/bank allocation');
    expect((await prisma.post.findUniqueOrThrow({ where: { id: mixed.post.id } })).addonPostUnits).toBe(2);
    expect(await posts.countMonthlyPostUnits({ userId, now })).toBe(120);
    expect(await posts.countAddonPostUnits({ userId })).toBe(102);
    expect(await posts.remove({ userId, postId: mixed.post.id })).toBe(true);
    expect(await posts.countMonthlyPostUnits({ userId, now })).toBe(118);
    expect(await posts.countAddonPostUnits({ userId })).toBe(100);
    await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'upgraded-plan', monthlyPostUnitLimit: 250 });
    expect(await posts.countAddonPostUnits({ userId })).toBe(100);
  }, 30000);
});
