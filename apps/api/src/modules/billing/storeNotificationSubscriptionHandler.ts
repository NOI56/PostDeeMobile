import type {
  SubscriptionStatus,
  SubscriptionStore
} from '../subscriptions/subscriptionStore.js';
import type { StoreNotificationEvent, StoreNotificationHandler } from './storeNotificationRoutes.js';

const GOOGLE_PLAY_STATUS_BY_NOTIFICATION_TYPE: Record<string, SubscriptionStatus | undefined> = {
  '1': 'ACTIVE',
  '2': 'ACTIVE',
  '4': 'ACTIVE',
  '5': 'PAST_DUE',
  '6': 'ACTIVE',
  '7': 'ACTIVE',
  '12': 'CANCELED',
  '13': 'CANCELED',
  '20': 'CANCELED'
};

const APPLE_STATUS_BY_NOTIFICATION_TYPE: Record<string, SubscriptionStatus | undefined> = {
  DID_FAIL_TO_RENEW: 'PAST_DUE',
  DID_RECOVER: 'ACTIVE',
  DID_RENEW: 'ACTIVE',
  EXPIRED: 'CANCELED',
  GRACE_PERIOD_EXPIRED: 'CANCELED',
  REFUND: 'CANCELED',
  REFUND_REVERSED: 'ACTIVE',
  REVOKE: 'CANCELED',
  SUBSCRIBED: 'ACTIVE'
};

const readTargetStatus = (event: StoreNotificationEvent) => {
  if (event.provider === 'google-play') {
    if (event.eventType === 'VOIDED_PURCHASE_NOTIFICATION') {
      return event.productType === '1' ? 'CANCELED' : undefined;
    }

    return event.notificationType
      ? GOOGLE_PLAY_STATUS_BY_NOTIFICATION_TYPE[event.notificationType]
      : undefined;
  }

  if (event.eventType === 'DID_FAIL_TO_RENEW' && event.subtype === 'GRACE_PERIOD') {
    return 'ACTIVE';
  }

  return APPLE_STATUS_BY_NOTIFICATION_TYPE[event.eventType];
};

const readBillingSubscriptionId = (event: StoreNotificationEvent) => {
  if (event.provider === 'google-play' && event.purchaseToken) {
    return `google-play:${event.purchaseToken}`;
  }

  if (event.provider === 'apple-app-store') {
    const appleBillingId = event.originalTransactionId ?? event.transactionId;

    if (appleBillingId) {
      return `apple-app-store:${appleBillingId}`;
    }
  }

  return undefined;
};

export const createStoreNotificationSubscriptionHandler = ({
  subscriptionStore
}: {
  subscriptionStore: SubscriptionStore;
}): StoreNotificationHandler => ({
  handle: async (event) => {
    const status = readTargetStatus(event);
    const billingSubscriptionId = readBillingSubscriptionId(event);

    if (!status || !billingSubscriptionId) {
      return;
    }

    await subscriptionStore.updateStatusByBillingSubscriptionId({
      billingSubscriptionId,
      status
    });
  }
});
