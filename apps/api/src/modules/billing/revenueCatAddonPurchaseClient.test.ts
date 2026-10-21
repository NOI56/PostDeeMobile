import { describe, expect, it, vi } from 'vitest';
import { createRevenueCatAddonPurchaseClient } from './revenueCatAddonPurchaseClient.js';

const row = { id: 'rc-internal-id', store_transaction_id: 'store-txn', store: 'play_store',
  purchase_date: '2026-10-21T12:00:00.000Z', is_sandbox: true };
const input = { userId: 'owner/one', productId: 'postdee_post100_caption50', transactionId: 'store-txn' };
const payload = (rows: unknown[]) => ({ subscriber: { original_app_user_id: 'owner/one', non_subscriptions: { postdee_post100_caption50: rows } } });

describe('RevenueCat verified add-on lookup', () => {
  it('does not grant expiring monthly credits from an App Store purchase', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([{ ...row, store: 'app_store' }]) }) });
    expect(await client.findPurchase(input)).toBeNull();
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
  it('never treats the internal RevenueCat id as the canonical store transaction', async () => {
    const client = createRevenueCatAddonPurchaseClient({ apiKey: 'fixture', fetchImpl: vi.fn().mockResolvedValue({ ok: true,
      json: async () => payload([{ ...row, store_transaction_id: undefined }]) }) });
    expect(await client.findPurchase({ ...input, transactionId: row.id })).toBeNull();
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
