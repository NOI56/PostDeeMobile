import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { afterAll, describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createPrismaMonthlyAddonRepository, type PrismaMonthlyAddonClient } from './prismaMonthlyAddonRepository.js';
import { monthlyAddonOwnerHash, monthlyAddonPurchaseKey } from './monthlyAddonStore.js';

// Synthetic local fixtures only. Refuse app databases and external hosts.
const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Monthly add-on DB tests require the dedicated loopback fixture on port 55441');
  }
}
describe.skipIf(!databaseUrl).sequential('monthly add-on real PostgreSQL transactions', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const store = createPrismaMonthlyAddonRepository({ prisma: prisma as unknown as PrismaMonthlyAddonClient });
  const userIds: string[] = [];
  const transactionIds: string[] = [];
  const member = async () => {
    const userId = `addon-fixture-${randomUUID()}`; userIds.push(userId);
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    return userId;
  };
  const purchase = (userId: string) => {
    const transactionId = `synthetic-${randomUUID()}`; transactionIds.push(transactionId);
    return { userId, transactionId, productId: 'postdee_post100_caption50', store: 'PLAY_STORE',
      environment: 'SANDBOX', purchasedAt: '2026-10-21T00:00:00.000Z' };
  };
  afterAll(async () => {
    await prisma.monthlyAddonPurchase.deleteMany({ where: { transactionId: { in: transactionIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.managedUploadOwner.deleteMany({ where: { ownerId: { in: userIds } } });
    await prisma.$disconnect();
  });
  it('grants a concurrent duplicate only once and preserves distinct purchases', async () => {
    const userId = await member(); const one = purchase(userId);
    const results = await Promise.allSettled(Array.from({ length: 4 }, () => store.applyPurchase(one)));
    expect(results.filter(result => result.status === 'rejected').map(result => {
      const reason = result.reason as { name?: string; code?: string; message?: string };
      return { name: reason?.name, code: reason?.code, message: reason?.message?.split('\n').at(-1)?.slice(0, 200) };
    })).toEqual([]);
    expect(results.filter(result => result.status === 'fulfilled' && result.value.applied)).toHaveLength(1);
    await store.applyPurchase(purchase(userId));
    expect(await store.readCredits({ userId, now: one.purchasedAt })).toEqual({ postUnits: 200, aiCaptions: 100 });
  });
  it('reconciles an RC history selector through its canonical store receipt once, respecting refund and owner fences', async () => {
    const userId = await member(); const one = purchase(userId); const selector = `rc-history-${randomUUID()}`;
    const findPurchase = vi.fn().mockImplementation(async (input: { userId: string }) => ({ ...one,
      userId: input.userId, verifiedSelector: selector }));
    const app = createApp({ config: readServerConfig({ POST_STORE: 'prisma', DATABASE_URL: databaseUrl,
      BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: 'fixture', REVENUECAT_REST_API_V1_KEY: 'fixture',
      REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), prisma: prisma as never, monthlyAddonStore: store,
      revenueCatAddonPurchaseClient: { findPurchase } });
    const confirm = (owner: string) => request(app).post('/billing/addons/confirm').set('x-postdee-user-id', owner)
      .send({ productId: one.productId, transactionId: selector, transactionIdKind: 'REVENUECAT' });
    await store.applyPurchase(one);
    await confirm(userId).expect(200); await confirm(userId).expect(200);
    expect(await prisma.monthlyAddonPurchase.count({ where: { transactionId: one.transactionId } })).toBe(1);
    expect(await prisma.monthlyAddonPurchase.count({ where: { transactionId: selector } })).toBe(0);
    const other = await member(); await confirm(other).expect(409);
    await store.revokePurchase(one); await confirm(userId).expect(409);
    expect(await store.readCredits({ userId, now: one.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('serializes two accounts claiming one transaction without any duplicate balance', async () => {
    const first = await member(), second = await member(); const one = purchase(first);
    const results = await Promise.allSettled([store.applyPurchase(one), store.applyPurchase({ ...one, userId: second })]);
    expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
    const balances = await Promise.all([first, second].map(userId => store.readCredits({ userId, now: one.purchasedAt })));
    expect(balances.reduce((sum, item) => sum + item.postUnits, 0)).toBe(100);
  });
  it('keeps refunds sticky across concurrent redelivery while unrevoked grants survive month rollover', async () => {
    const userId = await member(); const one = purchase(userId);
    await store.revokePurchase(one);
    const redeliveries = await Promise.allSettled([store.applyPurchase(one), store.revokePurchase(one)]);
    expect(redeliveries.filter(result => result.status === 'rejected')).toHaveLength(0);
    expect(await store.readCredits({ userId, now: one.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
    await store.applyPurchase(purchase(userId));
    expect(await store.readCredits({ userId, now: '2026-11-01T00:00:00.000Z' })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('retains a transaction tombstone after account deletion without retaining its UID', async () => {
    const userId = await member(); const one = purchase(userId); await store.applyPurchase(one);
    await prisma.user.delete({ where: { id: userId } });
    const retained = await prisma.monthlyAddonPurchase.findUnique({ where: { id: monthlyAddonPurchaseKey(one) } });
    expect(retained).toMatchObject({ userId: null, ownerHash: monthlyAddonOwnerHash(userId) });
    const other = await member();
    await expect(store.applyPurchase({ ...one, userId: other })).rejects.toThrow('already linked');
  });
  it('checks the durable deletion fence before any purchase write', async () => {
    const userId = await member(); const one = purchase(userId);
    await prisma.managedUploadOwner.create({ data: { ownerId: userId, status: 'DELETED' } });
    await expect(store.applyPurchase(one)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(await prisma.monthlyAddonPurchase.count({ where: { transactionId: one.transactionId } })).toBe(0);
  });
});
