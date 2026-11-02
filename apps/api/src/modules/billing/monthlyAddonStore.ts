import { createHash } from 'node:crypto';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';

// Frozen legacy grant, including historical configured SKU aliases. New tiers
// must supply their own snapshot instead of changing these quantities.
export const monthlyAddonPostUnits = 100;
export const monthlyAddonAiCaptions = 50;
// Purchased credits never expire and use the same policy on both app stores.
export const allowMonthlyAddonStore = (store: string, environment = 'PRODUCTION') =>
  (environment === 'PRODUCTION' || environment === 'SANDBOX') &&
  (store === 'PLAY_STORE' || store === 'APP_STORE' || (environment === 'SANDBOX' && store === 'TEST_STORE'));
export class MonthlyAddonUnsupportedStoreError extends Error {
  constructor() { super('Add-on credits are not supported by this store.'); }
}
export type MonthlyAddonPurchase = {
  userId: string; productId: string; transactionId: string; store: string;
  environment: string; purchasedAt: string;
  // Omitted only by legacy callers, whose historical contract is always 100/50.
  // New products receive these values from the server's verified SKU registry.
  postUnitsGranted?: number; aiCaptionsGranted?: number;
};
export type MonthlyAddonApplyResult = { applied: boolean; revoked: boolean; expiresAt: null; postUnits: number; aiCaptions: number };
export type MonthlyAddonStore = {
  readCredits: (input: { userId: string; now: string }) => Promise<{ postUnits: number; aiCaptions: number }>;
  countPurchases: (input: { userId: string }) => Promise<number>;
  applyPurchase: (input: MonthlyAddonPurchase) => Promise<MonthlyAddonApplyResult>;
  findPurchaseConfirmation: (input: { userId: string; productId: string; transactionId: string; environment: string; store?: string }) => Promise<MonthlyAddonApplyResult | null>;
  revokePurchase: (input: MonthlyAddonPurchase) => Promise<void>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};
export type MonthlyAddonGrantSnapshot = { postUnitsGranted: number; aiCaptionsGranted: number };
export const readMonthlyAddonGrant = (input: Pick<MonthlyAddonPurchase, 'postUnitsGranted' | 'aiCaptionsGranted'>) => {
  const legacy = input.postUnitsGranted === undefined && input.aiCaptionsGranted === undefined;
  const postUnits = legacy ? monthlyAddonPostUnits : input.postUnitsGranted;
  const aiCaptions = legacy ? monthlyAddonAiCaptions : input.aiCaptionsGranted;
  if (typeof postUnits !== 'number' || typeof aiCaptions !== 'number' ||
      !Number.isInteger(postUnits) || !Number.isInteger(aiCaptions) ||
      postUnits < 0 || aiCaptions < 0 || postUnits > 2147483647 || aiCaptions > 2147483647 ||
      (postUnits === 0 && aiCaptions === 0)) {
    throw new Error('Invalid add-on grant snapshot');
  }
  return { postUnits, aiCaptions };
};
export const sumMonthlyAddonGrants = (purchases: MonthlyAddonGrantSnapshot[]) => purchases.reduce((total, purchase) => {
  const grant = readMonthlyAddonGrant(purchase);
  const postUnits = total.postUnits + grant.postUnits;
  const aiCaptions = total.aiCaptions + grant.aiCaptions;
  if (!Number.isSafeInteger(postUnits) || !Number.isSafeInteger(aiCaptions)) throw new Error('Invalid add-on grant total');
  return { postUnits, aiCaptions };
}, { postUnits: 0, aiCaptions: 0 });
export const readMonthlyAddonWindow = (now: string) => {
  // Shared UTC window for included monthly allowances only. Purchased grants
  // and their consumption are lifetime totals under policy version 2.
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
  const purchases = new Map<string, MonthlyAddonPurchase & MonthlyAddonGrantSnapshot & { ownerHash: string; revoked: boolean }>();
  const apply = (input: MonthlyAddonPurchase, revoke: boolean) => runWithActiveOwner(input.userId, async () => {
    if (!revoke && !allowMonthlyAddonStore(input.store, input.environment)) throw new MonthlyAddonUnsupportedStoreError();
    const key = monthlyAddonPurchaseKey(input);
    const existing = purchases.get(key);
    if (existing && (existing.ownerHash !== monthlyAddonOwnerHash(input.userId) || existing.productId !== input.productId)) {
      throw new MonthlyAddonPurchaseConflictError();
    }
    if (existing) {
      if (revoke) existing.revoked = true;
      return { applied: false, revoked: existing.revoked, expiresAt: null, ...readMonthlyAddonGrant(existing) };
    }
    const grant = readMonthlyAddonGrant(input);
    purchases.set(key, { ...input, postUnitsGranted: grant.postUnits, aiCaptionsGranted: grant.aiCaptions,
      ownerHash: monthlyAddonOwnerHash(input.userId), revoked: revoke });
    return { applied: !revoke, revoked: revoke, expiresAt: null, ...grant };
  });
  return {
    readCredits: async ({ userId }) => {
      return sumMonthlyAddonGrants([...purchases.values()].filter(p => p.userId === userId && !p.revoked));
    },
    countPurchases: async ({ userId }) => [...purchases.values()].filter(p => p.userId === userId && !p.revoked).length,
    applyPurchase: input => apply(input, false),
    findPurchaseConfirmation: async input => {
      const purchase = [...purchases.values()].find(p => p.userId === input.userId && p.productId === input.productId &&
        p.transactionId === input.transactionId && p.environment === input.environment &&
        (input.store === undefined || p.store === input.store));
      return purchase ? { applied: false, revoked: purchase.revoked, expiresAt: null, ...readMonthlyAddonGrant(purchase) } : null;
    },
    revokePurchase: async input => { await apply(input, true); },
    deleteAllForUser: async userId => { for (const purchase of purchases.values()) if (purchase.userId === userId) {
      purchase.userId = ''; purchase.revoked = true;
    } }
  };
};
