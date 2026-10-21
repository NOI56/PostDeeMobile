import { describe, expect, it } from 'vitest';
import { createInMemoryMonthlyAddonStore, readMonthlyAddonWindow } from './monthlyAddonStore.js';

const purchase = { userId: 'paid-owner', productId: 'postdee_post100_caption50', transactionId: 'txn-one',
  store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T12:00:00.000Z' };

describe('monthly add-on ledger', () => {
  it('grants the same nonexpiring credits on the App Store and preserves refunds', async () => {
    const store = createInMemoryMonthlyAddonStore();
    const apple = { ...purchase, store: 'APP_STORE' };
    expect(await store.applyPurchase(apple)).toMatchObject({ applied: true, expiresAt: null });
    expect(await store.readCredits({ userId: purchase.userId, now: '2030-01-01T00:00:00.000Z' })).toEqual({ postUnits: 100, aiCaptions: 50 });
    await store.revokePurchase(apple);
    expect(await store.findPurchaseConfirmation(apple)).toMatchObject({ revoked: true });
  });
  it('adds each verified transaction once, independently of delivery order', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await Promise.all(Array.from({ length: 8 }, () => store.applyPurchase(purchase)));
    await store.applyPurchase({ ...purchase, transactionId: 'txn-older', purchasedAt: '2026-10-02T00:00:00.000Z' });
    expect(await store.readCredits({ userId: purchase.userId, now: '2026-10-31T23:59:59.999Z' })).toEqual({ postUnits: 200, aiCaptions: 100 });
    expect(await store.readCredits({ userId: purchase.userId, now: '2026-11-01T00:00:00.000Z' })).toEqual({ postUnits: 200, aiCaptions: 100 });
    expect(await store.findPurchaseConfirmation(purchase)).toMatchObject({ expiresAt: null });
    expect(await store.readCredits({ userId: 'other-owner', now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('never relinks an existing transaction to another owner or product', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await store.applyPurchase(purchase);
    await expect(store.applyPurchase({ ...purchase, userId: 'other-owner' })).rejects.toThrow('already linked');
    await expect(store.applyPurchase({ ...purchase, productId: 'different-product' })).rejects.toThrow('already linked');
  });
  it('keeps a refund tombstone when refund arrives before purchase and ignores repeats', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await store.revokePurchase(purchase);
    await store.revokePurchase(purchase);
    expect(await store.applyPurchase(purchase)).toMatchObject({ applied: false, revoked: true });
    expect(await store.readCredits({ userId: purchase.userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('revokes only the exact purchase without changing other packs', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await store.applyPurchase(purchase);
    await store.applyPurchase({ ...purchase, transactionId: 'txn-two' });
    await store.revokePurchase(purchase);
    expect(await store.readCredits({ userId: purchase.userId, now: purchase.purchasedAt })).toEqual({ postUnits: 100, aiCaptions: 50 });
  });
  it('does not revive purchases or credit after account deletion', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await store.applyPurchase(purchase);
    await store.deleteAllForUser?.(purchase.userId);
    await expect(store.applyPurchase({ ...purchase, userId: 'other-owner' })).rejects.toThrow('already linked');
    expect(await store.readCredits({ userId: purchase.userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('uses the existing UTC calendar-month boundary', () => {
    expect(readMonthlyAddonWindow('2026-10-31T23:59:59.999Z')).toEqual({ monthKey: '2026-10',
      startsAt: '2026-10-01T00:00:00.000Z', expiresAt: '2026-11-01T00:00:00.000Z' });
  });
});
