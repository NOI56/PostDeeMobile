import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryMonthlyAddonStore } from './monthlyAddonStore.js';
import type { RevenueCatAddonPurchaseClient } from './revenueCatAddonPurchaseClient.js';

const owner = 'multi-sku-owner';
const now = '2026-11-02T12:00:00.000Z';
const tiers = [
  { id: 'small', productId: 'postdee_post40_caption25', postUnits: 40, aiCaptions: 25, priceThb: 49 },
  { id: 'medium', productId: 'postdee_post90_caption50', postUnits: 90, aiCaptions: 50, priceThb: 99 },
  { id: 'large', productId: 'postdee_post190_caption100', postUnits: 190, aiCaptions: 100, priceThb: 199 }
];
const fixture = (tiersEnabled = false, legacyEnabled = true) => {
  const store = createInMemoryMonthlyAddonStore();
  const findPurchase = vi.fn<RevenueCatAddonPurchaseClient['findPurchase']>(async input => ({
    ...input, store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now
  }));
  const app = createApp({ config: readServerConfig({
    BILLING_PROVIDER: 'revenuecat', BILLING_ADDONS_ENABLED: String(legacyEnabled),
    BILLING_ADDON_TIERS_ENABLED: String(tiersEnabled),
    REVENUECAT_WEBHOOK_AUTH_TOKEN: 'multi-sku-fixture', REVENUECAT_REST_API_V1_KEY: 'fixture',
    REVENUECAT_ADDON_ENVIRONMENT: 'SANDBOX'
  }), monthlyAddonStore: store, revenueCatAddonPurchaseClient: { findPurchase }, now: () => new Date(now) });
  const bootstrap = () => request(app).get('/billing/subscription').set('x-postdee-user-id', owner);
  const catalog = () => request(app).get('/billing/addons').set('x-postdee-user-id', owner);
  const confirm = (productId: string, transactionId: string, extra: object = {}) => request(app)
    .post('/billing/addons/confirm').set('x-postdee-user-id', owner).send({ productId, transactionId, ...extra });
  const webhook = (productId: string, transactionId: string, type = 'NON_RENEWING_PURCHASE', extra: object = {}) => request(app)
    .post('/billing/revenuecat/webhooks').set('Authorization', 'Bearer multi-sku-fixture').send({ event: {
      id: `${type}-${transactionId}`, event_timestamp_ms: 1, type, app_user_id: owner,
      product_id: productId, transaction_id: transactionId, store: 'PLAY_STORE', environment: 'SANDBOX',
      purchased_at_ms: new Date(now).getTime(), ...extra
    } });
  const paid = () => request(app).post('/billing/revenuecat/webhooks')
    .set('Authorization', 'Bearer multi-sku-fixture').send({ event: {
      id: 'multi-paid', event_timestamp_ms: 1, type: 'RENEWAL', app_user_id: owner,
      product_id: 'postdee_pro_monthly', store: 'PLAY_STORE', environment: 'PRODUCTION',
      expiration_at_ms: new Date('2099-01-01').getTime()
    } });
  return { store, findPurchase, bootstrap, catalog, confirm, webhook, paid };
};

