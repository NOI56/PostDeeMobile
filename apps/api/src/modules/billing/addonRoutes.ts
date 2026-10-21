import type { RequestHandler, Router } from 'express';
import type { ServerConfig } from '../../config/env.js';
import { readAuthUser } from '../auth/authTypes.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import { monthlyAddonPostUnits, monthlyAddonAiCaptions, readMonthlyAddonWindow, allowMonthlyAddonStore,
  MonthlyAddonPurchaseConflictError, type MonthlyAddonStore } from './monthlyAddonStore.js';
import { RevenueCatAddonLookupError, type RevenueCatAddonPurchaseClient } from './revenueCatAddonPurchaseClient.js';

export type AddonConfig = Pick<ServerConfig, 'billingAddonsEnabled' | 'billingProvider' | 'revenueCatRestApiV1Key' |
  'revenueCatAddonProductId' | 'revenueCatAddonEnvironment'>;
export const monthlyAddonPurchasesEnabled = (config: AddonConfig) =>
  config.billingAddonsEnabled && config.billingProvider === 'revenuecat' && Boolean(config.revenueCatRestApiV1Key);
export const registerAddonRoutes = ({ router, authMiddleware, config, userStore, subscriptionStore,
  monthlyAddonStore, purchaseClient, now = () => new Date() }: {
  router: Router; authMiddleware: RequestHandler; config: AddonConfig; userStore: UserStore;
  subscriptionStore: SubscriptionStore; monthlyAddonStore: MonthlyAddonStore;
  purchaseClient: RevenueCatAddonPurchaseClient; now?: () => Date;
}) => {
  router.get('/billing/addons', authMiddleware, async (_request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const current = now().toISOString();
    const enabled = monthlyAddonPurchasesEnabled(config);
    const plan = await subscriptionStore.getPlan(user);
    const credits = enabled ? await monthlyAddonStore.readCredits({ userId: user.id, now: current }) : { postUnits: 0, aiCaptions: 0 };
    response.json({ status: 'ok', enabled, eligible: enabled && plan !== 'BASIC', productId: config.revenueCatAddonProductId,
      postUnits: monthlyAddonPostUnits, aiCaptions: monthlyAddonAiCaptions, priceThb: 49,
      monthKey: readMonthlyAddonWindow(current).monthKey, expiresAt: readMonthlyAddonWindow(current).expiresAt,
      purchasedPacks: credits.postUnits / monthlyAddonPostUnits });
  });
  router.post('/billing/addons/confirm', authMiddleware, async (request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    if (!monthlyAddonPurchasesEnabled(config)) {
      response.status(403).json({ status: 'error', code: 'BILLING_ADDONS_DISABLED', message: 'Add-on purchases are not available.' }); return;
    }
    const { productId, transactionId } = request.body ?? {};
    if (productId !== config.revenueCatAddonProductId || typeof transactionId !== 'string' ||
      !transactionId.trim() || transactionId.length > 512 || transactionId !== transactionId.trim()) {
      response.status(400).json({ status: 'error', code: 'ADDON_PURCHASE_INVALID', message: 'A configured product and store transaction are required.' }); return;
    }
    // Confirmation remains available after a membership expires: never ask an
    // already charged customer to buy the same transaction again.
    await userStore.ensure(user);
    const confirmed = await monthlyAddonStore.findPurchaseConfirmation({ userId: user.id, productId, transactionId,
      environment: config.revenueCatAddonEnvironment });
    if (confirmed) {
      if (confirmed.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.json({ status: 'ok', confirmed: true, transactionId, postUnits: monthlyAddonPostUnits,
        aiCaptions: monthlyAddonAiCaptions, expiresAt: confirmed.expiresAt }); return;
    }
    let purchase;
    try { purchase = await purchaseClient.findPurchase({ userId: user.id, productId, transactionId }); }
    catch (error) {
      if (!(error instanceof RevenueCatAddonLookupError)) throw error;
      // The store charge has already happened. Keep the exact transaction
      // pending instead of starting another purchase during an RC outage.
      response.status(202).json({ status: 'ok', confirmed: false, transactionId }); return;
    }
    if (!purchase) { response.status(202).json({ status: 'ok', confirmed: false, transactionId }); return; }
    if (!allowMonthlyAddonStore(purchase.store) && !purchase.revoked) {
      response.status(403).json({ status: 'error', code: 'ADDON_STORE_UNSUPPORTED', message: 'Monthly add-on purchases are only available on Android.' }); return;
    }
    if (purchase.userId !== user.id || purchase.productId !== productId || purchase.transactionId !== transactionId ||
      purchase.environment !== config.revenueCatAddonEnvironment) {
      response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_MISMATCH', message: 'This transaction could not be verified for this account and store.' }); return;
    }
    try {
      if (purchase.revoked) await monthlyAddonStore.revokePurchase(purchase);
      const result = purchase.revoked ? undefined : await monthlyAddonStore.applyPurchase(purchase);
      if (!result || result.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.json({ status: 'ok', confirmed: true, transactionId, postUnits: monthlyAddonPostUnits,
        aiCaptions: monthlyAddonAiCaptions, expiresAt: result.expiresAt });
    } catch (error) {
      if (!(error instanceof MonthlyAddonPurchaseConflictError)) throw error;
      response.status(409).json({ status: 'error', code: 'PURCHASE_ALREADY_LINKED', message: error.message });
    }
  });
};
