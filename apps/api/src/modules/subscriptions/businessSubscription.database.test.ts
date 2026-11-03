import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';

import { createPrismaTrialAccessStore } from '../admin/prismaTrialAccessStore.js';
import { withTrialAccess } from '../admin/trialAccess.js';
import { createPrismaSubscriptionRepository, type PrismaSubscriptionClient } from './prismaSubscriptionRepository.js';

const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Business subscription DB tests require the dedicated loopback fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl).sequential('Business subscription on real PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const id = `business-fixture-${randomUUID()}`;
  const user = { id, provider: 'firebase' as const };
  const store = createPrismaSubscriptionRepository({ prisma: prisma as unknown as PrismaSubscriptionClient });
  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id } });
    await prisma.$disconnect();
  });

  it('stores Business in the additive enum and preserves the same owner when changing plans', async () => {
    await prisma.user.create({ data: { id, firebaseUid: id, email: `${id}@example.test` } });
    await store.activatePlan(user, 'PRO', { billingSubscriptionId: `revenuecat:${id}`, currentPeriodEnd: '2099-12-01T00:00:00.000Z' });
    const before = await prisma.subscription.findUniqueOrThrow({ where: { userId: id } });
    await store.activatePlan(user, 'BUSINESS');
    const after = await prisma.subscription.findUniqueOrThrow({ where: { userId: id } });
    expect(after.id).toBe(before.id);
    expect(after.currentPeriodEnd).toEqual(before.currentPeriodEnd);
    expect(await store.getPlan(user)).toBe('BUSINESS');
    await store.activatePlan(user, 'STARTER');
    expect(await store.getPlan(user)).toBe('STARTER');
  });

  it('persists a Business trial and keeps purchased Business above a Pro trial', async () => {
    const trials = createPrismaTrialAccessStore(prisma);
    await trials.mutate({ requestId: randomUUID(), actorId: id, userId: id, expectedEmail: `${id}@example.test`,
      action: 'GRANT', plan: 'BUSINESS', days: 7, expectedVersion: 0, reason: 'Synthetic Business trial fixture' });
    expect((await trials.find(id))?.plan).toBe('BUSINESS');
    expect(await withTrialAccess(store, trials).getPlan(user)).toBe('BUSINESS');
    await store.activatePlan(user, 'BUSINESS');
    expect(await withTrialAccess(store, { find: async () => ({ userId: id, plan: 'PRO',
      startsAt: new Date(Date.now() - 60_000).toISOString(), expiresAt: new Date(Date.now() + 60_000).toISOString(),
      revokedAt: null, version: 1 }) }).getPlan(user)).toBe('BUSINESS');
  });

});
