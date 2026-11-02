import type { RequestHandler, Router } from 'express';
import type { ServerConfig } from '../../config/env.js';
import { readAuthUser } from '../auth/authTypes.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import type { PostStore } from '../posts/postStore.js';
import type { RealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import { monthlyAddonPostUnits, monthlyAddonAiCaptions, allowMonthlyAddonStore,
  MonthlyAddonPurchaseConflictError, type MonthlyAddonStore } from './monthlyAddonStore.js';
import { RevenueCatAddonLookupError, type RevenueCatAddonPurchaseClient } from './revenueCatAddonPurchaseClient.js';
import { addonCatalogVersion, addonTierProducts, addonGrantSnapshot, readAddonProductDefinition } from './addonProductCatalog.js';

export type AddonConfig = Pick<ServerConfig, 'billingAddonsEnabled' | 'billingAddonTiersEnabled' | 'billingProvider' | 'revenueCatRestApiV1Key' |
  'revenueCatAddonProductId' | 'revenueCatAddonEnvironment'>;
const addonVerificationConfigured = (config: AddonConfig) =>
  config.billingProvider === 'revenuecat' && Boolean(config.revenueCatRestApiV1Key);
export const monthlyAddonPurchasesEnabled = (config: AddonConfig) =>
  config.billingAddonsEnabled && addonVerificationConfigured(config);
const addonCreditPolicy = { policyVersion: 2, creditsExpire: false, expiresAt: null } as const;
export const registerAddonRoutes = ({ router, authMiddleware, config, userStore, subscriptionStore,
  monthlyAddonStore, postStore, captionUsageStore, purchaseClient, now = () => new Date() }: {
  router: Router; authMiddleware: RequestHandler; config: AddonConfig; userStore: UserStore;
  subscriptionStore: SubscriptionStore; monthlyAddonStore: MonthlyAddonStore;
  postStore: Pick<PostStore, 'countAddonPostUnits'>;
  captionUsageStore: Pick<RealClipCaptionUsageStore, 'countAddonUsages'>;
  purchaseClient: RevenueCatAddonPurchaseClient; now?: () => Date;
}) => {
  router.get('/billing/addons', authMiddleware, async (_request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const current = now().toISOString();
    const enabled = monthlyAddonPurchasesEnabled(config);
    const plan = await subscriptionStore.getPlan(user);
    const [credits, spentPostUnits, spentAiCaptions, purchasedPacks] = await Promise.all([
      monthlyAddonStore.readCredits({ userId: user.id, now: current }),
      postStore.countAddonPostUnits({ userId: user.id }), captionUsageStore.countAddonUsages({ userId: user.id }),
      monthlyAddonStore.countPurchases({ userId: user.id })
    ]);
    const tiersEnabled = enabled && config.billingAddonTiersEnabled;
    response.json({ status: 'ok', enabled, eligible: enabled && plan !== 'BASIC', productId: config.revenueCatAddonProductId,
      postUnits: monthlyAddonPostUnits, aiCaptions: monthlyAddonAiCaptions, priceThb: 49,
      catalogVersion: addonCatalogVersion,
      products: addonTierProducts.map(product => ({ ...product, enabled: tiersEnabled, eligible: tiersEnabled && plan !== 'BASIC' })),
      ...addonCreditPolicy, addonPostUnits: Math.max(credits.postUnits - spentPostUnits, 0),
      addonAiCaptions: Math.max(credits.aiCaptions - spentAiCaptions, 0),
      purchasedPacks });
  });
  router.post('/billing/addons/confirm', authMiddleware, async (request, response) => {
    const user = readAuthUser(response.locals);
    if (!user) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    if (!addonVerificationConfigured(config)) {
      response.status(403).json({ status: 'error', code: 'BILLING_ADDONS_DISABLED', message: 'Add-on verification is not configured.' }); return;
    }
    const { productId, transactionId } = request.body ?? {};
    const transactionIdKind = request.body?.transactionIdKind ?? 'STORE';
    if (typeof productId !== 'string' || !productId.trim() || productId.length > 256 || productId !== productId.trim() ||
      typeof transactionId !== 'string' ||
      !transactionId.trim() || transactionId.length > 512 || transactionId !== transactionId.trim() ||
      (transactionIdKind !== 'STORE' && transactionIdKind !== 'REVENUECAT')) {
      response.status(400).json({ status: 'error', code: 'ADDON_PURCHASE_INVALID', message: 'A configured product and store transaction are required.' }); return;
    }
    // Confirmation remains available after a membership expires: never ask an
    // already charged customer to buy the same transaction again.
    await userStore.ensure(user);
    const confirmed = transactionIdKind === 'STORE' ? await monthlyAddonStore.findPurchaseConfirmation({ userId: user.id, productId, transactionId,
      environment: config.revenueCatAddonEnvironment }) : null;
    if (confirmed) {
      if (confirmed.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.json({ status: 'ok', confirmed: true, productId, transactionId, transactionIdKind, postUnits: confirmed.postUnits,
        aiCaptions: confirmed.aiCaptions, ...addonCreditPolicy }); return;
    }
    const product = readAddonProductDefinition(productId, config.revenueCatAddonProductId);
    if (!product && transactionIdKind !== 'REVENUECAT') {
      response.status(400).json({ status: 'error', code: 'ADDON_PURCHASE_INVALID', message: 'A configured product and store transaction are required.' }); return;
    }
    let purchase;
    try { purchase = await purchaseClient.findPurchase({ userId: user.id, productId, transactionId,
      ...(transactionIdKind === 'REVENUECAT' ? { transactionIdKind: 'REVENUECAT' } : {}) }); }
    catch (error) {
      if (!(error instanceof RevenueCatAddonLookupError)) throw error;
      // The store charge has already happened. Keep the exact transaction
      // pending instead of starting another purchase during an RC outage.
      response.status(202).json({ status: 'ok', confirmed: false, productId, transactionId, transactionIdKind, ...addonCreditPolicy }); return;
    }
    if (!purchase) { response.status(202).json({ status: 'ok', confirmed: false, productId, transactionId, transactionIdKind, ...addonCreditPolicy }); return; }
    if (!allowMonthlyAddonStore(purchase.store, purchase.environment) && !purchase.revoked) {
      response.status(403).json({ status: 'error', code: 'ADDON_STORE_UNSUPPORTED', message: 'Add-on purchases are not supported by this store.' }); return;
    }
    const verifiedSelector = transactionIdKind === 'REVENUECAT' ? purchase.verifiedSelector : purchase.transactionId;
    if (purchase.userId !== user.id || purchase.productId !== productId || verifiedSelector !== transactionId ||
      purchase.environment !== config.revenueCatAddonEnvironment) {
      response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_MISMATCH', message: 'This transaction could not be verified for this account and store.' }); return;
    }
    if (!purchase.transactionId) {
      if (purchase.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.status(202).json({ status: 'ok', confirmed: false, productId, transactionId, transactionIdKind, ...addonCreditPolicy }); return;
    }
    if (!product) {
      // A retired configured alias may still exist in old durable receipts.
      // Exact provider proof may acknowledge its original ledger grant, but
      // can never create a new grant for an unregistered product.
      const historical = await monthlyAddonStore.findPurchaseConfirmation({ userId: user.id, productId,
        transactionId: purchase.transactionId, environment: purchase.environment, store: purchase.store });
      if (!historical) {
        response.status(400).json({ status: 'error', code: 'ADDON_PURCHASE_INVALID', message: 'A configured product and store transaction are required.' }); return;
      }
      if (purchase.revoked) await monthlyAddonStore.revokePurchase({ ...purchase, transactionId: purchase.transactionId });
      if (historical.revoked || purchase.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.json({ status: 'ok', confirmed: true, productId, transactionId, transactionIdKind,
        postUnits: historical.postUnits, aiCaptions: historical.aiCaptions, ...addonCreditPolicy }); return;
    }
    const canonicalPurchase = { ...purchase, transactionId: purchase.transactionId, ...addonGrantSnapshot(product) };
    try {
      if (purchase.revoked) await monthlyAddonStore.revokePurchase(canonicalPurchase);
      const result = purchase.revoked ? undefined : await monthlyAddonStore.applyPurchase(canonicalPurchase);
      if (!result || result.revoked) {
        response.status(409).json({ status: 'error', code: 'ADDON_PURCHASE_REVOKED', message: 'This transaction has been refunded or revoked.' }); return;
      }
      response.json({ status: 'ok', confirmed: true, productId, transactionId, transactionIdKind, postUnits: result.postUnits,
        aiCaptions: result.aiCaptions, ...addonCreditPolicy });
    } catch (error) {
      if (!(error instanceof MonthlyAddonPurchaseConflictError)) throw error;
      response.status(409).json({ status: 'error', code: 'PURCHASE_ALREADY_LINKED', message: error.message });
    }
  });
};
