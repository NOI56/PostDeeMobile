import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createInMemoryMonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import { createSubscriptionStore, type SubscriptionPlan } from '../subscriptions/subscriptionStore.js';
import { registerCaptionRoutes } from './captionRoutes.js';
import { generateLocalAffiliateCaption } from './captionService.js';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';

const fixture = (initialPlan: SubscriptionPlan = 'STARTER', authenticated = true) => {
  let plan = initialPlan;
  let instant = '2026-10-31T23:59:59.000Z';
  const userId = 'caption-quota-owner';
  const authUser = { id: userId, provider: 'mock' as const };
  const monthlyAddonStore = createInMemoryMonthlyAddonStore();
  const usageStore = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore, now: () => instant });
  const subscriptions = createSubscriptionStore();
  const getPlan = vi.spyOn(subscriptions, 'getPlan').mockImplementation(async () => plan);
  const generator = { generate: vi.fn(async () => generateLocalAffiliateCaption(['สินค้า'])) };
  const app = express();
  const router = express.Router();
  const auth: express.RequestHandler = (_request, response, next) => {
    if (authenticated) response.locals.authUser = authUser;
    next();
  };
  app.use(express.json());
  registerCaptionRoutes(router, generator, auth, subscriptions, undefined, usageStore,
    undefined, undefined, undefined, undefined, {
      monthlyAddonStore,
      billingAddonsEnabled: false,
      now: () => new Date(instant)
    });
  app.use(router);
  return { app, userId, authUser, usageStore, monthlyAddonStore, generator, getPlan,
    setPlan: (value: SubscriptionPlan) => { plan = value; },
    setNow: (value: string) => { instant = value; } };
};

describe('caption quota read route', () => {
  it.each([
    { plan: 'BASIC' as const, limit: 0, used: 0, remaining: 0 },
    { plan: 'STARTER' as const, limit: 50, used: 12, remaining: 38 },
    { plan: 'PRO' as const, limit: 120, used: 37, remaining: 83 },
    { plan: 'BASIC' as const, limit: 0, used: 12, remaining: 0 },
    { plan: 'STARTER' as const, limit: 50, used: 80, remaining: 0 }
  ])('returns $plan quota without discarding $used recorded monthly uses', async ({ plan, limit, used, remaining }) => {
    const { app, usageStore } = fixture(plan);
    vi.spyOn(usageStore, 'countForMonth').mockResolvedValue(used);
    const response = await request(app).get('/captions/quota').expect(200);
    expect(response.body).toEqual({ status: 'ok', plan, quota: {
      limit, usedThisMonth: used, remainingThisMonth: remaining,
      addonRemaining: 0, availableGenerations: remaining
    } });
    expect(response.headers['cache-control']).toBe('no-store');
  });

  it('reads only the authenticated user and injected UTC month, ignoring caller overrides', async () => {
    const { app, userId, authUser, usageStore, getPlan, setNow } = fixture();
    await usageStore.record({ userId, monthKey: '2026-10' });
    await usageStore.record({ userId, monthKey: '2026-10' });
    await usageStore.record({ userId, monthKey: '2026-09' });
    await usageStore.record({ userId: 'another-owner', monthKey: '2026-10' });
    const countForMonth = vi.spyOn(usageStore, 'countForMonth');
    const response = await request(app).get('/captions/quota')
      .set('x-postdee-user-id', 'another-owner')
      .set('x-postdee-subscription-plan', 'PRO')
      .query({ userId: 'another-owner', plan: 'PRO', monthKey: '2026-09' }).expect(200);
    expect(getPlan).toHaveBeenCalledExactlyOnceWith(authUser);
    expect(countForMonth).toHaveBeenCalledExactlyOnceWith({ userId, monthKey: '2026-10' });
    expect(response.body).toMatchObject({ plan: 'STARTER', quota: { usedThisMonth: 2, remainingThisMonth: 48 } });
    setNow('2026-11-01T07:00:00.000+07:00');
    const nextMonth = await request(app).get('/captions/quota').expect(200);
    expect(nextMonth.body.quota).toMatchObject({ usedThisMonth: 0, remainingThisMonth: 50 });
  });

  it('never reserves usage or generates captions on repeated reads', async () => {
    const { app, userId, usageStore, generator } = fixture();
    await usageStore.record({ userId, monthKey: '2026-10' });
    const reserve = vi.spyOn(usageStore, 'reserve');
    const record = vi.spyOn(usageStore, 'record');
    for (let index = 0; index < 2; index++) {
      const response = await request(app).get('/captions/quota').expect(200);
      expect(response.body.quota).toMatchObject({ usedThisMonth: 1, remainingThisMonth: 49 });
    }
    expect(reserve).not.toHaveBeenCalled();
    expect(record).not.toHaveBeenCalled();
    expect(generator.generate).not.toHaveBeenCalled();
  });

  it('keeps purchased credit availability across a month boundary and the purchase gate being off', async () => {
    const { app, userId, usageStore, monthlyAddonStore, setPlan, setNow } = fixture();
    await monthlyAddonStore.applyPurchase({ userId, productId: 'postdee_post_ai_49', transactionId: 'quota-addon',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T00:00:00.000Z' });
    for (let index = 0; index < 95; index++) {
      await usageStore.reserve({ userId, monthKey: '2026-10', limit: 50,
        includeMonthlyAddons: true, now: '2026-10-31T23:59:59.000Z' });
    }
    const exhaustedMonthly = await request(app).get('/captions/quota').expect(200);
    expect(exhaustedMonthly.body.quota).toEqual({ limit: 50, usedThisMonth: 50,
      remainingThisMonth: 0, addonRemaining: 5, availableGenerations: 5 });
    setNow('2026-11-01T00:00:00.000Z');
    const nextMonth = await request(app).get('/captions/quota').expect(200);
    expect(nextMonth.body.quota).toEqual({ limit: 50, usedThisMonth: 0,
      remainingThisMonth: 50, addonRemaining: 5, availableGenerations: 55 });
    setPlan('BASIC');
    const expired = await request(app).get('/captions/quota').expect(200);
    expect(expired.body.quota).toEqual({ limit: 0, usedThisMonth: 0,
      remainingThisMonth: 0, addonRemaining: 5, availableGenerations: 0 });
  });

  it('includes keyword and clip generations in the same monthly ledger', async () => {
    const { app, userId } = fixture();
    await request(app).post('/captions/generate').send({ keywords: ['สินค้า'] }).expect(200);
    await request(app).post('/captions/generate-from-clip')
      .send({ videoS3Key: `uploads/${userId}/clip/review.mp4` }).expect(200);
    const response = await request(app).get('/captions/quota').expect(200);
    expect(response.body.quota).toEqual({ limit: 50, usedThisMonth: 2,
      remainingThisMonth: 48, addonRemaining: 0, availableGenerations: 48 });
  });

  it('does not read any account balance without an authenticated user', async () => {
    const { app, usageStore, getPlan } = fixture('STARTER', false);
    const countForMonth = vi.spyOn(usageStore, 'countForMonth');
    const countAddonUsages = vi.spyOn(usageStore, 'countAddonUsages');
    await request(app).get('/captions/quota').expect(401);
    expect(getPlan).not.toHaveBeenCalled();
    expect(countForMonth).not.toHaveBeenCalled();
    expect(countAddonUsages).not.toHaveBeenCalled();
  });
});
