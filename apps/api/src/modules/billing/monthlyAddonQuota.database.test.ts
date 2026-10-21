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
describe.skipIf(!databaseUrl)('monthly addon PostgreSQL quota concurrency', () => {
  let prisma: PrismaClient;
  const userId = `addon-quota-db-${randomUUID()}`;
  const now = new Date().toISOString();
  const monthKey = now.slice(0, 7);
  const purchase = { userId, productId: 'postdee_post_ai_49', transactionId: randomUUID(),
    store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now };

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

  it('serializes the final post and AI units, then rejects new usage after refund', async () => {
    const addons = createPrismaMonthlyAddonRepository({ prisma: prisma as unknown as PrismaMonthlyAddonClient });
    const posts = createPrismaPostRepository({ prisma: prisma as unknown as PrismaPostClient });
    const captions = createPrismaRealClipCaptionUsageRepository({
      prisma: prisma as unknown as PrismaRealClipCaptionUsageClient
    });
    await addons.applyPurchase(purchase);
    await prisma.post.createMany({ data: Array.from({ length: 219 }, (_, index) => ({
      userId, caption: 'Quota fixture', videoS3Key: `uploads/${userId}/clip/${index}.mp4`,
      selectedPlatforms: ['TIKTOK' as const], status: 'QUEUED' as const, createdAt: new Date(now)
    })) });
    await prisma.realClipCaptionUsage.createMany({ data: Array.from({ length: 99 }, () => ({ userId, monthKey })) });
    const postInput = { userId, caption: 'Final addon unit', videoS3Key: `uploads/${userId}/clip/final.mp4`,
      platforms: ['TIKTOK' as const], monthlyPostUnitLimit: 120, includeMonthlyAddons: true, now };
    const postResults = await Promise.all(['last-a', 'last-b'].map(clientRequestId =>
      posts.createWithinMonthlyLimit({ ...postInput, clientRequestId })));
    expect(postResults.filter(result => result.ok && result.created)).toHaveLength(1);
    expect(postResults.filter(result => !result.ok)).toHaveLength(1);
    expect(await posts.countMonthlyPostUnits({ userId, now })).toBe(220);

    const captionInput = { userId, monthKey, limit: 50, includeMonthlyAddons: true, now };
    const captionResults = await Promise.all([captions.reserve(captionInput), captions.reserve(captionInput)]);
    expect(captionResults.filter(result => result.ok)).toHaveLength(1);
    expect(captionResults.filter(result => !result.ok)).toHaveLength(1);
    expect(await captions.countForMonth({ userId, monthKey })).toBe(100);
    const reservedCaption = captionResults.find(result => result.ok);
    if (!reservedCaption?.ok) throw new Error('Missing committed caption reservation');
    expect(await captions.release!(reservedCaption.record)).toBe(true);
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: true, usedThisMonth: 100 });

    await addons.revokePurchase(purchase);
    expect(await addons.readCredits({ userId, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: 'after-refund' })).toEqual({ ok: false });
    expect(await captions.reserve(captionInput)).toMatchObject({ ok: false, usedThisMonth: 100 });
    const winnerKey = postResults[0].ok ? 'last-a' : 'last-b';
    expect(await posts.createWithinMonthlyLimit({ ...postInput, clientRequestId: winnerKey }))
      .toMatchObject({ ok: true, created: false });
    expect(await prisma.post.count({ where: { userId } })).toBe(220);
  }, 30000);
});
