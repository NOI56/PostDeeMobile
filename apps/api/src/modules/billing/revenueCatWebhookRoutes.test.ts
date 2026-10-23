import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createOwnerMutationLock } from '../account/ownerMutationLock.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { registerRevenueCatWebhookRoutes } from './revenueCatWebhookRoutes.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';

const revenueCatToken = 'revenuecat-webhook-token';

const createRevenueCatApp = () =>
  createApp({
    config: readServerConfig({
      BILLING_PROVIDER: 'revenuecat',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken,
      REVENUECAT_STARTER_ENTITLEMENT_ID: 'starter',
      REVENUECAT_PRO_ENTITLEMENT_ID: 'pro',
      REVENUECAT_STARTER_PRODUCT_ID: 'postdee_starter_monthly',
      REVENUECAT_PRO_PRODUCT_ID: 'postdee_pro_monthly'
    })
  });

const postRevenueCatWebhookRaw = (app: ReturnType<typeof createRevenueCatApp>, body: string | object | undefined) =>
  request(app)
    .post('/billing/revenuecat/webhooks')
    .set('Authorization', `Bearer ${revenueCatToken}`)
    .send(body);

let revenueCatEventSequence = 0;

const postRevenueCatWebhook = (app: ReturnType<typeof createRevenueCatApp>, body: string | object | undefined) => {
  if (
    typeof body !== 'object' ||
    body === null ||
    !('event' in body) ||
    typeof body.event !== 'object' ||
    body.event === null
  ) {
    return postRevenueCatWebhookRaw(app, body);
  }

  revenueCatEventSequence += 1;
  return postRevenueCatWebhookRaw(app, {
    ...body,
    event: {
      id: `test-revenuecat-event-${revenueCatEventSequence}`,
      event_timestamp_ms: 1_784_044_800_000 + revenueCatEventSequence,
      environment: 'PRODUCTION',
      store: 'PLAY_STORE',
      ...body.event
    }
  });
};

const createKnownUser = (app: ReturnType<typeof createRevenueCatApp>, userId: string) =>
  request(app)
    .get('/billing/subscription')
    .set('x-postdee-user-id', userId)
    .expect(200);