describe('multi-SKU add-on catalog and fulfillment', () => {
  it('keeps legacy catalog fields while new tier sales default off', async () => {
    const s = fixture(); await s.bootstrap(); await s.paid();
    const { body } = await s.catalog().expect(200);
    expect(body).toMatchObject({ catalogVersion: 3, productId: 'postdee_post100_caption50',
      postUnits: 100, aiCaptions: 50, priceThb: 49, enabled: true, eligible: true,
      policyVersion: 2, creditsExpire: false, expiresAt: null, purchasedPacks: 0 });
    expect(body.products).toEqual(tiers.map(tier => ({ ...tier, enabled: false, eligible: false })));
  });

  it('lists exactly the approved tiers and requires effective Starter/Pro eligibility', async () => {
    const s = fixture(true); await s.bootstrap();
    expect((await s.catalog()).body.products).toEqual(tiers.map(tier => ({ ...tier, enabled: true, eligible: false })));
    await s.paid();
    expect((await s.catalog()).body.products).toEqual(tiers.map(tier => ({ ...tier, enabled: true, eligible: true })));
  });

  it('the original sales gate also disables new tier checkout but never hides owned balances', async () => {
    const s = fixture(true, false); await s.bootstrap();
    await s.store.applyPurchase({ userId: owner, productId: 'postdee_post100_caption50', transactionId: 'old',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    const { body } = await s.catalog().expect(200);
    expect(body.products.every((product: { enabled: boolean; eligible: boolean }) => !product.enabled && !product.eligible)).toBe(true);
    expect(body).toMatchObject({ addonPostUnits: 100, addonAiCaptions: 50, purchasedPacks: 1 });
  });

  for (const tier of tiers) {
    it(`fulfills verified ${tier.id} receipts while sales are off, ignoring client credit claims`, async () => {
      const s = fixture(false, false); await s.bootstrap();
      await s.confirm(tier.productId, tier.id, { postUnits: 999999, aiCaptions: 999999 }).expect(200)
        .expect(({ body }) => expect(body).toMatchObject({ confirmed: true, postUnits: tier.postUnits,
          aiCaptions: tier.aiCaptions, policyVersion: 2, creditsExpire: false, expiresAt: null }));
      await s.confirm(tier.productId, tier.id).expect(200);
      expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: tier.postUnits, aiCaptions: tier.aiCaptions });
    });
  }

  it('counts mixed legacy/new purchases as transactions rather than dividing post credits by 100', async () => {
    const s = fixture(); await s.bootstrap();
    await s.confirm('postdee_post100_caption50', 'legacy').expect(200);
    for (const tier of tiers) await s.confirm(tier.productId, tier.id).expect(200);
    expect((await s.catalog()).body).toMatchObject({ purchasedPacks: 4, addonPostUnits: 420, addonAiCaptions: 225 });
  });

  it('allows two medium purchases with distinct receipts to grant 180/100 at the unchanged reference price', async () => {
    const s = fixture(true); await s.bootstrap();
    await s.confirm(tiers[1].productId, 'medium-one').expect(200);
    await s.confirm(tiers[1].productId, 'medium-two').expect(200);
    const { body } = await s.catalog().expect(200);
    expect(body).toMatchObject({ purchasedPacks: 2, addonPostUnits: 180, addonAiCaptions: 100 });
    expect(body.products.find((product: { id: string }) => product.id === 'medium').priceThb).toBe(99);
    expect(body.products.find((product: { id: string }) => product.id === 'large').priceThb).toBe(199);
  });

  it('returns the stored transaction grant instead of recomputing it from the current catalog', async () => {
    const s = fixture(); await s.bootstrap();
    await s.store.applyPurchase({ userId: owner, productId: tiers[0].productId, transactionId: 'historical-alias',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    await s.confirm(tiers[0].productId, 'historical-alias').expect(200)
      .expect(({ body }) => expect(body).toMatchObject({ productId: tiers[0].productId, postUnits: 100, aiCaptions: 50 }));
    expect(s.findPurchase).not.toHaveBeenCalled();
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });

  it('resolves a new-SKU RevenueCat history selector to its canonical grant once', async () => {
    const s = fixture(); await s.bootstrap();
    s.findPurchase.mockResolvedValue({ userId: owner, productId: tiers[1].productId,
      transactionId: 'canonical-medium', verifiedSelector: 'rc-medium',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now });
    await s.confirm(tiers[1].productId, 'rc-medium', { transactionIdKind: 'REVENUECAT' }).expect(200)
      .expect(({ body }) => expect(body).toMatchObject({ productId: tiers[1].productId,
        transactionId: 'rc-medium', transactionIdKind: 'REVENUECAT', postUnits: 90, aiCaptions: 50 }));
    await s.webhook(tiers[1].productId, 'canonical-medium').expect(200);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 90, aiCaptions: 50 });
    expect((await s.catalog()).body.purchasedPacks).toBe(1);
  });

  it('rejects reusing a canonical receipt for a different SKU and preserves its first grant', async () => {
    const s = fixture(); await s.bootstrap();
    await s.confirm(tiers[0].productId, 'one-receipt').expect(200);
    await s.confirm(tiers[2].productId, 'one-receipt').expect(409)
      .expect(({ body }) => expect(body.code).toBe('PURCHASE_ALREADY_LINKED'));
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 40, aiCaptions: 25 });
    expect((await s.catalog()).body.purchasedPacks).toBe(1);
  });

  it('confirm and webhook deliveries share one immutable grant and refunds retain their tombstone', async () => {
    const s = fixture(); await s.bootstrap();
    const tier = tiers[0];
    await Promise.all([s.webhook(tier.productId, 'race').expect(200), s.confirm(tier.productId, 'race').expect(200)]);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 40, aiCaptions: 25 });
    await s.webhook(tier.productId, 'race', 'CANCELLATION').expect(200);
    await s.confirm(tier.productId, 'race').expect(409).expect(({ body }) => expect(body.code).toBe('ADDON_PURCHASE_REVOKED'));
    await s.webhook(tier.productId, 'race').expect(200);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect((await s.catalog()).body.purchasedPacks).toBe(0);
  });

  it('refund-before-purchase cannot later become a new grant of the selected tier', async () => {
    const s = fixture(); await s.bootstrap();
    const tier = tiers[2];
    await s.webhook(tier.productId, 'refund-first', 'CANCELLATION').expect(200);
    await s.webhook(tier.productId, 'refund-first').expect(200);
    await s.confirm(tier.productId, 'refund-first').expect(409);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });

  it('returns the historical snapshot for an already recorded retired legacy product', async () => {
    const s = fixture(); await s.bootstrap();
    await s.store.applyPurchase({ userId: owner, productId: 'retired_custom_legacy', transactionId: 'retired',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    await s.confirm('retired_custom_legacy', 'retired').expect(200)
      .expect(({ body }) => expect(body).toMatchObject({ postUnits: 100, aiCaptions: 50 }));
    expect(s.findPurchase).not.toHaveBeenCalled();
  });

  it('recovers a retired legacy alias through an exact RevenueCat-to-canonical ledger proof', async () => {
    const s = fixture(); await s.bootstrap();
    const productId = 'retired_custom_legacy';
    await s.store.applyPurchase({ userId: owner, productId, transactionId: 'retired-canonical',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    s.findPurchase.mockResolvedValue({ userId: owner, productId, transactionId: 'retired-canonical',
      verifiedSelector: 'retired-rc', store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now });
    await s.confirm(productId, 'retired-rc', { transactionIdKind: 'REVENUECAT' }).expect(200)
      .expect(({ body }) => expect(body).toMatchObject({ productId, postUnits: 100, aiCaptions: 50 }));
    expect(await s.store.countPurchases({ userId: owner })).toBe(1);
  });

  it('never grants an unregistered SKU from RevenueCat history without an existing ledger grant', async () => {
    const s = fixture(); await s.bootstrap();
    s.findPurchase.mockResolvedValue({ userId: owner, productId: 'unknown-product', transactionId: 'unknown-canonical',
      verifiedSelector: 'unknown-rc', store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now });
    await s.confirm('unknown-product', 'unknown-rc', { transactionIdKind: 'REVENUECAT' }).expect(400);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });

  it('revokes an authenticated historical-alias webhook without accepting new purchases for that unknown alias', async () => {
    const s = fixture(); await s.bootstrap();
    const productId = 'retired_custom_legacy';
    await s.store.applyPurchase({ userId: owner, productId, transactionId: 'retired-refund',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    await s.webhook(productId, 'retired-refund', 'CANCELLATION').expect(200);
    await s.webhook(productId, 'new-unregistered-purchase').expect(202);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect(await s.store.findPurchaseConfirmation({ userId: owner, productId,
      transactionId: 'retired-refund', environment: 'SANDBOX', store: 'PLAY_STORE' }))
      .toMatchObject({ revoked: true, postUnits: 100, aiCaptions: 50 });
  });

  it.each(['CANCELLATION', 'REFUND'])('prefers exact historical add-on proof over a pro entitlement on %s', async type => {
    const s = fixture(); await s.bootstrap(); await s.paid();
    const productId = 'retired_custom_legacy';
    await s.store.applyPurchase({ userId: owner, productId, transactionId: 'pro-tagged-refund',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2025-01-01T00:00:00.000Z' });
    await s.webhook(productId, 'pro-tagged-refund', type, { entitlement_ids: ['pro'] }).expect(200);
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 0, aiCaptions: 0 });
    expect((await s.bootstrap()).body.subscription).toMatchObject({ plan: 'PRO', status: 'ACTIVE' });
  });

  it('leaves ordinary subscription cancellation routing intact when no historical add-on receipt matches', async () => {
    const s = fixture(); await s.bootstrap(); await s.paid();
    await s.store.applyPurchase({ userId: owner, productId: 'postdee_post100_caption50', transactionId: 'unrelated-addon',
      store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: now });
    await s.webhook('postdee_pro_monthly', 'subscription-cancel', 'CANCELLATION', {
      entitlement_ids: ['pro'], environment: 'PRODUCTION'
    }).expect(202).expect(({ body }) => expect(body.code).toBe('REVENUECAT_EVENT_NOT_ACTIONABLE'));
    expect(await s.store.readCredits({ userId: owner, now })).toEqual({ postUnits: 100, aiCaptions: 50 });
    expect((await s.bootstrap()).body.subscription).toMatchObject({ plan: 'PRO', status: 'ACTIVE' });
  });
});
