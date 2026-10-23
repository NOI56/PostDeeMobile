import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryMonthlyAddonStore } from './monthlyAddonStore.js';
import { createRevenueCatSubscriberClient } from './revenueCatSubscriberClient.js';
import { createPrismaMonthlyAddonRepository } from './prismaMonthlyAddonRepository.js';

const webhookToken = 'environment-regression-fixture';
const observedAtMs = Date.parse('2026-10-23T00:00:00.000Z');
const expiration = '2100-01-01T00:00:00.000Z';
const config = (environment = 'PRODUCTION') => readServerConfig({
  BILLING_PROVIDER: 'revenuecat',
  REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken,
  REVENUECAT_SUBSCRIPTION_ENVIRONMENT: environment
});

const subscriberClient = (entitlements: Record<string, unknown>, subscriptions: Record<string, unknown>) =>
  createRevenueCatSubscriberClient({ apiKey: 'synthetic-rest-key', fetchImpl: vi.fn().mockResolvedValue({
    ok: true, json: async () => ({ request_date_ms: observedAtMs, subscriber: { entitlements, subscriptions } })
  }) });

const restore = (app: ReturnType<typeof createApp>, userId = 'isolated-environment-owner') =>
  request(app).post('/billing/revenuecat/resync').set('x-postdee-user-id', userId).send({});

const webhook = (app: ReturnType<typeof createApp>, event: Record<string, unknown>) =>
  request(app).post('/billing/revenuecat/webhooks').set('Authorization', `Bearer ${webhookToken}`).send({ event });

