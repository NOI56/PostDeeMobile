import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import type { RevenueCatSubscriberClient } from './revenueCatSubscriberClient.js';

const createRevenueCatConfig = (restApiKey = 'rc-secret-key') =>
  readServerConfig({
    BILLING_PROVIDER: 'revenuecat',
    REVENUECAT_WEBHOOK_AUTH_TOKEN: 'revenuecat-webhook-token',
    REVENUECAT_REST_API_V1_KEY: restApiKey,
    REVENUECAT_STARTER_ENTITLEMENT_ID: 'starter',
    REVENUECAT_PRO_ENTITLEMENT_ID: 'pro',
    REVENUECAT_STARTER_PRODUCT_ID: 'postdee_starter_monthly',
    REVENUECAT_PRO_PRODUCT_ID: 'postdee_pro_monthly'
  });

describe('RevenueCat subscription resync', () => {
  it('syncs the authenticated user to Pro and ignores body user ids', async () => {
    const loadSubscriber = vi.fn().mockResolvedValue({
      activeEntitlements: [
        {
          id: 'pro',
          productId: 'postdee_pro_monthly',
          expiresAt: '2100-01-01T00:00:00.000Z'
        }
      ]
    });
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: { loadSubscriber }
    });

    const response = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', 'seller-restore')
      .send({ appUserId: 'attacker-user' })
      .expect(200);

    expect(loadSubscriber).toHaveBeenCalledWith('seller-restore');
    expect(response.body).toMatchObject({
      status: 'ok',
      plan: 'PRO',
      subscription: {
        userId: 'seller-restore',
        plan: 'PRO',
        status: 'ACTIVE',
        billingSubscriptionId: 'revenuecat:seller-restore',
        currentPeriodEnd: '2100-01-01T00:00:00.000Z'
      }
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-restore')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('PRO');
  });

  it('prefers Pro when both paid entitlements are active', async () => {
    const client: RevenueCatSubscriberClient = {
      loadSubscriber: vi.fn().mockResolvedValue({
        activeEntitlements: [
          { id: 'starter', productId: 'postdee_starter_monthly' },
          { id: 'pro', productId: 'postdee_pro_monthly' }
        ]
      })
    };
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: client
    });

    const response = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', 'seller-both')
      .send({})
      .expect(200);

    expect(response.body.plan).toBe('PRO');
  });

  it('deactivates stale paid access when RevenueCat has no active entitlement', async () => {
    const loadSubscriber = vi
      .fn()
      .mockResolvedValueOnce({
        activeEntitlements: [{ id: 'pro', productId: 'postdee_pro_monthly' }]
      })
      .mockResolvedValueOnce({ activeEntitlements: [] });
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: { loadSubscriber }
    });
    const sync = () =>
      request(app)
        .post('/billing/revenuecat/resync')
        .set('x-postdee-user-id', 'seller-expired')
        .send({});

    await sync().expect(200);
    const response = await sync().expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      plan: 'BASIC',
      subscription: {
        userId: 'seller-expired',
        status: 'CANCELED'
      }
    });
    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-expired')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('BASIC');
  });

  it('does not deactivate a subscription verified by another provider', async () => {
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn().mockResolvedValue({ activeEntitlements: [] })
      },
      storePurchaseVerifier: {
        verify: async (purchase) => ({
          provider: 'google-play',
          platform: purchase.platform,
          productId: purchase.productId,
          purchaseToken: purchase.purchaseToken,
          verifiedAt: '2026-07-15T00:00:00.000Z'
        })
      }
    });

    await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-google-play')
      .expect(200);
    await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', 'Bearer revenuecat-webhook-token')
      .send({
        event: {
          type: 'INITIAL_PURCHASE',
          app_user_id: 'seller-google-play',
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly',
          expiration_at_ms: 1
        }
      })
      .expect(200);
    const expiredResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-google-play')
      .expect(200);
    expect(expiredResponse.body.subscription.plan).toBe('BASIC');

    await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-google-play')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'google-play-token'
      })
      .expect(200);

    const response = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', 'seller-google-play')
      .send({})
      .expect(200);
    expect(response.body).toMatchObject({
      status: 'ok',
      plan: 'BASIC',
      effectivePlan: 'PRO',
      subscription: null
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-google-play')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('PRO');
  });

  it('preserves paid access when RevenueCat returns an unmapped active entitlement', async () => {
    const loadSubscriber = vi
      .fn()
      .mockResolvedValueOnce({
        activeEntitlements: [{ id: 'pro', productId: 'postdee_pro_monthly' }]
      })
      .mockResolvedValueOnce({
        activeEntitlements: [{ id: 'renamed-pro', productId: 'renamed-product' }]
      });
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: { loadSubscriber }
    });
    const sync = () =>
      request(app)
        .post('/billing/revenuecat/resync')
        .set('x-postdee-user-id', 'seller-unmapped')
        .send({});

    await sync().expect(200);
    const response = await sync().expect(409);
    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_ENTITLEMENT_NOT_MAPPED'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-unmapped')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('PRO');
  });

  it('returns a safe error and preserves access when RevenueCat lookup fails', async () => {
    const loadSubscriber = vi
      .fn()
      .mockResolvedValueOnce({
        activeEntitlements: [{ id: 'pro', productId: 'postdee_pro_monthly' }]
      })
      .mockRejectedValueOnce(new Error('upstream secret detail'));
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: { loadSubscriber }
    });
    const sync = () =>
      request(app)
        .post('/billing/revenuecat/resync')
        .set('x-postdee-user-id', 'seller-provider-error')
        .send({});

    await sync().expect(200);
    const errorResponse = await sync().expect(502);
    expect(errorResponse.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_RESYNC_FAILED'
    });
    expect(JSON.stringify(errorResponse.body)).not.toContain('upstream secret detail');

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-provider-error')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('PRO');
  });

  it('reports when the server-side RevenueCat key is not configured', async () => {
    const app = createApp({ config: createRevenueCatConfig('') });

    const response = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', 'seller-no-key')
      .send({})
      .expect(501);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_RESYNC_NOT_CONFIGURED'
    });
  });
});
