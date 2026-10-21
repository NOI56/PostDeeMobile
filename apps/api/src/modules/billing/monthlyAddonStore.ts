import { createHash } from 'node:crypto';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';

export const monthlyAddonPostUnits = 100;
export const monthlyAddonAiCaptions = 50;
// This SKU expires at the UTC month boundary. It is offered on Android only;
// App Store purchased credits must not expire under its in-app purchase rules.
export const allowMonthlyAddonStore = (store: string) => store === 'PLAY_STORE' || store === 'TEST_STORE';
export class MonthlyAddonUnsupportedStoreError extends Error {
  constructor() { super('Monthly add-on credits are not supported by this store.'); }
}
export type MonthlyAddonPurchase = {
  userId: string; productId: string; transactionId: string; store: string;
  environment: string; purchasedAt: string;
};
export type MonthlyAddonApplyResult = { applied: boolean; revoked: boolean; expiresAt: string };
export type MonthlyAddonStore = {
  readCredits: (input: { userId: string; now: string }) => Promise<{ postUnits: number; aiCaptions: number }>;
  applyPurchase: (input: MonthlyAddonPurchase) => Promise<MonthlyAddonApplyResult>;
  findPurchaseConfirmation: (input: { userId: string; productId: string; transactionId: string; environment: string }) => Promise<MonthlyAddonApplyResult | null>;
  revokePurchase: (input: MonthlyAddonPurchase) => Promise<void>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};
export const readMonthlyAddonWindow = (now: string) => {
  const date = new Date(now);
  if (!Number.isFinite(date.getTime())) throw new Error('Invalid monthly add-on date');
  const startsAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1)).toISOString();
  const expiresAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1)).toISOString();
  return { monthKey: startsAt.slice(0, 7), startsAt, expiresAt };
};
export const monthlyAddonOwnerHash = (userId: string) => createHash('sha256').update(userId).digest('hex');
export const monthlyAddonPurchaseKey = (input: Pick<MonthlyAddonPurchase, 'store' | 'environment' | 'transactionId'>) =>
  createHash('sha256').update(JSON.stringify([input.store, input.environment, input.transactionId])).digest('hex');
export class MonthlyAddonPurchaseConflictError extends Error {
  constructor() { super('This purchase is already linked to another account or product.'); }
}
export const createInMemoryMonthlyAddonStore = ({ runWithActiveOwner = async (_id, operation) => operation() }:
  { runWithActiveOwner?: RunWithActiveOwner } = {}): MonthlyAddonStore => {
  const purchases = new Map<string, MonthlyAddonPurchase & { ownerHash: string; revoked: boolean }>();
  const apply = (input: MonthlyAddonPurchase, revoke: boolean) => runWithActiveOwner(input.userId, async () => {
    if (!revoke && !allowMonthlyAddonStore(input.store)) throw new MonthlyAddonUnsupportedStoreError();
    const key = monthlyAddonPurchaseKey(input);
    const existing = purchases.get(key);
    if (existing && (existing.ownerHash !== monthlyAddonOwnerHash(input.userId) || existing.productId !== input.productId)) {
      throw new MonthlyAddonPurchaseConflictError();
    }
    if (existing) {
      if (revoke) existing.revoked = true;
      return { applied: false, revoked: existing.revoked, expiresAt: readMonthlyAddonWindow(existing.purchasedAt).expiresAt };
    }
    purchases.set(key, { ...input, ownerHash: monthlyAddonOwnerHash(input.userId), revoked: revoke });
    return { applied: !revoke, revoked: revoke, expiresAt: readMonthlyAddonWindow(input.purchasedAt).expiresAt };
  });
  return {
    readCredits: async ({ userId, now }) => {
      const window = readMonthlyAddonWindow(now);
      const count = [...purchases.values()].filter(p => p.userId === userId && !p.revoked &&
        p.purchasedAt >= window.startsAt && p.purchasedAt < window.expiresAt).length;
      return { postUnits: count * monthlyAddonPostUnits, aiCaptions: count * monthlyAddonAiCaptions };
    },
    applyPurchase: input => apply(input, false),
    findPurchaseConfirmation: async input => {
      const purchase = [...purchases.values()].find(p => p.userId === input.userId && p.productId === input.productId &&
        p.transactionId === input.transactionId && p.environment === input.environment);
      return purchase ? { applied: false, revoked: purchase.revoked, expiresAt: readMonthlyAddonWindow(purchase.purchasedAt).expiresAt } : null;
    },
    revokePurchase: async input => { await apply(input, true); },
    deleteAllForUser: async userId => { for (const purchase of purchases.values()) if (purchase.userId === userId) {
      purchase.userId = ''; purchase.revoked = true;
    } }
  };
};