describe('RevenueCat webhooks', () => {
  it('settles an authenticated receipt while new checkout is disabled', async () => {
    const { createInMemoryMonthlyAddonStore } = await import('./monthlyAddonStore.js');
    const store = createInMemoryMonthlyAddonStore();
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', BILLING_ADDONS_ENABLED: 'false',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken, REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), monthlyAddonStore: store });
    await createKnownUser(app, 'checkout-disabled-owner');
    await postRevenueCatWebhook(app, { event: { type: 'NON_RENEWING_PURCHASE', app_user_id: 'checkout-disabled-owner',
      product_id: 'postdee_post100_caption50', store: 'PLAY_STORE', environment: 'SANDBOX',
      transaction_id: 'disabled-checkout-receipt', purchased_at_ms: new Date('2026-10-21T00:00:00.000Z').getTime() } }).expect(200);
    expect(await store.readCredits({ userId: 'checkout-disabled-owner', now: '2027-01-01T00:00:00.000Z' })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('grants a nonexpiring App Store add-on and records its refund without upgrading the plan', async () => {
    const { createInMemoryMonthlyAddonStore } = await import('./monthlyAddonStore.js');
    const store = createInMemoryMonthlyAddonStore();
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', BILLING_ADDONS_ENABLED: 'true',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken, REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), monthlyAddonStore: store });
    await createKnownUser(app, 'apple-addon-owner');
    const event = { app_user_id: 'apple-addon-owner', product_id: 'postdee_post100_caption50', store: 'APP_STORE',
      environment: 'SANDBOX', transaction_id: 'apple-addon-txn', purchased_at_ms: new Date('2026-10-21T00:00:00.000Z').getTime() };
    await postRevenueCatWebhook(app, { event: { ...event, type: 'NON_RENEWING_PURCHASE' } }).expect(200);
    expect(await store.readCredits({ userId: 'apple-addon-owner', now: '2028-10-21T00:00:00.000Z' })).toEqual({ postUnits: 100, aiCaptions: 50 });
    expect((await request(app).get('/billing/subscription').set('x-postdee-user-id', 'apple-addon-owner')).body.subscription.plan).toBe('BASIC');
    await postRevenueCatWebhook(app, { event: { ...event, type: 'CANCELLATION' } }).expect(200);
    expect(await store.findPurchaseConfirmation({ userId: 'apple-addon-owner', productId: event.product_id,
      transactionId: event.transaction_id, environment: event.environment })).toMatchObject({ revoked: true });
  });
  it('credits add-on transactions once and preserves a refund-before-purchase tombstone without changing the plan', async () => {
    const { createInMemoryMonthlyAddonStore } = await import('./monthlyAddonStore.js');
    const store = createInMemoryMonthlyAddonStore();
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', BILLING_ADDONS_ENABLED: 'true',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken, REVENUECAT_REST_API_V1_KEY: 'fixture', REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), monthlyAddonStore: store });
    await createKnownUser(app, 'addon-owner');
    const event = { app_user_id: 'addon-owner', product_id: 'postdee_post100_caption50', environment: 'SANDBOX',
      store: 'PLAY_STORE', transaction_id: 'addon-store-txn', purchased_at_ms: new Date('2026-10-21T00:00:00.000Z').getTime() };
    await postRevenueCatWebhook(app, { event: { ...event, type: 'CANCELLATION' } }).expect(200);
    await postRevenueCatWebhook(app, { event: { ...event, type: 'NON_RENEWING_PURCHASE' } }).expect(200);
    await postRevenueCatWebhook(app, { event: { ...event, transaction_id: 'addon-two', type: 'NON_RENEWING_PURCHASE' } }).expect(200);
    await postRevenueCatWebhook(app, { event: { ...event, transaction_id: 'addon-two', type: 'NON_RENEWING_PURCHASE' } }).expect(200);
    expect(await store.readCredits({ userId: 'addon-owner', now: '2026-10-21T00:00:00.000Z' })).toEqual({ postUnits: 100, aiCaptions: 50 });
    expect((await request(app).get('/billing/subscription').set('x-postdee-user-id', 'addon-owner')).body.subscription.plan).toBe('BASIC');
  });
  it('rejects malformed add-on proof and ignores another store environment', async () => {
    const { createInMemoryMonthlyAddonStore } = await import('./monthlyAddonStore.js');
    const store = createInMemoryMonthlyAddonStore();
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', BILLING_ADDONS_ENABLED: 'true',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken, REVENUECAT_ADDON_ENVIRONMENT: 'PRODUCTION' }), monthlyAddonStore: store });
    await createKnownUser(app, 'addon-owner');
    const event = { type: 'NON_RENEWING_PURCHASE', app_user_id: 'addon-owner', product_id: 'postdee_post100_caption50',
      store: 'PLAY_STORE', environment: 'PRODUCTION', transaction_id: 'proof', purchased_at_ms: 100 };
    await postRevenueCatWebhook(app, { event: { ...event, transaction_id: undefined } }).expect(400);
    await postRevenueCatWebhook(app, { event: { ...event, environment: 'SANDBOX' } }).expect(202);
  });
  it('acknowledges a final-write tombstone even when the process coordinator still sees an active owner', async () => {
    const app = express();
    const router = express.Router();
    const owners = createInMemoryUploadSessionStore();
    const userStore = createUserStore();
    await userStore.ensure({ id: 'owner-remote-deleted', provider: 'firebase' });
    const subscriptionStore = createSubscriptionStore({ runWithActiveOwner: owners.runWithActiveOwner });
    await owners.beginOwnerDeletion('owner-remote-deleted');
    app.use(express.json());
    registerRevenueCatWebhookRoutes({ router, userStore, subscriptionStore,
      config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken }) });
    app.use(router);
    await request(app).post('/billing/revenuecat/webhooks').set('Authorization', `Bearer ${revenueCatToken}`)
      .send({ event: { id: 'event-remote-deleted', event_timestamp_ms: 1, type: 'RENEWAL',
        app_user_id: 'owner-remote-deleted', entitlement_ids: ['pro'], product_id: 'postdee_pro_monthly',
        environment: 'PRODUCTION', store: 'PLAY_STORE' } })
      .expect(202).expect(({ body }) => { expect(body.code).toBe('REVENUECAT_USER_NOT_FOUND'); });
    await expect(subscriptionStore.getPlan({ id: 'owner-remote-deleted', provider: 'firebase' })).resolves.toBe('BASIC');
  });

  it('acknowledges an actionable event without mutating after account deletion seals the owner', async () => {
    const app = express();
    const router = express.Router();
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore();
    const ownerMutationLock = createOwnerMutationLock();
    const userId = 'seller-revenuecat-deleting-race';
    await userStore.ensure({ id: userId, provider: 'firebase' });
    ownerMutationLock.markDeleting(userId);
    app.use(express.json());
    registerRevenueCatWebhookRoutes({
      router,
      config: readServerConfig({
        BILLING_PROVIDER: 'revenuecat',
        REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken,
        REVENUECAT_STARTER_ENTITLEMENT_ID: 'starter',
        REVENUECAT_PRO_ENTITLEMENT_ID: 'pro',
        REVENUECAT_STARTER_PRODUCT_ID: 'postdee_starter_monthly',
        REVENUECAT_PRO_PRODUCT_ID: 'postdee_pro_monthly'
      }),
      userStore,
      subscriptionStore,
      ownerMutationLock
    });
    app.use(router);

    await postRevenueCatWebhook(app as ReturnType<typeof createRevenueCatApp>, {
      event: {
        type: 'RENEWAL',
        app_user_id: userId,
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    })
      .expect(202)
      .expect(({ body }) => {
        expect(body).toMatchObject({
          status: 'ok',
          ignored: true,
          code: 'REVENUECAT_USER_NOT_FOUND'
        });
      });
    await expect(
      subscriptionStore.getPlan({ id: userId, provider: 'firebase' })
    ).resolves.toBe('BASIC');
  });

  it('rejects webhook requests without the configured bearer token', async () => {
    const app = createRevenueCatApp();

    const response = await request(app)
      .post('/billing/revenuecat/webhooks')
      .send({
        event: {
          type: 'INITIAL_PURCHASE',
          app_user_id: 'seller-revenuecat-auth',
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      })
      .expect(401);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_WEBHOOK_UNAUTHORIZED'
    });
  });

  it('activates Starter for a RevenueCat Starter entitlement event', async () => {
    const app = createRevenueCatApp();
    await createKnownUser(app, 'seller-revenuecat-starter');

    const activationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-starter',
        entitlement_ids: ['starter'],
        product_id: 'postdee_starter_monthly',
        expiration_at_ms: 4102444800000
      }
    }).expect(200);

    expect(activationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-starter',
      plan: 'STARTER',
      status: 'ACTIVE',
      billingSubscriptionId: 'revenuecat:seller-revenuecat-starter'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-revenuecat-starter')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-starter',
      plan: 'STARTER',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: false
    });
  });

  it('activates Pro for a RevenueCat Pro product event', async () => {
    const app = createRevenueCatApp();
    await createKnownUser(app, 'seller-revenuecat-pro');

    const activationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'RENEWAL',
        app_user_id: 'seller-revenuecat-pro',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        expiration_at_ms: 4102444800000
      }
    }).expect(200);

    expect(activationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-pro',
      plan: 'PRO',
      status: 'ACTIVE',
      currentPeriodEnd: '2100-01-01T00:00:00.000Z'
    });
  });

  it('clears a stale period end for lifetime RevenueCat access', async () => {
    const app = createRevenueCatApp();
    await createKnownUser(app, 'seller-revenuecat-lifetime');

    await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-lifetime',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        expiration_at_ms: 1
      }
    }).expect(200);

    const lifetimeResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'NON_RENEWING_PURCHASE',
        app_user_id: 'seller-revenuecat-lifetime',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        expiration_at_ms: null
      }
    }).expect(200);

    expect(lifetimeResponse.body.subscription.currentPeriodEnd).toBeUndefined();
    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-revenuecat-lifetime')
      .expect(200);
    expect(subscriptionResponse.body.subscription.plan).toBe('PRO');
  });

  it('marks an existing RevenueCat subscription as canceled after expiration', async () => {
    const app = createRevenueCatApp();
    await createKnownUser(app, 'seller-revenuecat-expired');

    await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-expired',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(200);

    const expirationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'EXPIRATION',
        app_user_id: 'seller-revenuecat-expired',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(200);

    expect(expirationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-expired',
      plan: 'PRO',
      status: 'CANCELED'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-revenuecat-expired')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-expired',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('ignores an older expiration that arrives after a newer renewal', async () => {
    const app = createRevenueCatApp();
    const userId = 'seller-revenuecat-out-of-order';
    await createKnownUser(app, userId);

    await postRevenueCatWebhook(app, {
      event: {
        id: 'event-renewal-newer',
        type: 'RENEWAL',
        app_user_id: userId,
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        event_timestamp_ms: 1_784_044_800_000,
        expiration_at_ms: 4_102_444_800_000
      }
    }).expect(200);

    const staleResponse = await postRevenueCatWebhook(app, {
      event: {
        id: 'event-expiration-older',
        type: 'EXPIRATION',
        app_user_id: userId,
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        event_timestamp_ms: 1_784_044_799_000
      }
    }).expect(200);

    expect(staleResponse.body).toMatchObject({
      status: 'ok',
      ignored: true,
      eventType: 'EXPIRATION'
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

  it('idempotently ignores a repeated RevenueCat event', async () => {
    const app = createRevenueCatApp();
    const userId = 'seller-revenuecat-duplicate';
    await createKnownUser(app, userId);
    const event = {
      id: 'event-renewal-duplicate',
      type: 'RENEWAL',
      app_user_id: userId,
      entitlement_ids: ['pro'],
      product_id: 'postdee_pro_monthly',
      event_timestamp_ms: 1_784_044_800_000
    };

    await postRevenueCatWebhook(app, { event }).expect(200);
    const duplicateResponse = await postRevenueCatWebhook(app, { event }).expect(200);

    expect(duplicateResponse.body).toMatchObject({
      status: 'ok',
      ignored: true,
      eventType: 'RENEWAL'
    });
  });

  it('does not revoke entitlements for non-expiring RevenueCat lifecycle events', async () => {
    const app = createRevenueCatApp();

    for (const eventType of ['CANCELLATION', 'SUBSCRIPTION_PAUSED', 'BILLING_ISSUE']) {
      const userId = `seller-revenuecat-${eventType.toLowerCase().replace(/_/g, '-')}`;
      await createKnownUser(app, userId);

      await postRevenueCatWebhook(app, {
        event: {
          type: 'INITIAL_PURCHASE',
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      }).expect(200);

      const lifecycleResponse = await postRevenueCatWebhook(app, {
        event: {
          type: eventType,
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      }).expect(202);

      expect(lifecycleResponse.body).toMatchObject({
        status: 'ok',
        ignored: true,
        code: 'REVENUECAT_EVENT_NOT_ACTIONABLE'
      });

      const subscriptionResponse = await request(app)
        .get('/billing/subscription')
        .set('x-postdee-user-id', userId)
        .expect(200);

      expect(subscriptionResponse.body.subscription).toMatchObject({
        userId,
        plan: 'PRO',
        status: 'ACTIVE'
      });
    }
  });

  it('acknowledges unsupported RevenueCat products without changing entitlements', async () => {
    const app = createRevenueCatApp();

    const response = await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-unknown',
        entitlement_ids: ['unknown'],
        product_id: 'unknown_product'
      }
    }).expect(202);

    expect(response.body).toMatchObject({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_PRODUCT_NOT_MAPPED'
    });
  });

  it('ignores active events for users that do not exist instead of recreating them', async () => {
    const app = createRevenueCatApp();

    const response = await postRevenueCatWebhook(app, {
      event: {
        type: 'RENEWAL',
        app_user_id: 'seller-revenuecat-deleted',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(202);

    expect(response.body).toMatchObject({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_USER_NOT_FOUND'
    });
  });

  it('does not recreate a user from a late active event after account deletion', async () => {
    const app = createRevenueCatApp();
    const userId = 'seller-revenuecat-deleted-late-event';
    await createKnownUser(app, userId);
    await request(app).delete('/account').set('x-postdee-user-id', userId).expect(200);

    const response = await postRevenueCatWebhook(app, {
      event: {
        type: 'RENEWAL',
        app_user_id: userId,
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(202);

    expect(response.body).toMatchObject({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_USER_NOT_FOUND'
    });
  });

  it('rejects actionable RevenueCat events without valid ordering metadata', async () => {
    const app = createRevenueCatApp();

    await postRevenueCatWebhookRaw(app, {
      event: {
        id: 'event-missing-timestamp',
        type: 'RENEWAL',
        app_user_id: 'seller-revenuecat-missing-timestamp',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    })
      .expect(400)
      .expect(({ body }) => {
        expect(body.code).toBe('REVENUECAT_WEBHOOK_INVALID');
      });
  });

  it('rejects malformed RevenueCat webhook payloads', async () => {
    const app = createRevenueCatApp();

    const response = await postRevenueCatWebhook(app, {}).expect(400);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_WEBHOOK_INVALID'
    });
  });
});
