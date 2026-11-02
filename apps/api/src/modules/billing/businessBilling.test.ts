import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { readPaidPlanRequest } from './billingService.js';
import type { RevenueCatActiveEntitlement } from './revenueCatSubscriberClient.js';
import { selectRevenueCatPaidEntitlement } from './revenueCatSubscriptionPolicy.js';

const user = { id: 'business-billing-owner', provider: 'mock' as const };
const webhookToken = 'business-webhook-fixture';
const business = { id: 'business', productId: 'postdee_business_monthly', isSandbox: false,
  store: 'PLAY_STORE', expiresAt: '2100-01-01T00:00:00.000Z' };
const pro = { ...business, id: 'pro', productId: 'postdee_pro_monthly' };
const config = () => readServerConfig({ BILLING_PROVIDER: 'revenuecat',
  REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken });

const webhook = (app: ReturnType<typeof createApp>, event: Record<string, unknown>) =>
  request(app).post('/billing/revenuecat/webhooks').set('Authorization', `Bearer ${webhookToken}`)
    .send({ event: { id: 'business-event', app_user_id: user.id, event_timestamp_ms: 200,
      environment: 'PRODUCTION', store: 'PLAY_STORE', ...event } });

const planFor = async (app: ReturnType<typeof createApp>, userId = user.id) => {
  const status = await request(app).get('/billing/subscription').set('x-postdee-user-id', userId).expect(200);
  return status.body.subscription.plan;
};
const activateBusiness = async (app: ReturnType<typeof createApp>, userId = user.id) => {
  await planFor(app, userId);
  await webhook(app, { id: `business-initial-${userId}`, event_timestamp_ms: 100, app_user_id: userId,
    type: 'INITIAL_PURCHASE', product_id: business.productId, entitlement_ids: ['business'],
    expiration_at_ms: Date.parse(business.expiresAt) }).expect(200);
};

