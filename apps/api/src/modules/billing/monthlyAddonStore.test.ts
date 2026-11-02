import { describe, expect, it } from 'vitest';
import { createInMemoryMonthlyAddonStore, readMonthlyAddonWindow } from './monthlyAddonStore.js';

const purchase = { userId: 'paid-owner', productId: 'postdee_post100_caption50', transactionId: 'txn-one',
  store: 'PLAY_STORE', environment: 'SANDBOX', purchasedAt: '2026-10-21T12:00:00.000Z' };

describe('monthly add-on ledger', () => {
  it('matches an exact store when recovering a canonical receipt for a retired configured alias', async () => {
    const store = createInMemoryMonthlyAddonStore();
    const retired = { ...purchase, productId: 'retired-configured-alias', postUnitsGranted: 40, aiCaptionsGranted: 25 };
    await store.applyPurchase(retired);
    expect(await store.findPurchaseConfirmation({ ...retired, store: 'APP_STORE' })).toBeNull();
    expect(await store.findPurchaseConfirmation({ ...retired, store: 'PLAY_STORE' }))
      .toMatchObject({ postUnits: 40, aiCaptions: 25 });
    await store.applyPurchase({ ...retired, store: 'APP_STORE', postUnitsGranted: 90, aiCaptionsGranted: 50 });
    expect(await store.findPurchaseConfirmation({ ...retired, store: 'APP_STORE' }))
      .toMatchObject({ postUnits: 90, aiCaptions: 50 });
    expect(await store.findPurchaseConfirmation({ ...retired, store: 'PLAY_STORE' }))
      .toMatchObject({ postUnits: 40, aiCaptions: 25 });
  });
  it('sums immutable mixed-SKU grants while preserving historical and configured legacy packs', async () => {
    const store = createInMemoryMonthlyAddonStore();
    await store.applyPurchase(purchase);
    await store.applyPurchase({ ...purchase, productId: 'configured-legacy-alias', transactionId: 'legacy-alias' });
    for (const [productId, postUnitsGranted, aiCaptionsGranted] of [
      ['postdee_post40_caption25', 40, 25],
      ['postdee_post90_caption50', 90, 50],
      ['postdee_post190_caption100', 190, 100]
    ] as const) {
      await store.applyPurchase({ ...purchase, productId, transactionId: productId, postUnitsGranted, aiCaptionsGranted });
    }
    expect(await store.readCredits({ userId: purchase.userId, now: '2030-01-01T00:00:00.000Z' }))
      .toEqual({ postUnits: 520, aiCaptions: 275 });
    expect(await store.countPurchases({ userId: purchase.userId })).toBe(5);
    expect(await store.countPurchases({ userId: 'other-owner' })).toBe(0);
  });
  it('never replaces the first verified grant on duplicate confirmation or a refund redelivery', async () => {
    const store = createInMemoryMonthlyAddonStore();
    const small = { ...purchase, productId: 'postdee_post40_caption25', postUnitsGranted: 40, aiCaptionsGranted: 25 };
    expect(await store.applyPurchase(small)).toMatchObject({ postUnits: 40, aiCaptions: 25 });
    const changed = { ...small, postUnitsGranted: 190, aiCaptionsGranted: 100 };
    expect(await store.applyPurchase(changed)).toMatchObject({ applied: false, postUnits: 40, aiCaptions: 25 });
    expect(await store.findPurchaseConfirmation(small)).toMatchObject({ postUnits: 40, aiCaptions: 25 });
    await store.revokePurchase(changed);
    expect(await store.findPurchaseConfirmation(small)).toMatchObject({ revoked: true, postUnits: 40, aiCaptions: 25 });
    expect(await store.countPurchases({ userId: purchase.userId })).toBe(0);
    expect(await store.readCredits({ userId: purchase.userId, now: purchase.purchasedAt })).toEqual({ postUnits: 0, aiCaptions: 0 });
  });
  it('keeps a multi-SKU refund tombstone and its original grant when refund arrives first', async () => {
    const store = createInMemoryMonthlyAddonStore();
    const small = { ...purchase, productId: 'postdee_post40_caption25', postUnitsGranted: 40, aiCaptionsGranted: 25 };
    await store.revokePurchase(small);
    expect(await store.applyPurchase({ ...small, postUnitsGranted: 90, aiCaptionsGranted: 50 }))
      .toMatchObject({ applied: false, revoked: true, postUnits: 40, aiCaptions: 25 });
    expect(await store.countPurchases({ userId: purchase.userId })).toBe(0);
  });
  it.each([
    { postUnitsGranted: 40 }, { aiCaptionsGranted: 25 },
    { postUnitsGranted: -1, aiCaptionsGranted: 25 },
    { postUnitsGranted: 40.5, aiCaptionsGranted: 25 },
    { postUnitsGranted: 0, aiCaptionsGranted: 0 },
    { postUnitsGranted: Number.MAX_SAFE_INTEGER + 1, aiCaptionsGranted: 25 }
  ])('refuses a malformed new grant without recording the purchase (%j)', async grant => {
    const store = createInMemoryMonthlyAddonStore();
    await expect(store.applyPurchase({ ...purchase, ...grant })).rejects.toThrow('grant');
    expect(await store.countPurchases({ userId: purchase.userId })).toBe(0);
  });
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
