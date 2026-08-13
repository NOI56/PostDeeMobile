import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createOwnerMutationLock } from '../account/ownerMutationLock.js';
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
  it('does not ensure or reconcile a user when deletion seals the owner during subscriber lookup', async () => {
    const ownerMutationLock = createOwnerMutationLock();
    const userId = 'seller-resync-delete-race';
    let markLookupStarted!: () => void;
    let releaseLookup!: () => void;
    const lookupStarted = new Promise<void>((resolve) => {
      markLookupStarted = resolve;
    });
    const lookupGate = new Promise<void>((resolve) => {
      releaseLookup = resolve;
    });
    const app = createApp({
      config: createRevenueCatConfig(),
      ownerMutationLock,
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn(async () => {
          markLookupStarted();
          await lookupGate;
          return {
            observedAtMs: 1_784_044_899_001,
            activeEntitlements: [
              { id: 'pro', productId: 'postdee_pro_monthly' }
            ]
          };
        })
      }
    });
    const resync = request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId)
      .send({})
      .then((response) => response);

    await lookupStarted;
    ownerMutationLock.markDeleted(userId);
    releaseLookup();

    const response = await resync;
    expect(response.status).toBe(409);
    expect(response.body).toMatchObject({
      status: 'error',
      code: 'ACCOUNT_DELETION_IN_PROGRESS'
    });
  });

  it('lets an in-flight resync finish before account deletion enters cleanup', async () => {
    const userId = 'seller-resync-before-delete';
    let markLookupStarted!: () => void;
    let releaseLookup!: () => void;
    const lookupStarted = new Promise<void>((resolve) => {
      markLookupStarted = resolve;
    });
    const lookupGate = new Promise<void>((resolve) => {
      releaseLookup = resolve;
    });
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn(async () => {
          markLookupStarted();
          await lookupGate;
          return {
            observedAtMs: 1_784_044_899_002,
            activeEntitlements: [
              { id: 'pro', productId: 'postdee_pro_monthly' }
            ]
          };
        })
      }
    });
    const resync = request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId)
      .send({})
      .then((response) => response);

    await lookupStarted;
    let deletionSettled = false;
    const deletion = request(app)
      .delete('/account')
      .set('x-postdee-user-id', userId)
      .then((response) => {
        deletionSettled = true;
        return response;
      });
    await new Promise<void>((resolve) => setImmediate(resolve));
    expect(deletionSettled).toBe(false);

    releaseLookup();
    expect((await resync).status).toBe(200);
    expect((await deletion).status).toBe(200);
  });

  it('syncs the authenticated user to Pro and ignores body user ids', async () => {
    const loadSubscriber = vi.fn().mockResolvedValue({
      observedAtMs: 1_784_044_800_001,
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
        observedAtMs: 1_784_044_800_002,
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
        observedAtMs: 1_784_044_800_003,
        activeEntitlements: [{ id: 'pro', productId: 'postdee_pro_monthly' }]
      })
      .mockResolvedValueOnce({
        observedAtMs: 1_784_044_800_004,
        activeEntitlements: []
      });
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

  it('does not let an older subscriber snapshot cancel a newer webhook renewal', async () => {
    const userId = 'seller-resync-older-than-webhook';
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn().mockResolvedValue({
          observedAtMs: 1_784_044_800_100,
          activeEntitlements: []
        })
      }
    });

    await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', 'Bearer revenuecat-webhook-token')
      .send({
        event: {
          id: 'newer-renewal',
          type: 'RENEWAL',
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly',
          event_timestamp_ms: 1_784_044_800_200
        }
      })
      .expect(200);

    const staleSyncResponse = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId)
      .send({})
      .expect(200);

    expect(staleSyncResponse.body).toMatchObject({
      plan: 'PRO',
      effectivePlan: 'PRO',
      subscription: null
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(subscriptionResponse.body.subscription).toMatchObject({
      plan: 'PRO',
      status: 'ACTIVE'
    });
  });

  it('does not let an older paid snapshot reactivate a newer webhook expiration', async () => {
    const userId = 'seller-paid-resync-older-than-expiration';
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn().mockResolvedValue({
          observedAtMs: 1_784_044_800_500,
          activeEntitlements: [
            { id: 'pro', productId: 'postdee_pro_monthly' }
          ]
        })
      }
    });

    await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', 'Bearer revenuecat-webhook-token')
      .send({
        event: {
          id: 'initial-paid-state',
          type: 'INITIAL_PURCHASE',
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly',
          event_timestamp_ms: 1_784_044_800_400
        }
      })
      .expect(200);
    await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', 'Bearer revenuecat-webhook-token')
      .send({
        event: {
          id: 'newer-expiration',
          type: 'EXPIRATION',
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly',
          event_timestamp_ms: 1_784_044_800_600
        }
      })
      .expect(200);

    const staleSyncResponse = await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId)
      .send({})
      .expect(200);

    expect(staleSyncResponse.body).toMatchObject({
      plan: 'BASIC',
      subscription: null
    });
    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(subscriptionResponse.body.subscription).toMatchObject({
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('does not let an older or equal webhook overwrite a newer subscriber snapshot', async () => {
    const userId = 'seller-resync-newer-than-webhook';
    const observedAtMs = 1_784_044_800_400;
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn().mockResolvedValue({
          observedAtMs,
          activeEntitlements: [
            { id: 'pro', productId: 'postdee_pro_monthly' }
          ]
        })
      }
    });

    await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId)
      .send({})
      .expect(200);

    for (const [eventId, eventTimestampMs] of [
      ['older-expiration', observedAtMs - 1],
      ['equal-expiration', observedAtMs]
    ] as const) {
      await request(app)
        .post('/billing/revenuecat/webhooks')
        .set('Authorization', 'Bearer revenuecat-webhook-token')
        .send({
          event: {
            id: eventId,
            type: 'EXPIRATION',
            app_user_id: userId,
            entitlement_ids: ['pro'],
            product_id: 'postdee_pro_monthly',
            event_timestamp_ms: eventTimestampMs
          }
        })
        .expect(200)
        .expect(({ body }) => {
          expect(body.ignored).toBe(true);
        });
    }

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(subscriptionResponse.body.subscription).toMatchObject({
      plan: 'PRO',
      status: 'ACTIVE'
    });
  });

  it('does not deactivate a subscription verified by another provider', async () => {
    const app = createApp({
      config: createRevenueCatConfig(),
      revenueCatSubscriberClient: {
        loadSubscriber: vi.fn().mockResolvedValue({
          observedAtMs: 1_784_044_800_005,
          activeEntitlements: []
        })
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
          id: 'event-google-play-expired-revenuecat',
          type: 'INITIAL_PURCHASE',
          app_user_id: 'seller-google-play',
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly',
          event_timestamp_ms: 1_784_044_800_000,
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
        observedAtMs: 1_784_044_800_006,
        activeEntitlements: [{ id: 'pro', productId: 'postdee_pro_monthly' }]
      })
      .mockResolvedValueOnce({
        observedAtMs: 1_784_044_800_007,
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
        observedAtMs: 1_784_044_800_008,
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