describe('Business subscription billing', () => {
  it('accepts Business as a paid plan without changing Basic request validation', () => {
    expect(readPaidPlanRequest({ plan: 'BUSINESS' })).toEqual({ ok: true, plan: 'BUSINESS' });
    expect(readPaidPlanRequest({ plan: 'BASIC' }).ok).toBe(false);
  });

  it('prefers Business over Pro and Starter regardless of provider array order', () => {
    expect(selectRevenueCatPaidEntitlement([pro, business], config())?.plan).toBe('BUSINESS');
    expect(selectRevenueCatPaidEntitlement([business, pro], config())?.plan).toBe('BUSINESS');
    expect(selectRevenueCatPaidEntitlement([{ ...business, isSandbox: true }, pro], config())?.plan).toBe('PRO');
  });

  it('keeps new Business readiness off by default and leaves the old readiness request valid', async () => {
    const app = createApp();
    await request(app).post('/billing/purchase-readiness').set('x-postdee-user-id', user.id)
      .send({ plan: 'BUSINESS' }).expect(409)
      .expect(({ body }) => expect(body.code).toBe('BUSINESS_PLAN_UNAVAILABLE'));
    await request(app).post('/billing/purchase-readiness').set('x-postdee-user-id', user.id)
      .send({}).expect(200);
    const status = await request(app).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    expect(status.body.subscription.businessPlanAvailable).toBe(false);
    const enabled = createApp({ config: readServerConfig({ BILLING_BUSINESS_ENABLED: 'true',
      BILLING_PROVIDER: 'revenuecat', REVENUECAT_REST_API_V1_KEY: 'fixture-key-no-network' }) });
    await request(enabled).post('/billing/purchase-readiness').set('x-postdee-user-id', user.id)
      .send({ plan: 'BUSINESS' }).expect(200)
      .expect({ status: 'ok', purchaseReady: true, preparationProtocol: 1, plan: 'BUSINESS' });
    const enabledStatus = await request(enabled).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    expect(enabledStatus.body.subscription.businessPlanAvailable).toBe(true);
  });

  it.each([
    ['revenuecat', false, false], ['revenuecat', true, true], ['store', false, false], ['store', true, false],
    ['mock', true, false]
  ] as const)('only offers Business with ready %s verification (ready=%s)', async (provider, ready, available) => {
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: provider, BILLING_BUSINESS_ENABLED: 'true',
      ...(provider === 'revenuecat' && ready ? { REVENUECAT_REST_API_V1_KEY: 'fixture-key-no-network' } : {}) }),
      ...(provider === 'store' && ready ? { storePurchaseVerifier: { verify: async () => { throw new Error('Not called by readiness'); } } } : {}) });
    const status = await request(app).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    expect(status.body.subscription.businessPlanAvailable).toBe(available);
    await request(app).post('/billing/purchase-readiness').set('x-postdee-user-id', user.id)
      .send({ plan: 'BUSINESS' }).expect(available ? 200 : 409);
  });

  it.each(['ANDROID', 'IOS'] as const)('allows a local mock %s Business fixture without offering real sales', async platform => {
    const app = createApp();
    const response = await request(app).post('/billing/store/verify').set('x-postdee-user-id', user.id)
      .send({ platform, productId: business.productId, purchaseToken: 'business-token', transactionId: 'business-tx' })
      .expect(200);
    expect(response.body.subscription.plan).toBe('BUSINESS');
    expect(response.body.purchase).toMatchObject(platform === 'ANDROID'
      ? { platform, productId: business.productId, purchaseToken: 'business-token' }
      : { platform, productId: business.productId, transactionId: 'business-tx' });
    const status = await request(app).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    expect(status.body.subscription).toMatchObject({ plan: 'BUSINESS', monthlyPostLimit: 400,
      baseMonthlyPostLimit: 400, monthlyAiCaptionLimit: 220, maxProfileLinks: 50,
      canSchedule: true, canUseAiCaptions: true, canUseAnalytics: false, businessPlanAvailable: false });
  });

  it.each(['store', 'revenuecat'] as const)('rejects direct native Business with %s before invoking a verifier', async provider => {
    const verify = vi.fn(async () => { throw new Error('Direct Business verification must not run'); });
    const app = createApp({ config: readServerConfig({ BILLING_PROVIDER: provider, BILLING_BUSINESS_ENABLED: 'true',
      REVENUECAT_REST_API_V1_KEY: 'fixture-key-no-network' }), storePurchaseVerifier: { verify } });
    for (const platform of ['ANDROID', 'IOS']) {
      await request(app).post('/billing/store/verify').set('x-postdee-user-id', user.id)
        .send({ platform, productId: business.productId, purchaseToken: 'business-token', transactionId: 'business-tx' })
        .expect(409).expect(({ body }) => expect(body.code).toBe('BUSINESS_DIRECT_STORE_UNSUPPORTED'));
    }
    expect(verify).not.toHaveBeenCalled();
    expect(await planFor(app)).toBe('BASIC');
  });

  it('keeps explicit local mock activation available without advertising a Business offer', async () => {
    const app = createApp({ config: readServerConfig({ BILLING_BUSINESS_ENABLED: 'true' }) });
    await request(app).post('/billing/mock-success').set('x-postdee-user-id', user.id)
      .send({ plan: 'BUSINESS' }).expect(200);
    const status = await request(app).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    expect(status.body.subscription).toMatchObject({ plan: 'BUSINESS', businessPlanAvailable: false });
  });

  it('restores the strongest verified entitlement while new Business sales are off, then falls back to Pro', async () => {
    let entitlements: RevenueCatActiveEntitlement[] = [pro, business];
    let observedAtMs = 300;
    const app = createApp({ config: config(), revenueCatSubscriberClient: {
      loadSubscriber: async () => ({ observedAtMs: ++observedAtMs, activeEntitlements: entitlements }) } });
    const restore = () => request(app).post('/billing/revenuecat/resync').set('x-postdee-user-id', user.id).send({});
    expect((await restore().expect(200)).body.plan).toBe('BUSINESS');
    entitlements = [pro];
    expect((await restore().expect(200)).body.plan).toBe('PRO');
    entitlements = [];
    expect((await restore().expect(200)).body.plan).toBe('BASIC');
  });

  it.each(['RENEWAL', 'EXPIRATION'])('does not let an old Pro %s remove verified Business access', async type => {
    const loadSubscriber = vi.fn(async () => ({ observedAtMs: 201, activeEntitlements: [pro, business] }));
    const app = createApp({ config: config(),
      revenueCatSubscriberClient: { loadSubscriber } });
    await activateBusiness(app);
    const response = await webhook(app, { type, product_id: pro.productId, entitlement_ids: ['pro'] }).expect(200);
    expect(response.body.subscription.plan).toBe('BUSINESS');
    expect(await planFor(app)).toBe('BUSINESS');
    expect(loadSubscriber).toHaveBeenCalledWith(user.id);
  });

  it('falls back from expired Business to remaining Pro and keeps a stale snapshot retryable', async () => {
    let observedAtMs = 199;
    const app = createApp({ config: config(),
      revenueCatSubscriberClient: { loadSubscriber: async () => ({ observedAtMs, activeEntitlements: [pro] }) } });
    await activateBusiness(app);
    const event = { type: 'EXPIRATION', product_id: business.productId, entitlement_ids: ['business'] };
    await webhook(app, event).expect(502);
    expect(await planFor(app)).toBe('BUSINESS');
    observedAtMs = 201;
    const response = await webhook(app, event).expect(200);
    expect(response.body.subscription.plan).toBe('PRO');
    expect(await planFor(app)).toBe('PRO');
  });

  it.each([
    ['CANCELLATION', [business], 'BUSINESS'],
    ['CANCELLATION', [pro], 'PRO'],
    ['REFUND', [], 'BASIC']
  ] as const)('reconciles Business %s against remaining provider access (%s)', async (type, entitlements, expected) => {
    const app = createApp({ config: config(), revenueCatSubscriberClient: {
      loadSubscriber: async () => ({ observedAtMs: 201, activeEntitlements: [...entitlements] }) } });
    await activateBusiness(app);
    await webhook(app, { type, product_id: business.productId, entitlement_ids: ['business'] }).expect(200);
    expect(await planFor(app)).toBe(expected);
  });

  it('grants a trusted initial Business event while the sales switch is off', async () => {
    const app = createApp({ config: config() });
    await request(app).get('/billing/subscription').set('x-postdee-user-id', user.id).expect(200);
    const response = await webhook(app, { type: 'INITIAL_PURCHASE', product_id: business.productId,
      entitlement_ids: ['pro', 'business'], expiration_at_ms: Date.parse(business.expiresAt) }).expect(200);
    expect(response.body.subscription.plan).toBe('BUSINESS');
  });

  it('reconciles transferred Business ownership using the strongest entitlement while sales are off', async () => {
    const source = { id: 'business-transfer-source', provider: 'mock' as const };
    const destination = { id: 'business-transfer-destination', provider: 'mock' as const };
    const app = createApp({ config: config(), revenueCatSubscriberClient: {
      loadSubscriber: async id => ({ observedAtMs: 201, activeEntitlements: id === destination.id ? [pro, business] : [] }) } });
    for (const owner of [source, destination]) {
      await request(app).get('/billing/subscription').set('x-postdee-user-id', owner.id).expect(200);
    }
    await activateBusiness(app, source.id);
    await webhook(app, { type: 'TRANSFER', transferred_from: [source.id], transferred_to: [destination.id] }).expect(200);
    expect(await planFor(app, source.id)).toBe('BASIC');
    expect(await planFor(app, destination.id)).toBe('BUSINESS');
  });
});
