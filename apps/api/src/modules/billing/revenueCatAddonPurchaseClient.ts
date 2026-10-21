import { allowMonthlyAddonStore, type MonthlyAddonPurchase } from './monthlyAddonStore.js';

export type AddonTransactionIdKind = 'STORE' | 'REVENUECAT';
export type VerifiedRevenueCatAddonPurchase = Omit<MonthlyAddonPurchase, 'transactionId'> & {
  transactionId?: string; verifiedSelector?: string; revoked?: boolean;
};
export type RevenueCatAddonPurchaseClient = { findPurchase: (input: { userId: string; productId: string; transactionId: string;
  transactionIdKind?: AddonTransactionIdKind }) => Promise<VerifiedRevenueCatAddonPurchase | null> };
export class RevenueCatAddonLookupError extends Error {
  constructor() { super('RevenueCat add-on purchase could not be verified'); }
}
export class RevenueCatAddonAmbiguousSelectorError extends RevenueCatAddonLookupError {
  constructor() { super(); this.message = 'RevenueCat add-on transaction selector is ambiguous'; }
}
const record = (value: unknown): Record<string, unknown> | undefined =>
  typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
export const normalizeRevenueCatAddonStore = (value: unknown): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const normalized = value.toUpperCase();
  return ['PLAY_STORE', 'APP_STORE', 'TEST_STORE'].includes(normalized) ? normalized : undefined;
};
export const createRevenueCatAddonPurchaseClient = ({ apiKey, fetchImpl = fetch, timeoutMs = 8000 }:
  { apiKey?: string; fetchImpl?: typeof fetch; timeoutMs?: number } = {}): RevenueCatAddonPurchaseClient => ({
  findPurchase: async input => {
    if (!apiKey) throw new RevenueCatAddonLookupError();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(input.userId)}`,
        { headers: { Authorization: `Bearer ${apiKey}` }, signal: controller.signal });
      if (!response.ok) throw new RevenueCatAddonLookupError();
      const root = record(await response.json());
      const subscriber = record(root?.subscriber);
      if (!subscriber) throw new RevenueCatAddonLookupError();
      // Aliased/anonymous customer histories are not proof of which PostDee
      // account bought a consumable. Its canonical webhook can settle later.
      if (subscriber.original_app_user_id !== input.userId) return null;
      const purchases = record(subscriber.non_subscriptions);
      const rows = purchases?.[input.productId];
      if (!rows) return null;
      if (!Array.isArray(rows)) throw new RevenueCatAddonLookupError();
      const revenueCatSelector = input.transactionIdKind === 'REVENUECAT';
      const selectorField = revenueCatSelector ? 'id' : 'store_transaction_id';
      const candidates = rows.map(record).filter((row): row is Record<string, unknown> =>
        Boolean(row && row[selectorField] === input.transactionId));
      if (candidates.length === 0) return null;
      if (candidates.length !== 1) throw new RevenueCatAddonAmbiguousSelectorError();
      const row = candidates[0];
      const store = normalizeRevenueCatAddonStore(row.store);
      if (store && !allowMonthlyAddonStore(store)) return null;
      const date = typeof row.purchase_date === 'string' ? new Date(row.purchase_date) : undefined;
      if (!store || typeof row.is_sandbox !== 'boolean' || !date || !Number.isFinite(date.getTime())) throw new RevenueCatAddonLookupError();
      const transactionId = typeof row.store_transaction_id === 'string' && row.store_transaction_id.trim() === row.store_transaction_id &&
        row.store_transaction_id.length > 0 ? row.store_transaction_id : undefined;
      // Customer Info `id` can select an exact RC history row, but only its
      // explicit canonical store id is a grant key. Date/amount similarity
      // cannot prove identity when the two systems observe events out of order.
      return { userId: input.userId, productId: input.productId, ...(transactionId ? { transactionId } : {}), store,
        environment: row.is_sandbox ? 'SANDBOX' : 'PRODUCTION', purchasedAt: date.toISOString(),
        ...(revenueCatSelector ? { verifiedSelector: input.transactionId } : {}),
        ...(row.refunded_at || row.refund_date ? { revoked: true } : {}) };
    } catch (error) {
      if (error instanceof RevenueCatAddonLookupError) throw error;
      throw new RevenueCatAddonLookupError();
    }
    finally { clearTimeout(timeout); }
  }
});
