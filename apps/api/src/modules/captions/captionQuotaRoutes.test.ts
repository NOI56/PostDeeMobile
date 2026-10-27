import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { generateLocalAffiliateCaption } from './captionService.js';
import {
  createInMemoryRealClipCaptionUsageStore,
  readCurrentRealClipCaptionMonthKey
} from './captionUsageStore.js';

describe('caption quota route', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it.each([
    { plan: 'BASIC', limit: 0, usedThisMonth: 0, remainingThisMonth: 0 },
    { plan: 'STARTER', limit: 50, usedThisMonth: 12, remainingThisMonth: 38 },
    { plan: 'PRO', limit: 120, usedThisMonth: 37, remainingThisMonth: 83 },
    { plan: 'BASIC', limit: 0, usedThisMonth: 12, remainingThisMonth: 0 },
    { plan: 'STARTER', limit: 50, usedThisMonth: 80, remainingThisMonth: 0 }
  ])('returns $plan quota with $usedThisMonth uses, preserving usage after downgrade', async ({
    plan,
    limit,
    usedThisMonth,
    remainingThisMonth
  }) => {
    const usageStore = createInMemoryRealClipCaptionUsageStore();
    vi.spyOn(usageStore, 'countForMonth').mockResolvedValue(usedThisMonth);
    const app = createApp({ realClipCaptionUsageStore: usageStore });

    const response = await request(app)
      .get('/captions/quota')
      .set('x-postdee-subscription-plan', plan)
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      plan,
      quota: { limit, usedThisMonth, remainingThisMonth }
    });
    expect(response.headers['cache-control']).toBe('no-store');
  });

  it('reads only the authenticated user and current UTC month, ignoring caller overrides', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-31T23:30:00.000Z'));
    const usageStore = createInMemoryRealClipCaptionUsageStore();
    await usageStore.record({ userId: 'seller-owner', monthKey: '2026-10' });
    await usageStore.record({ userId: 'seller-owner', monthKey: '2026-10' });
    await usageStore.record({ userId: 'seller-owner', monthKey: '2026-09' });
    await usageStore.record({ userId: 'seller-other', monthKey: '2026-10' });
    const countForMonth = vi.spyOn(usageStore, 'countForMonth');
    const app = createApp({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase' }),
      firebaseVerifier: {
        verifyIdToken: async () => ({
          id: 'seller-owner',
          provider: 'firebase',
          subscriptionPlan: 'STARTER'
        })
      },
      realClipCaptionUsageStore: usageStore
    });

    const response = await request(app)
      .get('/captions/quota')
      .set('Authorization', 'Bearer verified-owner-token')
      .set('x-postdee-user-id', 'seller-other')
      .set('x-postdee-subscription-plan', 'PRO')
      .query({ userId: 'seller-other', plan: 'PRO', monthKey: '2026-09' })
      .expect(200);

    expect(countForMonth).toHaveBeenCalledExactlyOnceWith({
      userId: 'seller-owner',
      monthKey: '2026-10'
    });
    expect(response.body).toEqual({
      status: 'ok',
      plan: 'STARTER',
      quota: { limit: 50, usedThisMonth: 2, remainingThisMonth: 48 }
    });
  });

  it('does not consume quota or generate captions when read repeatedly', async () => {
    const usageStore = createInMemoryRealClipCaptionUsageStore();
    await usageStore.record({
      userId: 'seller-read-only',
      monthKey: readCurrentRealClipCaptionMonthKey()
    });
    const reserve = vi.spyOn(usageStore, 'reserve');
    const record = vi.spyOn(usageStore, 'record');
    const generate = vi.fn(async () => generateLocalAffiliateCaption(['test']));
    const app = createApp({
      realClipCaptionUsageStore: usageStore,
      captionGenerator: { generate }
    });

    for (let index = 0; index < 2; index += 1) {
      const response = await request(app)
        .get('/captions/quota')
        .set('x-postdee-user-id', 'seller-read-only')
        .set('x-postdee-subscription-plan', 'STARTER')
        .expect(200);

      expect(response.body.quota).toEqual({
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49
      });
    }

    expect(reserve).not.toHaveBeenCalled();
    expect(record).not.toHaveBeenCalled();
    expect(generate).not.toHaveBeenCalled();
  });

  it('includes keyword and real-clip generations in the same quota', async () => {
    const app = createApp();
    const userId = 'seller-shared-caption-usage';

    await request(app)
      .post('/captions/generate')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ keywords: ['กระเป๋า'] })
      .expect(200);
    await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: `uploads/${userId}/clip/review.mp4` })
      .expect(200);

    const response = await request(app)
      .get('/captions/quota')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .expect(200);

    expect(response.body.quota).toEqual({
      limit: 50,
      usedThisMonth: 2,
      remainingThisMonth: 48
    });
  });

  it('requires authentication before reading usage', async () => {
    const usageStore = createInMemoryRealClipCaptionUsageStore();
    const countForMonth = vi.spyOn(usageStore, 'countForMonth');
    const verifyIdToken = vi.fn(async () => ({
      id: 'seller-authenticated',
      provider: 'firebase' as const
    }));
    const app = createApp({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase' }),
      firebaseVerifier: { verifyIdToken },
      realClipCaptionUsageStore: usageStore
    });

    await request(app).get('/captions/quota').expect(401);

    expect(verifyIdToken).not.toHaveBeenCalled();
    expect(countForMonth).not.toHaveBeenCalled();
  });
});
