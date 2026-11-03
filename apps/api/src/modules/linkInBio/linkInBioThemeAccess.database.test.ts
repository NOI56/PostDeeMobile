import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import express from 'express';
import request from 'supertest';
import { afterAll, describe, expect, it } from 'vitest';

import { createPrismaSubscriptionRepository, type PrismaSubscriptionClient } from '../subscriptions/prismaSubscriptionRepository.js';
import { createDefaultLinkInBioTemplateAppearance } from './linkInBioAppearance.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';
import { samePremiumProfileStyling } from './linkInBioThemeAccess.js';
import { LinkInBioError } from './linkInBioStore.js';

const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Theme membership DB tests require the dedicated loopback fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl).sequential('profile theme membership on real PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const userId = `theme-fixture-${randomUUID()}`;
  const slug = `theme-${randomUUID().slice(0, 18)}`;
  const user = { id: userId, provider: 'firebase' as const };
  const profiles = createPrismaLinkInBioRepository({ prisma: prisma as unknown as PrismaLinkInBioClient });
  const subscriptions = createPrismaSubscriptionRepository({ prisma: prisma as unknown as PrismaSubscriptionClient });
  const appearance = { ...createDefaultLinkInBioTemplateAppearance('cartoon-doodle-shop'), description: 'Retained owner content' };
  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: userId } });
    await prisma.$disconnect();
  });

  it('loads owner identity from the same published row and uses paid expiry without rewriting saved style', async () => {
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    await profiles.publish({ userId, storeName: 'Theme DB fixture', slug, appearance,
      links: [{ id: 'buy', title: 'Owner destination', url: 'https://example.com/shop' }] });
    const snapshot = await profiles.getPublishedWithOwnerBySlug!(slug);
    expect(snapshot?.userId).toBe(userId);
    expect(snapshot?.profile).not.toHaveProperty('userId');
    const app = express();
    const router = express.Router();
    registerLinkInBioRoutes(router, (_req, res, next) => { res.locals.authUser = user; next(); },
      profiles, undefined, { subscriptionStore: subscriptions });
    app.use(router);
    await subscriptions.activatePlan(user, 'STARTER', { currentPeriodEnd: '2099-12-01T00:00:00.000Z' });
    const active = await request(app).get(`/p/${slug}`).expect(200);
    expect(active.text.includes('data-template="cartoon-doodle-shop"')).toBe(true);
    await prisma.subscription.update({ where: { userId }, data: { currentPeriodEnd: new Date('2000-01-01T00:00:00Z') } });
    const expired = await request(app).get(`/p/${slug}`).set('x-postdee-user-id', 'other-owner')
      .set('x-postdee-subscription-plan', 'BUSINESS').expect(200);
    expect(expired.headers['cache-control']).toBe('no-store');
    expect(expired.text.includes('data-template="cartoon-doodle-shop"')).toBe(false);
    expect(expired.text.includes('data-theme="minimal"')).toBe(true);
    expect(expired.text).toContain(appearance.description);
    expect((await prisma.linkInBioProfile.findUniqueOrThrow({ where: { userId } })).appearance).toEqual(appearance);
    await subscriptions.activatePlan(user, 'STARTER', { currentPeriodEnd: '2099-12-01T00:00:00.000Z' });
    expect((await request(app).get(`/p/${slug}`).expect(200)).text.includes('data-template="cartoon-doodle-shop"')).toBe(true);
  });

  it('rejects a cross-transaction stale premium retention without overwriting the newer style', async () => {
    const input = { userId, storeName: 'Theme concurrency fixture', slug,
      links: [{ id: 'buy', title: 'Owner destination', url: 'https://example.com/shop' }], appearance };
    await profiles.publish(input);
    let entered!: () => void;
    let release!: () => void;
    const enteredPromise = new Promise<void>(resolve => { entered = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    const gated = {
      linkInBioProfile: prisma.linkInBioProfile,
      linkInBioSlugReservation: prisma.linkInBioSlugReservation,
      $transaction: async <T>(operation: Parameters<PrismaLinkInBioClient['$transaction']>[0], options?: { isolationLevel: 'Serializable' }): Promise<T> =>
        prisma.$transaction(async tx => {
          const delegate = new Proxy(tx.linkInBioProfile, {
            get(target, key, receiver) {
              if (key === 'findUnique') return async (args: Parameters<typeof target.findUnique>[0]) => {
                const row = await target.findUnique(args);
                entered(); await gate; return row;
              };
              return Reflect.get(target, key, receiver);
            }
          });
          return operation({ linkInBioProfile: delegate, linkInBioSlugReservation: tx.linkInBioSlugReservation } as unknown as
            Parameters<Parameters<PrismaLinkInBioClient['$transaction']>[0]>[0]) as Promise<T>;
        }, options)
    } as unknown as PrismaLinkInBioClient;
    const guarded = createPrismaLinkInBioRepository({ prisma: gated });
    const pending = guarded.publish(input, { validateCurrentAppearance: current => {
      if (!current?.appearance || !samePremiumProfileStyling(current.appearance, appearance)) {
        throw new LinkInBioError(409, 'LINK_IN_BIO_APPEARANCE_CONFLICT', 'The saved style changed');
      }
      return undefined;
    } }).then(() => undefined, error => error as LinkInBioError);
    await enteredPromise;
    const newer = createDefaultLinkInBioTemplateAppearance('cartoon-comic-panels');
    try { await profiles.publish({ ...input, appearance: newer }); } finally { release(); }
    expect(await pending).toMatchObject({ statusCode: 409, code: 'LINK_IN_BIO_APPEARANCE_CONFLICT' });
    expect((await prisma.linkInBioProfile.findUniqueOrThrow({ where: { userId } })).appearance).toEqual(newer);
  }, 15_000);
});
