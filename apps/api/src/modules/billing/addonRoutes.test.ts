import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryMonthlyAddonStore } from './monthlyAddonStore.js';
import { createRevenueCatAddonPurchaseClient, RevenueCatAddonLookupError } from './revenueCatAddonPurchaseClient.js';

const userId = 'addon-paid-owner';
const purchase = { userId, productId: 'postdee_post100_caption50', transactionId: 'store-txn',
  store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T12:00:00.000Z' };
const setup = (enabled = true) => {
  const store = createInMemoryMonthlyAddonStore();
  const findPurchase = vi.fn().mockResolvedValue(purchase);
  const app = createApp({ config: readServerConfig({ BILLING_ADDONS_ENABLED: enabled ? 'true' : 'false',
    BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: 'fixture', REVENUECAT_REST_API_V1_KEY: 'fixture',
    REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), monthlyAddonStore: store, revenueCatAddonPurchaseClient: { findPurchase },
    now: () => new Date('2026-10-21T12:00:00.000Z') });
  const paid = () => request(app).post('/billing/revenuecat/webhooks').set('Authorization', 'Bearer fixture')
    .send({ event: { id: 'paid-plan', type: 'RENEWAL', app_user_id: userId, event_timestamp_ms: 1,
      product_id: 'postdee_pro_monthly', expiration_at_ms: new Date('2099-01-01').getTime() } });
  const bootstrap = () => request(app).get('/billing/subscription').set('x-postdee-user-id', userId);
  const confirm = (transactionId = 'store-txn') => request(app).post('/billing/addons/confirm')
    .set('x-postdee-user-id', userId).send({ productId: purchase.productId, transactionId });
  return { app, store, findPurchase, paid, bootstrap, confirm };
};
describe('monthly add-on purchase routes', () => {
  it('refuses App Store monthly credits without granting or changing the subscription', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce({ ...purchase, store: 'APP_STORE' });
    await s.confirm().expect(403).expect(({ body }) => expect(body.code).toBe('ADDON_STORE_UNSUPPORTED'));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect((await request(s.app).get('/billing/subscription').set('x-postdee-user-id', userId)).body.subscription.plan).toBe('BASIC');
  });
  it('does not grant another canonical transaction returned by the verification provider', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce({ ...purchase, transactionId: 'other-canonical-id' });
    await s.confirm().expect(409).expect(({ body }) => expect(body.code).toBe('ADDON_PURCHASE_MISMATCH'));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('does not grant matching store history whose original RevenueCat owner belongs to another account', async () => {
    const store = createInMemoryMonthlyAddonStore();
    const purchaseClient = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => ({ subscriber: { original_app_user_id: 'other-original-owner', non_subscriptions: {
        [purchase.productId]: [{ id: 'rc-id', store_transaction_id: purchase.transactionId, store: 'play_store',
          purchase_date: purchase.purchasedAt, is_sandbox: true }] } } }) }) });
    const app = createApp({ config: readServerConfig({ BILLING_ADDONS_ENABLED: 'true', BILLING_PROVIDER: 'revenuecat',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: 'fixture', REVENUECAT_REST_API_V1_KEY: 'fixture', REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }),
      monthlyAddonStore: store, revenueCatAddonPurchaseClient: purchaseClient });
    await request(app).post('/billing/addons/confirm').set('x-postdee-user-id', userId)
      .send({ productId: purchase.productId, transactionId: purchase.transactionId }).expect(202);
    expect(await store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('is disabled by default and never contacts payment verification', async () => {
    const s = setup(false); await s.bootstrap();
    const result = await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId).expect(200);
    expect(result.body).toMatchObject({ enabled: false, eligible: false, postUnits: 100, aiCaptions: 50, priceThb: 49 });
    await s.confirm().expect(403); expect(s.findPurchase).not.toHaveBeenCalled();
  });
  it('shows only Starter/Pro as eligible without changing the base plan', async () => {
    const s = setup(); await s.bootstrap();
    expect((await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId)).body.eligible).toBe(false);
    await s.paid().expect(200);
    expect((await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId)).body).toMatchObject({ eligible: true, purchasedPacks: 0,
      monthKey: '2026-10', expiresAt: '2026-11-01T00:00:00.000Z' });
  });
  it('confirms only a server-verified transaction and retries without another grant', async () => {
    const s = setup(); await s.bootstrap(); await s.paid();
    await s.confirm().expect(200).expect(({ body }) => expect(body).toMatchObject({ confirmed: true, transactionId: 'store-txn', postUnits: 100, aiCaptions: 50 }));
    await s.confirm().expect(200);
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('keeps an unobserved transaction pending without granting credits', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce(null);
    await s.confirm().expect(202).expect(({ body }) => expect(body.confirmed).toBe(false));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('confirms a canonical webhook transaction when the REST history omits its store id', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase(purchase); s.findPurchase.mockResolvedValueOnce(null);
    await s.confirm().expect(200).expect(({ body }) => expect(body.confirmed).toBe(true));
    expect(s.findPurchase).not.toHaveBeenCalled();
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('returns revoked for a refunded webhook transaction without requiring REST history', async () => {
    const s = setup(); await s.bootstrap(); await s.store.revokePurchase(purchase); s.findPurchase.mockResolvedValueOnce(null);
    await s.confirm().expect(409).expect(({ body }) => expect(body.code).toBe('ADDON_PURCHASE_REVOKED'));
    expect(s.findPurchase).not.toHaveBeenCalled();
  });
  it('keeps the original purchase pending when RevenueCat is temporarily unavailable', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockRejectedValueOnce(new RevenueCatAddonLookupError());
    await s.confirm().expect(202).expect(({ body }) => expect(body).toMatchObject({ confirmed: false, transactionId: 'store-txn' }));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('rejects another owner or store environment returned by the provider', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce({ ...purchase, userId: 'another-owner' });
    await s.confirm().expect(409);
    s.findPurchase.mockResolvedValueOnce({ ...purchase, environment: 'PRODUCTION' });
    await s.confirm().expect(409);
  });
  it('revokes a refunded transaction and never reports confirmation', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce({ ...purchase, revoked: true });
    await s.confirm().expect(409);
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
});
