import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { registerCaptionRoutes } from './captionRoutes.js';
import { generateLocalAffiliateCaption, generateLocalRealClipCaption } from './captionService.js';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';
import type { RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';

const platforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
const userId = 'credit-owner';
const monthKey = '2026-10';
const videoS3Key = `uploads/${userId}/clip/source.mp4`;
const fixture = ({ addonCredits = 0, fail = false } = {}) => {
  const monthlyAddonStore = { readCredits: async () => ({ postUnits: 0, aiCaptions: addonCredits }) };
  const usage = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore });
  const subscriptions = createSubscriptionStore();
  vi.spyOn(subscriptions, 'getPlan').mockResolvedValue('STARTER');
  const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => {
    if (fail) throw new Error('provider unavailable');
    return { ...generateLocalRealClipCaption(input), model: 'test-ai' };
  });
  const fetchMedia = vi.fn(async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' }));
  const cleanup = vi.fn(async (_key: string) => {});
  const app = express();
  const router = express.Router();
  app.use(express.json());
  registerCaptionRoutes(router, { generate: async () => generateLocalAffiliateCaption(['สินค้า']) },
    (_req, res, next) => { res.locals.authUser = { id: userId, provider: 'mock' }; next(); },
    subscriptions, undefined, usage, { generate }, fetchMedia, cleanup, undefined,
    { monthlyAddonStore, now: () => new Date('2026-10-25T00:00:00.000Z') });
  app.use(router);
  const seed = async (count: number) => {
    for (let index = 0; index < count; index++) await usage.record({ userId, monthKey });
  };
  const post = (body: object) => request(app).post('/captions/generate-from-clip').send({ videoS3Key, ...body });
  return { app, usage, generate, fetchMedia, cleanup, seed, post };
};

describe('caption credits per selected channel', () => {
  it.each([1, 2, 3, 4])('charges %s credits in one provider call', async cost => {
    const { usage, generate, post } = fixture();
    const response = await post({ platforms: platforms.slice(0, cost), expectedCredits: cost }).expect(200);
    expect(response.body.quota).toMatchObject({ requestedCredits: cost, chargedCredits: cost,
      usedThisMonth: cost, remainingThisMonth: 50 - cost });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(cost);
    expect(generate).toHaveBeenCalledOnce();
  });

  it('keeps shared captions and old single-channel requests at one credit', async () => {
    const { post } = fixture();
    for (const body of [{}, { platforms: ['TIKTOK'] }]) {
      const response = await post(body).expect(200);
      expect(response.body.quota).toMatchObject({ requestedCredits: 1, chargedCredits: 1 });
    }
  });

  it.each([undefined, 1, 3, 5, '4', null])('rejects unconfirmed or mismatched multi-channel cost %s without debit', async expectedCredits => {
    const { post, usage, generate, fetchMedia, cleanup } = fixture();
    const response = await post({ platforms, expectedCredits, deleteAfterUse: true }).expect(409);
    expect(response.body).toMatchObject({ code: 'AI_CAPTION_COST_CONFIRMATION_REQUIRED',
      quota: { requiredCredits: 4, chargedCredits: 0 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
    expect(generate).not.toHaveBeenCalled();
    expect(fetchMedia).not.toHaveBeenCalled();
    expect(cleanup).toHaveBeenCalledExactlyOnceWith(videoS3Key);
  });

  it('also rejects a supplied incorrect shared-caption price', async () => {
    const { post, usage, generate } = fixture();
    await post({ expectedCredits: 4 }).expect(409);
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
    expect(generate).not.toHaveBeenCalled();
  });

  it('reports the actual three available credits and reserves nothing for a four-credit request', async () => {
    const { seed, post, usage, generate, fetchMedia } = fixture();
    await seed(47);
    const response = await post({ platforms, expectedCredits: 4 }).expect(429);
    expect(response.body.quota).toMatchObject({ requiredCredits: 4, usedThisMonth: 47,
      remainingThisMonth: 3, addonRemaining: 0, availableGenerations: 3 });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(47);
    expect(generate).not.toHaveBeenCalled();
    expect(fetchMedia).not.toHaveBeenCalled();
  });

  it('spends the monthly balance first and completes the batch from purchased credits', async () => {
    const { seed, post, usage } = fixture({ addonCredits: 2 });
    await seed(48);
    const response = await post({ platforms, expectedCredits: 4 }).expect(200);
    expect(response.body.quota).toMatchObject({ requestedCredits: 4, chargedCredits: 4,
      usedThisMonth: 50, remainingThisMonth: 0, addonRemaining: 0, availableGenerations: 0 });
    expect(await usage.countAddonUsages({ userId })).toBe(2);
  });

  it('can fund all four channels from retained purchased credits after monthly exhaustion', async () => {
    const { seed, post, usage } = fixture({ addonCredits: 4 });
    await seed(50);
    const response = await post({ platforms, expectedCredits: 4 }).expect(200);
    expect(response.body.quota).toMatchObject({ chargedCredits: 4, usedThisMonth: 50,
      remainingThisMonth: 0, addonRemaining: 0, availableGenerations: 0 });
    expect(await usage.countAddonUsages({ userId })).toBe(4);
  });

  it('leaves both monthly and purchased credits untouched when their combined three cannot fund four', async () => {
    const { seed, post, usage, generate } = fixture({ addonCredits: 1 });
    await seed(48);
    const response = await post({ platforms, expectedCredits: 4 }).expect(429);
    expect(response.body.quota).toMatchObject({ requiredCredits: 4, remainingThisMonth: 2,
      addonRemaining: 1, availableGenerations: 3 });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(48);
    expect(await usage.countAddonUsages({ userId })).toBe(0);
    expect(generate).not.toHaveBeenCalled();
  });

  it('refunds all four mixed credits after provider failure while preserving previous usage', async () => {
    const { seed, post, usage, generate } = fixture({ addonCredits: 2, fail: true });
    await seed(48);
    const response = await post({ platforms, expectedCredits: 4 }).expect(200);
    expect(response.body).toMatchObject({ isFallback: true, quota: { requestedCredits: 4,
      chargedCredits: 0, charged: false, usedThisMonth: 48, remainingThisMonth: 2, addonRemaining: 2 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(48);
    expect(await usage.countAddonUsages({ userId })).toBe(0);
    expect(generate).toHaveBeenCalledOnce();
  });

  it('does not claim a refund when the atomic batch release fails', async () => {
    const { post, usage } = fixture({ fail: true });
    vi.spyOn(usage, 'releaseMany').mockRejectedValue(new Error('database unavailable'));
    const response = await post({ platforms, expectedCredits: 4 }).expect(200);
    expect(response.body).toMatchObject({ isFallback: true, quota: { requestedCredits: 4,
      chargedCredits: 4, charged: true, usedThisMonth: 4, remainingThisMonth: 46 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(4);
  });

  it('allows only one concurrent four-channel request to spend the final four credits', async () => {
    const { seed, post, usage, generate } = fixture();
    await seed(46);
    const responses = await Promise.all([post({ platforms, expectedCredits: 4 }), post({ platforms, expectedCredits: 4 })]);
    expect(responses.map(response => response.status).sort()).toEqual([200, 429]);
    expect(await usage.countForMonth({ userId, monthKey })).toBe(50);
    expect(generate).toHaveBeenCalledOnce();
  });
});
