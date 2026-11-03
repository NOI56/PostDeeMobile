import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createMemoryTrialAccessStore, withTrialAccess } from '../admin/trialAccess.js';
import { createAuthMiddlewareFromConfig } from '../auth/authMiddlewareFactory.js';
import { createPostStore } from '../posts/postStore.js';
import { createSubscriptionStore, type SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { registerBillingRoutes } from './billingRoutes.js';

const owner = { id: 'theme-billing-owner', provider: 'mock' as const };
const fixture = (subscriptions: SubscriptionStore) => {
  const app = express();
  const router = express.Router();
  app.use(express.json());
  registerBillingRoutes(router, createAuthMiddlewareFromConfig({ config: { authProvider: 'mock', mockUserId: owner.id } }),
    createUserStore(), subscriptions, createPostStore());
  app.use(router);
  return app;
};

describe('purchased profile-theme entitlement in subscription status', () => {
  it.each(['BASIC', 'STARTER', 'PRO', 'BUSINESS'] as const)('reports the authoritative %s membership flag', async plan => {
    const subscriptions = createSubscriptionStore();
    if (plan !== 'BASIC') await subscriptions.activatePlan(owner, plan);
    const response = await request(fixture(subscriptions)).get('/billing/subscription').expect(200);
    expect(response.body.subscription.canUsePremiumProfileThemes).toBe(plan !== 'BASIC');
  });

  it('does not trust a mock plan header even though other development capabilities still honor it', async () => {
    const response = await request(fixture(createSubscriptionStore())).get('/billing/subscription')
      .set('x-postdee-subscription-plan', 'PRO').expect(200);
    expect(response.body.subscription.plan).toBe('PRO');
    expect(response.body.subscription.canUsePremiumProfileThemes).toBe(false);
  });

  it('keeps admin-trial-only access separate from a purchased membership', async () => {
    const trials = createMemoryTrialAccessStore();
    await trials.mutate({ requestId: 'theme-billing-trial', actorId: 'admin', userId: owner.id, action: 'GRANT',
      plan: 'PRO', days: 7, expectedVersion: 0, reason: 'Synthetic theme trial fixture' });
    const response = await request(fixture(withTrialAccess(createSubscriptionStore(), trials)))
      .get('/billing/subscription').expect(200);
    expect(response.body.subscription).toMatchObject({ plan: 'PRO', purchasedPlan: 'BASIC', canUsePremiumProfileThemes: false });
  });

  it('returns false when a paid period has ended', async () => {
    const subscriptions = createSubscriptionStore({ now: () => '2026-11-03T00:00:00.000Z' });
    await subscriptions.activatePlan(owner, 'BUSINESS', { currentPeriodEnd: '2026-11-02T00:00:00.000Z' });
    const response = await request(fixture(subscriptions)).get('/billing/subscription').expect(200);
    expect(response.body.subscription).toMatchObject({ plan: 'BASIC', canUsePremiumProfileThemes: false });
  });
});
