import { describe, expect, it, vi } from 'vitest';
import { createRevenueCatAddonPurchaseClient } from './revenueCatAddonPurchaseClient.js';

const row = { id: 'rc-internal-id', store_transaction_id: 'store-txn', store: 'play_store',
  purchase_date: '2026-10-21T12:00:00.000Z', is_sandbox: true };
const input = { userId: 'owner/one', productId: 'postdee_post100_caption50', transactionId: 'store-txn' };
const payload = (rows: unknown[]) => ({ subscriber: { original_app_user_id: 'owner/one', non_subscriptions: { postdee_post100_caption50: rows } } });

describe('RevenueCat verified add-on lookup', () => {
  it('verifies nonexpiring credits from an App Store purchase', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([{ ...row, store: 'app_store' }]) }) });
    expect(await client.findPurchase(input)).toMatchObject({ store: 'APP_STORE', transactionId: input.transactionId });
  });
  it.each(['another-owner', '$RCAnonymousID:fixture', undefined])('keeps original owner %s pending rather than granting alias history', async originalOwner => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => ({ subscriber: { ...payload([row]).subscriber, original_app_user_id: originalOwner } }) }) });
    expect(await client.findPurchase(input)).toBeNull();
  });
  it('loads the authenticated owner and matches the store transaction rather than an entitlement', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, json: async () => payload([row]) });
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl });
    expect(await client.findPurchase(input)).toEqual({ userId: input.userId, productId: input.productId,
      transactionId: 'store-txn', store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: row.purchase_date });
    expect(fetchImpl.mock.calls[0]?.[0]).toBe('https://api.revenuecat.com/v1/subscribers/owner%2Fone');
  });
  it('returns pending for a different transaction or missing non-subscription history', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true, json: async () => payload([row]) }) });
    expect(await client.findPurchase({ ...input, transactionId: 'client-forged' })).toBeNull();
  });
  it('returns only verified details for a RevenueCat selector without a canonical store transaction', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([{ ...row, store_transaction_id: undefined }]) }) });
    expect(await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' })).toMatchObject({ verifiedSelector: row.id,
      purchasedAt: row.purchase_date, store: 'PLAY_STORE' });
    expect((await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' }))?.transactionId).toBeUndefined();
  });
  it('resolves a history selector to its verified canonical store transaction', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([row]) }) });
    expect(await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' })).toMatchObject({ transactionId: 'store-txn', verifiedSelector: row.id });
  });
  it('keeps store and RevenueCat selector namespaces separate even when their values collide', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([row, { ...row, id: 'other-rc-id', store_transaction_id: row.id }]) }) });
    expect(await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'STORE' })).toMatchObject({ transactionId: row.id });
    expect(await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' })).toMatchObject({ transactionId: 'store-txn', verifiedSelector: row.id });
  });
  it('fails closed when duplicate rows share the same RevenueCat selector', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([row, { ...row, store_transaction_id: 'different-store-txn' }]) }) });
    await expect(client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' })).rejects.toThrow('ambiguous');
  });
  it('does not invent a canonical id from matching purchase metadata', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([{ ...row, store_transaction_id: undefined }, { ...row, id: 'second-rc-id', store_transaction_id: undefined }]) }) });
    expect((await client.findPurchase({ ...input, transactionId: row.id, transactionIdKind: 'REVENUECAT' }))?.transactionId).toBeUndefined();
  });
  it.each([{ ...row, purchase_date: 'bad-date' }, { ...row, is_sandbox: undefined }, { ...row, store: 'unknown-store' }])('rejects unverifiable store metadata %#', async (value) => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true, json: async () => payload([value]) }) });
    await expect(client.findPurchase(input)).rejects.toThrow();
  });
  it('preserves refund metadata for reconciliation', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true, json: async () => payload([{ ...row, refunded_at: '2026-10-22T00:00:00.000Z' }]) }) });
    expect(await client.findPurchase(input)).toMatchObject({ revoked: true });
  });
});
