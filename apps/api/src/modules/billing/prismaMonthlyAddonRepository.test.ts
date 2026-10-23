import { describe, expect, it, vi } from 'vitest';
import { createPrismaMonthlyAddonRepository, readPrismaMonthlyAddonCredits,
  type PrismaMonthlyAddonClient } from './prismaMonthlyAddonRepository.js';
import { monthlyAddonOwnerHash, monthlyAddonPurchaseKey } from './monthlyAddonStore.js';

const input = { userId: 'owner', productId: 'postdee_post100_caption50', transactionId: 'one',
  store: 'PLAY_STORE', environment: 'PRODUCTION', purchasedAt: '2026-10-21T00:00:00.000Z' };
const fixture = () => {
  const tx = { managedUploadOwner: { upsert: vi.fn().mockResolvedValue({ status: 'ACTIVE' }), updateMany: vi.fn().mockResolvedValue({ count: 1 }) },
    monthlyAddonPurchase: { findMany: vi.fn().mockResolvedValue([{ id: 'a' }, { id: 'b' }]), findUnique: vi.fn().mockResolvedValue(null),
      create: vi.fn().mockResolvedValue({}), update: vi.fn().mockResolvedValue({}) } };
  const $transaction = vi.fn(async (operation: (client: typeof tx) => unknown) => operation(tx));
  const prisma = { ...tx, $transaction } as unknown as PrismaMonthlyAddonClient;
  return { tx, $transaction, store: createPrismaMonthlyAddonRepository({ prisma }) };
};
describe('Prisma monthly add-on ledger', () => {
  it('keeps isolated sandbox Test Store grants and production Test Store refund tombstones', async () => {
    const { store, tx } = fixture();
    const sandbox = { ...input, store: 'TEST_STORE', environment: 'SANDBOX' };
    await expect(store.applyPurchase(sandbox)).resolves.toMatchObject({ applied: true });
    expect(tx.monthlyAddonPurchase.create).toHaveBeenCalledWith({ data: expect.objectContaining({ store: 'TEST_STORE', environment: 'SANDBOX', revoked: false }) });
    await store.revokePurchase({ ...sandbox, environment: 'PRODUCTION' });
    expect(tx.monthlyAddonPurchase.create).toHaveBeenLastCalledWith({ data: expect.objectContaining({ store: 'TEST_STORE', environment: 'PRODUCTION', revoked: true }) });
  });
  it('retries an exhausted inner serialization race at the bounded purchase-ledger boundary', async () => {
    const { store, tx, $transaction } = fixture();
    for (let attempt = 0; attempt < 6; attempt += 1) $transaction.mockRejectedValueOnce({ code: 'P2034' });
    await expect(store.applyPurchase(input)).resolves.toMatchObject({ applied: true });
    expect($transaction).toHaveBeenCalledTimes(7);
    expect(tx.monthlyAddonPurchase.create).toHaveBeenCalledTimes(1);
  });
  it('keeps persistent serialization failures bounded without granting any credit', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0.999999);
    try {
      const { store, tx, $transaction } = fixture();
      const conflict = Object.assign(new Error('persistent write conflict'), { code: 'P2034' });
      $transaction.mockRejectedValue(conflict);
      const startedAt = Date.now();
      const assertion = expect(store.applyPurchase(input)).rejects.toBe(conflict);
      await vi.runAllTimersAsync();
      await assertion;
      // Three owner retry budgets plus the existing 20ms and 40ms ledger pauses.
      expect(Date.now() - startedAt).toBe(3 * 1145 + 20 + 40);
      expect($transaction).toHaveBeenCalledTimes(18);
      expect(tx.monthlyAddonPurchase.create).not.toHaveBeenCalled();
      expect(tx.monthlyAddonPurchase.update).not.toHaveBeenCalled();
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });
  it('reads all-time valid grants from the same supplied transaction', async () => {
    const { tx } = fixture();
    expect(await readPrismaMonthlyAddonCredits(tx, 'owner', input.purchasedAt)).toEqual({ postUnits: 200, aiCaptions: 100 });
    expect(tx.monthlyAddonPurchase.findMany).toHaveBeenCalledWith({ where: { userId: 'owner', revoked: false }, select: { id: true } });
  });
  it('holds the durable owner lock in the same serializable transaction as granting', async () => {
    const { store, tx, $transaction } = fixture();
    await expect(store.applyPurchase(input)).resolves.toMatchObject({ applied: true, expiresAt: null });
    expect($transaction).toHaveBeenCalledWith(expect.any(Function), { isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 });
    expect(tx.managedUploadOwner.updateMany.mock.invocationCallOrder[0]).toBeLessThan(tx.monthlyAddonPurchase.create.mock.invocationCallOrder[0]!);
    expect(tx.monthlyAddonPurchase.create).toHaveBeenCalledWith({ data: { ...input, id: monthlyAddonPurchaseKey(input),
      ownerHash: monthlyAddonOwnerHash(input.userId), purchasedAt: new Date(input.purchasedAt), revoked: false } });
  });
  it('cannot grant after deletion even if the process owner coordinator is stale', async () => {
    const { store, tx } = fixture(); tx.managedUploadOwner.upsert.mockResolvedValue({ status: 'DELETED' });
    await expect(store.applyPurchase(input)).rejects.toThrow('Account deletion');
    expect(tx.monthlyAddonPurchase.create).not.toHaveBeenCalled();
  });
  it('keeps refund tombstones and immutable owners', async () => {
    const { store, tx } = fixture();
    const row = { ...input, id: monthlyAddonPurchaseKey(input), ownerHash: monthlyAddonOwnerHash(input.userId), purchasedAt: new Date(input.purchasedAt), revoked: true };
    tx.monthlyAddonPurchase.findUnique.mockResolvedValue(row);
    await expect(store.applyPurchase(input)).resolves.toMatchObject({ applied: false, revoked: true });
    await expect(store.applyPurchase({ ...input, userId: 'other' })).rejects.toThrow('already linked');
    expect(tx.monthlyAddonPurchase.create).not.toHaveBeenCalled();
  });
  it('retries a cross-owner unique race and rejects the second claimant', async () => {
    const { store, tx } = fixture();
    tx.monthlyAddonPurchase.create.mockRejectedValueOnce({ code: 'P2002' });
    tx.monthlyAddonPurchase.findUnique.mockResolvedValueOnce(null).mockResolvedValue({ ...input, id: monthlyAddonPurchaseKey(input),
      ownerHash: monthlyAddonOwnerHash('other-owner'), purchasedAt: new Date(input.purchasedAt), revoked: false });
    await expect(store.applyPurchase(input)).rejects.toThrow('already linked');
    expect(tx.monthlyAddonPurchase.create).toHaveBeenCalledTimes(1);
  });
});
