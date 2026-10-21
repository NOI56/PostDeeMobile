import { allowMonthlyAddonStore, type MonthlyAddonPurchase } from './monthlyAddonStore.js';

export type RevenueCatAddonPurchaseClient = { findPurchase: (input: { userId: string; productId: string; transactionId: string }) =>
  Promise<(MonthlyAddonPurchase & { revoked?: boolean }) | null> };
export class RevenueCatAddonLookupError extends Error {
  constructor() { super('RevenueCat add-on purchase could not be verified'); }
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
      for (const raw of rows) {
        const row = record(raw);
        // Customer Info `id` is RevenueCat's internal purchase id. It must
        // never produce a second grant alongside the webhook's store id.
        if (!row || row.store_transaction_id !== input.transactionId) continue;
        const store = normalizeRevenueCatAddonStore(row.store);
        if (store && !allowMonthlyAddonStore(store)) return null;
        const date = typeof row.purchase_date === 'string' ? new Date(row.purchase_date) : undefined;
        if (!store || typeof row.is_sandbox !== 'boolean' || !date || !Number.isFinite(date.getTime())) throw new RevenueCatAddonLookupError();
        const transactionId = row.store_transaction_id;
        if (typeof transactionId !== 'string' || !transactionId) throw new RevenueCatAddonLookupError();
        return { userId: input.userId, productId: input.productId, transactionId, store,
          environment: row.is_sandbox ? 'SANDBOX' : 'PRODUCTION', purchasedAt: date.toISOString(),
          ...(row.refunded_at || row.refund_date ? { revoked: true } : {}) };
      }
      return null;
    } catch { throw new RevenueCatAddonLookupError(); }
    finally { clearTimeout(timeout); }
  }
});
