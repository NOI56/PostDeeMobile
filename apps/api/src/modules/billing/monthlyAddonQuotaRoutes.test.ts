import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createUserStore } from '../users/userStore.js';
import { createSubscriptionStore, type SubscriptionPlan } from '../subscriptions/subscriptionStore.js';
import { createPostStore } from '../posts/postStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { registerPostRoutes } from '../posts/postRoutes.js';
import { createInMemoryRealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import { registerCaptionRoutes } from '../captions/captionRoutes.js';
import { registerBillingRoutes } from './billingRoutes.js';
import { createInMemoryMonthlyAddonStore } from './monthlyAddonStore.js';

const fixture = async (initialPlan: SubscriptionPlan = 'STARTER', enabled = true) => {
  let plan = initialPlan;
  let instant = '2026-10-31T23:59:59.000Z';
  const userId = 'monthly-addon-quota-owner';
  const now = () => new Date(instant);
  const monthlyAddonStore = createInMemoryMonthlyAddonStore();
  await monthlyAddonStore.applyPurchase({ userId, productId: 'postdee_post_ai_49', transactionId: 'purchase-1',
    store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T00:00:00.000Z' });
  const posts = createPostStore({ monthlyAddonStore });
  const captions = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore, now: () => instant });
  const subscriptions = createSubscriptionStore();
  vi.spyOn(subscriptions, 'getPlan').mockImplementation(async () => plan);
  const users = createUserStore();
  const generator = { generate: vi.fn(async () => ({ caption: 'แคปชันทดสอบ', hashtags: ['#ทดสอบ'],
    affiliateLinkPlaceholder: '[ลิงก์]', model: 'test' })) };
  const app = express();
  const router = express.Router();
  const auth: express.RequestHandler = (_request, response, next) => {
    response.locals.authUser = { id: userId, provider: 'mock', phoneVerified: true };
    next();
  };
  const options = { monthlyAddonStore, billingAddonsEnabled: enabled, now };
  app.use(express.json());
  registerBillingRoutes(router, auth, users, subscriptions, posts, options);
  registerPostRoutes(router, posts, createInMemoryPublishQueue(), auth, users, subscriptions,
    createInMemoryPlatformPublishStore(), { ...options, allowSubscriptionPlanOverride: false });
  registerCaptionRoutes(router, generator, auth, subscriptions, undefined, captions,
    undefined, undefined, undefined, users, options);
  app.use(router);
  return { app, posts, captions, userId, generator, setPlan: (value: SubscriptionPlan) => { plan = value; },
    setNow: (value: string) => { instant = value; } };
};

describe('monthly addon quota integration', () => {
  it('reports combined post limits and retains purchases across a plan upgrade', async () => {
    const { app, setPlan } = await fixture();
    const starter = await request(app).get('/billing/subscription').expect(200);
    expect(starter.body.subscription).toMatchObject({ plan: 'STARTER', baseMonthlyPostLimit: 120,
      monthlyPostLimit: 220, remainingPostsThisMonth: 220, addonPostUnits: 100, addonAiCaptions: 50,
      addonExpiresAt: '2026-11-01T00:00:00.000Z' });
    setPlan('PRO');
    expect((await request(app).get('/billing/subscription').expect(200)).body.subscription)
      .toMatchObject({ monthlyPostLimit: 350, addonPostUnits: 100, addonAiCaptions: 50 });
  });

  it('does not grant addon access after subscription expiry or when the feature is disabled', async () => {
    const expired = await fixture('BASIC');
    expect((await request(expired.app).get('/billing/subscription').expect(200)).body.subscription)
      .toMatchObject({ monthlyPostLimit: 3, addonPostUnits: 0, addonAiCaptions: 0, canUseAiCaptions: false });
    await request(expired.app).post('/captions/generate').send({ keywords: ['สินค้า'] }).expect(402);
    const disabled = await fixture('STARTER', false);
    const response = await request(disabled.app).get('/billing/subscription').expect(200);
    expect(response.body.subscription.monthlyPostLimit).toBe(120);
    expect(response.body.subscription).not.toHaveProperty('addonPostUnits');
  });

  it('expires at the UTC monthly boundary and does not roll unused credits forward', async () => {
    const { app, setNow } = await fixture();
    setNow('2026-11-01T06:59:59.000+07:00');
    expect((await request(app).get('/billing/subscription')).body.subscription.monthlyPostLimit).toBe(220);
    setNow('2026-11-01T07:00:00.000+07:00');
    expect((await request(app).get('/billing/subscription')).body.subscription)
      .toMatchObject({ monthlyPostLimit: 120, addonPostUnits: 0, addonAiCaptions: 0 });
  });

  it('counts selected platforms and reserves the final addon post unit once', async () => {
    const { app, posts, userId } = await fixture();
    for (let index = 0; index < 219; index += 1) {
      await posts.createWithinMonthlyLimit({ userId, caption: 'Existing', videoS3Key: `uploads/${userId}/clip/${index}.mp4`,
        platforms: ['TIKTOK'], monthlyPostUnitLimit: 120, includeMonthlyAddons: true, now: '2026-10-31T23:59:59.000Z' });
    }
    const submit = (clientRequestId: string, platforms = ['TIKTOK']) => request(app).post('/posts').send({
      clientRequestId, caption: 'Addon post', videoS3Key: `uploads/${userId}/clip/video.mp4`, platforms });
    await submit('two-platforms', ['TIKTOK', 'YOUTUBE_SHORTS']).expect(402);
    const results = await Promise.all([submit('last-a'), submit('last-b')]);
    expect(results.map(result => result.status).sort()).toEqual([201, 402]);
    expect(results.find(result => result.status === 402)?.body.message).toContain('220 post units');
    const winner = results[0].status === 201 ? 'last-a' : 'last-b';
    await submit(winner).expect(200);
    expect((await request(app).get('/billing/subscription')).body.subscription)
      .toMatchObject({ usedPostsThisMonth: 220, remainingPostsThisMonth: 0 });
  });

  it.each(['/captions/generate', '/captions/generate-from-clip'])(
    'shares addon AI credits with the base allowance for %s', async endpoint => {
      const { app, captions, userId } = await fixture();
      for (let index = 0; index < 99; index += 1) await captions.record({ userId, monthKey: '2026-10' });
      const body = endpoint.endsWith('from-clip')
        ? { videoS3Key: `uploads/${userId}/clip/video.mp4` } : { keywords: ['สินค้า'] };
      const success = await request(app).post(endpoint).send(body).expect(200);
      expect(success.body.quota).toMatchObject({ limit: 100, usedThisMonth: 100, remainingThisMonth: 0 });
      const exceeded = await request(app).post(endpoint).send(body).expect(429);
      expect(exceeded.body.quota).toMatchObject({ limit: 100, usedThisMonth: 100, remainingThisMonth: 0 });
    }
  );

  it('refunds an addon caption when the provider fails without releasing other usage', async () => {
    const { app, captions, userId, generator } = await fixture();
    for (let index = 0; index < 99; index += 1) await captions.record({ userId, monthKey: '2026-10' });
    generator.generate.mockRejectedValueOnce(new Error('provider unavailable'));
    const response = await request(app).post('/captions/generate').send({ keywords: ['สินค้า'] }).expect(200);
    expect(response.body.quota).toMatchObject({ limit: 100, usedThisMonth: 99, remainingThisMonth: 1, charged: false });
    expect(await captions.countForMonth({ userId, monthKey: '2026-10' })).toBe(99);
  });
});
