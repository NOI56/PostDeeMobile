import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { registerAnalyticsRoutes } from './analyticsRoutes.js';

const retiredResponse = {
  status: 'error',
  code: 'ANALYTICS_RETIRED',
  message: 'Post analytics has been retired'
};

describe('retired analytics routes', () => {
  it.each(['BASIC', 'STARTER', 'PRO'])('retires analytics for %s users', async (plan) => {
    const app = createApp();

    const response = await request(app)
      .get('/analytics/summary')
      .set('x-postdee-subscription-plan', plan)
      .expect(410);

    expect(response.body).toEqual(retiredResponse);
  });

  it.each(['today', '7d', '30d', '90d', 'year', 'forever', '7d&range=year'])(
    'returns retirement instead of validating range %s',
    async (range) => {
      const app = createApp();

      const response = await request(app)
        .get(`/analytics/summary?range=${range}`)
        .set('x-postdee-subscription-plan', 'PRO')
        .expect(410);

      expect(response.body).toEqual(retiredResponse);
    }
  );

  it('does not read a subscription or metrics for an authenticated request', async () => {
    const app = express();
    const subscriptionStore = createSubscriptionStore();
    const getPlan = vi.spyOn(subscriptionStore, 'getPlan');
    const analyticsStore = { summaryForUser: vi.fn() };
    registerAnalyticsRoutes(
      app,
      (_request, response, next) => {
        response.locals.authUser = { id: 'seller-analytics', provider: 'mock' };
        next();
      },
      subscriptionStore,
      analyticsStore
    );

    const response = await request(app).get('/analytics/summary?range=7d').expect(410);

    expect(response.body).toEqual(retiredResponse);
    expect(getPlan).not.toHaveBeenCalled();
    expect(analyticsStore.summaryForUser).not.toHaveBeenCalled();
  });

  it('still requires authentication before returning retirement', async () => {
    const verifyIdToken = vi.fn().mockResolvedValue({ id: 'seller-analytics', provider: 'firebase' });
    const analyticsStore = { summaryForUser: vi.fn() };
    const app = createApp({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'postdee-test' }),
      firebaseVerifier: { verifyIdToken },
      analyticsStore
    });

    await request(app).get('/analytics/summary').expect(401);
    expect(verifyIdToken).not.toHaveBeenCalled();
    expect(analyticsStore.summaryForUser).not.toHaveBeenCalled();

    const response = await request(app)
      .get('/analytics/summary')
      .set('Authorization', 'Bearer analytics-retirement-token')
      .expect(410);

    expect(response.body).toEqual(retiredResponse);
    expect(verifyIdToken).toHaveBeenCalledWith('analytics-retirement-token');
    expect(analyticsStore.summaryForUser).not.toHaveBeenCalled();
  });
});