describe('RevenueCat production purchase isolation', () => {
  it.each(['starter', 'pro'])('does not restore a sandbox Test Store %s subscription into production', async (plan) => {
    const productId = `postdee_${plan}_monthly`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        request_date_ms: observedAtMs,
        subscriber: {
          entitlements: { [plan]: { product_identifier: productId, expires_date: expiration } },
          subscriptions: { [productId]: { is_sandbox: true, store: 'test_store' } }
        }
      })
    });
    const app = createApp({
      config: config(),
      revenueCatSubscriberClient: createRevenueCatSubscriberClient({ apiKey: 'synthetic-rest-key', fetchImpl })
    });
    const userId = `sandbox-${plan}-owner`;

    const restored = await request(app).post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', userId).send({}).expect(200);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(restored.body.plan).toBe('BASIC');
    const subscription = await request(app).get('/billing/subscription')
      .set('x-postdee-user-id', userId).expect(200);
    expect(subscription.body.subscription.plan).toBe('BASIC');
  });

  it('acknowledges a sandbox subscription webhook without activating a production plan', async () => {
    const app = createApp({ config: config() });
    const userId = 'sandbox-webhook-owner';
    await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);

    const result = await request(app).post('/billing/revenuecat/webhooks')
      .set('Authorization', `Bearer ${webhookToken}`)
      .send({ event: {
        id: 'sandbox-purchase', type: 'INITIAL_PURCHASE', app_user_id: userId,
        event_timestamp_ms: observedAtMs, entitlement_ids: ['pro'], product_id: 'postdee_pro_monthly',
        environment: 'SANDBOX', store: 'TEST_STORE', expiration_at_ms: Date.parse(expiration)
      } }).expect(202);

    expect(result.body.ignored).toBe(true);
    const subscription = await request(app).get('/billing/subscription')
      .set('x-postdee-user-id', userId).expect(200);
    expect(subscription.body.subscription.plan).toBe('BASIC');
  });

  it('does not grant production add-on credits from the Test Store', async () => {
    const store = createInMemoryMonthlyAddonStore();

    await expect(store.applyPurchase({
      userId: 'test-store-addon-owner', productId: 'postdee_post100_caption50', transactionId: 'test-store-production-transaction',
      store: 'TEST_STORE', environment: 'PRODUCTION', purchasedAt: new Date(observedAtMs).toISOString()
    })).rejects.toThrow('not supported');
    expect(await store.readCredits({ userId: 'test-store-addon-owner', now: expiration }))
      .toEqual({ postUnits: 0, aiCaptions: 0 });
  });

  it.each([expiration, null])('requires verified purchase provenance for lifetime or recurring access (%s)', async (expiresDate) => {
    const app = createApp({ config: config(), revenueCatSubscriberClient: subscriberClient({
      pro: { product_identifier: 'postdee_pro_monthly', expires_date: expiresDate }
    }, { postdee_pro_monthly: { is_sandbox: true, store: 'test_store' } }) });
    expect((await restore(app).expect(200)).body.plan).toBe('BASIC');
  });

  it.each([
    {}, { store: 'play_store' }, { is_sandbox: false },
    { is_sandbox: 'false', store: 'play_store' }, { is_sandbox: false, store: 'unknown_store' },
    { is_sandbox: false, store: 'test_store' }
  ])('does not grant access from unverified production subscription metadata %#', async (subscription) => {
    const app = createApp({ config: config(), revenueCatSubscriberClient: subscriberClient({
      pro: { product_identifier: 'postdee_pro_monthly', expires_date: expiration }
    }, { postdee_pro_monthly: subscription }) });
    expect((await restore(app).expect(200)).body.plan).toBe('BASIC');
  });

  it.each([
    { environment: 'PRODUCTION', isSandbox: false, store: 'play_store' },
    { environment: 'PRODUCTION', isSandbox: false, store: 'app_store' },
    { environment: 'SANDBOX', isSandbox: true, store: 'test_store' }
  ])('retains valid subscription restore for $environment/$store', async ({ environment, isSandbox, store }) => {
    const app = createApp({ config: config(environment), revenueCatSubscriberClient: subscriberClient({
      pro: { product_identifier: 'postdee_pro_monthly', expires_date: expiration }
    }, { postdee_pro_monthly: { is_sandbox: isSandbox, store } }) });
    expect((await restore(app).expect(200)).body.plan).toBe('PRO');
  });

  it('selects a permitted Starter entitlement before an ineligible sandbox Pro entitlement', async () => {
    const app = createApp({ config: config(), revenueCatSubscriberClient: subscriberClient({
      pro: { product_identifier: 'postdee_pro_monthly', expires_date: expiration },
      starter: { product_identifier: 'postdee_starter_monthly', expires_date: expiration }
    }, {
      postdee_pro_monthly: { is_sandbox: true, store: 'test_store' },
      postdee_starter_monthly: { is_sandbox: false, store: 'play_store' }
    }) });
    expect((await restore(app).expect(200)).body.plan).toBe('STARTER');
  });

  it.each([
    { environment: undefined, store: 'PLAY_STORE' },
    { environment: 'PRODUCTION', store: undefined },
    { environment: 'PRODUCTION', store: 'TEST_STORE' },
    { environment: 'PRODUCTION', store: 'unknown_store' }
  ])('does not grant a production subscription webhook with unverified provenance %#', async (provenance) => {
    const app = createApp({ config: config() });
    const userId = 'unknown-webhook-provenance-owner';
    await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    await webhook(app, { id: 'unknown-provenance', type: 'RENEWAL', app_user_id: userId,
      entitlement_ids: ['pro'], product_id: 'postdee_pro_monthly', event_timestamp_ms: observedAtMs,
      ...provenance }).expect(202);
    const subscription = await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    expect(subscription.body.subscription.plan).toBe('BASIC');
  });

  it('ignores a sandbox expiration without consuming the production ordering cursor', async () => {
    const app = createApp({ config: config() });
    const userId = 'production-renewal-owner';
    await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    const event = { app_user_id: userId, entitlement_ids: ['pro'], product_id: 'postdee_pro_monthly',
      environment: 'PRODUCTION', store: 'PLAY_STORE', expiration_at_ms: Date.parse(expiration) };
    await webhook(app, { ...event, id: 'production-initial', type: 'INITIAL_PURCHASE', event_timestamp_ms: observedAtMs }).expect(200);
    await webhook(app, { ...event, id: 'sandbox-expiration', type: 'EXPIRATION', environment: 'SANDBOX',
      store: 'TEST_STORE', event_timestamp_ms: observedAtMs + 2 }).expect(202);
    const subscription = await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    expect(subscription.body.subscription.plan).toBe('PRO');
    const renewed = await webhook(app, { ...event, id: 'production-renewal', type: 'RENEWAL', event_timestamp_ms: observedAtMs + 1 }).expect(200);
    expect(renewed.body.ignored).toBe(false);
  });

  it('allows Test Store subscription events only in an explicitly sandbox environment', async () => {
    const app = createApp({ config: config('SANDBOX') });
    const userId = 'sandbox-test-subscription-owner';
    await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    await webhook(app, { id: 'sandbox-initial', type: 'INITIAL_PURCHASE', app_user_id: userId,
      product_id: 'postdee_starter_monthly', event_timestamp_ms: observedAtMs, environment: 'SANDBOX', store: 'TEST_STORE',
      expiration_at_ms: Date.parse(expiration) }).expect(200);
    const subscription = await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    expect(subscription.body.subscription.plan).toBe('STARTER');
  });

  it('rejects production Test Store grants before starting a Prisma transaction', async () => {
    const transaction = vi.fn();
    const store = createPrismaMonthlyAddonRepository({ prisma: { $transaction: transaction } as never });
    await expect(store.applyPurchase({ userId: 'prisma-production-owner', productId: 'postdee_post100_caption50',
      transactionId: 'invalid-production-test-store', environment: 'PRODUCTION', store: 'TEST_STORE',
      purchasedAt: new Date(observedAtMs).toISOString() })).rejects.toThrow('not supported');
    expect(transaction).not.toHaveBeenCalled();
  });

  it('keeps isolated sandbox Test Store add-on credits available', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await expect(store.applyPurchase({ userId: 'sandbox-addon-owner', productId: 'postdee_post100_caption50',
      transactionId: 'sandbox-test-store-transaction', environment: 'SANDBOX', store: 'TEST_STORE',
      purchasedAt: new Date(observedAtMs).toISOString() })).resolves.toMatchObject({ applied: true });
    expect(await store.readCredits({ userId: 'sandbox-addon-owner', now: expiration }))
      .toEqual({ postUnits: 100, aiCaptions: 50 });
  });

  it.each(['PRODUCTION', 'SANDBOX'])('isolates Test Store add-on confirmation in %s', async environment => {
    const store = createInMemoryMonthlyAddonStore();
    const purchase = { userId: 'addon-confirm-owner', productId: 'postdee_post100_caption50', transactionId: 'test-confirm-transaction',
      environment, store: 'TEST_STORE', purchasedAt: new Date(observedAtMs).toISOString() };
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken,
      REVENUECAT_REST_API_V1_KEY: 'synthetic-rest-key', REVENUECAT_ADDON_ENVIRONMENT: environment }),
      monthlyAddonStore: store, revenueCatAddonPurchaseClient: { findPurchase: vi.fn().mockResolvedValue(purchase) } });
    await request(app).post('/billing/addons/confirm').set('x-postdee-user-id', purchase.userId)
      .send({ productId: purchase.productId, transactionId: purchase.transactionId }).expect(environment === 'SANDBOX' ? 200 : 403);
    expect((await store.readCredits({ userId: purchase.userId, now: expiration })).postUnits).toBe(environment === 'SANDBOX' ? 100 : 0);
  });

  it.each(['PRODUCTION', 'SANDBOX'])('isolates Test Store add-on webhook grants in %s', async environment => {
    const store = createInMemoryMonthlyAddonStore();
    const userId = 'addon-webhook-owner';
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken,
      REVENUECAT_ADDON_ENVIRONMENT: environment }), monthlyAddonStore: store });
    await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
    await webhook(app, { app_user_id: userId, product_id: 'postdee_post100_caption50', id: 'test-addon-event',
      type: 'NON_RENEWING_PURCHASE', environment, store: 'TEST_STORE', event_timestamp_ms: observedAtMs,
      purchased_at_ms: observedAtMs, transaction_id: 'test-addon-webhook-transaction' }).expect(environment === 'SANDBOX' ? 200 : 202);
    expect((await store.readCredits({ userId, now: expiration })).postUnits).toBe(environment === 'SANDBOX' ? 100 : 0);
  });
});
