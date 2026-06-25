import { describe, expect, it } from 'vitest';

import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createStoreNotificationSubscriptionHandler } from './storeNotificationSubscriptionHandler.js';

describe('createStoreNotificationSubscriptionHandler', () => {
  it('cancels Pro access when Google Play reports an expired subscription', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-google-expired', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );

    await handler.handle({
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationType: '13',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-google-expired', provider: 'mock' })
    ).resolves.toBe('BASIC');
  });

  it('keeps Pro access when Google Play reports user cancellation before expiry', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-google-canceled', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );

    await handler.handle({
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationType: '3',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-google-canceled', provider: 'mock' })
    ).resolves.toBe('PRO');
  });

  it('reactivates Pro access when Google Play reports a renewal', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-google-renewed', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );
    await subscriptionStore.updateStatusByBillingSubscriptionId({
      billingSubscriptionId: 'google-play:android-purchase-token',
      status: 'CANCELED'
    });

    await handler.handle({
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationType: '2',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-google-renewed', provider: 'mock' })
    ).resolves.toBe('PRO');
  });

  it('keeps Pro access when Google Play reports a subscription entering grace period', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-google-grace', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );
    await subscriptionStore.updateStatusByBillingSubscriptionId({
      billingSubscriptionId: 'google-play:android-purchase-token',
      status: 'PAST_DUE'
    });

    await handler.handle({
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationType: '6',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-google-grace', provider: 'mock' })
    ).resolves.toBe('PRO');
  });

  it('cancels Pro access when Google Play reports a voided subscription purchase', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-google-voided', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );

    await handler.handle({
      provider: 'google-play',
      eventType: 'VOIDED_PURCHASE_NOTIFICATION',
      productType: '1',
      refundType: '1',
      purchaseToken: 'android-purchase-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-google-voided', provider: 'mock' })
    ).resolves.toBe('BASIC');
  });

  it('cancels Pro access when Apple reports an expired subscription with a known transaction id', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-apple-expired', provider: 'mock' },
      {
        billingSubscriptionId: 'apple-app-store:ios-transaction-id'
      }
    );

    await handler.handle({
      provider: 'apple-app-store',
      eventType: 'EXPIRED',
      notificationType: 'EXPIRED',
      transactionId: 'ios-transaction-id',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-apple-expired', provider: 'mock' })
    ).resolves.toBe('BASIC');
  });

  it('uses Apple original transaction id when renewal notifications use a new transaction id', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-apple-renewal-expired', provider: 'mock' },
      {
        billingSubscriptionId: 'apple-app-store:ios-original-transaction-id'
      }
    );

    await handler.handle({
      provider: 'apple-app-store',
      eventType: 'EXPIRED',
      notificationType: 'EXPIRED',
      transactionId: 'ios-renewal-transaction-id',
      originalTransactionId: 'ios-original-transaction-id',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-apple-renewal-expired', provider: 'mock' })
    ).resolves.toBe('BASIC');
  });

  it('keeps Pro access when Apple reports billing retry with a grace period', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await subscriptionStore.activatePro(
      { id: 'seller-apple-grace', provider: 'mock' },
      {
        billingSubscriptionId: 'apple-app-store:ios-original-transaction-id'
      }
    );
    await subscriptionStore.updateStatusByBillingSubscriptionId({
      billingSubscriptionId: 'apple-app-store:ios-original-transaction-id',
      status: 'PAST_DUE'
    });

    await handler.handle({
      provider: 'apple-app-store',
      eventType: 'DID_FAIL_TO_RENEW',
      notificationType: 'DID_FAIL_TO_RENEW',
      subtype: 'GRACE_PERIOD',
      originalTransactionId: 'ios-original-transaction-id',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-apple-grace', provider: 'mock' })
    ).resolves.toBe('PRO');
  });

  it('ignores notifications that do not include a known billing id', async () => {
    const subscriptionStore = createSubscriptionStore();
    const handler = createStoreNotificationSubscriptionHandler({ subscriptionStore });

    await handler.handle({
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationType: '13',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'unknown-token',
      raw: {}
    });

    await expect(
      subscriptionStore.getPlan({ id: 'seller-unknown-token', provider: 'mock' })
    ).resolves.toBe('BASIC');
  });
});
