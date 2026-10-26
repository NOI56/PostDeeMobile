import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createMemoryTrialAccessStore } from '../admin/trialAccess.js';
import type { AuthUser } from '../auth/authTypes.js';
import { createSubscriptionStore, type SubscriptionPlan, type SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createDefaultLinkInBioAppearance } from './linkInBioAppearance.js';
import { registerLinkInBioRoutes } from './linkInBioRoutes.js';
import { createInMemoryLinkInBioStore } from './linkInBioStore.js';

const owner: AuthUser = { id: 'profile-owner', provider: 'firebase' };
const page = (count: number) => ({
  storeName: 'ร้านเดิม', slug: 'profile-shop',
  links: Array.from({ length: count }, (_, index) => ({
    id: `link-${index}`, title: `ช่องทาง ${index + 1}`, url: `https://example.com/${index}`
  }))
});
const firebaseApp = (options: Omit<NonNullable<Parameters<typeof createApp>[0]>, 'config' | 'firebaseVerifier'> = {}) =>
  createApp({
    ...options,
    config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'profile-test',
      ...(options.trialAccessStore ? { TRIAL_ACCESS_ENABLED: 'true',
        DATABASE_URL: 'postgresql://fixture@127.0.0.1:1/unused_trial_fixture' } : {}) }),
    firebaseVerifier: { verifyIdToken: async () => owner }
  });
const publish = (app: ReturnType<typeof createApp>, count: number) =>
  request(app).post('/link-in-bio/publish').set('Authorization', 'Bearer owner-token').send(page(count));
const routeFixture = (subscriptionStore?: Pick<SubscriptionStore, 'getPlan'>) => {
  const app = express();
  app.use(express.json());
  const router = express.Router();
  const store = createInMemoryLinkInBioStore();
  const validateImages = vi.fn(async () => {});
  registerLinkInBioRoutes(router, (_request, response, next) => {
    response.locals.authUser = owner;
    next();
  }, store, undefined, { subscriptionStore, validateImages });
  app.use(router);
  return { app, store, validateImages };
};

