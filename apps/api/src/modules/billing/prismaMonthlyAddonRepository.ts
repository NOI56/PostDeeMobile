import { runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';
import { MonthlyAddonPurchaseConflictError, MonthlyAddonUnsupportedStoreError, allowMonthlyAddonStore, monthlyAddonOwnerHash, monthlyAddonPurchaseKey,
  readMonthlyAddonGrant, sumMonthlyAddonGrants,
  type MonthlyAddonGrantSnapshot, type MonthlyAddonPurchase, type MonthlyAddonStore } from './monthlyAddonStore.js';

type PurchaseRow = MonthlyAddonGrantSnapshot & { id: string; userId: string | null; ownerHash: string; productId: string;
  purchasedAt: Date; revoked: boolean };
export type PrismaMonthlyAddonReadTransaction = {
  monthlyAddonPurchase: { findMany: (input: { where: { userId: string; revoked: false };
    select: { id: true; postUnitsGranted: true; aiCaptionsGranted: true } }) => Promise<Array<{ id: string } & MonthlyAddonGrantSnapshot>> };
};
type PurchaseTransaction = PrismaOwnerLifecycleTransaction & PrismaMonthlyAddonReadTransaction & {
  monthlyAddonPurchase: {
    findUnique: (input: { where: { id: string } }) => Promise<PurchaseRow | null>;
    findFirst: (input: { where: { userId: string; productId: string; transactionId: string; environment: string; store?: string } }) => Promise<PurchaseRow | null>;
    create: (input: { data: PurchaseRow & { store: string; environment: string; transactionId: string } }) => Promise<PurchaseRow>;
    update: (input: { where: { id: string }; data: { revoked: true } }) => Promise<PurchaseRow>;
  };
};
export type PrismaMonthlyAddonClient = PurchaseTransaction & {
  $transaction: <T>(operation: (transaction: PurchaseTransaction) => Promise<T>, options:
    { isolationLevel: 'Serializable'; maxWait: number; timeout: number }) => Promise<T>;
};
export const readPrismaMonthlyAddonCredits = async (transaction: PrismaMonthlyAddonReadTransaction, userId: string, _now: string) => {
  const records = await transaction.monthlyAddonPurchase.findMany({ where: { userId, revoked: false },
    select: { id: true, postUnitsGranted: true, aiCaptionsGranted: true } });
  return sumMonthlyAddonGrants(records);
};
export const createPrismaMonthlyAddonRepository = ({ prisma }: { prisma: PrismaMonthlyAddonClient }): MonthlyAddonStore => {
  const apply = async (input: MonthlyAddonPurchase, revoke: boolean) => {
    if (!revoke && !allowMonthlyAddonStore(input.store, input.environment)) throw new MonthlyAddonUnsupportedStoreError();
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await runActiveOwnerTransaction(prisma, input.userId, async transaction => {
          const id = monthlyAddonPurchaseKey(input);
          const existing = await transaction.monthlyAddonPurchase.findUnique({ where: { id } });
          if (existing && (existing.ownerHash !== monthlyAddonOwnerHash(input.userId) || existing.productId !== input.productId)) {
            throw new MonthlyAddonPurchaseConflictError();
          }
          if (existing) {
            if (revoke && !existing.revoked) await transaction.monthlyAddonPurchase.update({ where: { id }, data: { revoked: true } });
            return { applied: false, revoked: existing.revoked || revoke || existing.userId === null, expiresAt: null,
              ...readMonthlyAddonGrant(existing) };
          }
          const grant = readMonthlyAddonGrant(input);
          await transaction.monthlyAddonPurchase.create({ data: { id, userId: input.userId,
            ownerHash: monthlyAddonOwnerHash(input.userId), productId: input.productId, store: input.store,
            environment: input.environment, transactionId: input.transactionId,
            purchasedAt: new Date(input.purchasedAt), revoked: revoke,
            postUnitsGranted: grant.postUnits, aiCaptionsGranted: grant.aiCaptions } });
          return { applied: !revoke, revoked: revoke, expiresAt: null, ...grant };
        });
      } catch (error) {
        const retryable = typeof error === 'object' && error !== null && 'code' in error &&
          (error.code === 'P2002' || error.code === 'P2034');
        if (!retryable || attempt === 2) throw error;
        // Several duplicate deliveries can exhaust the inner owner retry while
        // another contender commits. Restart the whole ledger operation with
        // a bounded pause so it observes that immutable transaction receipt.
        await new Promise(resolve => setTimeout(resolve, 20 * (attempt + 1)));
      }
    }
    throw new Error('Monthly add-on transaction retry exhausted');
  };
  return { readCredits: ({ userId, now }) => readPrismaMonthlyAddonCredits(prisma, userId, now),
    countPurchases: async ({ userId }) => (await prisma.monthlyAddonPurchase.findMany({ where: { userId, revoked: false },
      select: { id: true, postUnitsGranted: true, aiCaptionsGranted: true } })).length,
    findPurchaseConfirmation: async input => {
      const purchase = await prisma.monthlyAddonPurchase.findFirst({ where: input });
      return purchase ? { applied: false, revoked: purchase.revoked, expiresAt: null, ...readMonthlyAddonGrant(purchase) } : null;
    },
    applyPurchase: input => apply(input, false), revokePurchase: async input => { await apply(input, true); } };
};
