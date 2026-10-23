import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryMonthlyAddonStore } from './monthlyAddonStore.js';
import { createInMemoryRealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import { createRevenueCatAddonPurchaseClient, RevenueCatAddonLookupError } from './revenueCatAddonPurchaseClient.js';

const userId = 'addon-paid-owner';
const purchase = { userId, productId: 'postdee_post100_caption50', transactionId: 'store-txn',
  store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T12:00:00.000Z' };
const setup = (enabled = true) => {
  const store = createInMemoryMonthlyAddonStore();
  const captionUsage = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore: store });
  const findPurchase = vi.fn().mockResolvedValue(purchase);
  const app = createApp({ config: readServerConfig({ BILLING_ADDONS_ENABLED: enabled ? 'true' : 'false',
    BILLING_PROVIDER: 'revenuecat', REVENUECAT_WEBHOOK_AUTH_TOKEN: 'fixture', REVENUECAT_REST_API_V1_KEY: 'fixture',
    REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX' }), monthlyAddonStore: store, realClipCaptionUsageStore: captionUsage, revenueCatAddonPurchaseClient: { findPurchase },
    now: () => new Date('2026-10-21T12:00:00.000Z') });
  const paid = () => request(app).post('/billing/revenuecat/webhooks').set('Authorization', 'Bearer fixture')
    .send({ event: { id: 'paid-plan', type: 'RENEWAL', app_user_id: userId, event_timestamp_ms: 1,
      environment: 'PRODUCTION', store: 'PLAY_STORE',
      product_id: 'postdee_pro_monthly', expiration_at_ms: new Date('2099-01-01').getTime() } });
  const bootstrap = () => request(app).get('/billing/subscription').set('x-postdee-user-id', userId);
  const confirm = (transactionId = 'store-txn', transactionIdKind?: string) => request(app).post('/billing/addons/confirm')
    .set('x-postdee-user-id', userId).send({ productId: purchase.productId, transactionId,
      ...(transactionIdKind ? { transactionIdKind } : {}) });
  return { app, store, captionUsage, findPurchase, paid, bootstrap, confirm };
};
describe('monthly add-on purchase routes', () => {
  it('resolves a RevenueCat history selector to a canonical receipt without granting it twice', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase(purchase);
    s.findPurchase.mockResolvedValue({ ...purchase, verifiedSelector: 'rc-history-id' });
    await s.confirm('rc-history-id', 'REVENUECAT').expect(200).expect(({ body }) => expect(body).toMatchObject({ transactionId: 'rc-history-id', transactionIdKind: 'REVENUECAT', confirmed: true }));
    await s.confirm('rc-history-id', 'REVENUECAT').expect(200);
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
    await s.store.revokePurchase(purchase);
    await s.confirm('rc-history-id', 'REVENUECAT').expect(409).expect(({ body }) => expect(body.code).toBe('ADDON_PURCHASE_REVOKED'));
  });
  it('does not guess a canonical ledger receipt from matching date metadata', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase(purchase);
    s.findPurchase.mockResolvedValue({ ...purchase, transactionId: undefined, verifiedSelector: 'rc-history-id' });
    await s.confirm('rc-history-id', 'REVENUECAT').expect(202).expect(({ body }) => expect(body.confirmed).toBe(false));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('does not revoke another canonical receipt using a refunded history row without its store id', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase(purchase);
    s.findPurchase.mockResolvedValue({ ...purchase, transactionId: undefined, verifiedSelector: 'refunded-rc-id', revoked: true });
    await s.confirm('refunded-rc-id', 'REVENUECAT').expect(409);
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('does not relink another account canonical receipt through a RevenueCat history selector', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase({ ...purchase, userId: 'another-owner' });
    s.findPurchase.mockResolvedValue({ ...purchase, verifiedSelector: 'rc-history-id' });
    await s.confirm('rc-history-id', 'REVENUECAT').expect(409).expect(({ body }) => expect(body.code).toBe('PURCHASE_ALREADY_LINKED'));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('never shortcuts a RevenueCat selector through a colliding canonical ledger id', async () => {
    const s = setup(); await s.bootstrap(); await s.store.applyPurchase({ ...purchase, transactionId: 'rc-history-id' });
    s.findPurchase.mockResolvedValue(null);
    await s.confirm('rc-history-id', 'REVENUECAT').expect(202);
    expect(s.findPurchase).toHaveBeenCalledWith({ userId, productId: purchase.productId, transactionId: 'rc-history-id', transactionIdKind: 'REVENUECAT' });
    await s.confirm('rc-history-id', 'STORE').expect(200);
  });
  it('rejects an unknown selector namespace before looking up the provider', async () => {
    const s = setup(); await s.bootstrap(); await s.confirm('store-txn', 'UNKNOWN').expect(400);
    expect(s.findPurchase).not.toHaveBeenCalled();
  });
  it('confirms the same nonexpiring App Store credits without changing the subscription', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce({ ...purchase, store: 'APP_STORE' });
    await s.confirm().expect(200).expect(({ body }) => expect(body).toMatchObject({ confirmed: true, policyVersion: 2, creditsExpire: false, expiresAt: null }));
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
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
  it('disables new checkout while keeping an already charged purchase verifiable', async () => {
    const s = setup(false); await s.bootstrap();
    const result = await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId).expect(200);
    expect(result.body).toMatchObject({ enabled: false, eligible: false, postUnits: 100, aiCaptions: 50, priceThb: 49 });
    await s.confirm().expect(200);
    expect(s.findPurchase).toHaveBeenCalledWith({ userId, productId: purchase.productId, transactionId: purchase.transactionId });
  });
  it('fails closed before verification when the provider configuration is missing', async () => {
    const findPurchase = vi.fn();
    const app = createApp({ config: readServerConfig({}), revenueCatAddonPurchaseClient: { findPurchase } });
    await request(app).post('/billing/addons/confirm').set('x-postdee-user-id', userId)
      .send({ productId: purchase.productId, transactionId: purchase.transactionId }).expect(403);
    expect(findPurchase).not.toHaveBeenCalled();
  });
  it('shows only Starter/Pro as eligible without changing the base plan', async () => {
    const s = setup(); await s.bootstrap();
    expect((await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId)).body.eligible).toBe(false);
    await s.paid().expect(200);
    expect((await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId)).body).toMatchObject({ eligible: true, purchasedPacks: 0,
      policyVersion: 2, creditsExpire: false, expiresAt: null, addonPostUnits: 0, addonAiCaptions: 0 });
  });
  it('reports an existing bank while purchases are disabled or the membership is Basic', async () => {
    const s = setup(false); await s.bootstrap(); await s.store.applyPurchase({ ...purchase, purchasedAt: '2025-01-01T00:00:00.000Z' });
    const result = await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId).expect(200);
    expect(result.body).toMatchObject({ enabled: false, eligible: false, purchasedPacks: 1, addonPostUnits: 100,
      addonAiCaptions: 50, policyVersion: 2, creditsExpire: false, expiresAt: null });
    expect(result.body).not.toHaveProperty('monthKey');
  });
  it('reports net lifetime balances and keeps refund debt until new credits or an exact release covers it', async () => {
    const s = setup(false); await s.bootstrap(); await s.store.applyPurchase(purchase);
    const reservation = await s.captionUsage.reserve({ userId, monthKey: '2026-10', limit: 0,
      includeMonthlyAddons: true, now: purchase.purchasedAt });
    expect(reservation.ok).toBe(true);
    const balance = async () => (await request(s.app).get('/billing/addons').set('x-postdee-user-id', userId).expect(200)).body;
    expect(await balance()).toMatchObject({ purchasedPacks: 1, addonPostUnits: 100, addonAiCaptions: 49 });
    await s.store.revokePurchase(purchase);
    expect(await balance()).toMatchObject({ purchasedPacks: 0, addonAiCaptions: 0 });
    await s.store.applyPurchase({ ...purchase, transactionId: 'new-pack-after-refund', purchasedAt: '2026-11-01T00:00:00.000Z' });
    expect(await balance()).toMatchObject({ purchasedPacks: 1, addonAiCaptions: 49 });
    if (reservation.ok) await s.captionUsage.release?.(reservation.record);
    expect(await balance()).toMatchObject({ purchasedPacks: 1, addonAiCaptions: 50 });
  });
  it('confirms only a server-verified transaction and retries without another grant', async () => {
    const s = setup(); await s.bootstrap(); await s.paid();
    await s.confirm().expect(200).expect(({ body }) => expect(body).toMatchObject({ confirmed: true, transactionId: 'store-txn', postUnits: 100, aiCaptions: 50 }));
    await s.confirm().expect(200);
    expect(await s.store.readCredits({ userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('keeps an unobserved transaction pending without granting credits', async () => {
    const s = setup(); await s.bootstrap(); s.findPurchase.mockResolvedValueOnce(null);
    await s.confirm().expect(202).expect(({ body }) => expect(body).toMatchObject({ confirmed: false, policyVersion: 2, creditsExpire: false, expiresAt: null }));
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