describe('profile-link plan entitlements', () => {
  it.each([
    ['BASIC', 2], ['STARTER', 7], ['PRO', 20]
  ] as const)('%s allows %i links and rejects the next link', async (plan, maximum) => {
    const app = firebaseApp();
    if (plan !== 'BASIC') {
      await request(app).post('/billing/mock-success').set('Authorization', 'Bearer owner-token')
        .send({ plan }).expect(200);
    }
    const status = await request(app).get('/billing/subscription').set('Authorization', 'Bearer owner-token').expect(200);
    expect(status.body.subscription).toMatchObject({ plan, maxProfileLinks: maximum });
    const accepted = await publish(app, maximum).expect(200);
    expect(accepted.body.profile.links).toEqual(page(maximum).links);
    const rejected = await publish(app, maximum + 1).expect(plan === 'PRO' ? 400 : 403);
    if (plan === 'PRO') {
      expect(rejected.body.code).toBe('LINK_IN_BIO_INVALID_INPUT');
    } else {
      expect(rejected.body).toMatchObject({ status: 'error', code: 'LINK_IN_BIO_LINK_LIMIT_EXCEEDED',
        plan, maxProfileLinks: maximum, requestedLinks: maximum + 1 });
      expect(rejected.body.message).toContain(`${maximum}`);
      expect(rejected.body.message).toContain('ลิงก์');
    }
    const retained = await request(app).get('/link-in-bio').set('Authorization', 'Bearer owner-token').expect(200);
    expect(retained.body).toEqual(accepted.body);
  });

  it('guards an old Firebase client without trusting body or development plan headers', async () => {
    const app = firebaseApp();
    await request(app).post('/link-in-bio/publish').set('Authorization', 'Bearer owner-token')
      .set('x-postdee-user-id', 'another-owner').set('x-postdee-subscription-plan', 'PRO')
      .send({ ...page(3), plan: 'PRO', subscriptionPlan: 'PRO', maxProfileLinks: 20,
        userId: 'another-owner' }).expect(403)
      .expect(({ body }) => expect(body).toMatchObject({ code: 'LINK_IN_BIO_LINK_LIMIT_EXCEEDED',
        plan: 'BASIC', maxProfileLinks: 2, requestedLinks: 3 }));
    await request(app).get('/link-in-bio').set('Authorization', 'Bearer owner-token')
      .expect(200, { status: 'ok', profile: null });
    await request(app).get('/p/profile-shop').expect(404);
  });

  it.each([
    ['STARTER', 7], ['PRO', 20]
  ] as const)('uses active %s trial access and drops to Basic after expiry', async (plan, maximum) => {
    let now = new Date('2026-10-26T10:00:00Z');
    const trials = createMemoryTrialAccessStore({ now: () => now });
    await trials.mutate({ requestId: `trial-${plan}`, actorId: 'admin', userId: owner.id,
      action: 'GRANT', plan, days: 7, expectedVersion: 0, reason: 'Profile trial fixture' });
    const app = firebaseApp({ trialAccessStore: trials, now: () => now });
    await publish(app, maximum).expect(200);
    const active = await request(app).get('/billing/subscription').set('Authorization', 'Bearer owner-token').expect(200);
    expect(active.body.subscription).toMatchObject({ plan, maxProfileLinks: maximum, purchasedPlan: 'BASIC' });
    now = new Date('2026-11-02T10:00:00Z');
    const expired = await request(app).get('/billing/subscription').set('Authorization', 'Bearer owner-token').expect(200);
    expect(expired.body.subscription).toMatchObject({ plan: 'BASIC', maxProfileLinks: 2 });
    await publish(app, 3).expect(403);
    const retained = await request(app).get('/link-in-bio').set('Authorization', 'Bearer owner-token').expect(200);
    expect(retained.body.profile.links).toHaveLength(maximum);
    await request(app).get('/p/profile-shop').expect(200);
  });

  it('uses the existing paid-period expiry resolver rather than stale active paid status', async () => {
    let now = '2026-10-26T10:00:00.000Z';
    const subscriptions = createSubscriptionStore({ now: () => now });
    await subscriptions.activatePro(owner, { currentPeriodEnd: '2026-10-27T10:00:00.000Z' });
    const { app } = routeFixture(subscriptions);
    await request(app).post('/link-in-bio/publish').send(page(20)).expect(200);
    now = '2026-10-27T10:00:00.000Z';
    await request(app).post('/link-in-bio/publish').send(page(3)).expect(403)
      .expect(({ body }) => expect(body).toMatchObject({ plan: 'BASIC', maxProfileLinks: 2 }));
    await request(app).get('/link-in-bio').expect(200)
      .expect(({ body }) => expect(body.profile.links).toHaveLength(20));
  });

  it('removes revoked trial access on the next publication while keeping the published page', async () => {
    const now = () => new Date('2026-10-26T10:00:00Z');
    const trials = createMemoryTrialAccessStore({ now });
    const grant = { requestId: 'grant-revoked-trial', actorId: 'admin', userId: owner.id,
      action: 'GRANT' as const, plan: 'PRO' as const, days: 7, expectedVersion: 0,
      reason: 'Profile trial fixture' };
    await trials.mutate(grant);
    const app = firebaseApp({ trialAccessStore: trials, now });
    const accepted = await publish(app, 20).expect(200);
    await trials.mutate({ ...grant, requestId: 'revoke-profile-trial', action: 'REVOKE', expectedVersion: 1 });
    await publish(app, 3).expect(403)
      .expect(({ body }) => expect(body).toMatchObject({ plan: 'BASIC', maxProfileLinks: 2 }));
    expect((await request(app).get('/link-in-bio').set('Authorization', 'Bearer owner-token').expect(200)).body)
      .toEqual(accepted.body);
  });

  it('keeps an existing over-limit page and its exact owner envelope until a valid new publication', async () => {
    const getPlan = vi.fn(async (): Promise<SubscriptionPlan> => 'BASIC');
    const { app, store, validateImages } = routeFixture({ getPlan });
    const appearance = { ...createDefaultLinkInBioAppearance(), description: 'ข้อมูลเดิม',
      logoKey: 'uploads/profile-owner/logo.png' };
    await store.publish({ ...page(20), userId: owner.id, appearance });
    const initial = await request(app).get('/link-in-bio').expect(200);
    expect(Object.keys(initial.body).sort()).toEqual(['profile', 'status']);
    const originalHtml = (await request(app).get('/p/profile-shop').expect(200)).text;
    expect(getPlan).not.toHaveBeenCalled();
    const write = vi.spyOn(store, 'publish');
    await request(app).post('/link-in-bio/publish').send({ ...page(3), storeName: 'เปลี่ยนชื่อ' }).expect(403);
    expect(write).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    expect(getPlan).toHaveBeenCalledExactlyOnceWith(owner);
    expect((await request(app).get('/link-in-bio').expect(200)).body).toEqual(initial.body);
    const retainedHtml = (await request(app).get('/p/profile-shop').expect(200)).text;
    expect(retainedHtml.replace(/nonce="[^"]+"/g, 'nonce="fixture"'))
      .toEqual(originalHtml.replace(/nonce="[^"]+"/g, 'nonce="fixture"'));
    const updated = await request(app).post('/link-in-bio/publish').send(page(2)).expect(200);
    expect(updated.body.profile.links).toEqual(page(2).links);
    expect(updated.body.profile.appearance).toEqual(initial.body.profile.appearance);
  });

  it.each(['missing resolver', 'lookup rejected', 'unknown plan', 'prototype key'])('fails closed with 503 when %s', async (mode) => {
    const getPlan = vi.fn(async () => {
      if (mode === 'lookup rejected') throw new Error('Sensitive database detail');
      return (mode === 'prototype key' ? 'toString' : 'INVALID') as SubscriptionPlan;
    });
    const { app, store, validateImages } = routeFixture(mode === 'missing resolver' ? undefined : { getPlan });
    await store.publish({ ...page(2), userId: owner.id });
    const previous = (await request(app).get('/link-in-bio').expect(200)).body;
    const write = vi.spyOn(store, 'publish');
    const rejected = await request(app).post('/link-in-bio/publish').send(page(1)).expect(503);
    expect(rejected.body.status).toBe('error');
    expect(rejected.body.message).toContain('กรุณาลองใหม่');
    expect(JSON.stringify(rejected.body)).not.toContain('Sensitive');
    expect(write).not.toHaveBeenCalled();
    expect(validateImages).not.toHaveBeenCalled();
    expect((await request(app).get('/link-in-bio').expect(200)).body).toEqual(previous);
    await request(app).get('/p/profile-shop').expect(200);
  });
});
