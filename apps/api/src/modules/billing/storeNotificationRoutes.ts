import type { Response, Router } from 'express';

import { StorePurchaseVerificationError } from './storePurchaseService.js';

export type StoreNotificationEvent = {
  provider: 'google-play' | 'apple-app-store';
  eventType: string;
  notificationId?: string;
  notificationType?: string;
  subtype?: string;
  productId?: string;
  purchaseToken?: string;
  transactionId?: string;
  originalTransactionId?: string;
  productType?: string;
  refundType?: string;
  raw: unknown;
};

export type StoreNotificationHandler = {
  handle: (event: StoreNotificationEvent) => Promise<void>;
};

type AppleSignedNotification = {
  notificationUUID?: unknown;
  notificationType?: unknown;
  subtype?: unknown;
  data?: {
    decodedTransaction?: {
      transactionId?: unknown;
      originalTransactionId?: unknown;
    };
  };
};

export type AppleSignedNotificationDecoder = (
  signedPayload: string
) => Promise<AppleSignedNotification>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const readString = (value: unknown) => (typeof value === 'string' ? value : undefined);

const readNumberOrString = (value: unknown) => {
  if (typeof value === 'string') {
    return value;
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }

  return undefined;
};

const decodePubSubData = (body: unknown) => {
  if (!isRecord(body) || !isRecord(body.message)) {
    throw new StorePurchaseVerificationError({
      statusCode: 400,
      code: 'GOOGLE_PLAY_NOTIFICATION_INVALID',
      message: 'Google Play notification payload must include message.data'
    });
  }

  const data = readString(body.message.data);

  if (!data) {
    throw new StorePurchaseVerificationError({
      statusCode: 400,
      code: 'GOOGLE_PLAY_NOTIFICATION_INVALID',
      message: 'Google Play notification payload must include message.data'
    });
  }

  try {
    return {
      messageId: readString(body.message.messageId),
      payload: JSON.parse(Buffer.from(data, 'base64').toString('utf8')) as unknown
    };
  } catch {
    throw new StorePurchaseVerificationError({
      statusCode: 400,
      code: 'GOOGLE_PLAY_NOTIFICATION_INVALID',
      message: 'Google Play notification data must be valid base64 JSON'
    });
  }
};

export const readGooglePlayNotificationEvent = (body: unknown): StoreNotificationEvent => {
  const { messageId, payload } = decodePubSubData(body);

  if (!isRecord(payload)) {
    throw new StorePurchaseVerificationError({
      statusCode: 400,
      code: 'GOOGLE_PLAY_NOTIFICATION_INVALID',
      message: 'Google Play notification data must be an object'
    });
  }

  if (isRecord(payload.subscriptionNotification)) {
    const notification = payload.subscriptionNotification;

    return {
      provider: 'google-play',
      eventType: 'SUBSCRIPTION_NOTIFICATION',
      notificationId: messageId,
      notificationType: readNumberOrString(notification.notificationType),
      productId: readString(notification.subscriptionId),
      purchaseToken: readString(notification.purchaseToken),
      raw: payload
    };
  }

  if (isRecord(payload.voidedPurchaseNotification)) {
    const notification = payload.voidedPurchaseNotification;

    return {
      provider: 'google-play',
      eventType: 'VOIDED_PURCHASE_NOTIFICATION',
      notificationId: messageId,
      productType: readNumberOrString(notification.productType),
      refundType: readNumberOrString(notification.refundType),
      purchaseToken: readString(notification.purchaseToken),
      raw: payload
    };
  }

  return {
    provider: 'google-play',
    eventType: isRecord(payload.testNotification)
      ? 'TEST_NOTIFICATION'
      : 'UNKNOWN_NOTIFICATION',
    notificationId: messageId,
    raw: payload
  };
};

const readAppleSignedPayload = (body: unknown) => {
  if (!isRecord(body)) {
    return undefined;
  }

  return readString(body.signedPayload);
};

export const readAppleNotificationEvent = async ({
  body,
  decoder
}: {
  body: unknown;
  decoder: AppleSignedNotificationDecoder;
}): Promise<StoreNotificationEvent> => {
  const signedPayload = readAppleSignedPayload(body);

  if (!signedPayload) {
    throw new StorePurchaseVerificationError({
      statusCode: 400,
      code: 'APPLE_NOTIFICATION_INVALID',
      message: 'Apple notification payload must include signedPayload'
    });
  }

  const notification = await decoder(signedPayload);
  const notificationType = readString(notification.notificationType);
  const transaction = notification.data?.decodedTransaction;

  return {
    provider: 'apple-app-store',
    eventType: notificationType ?? 'UNKNOWN_NOTIFICATION',
    notificationId: readString(notification.notificationUUID),
    notificationType,
    subtype: readString(notification.subtype),
    transactionId: readString(transaction?.transactionId),
    originalTransactionId: readString(transaction?.originalTransactionId),
    raw: notification
  };
};

const handleStoreNotificationError = (response: Response, error: unknown) => {
  if (error instanceof StorePurchaseVerificationError) {
    response.status(error.statusCode).json({
      status: 'error',
      code: error.code,
      message: error.message
    });
    return;
  }

  response.status(502).json({
    status: 'error',
    code: 'STORE_NOTIFICATION_FAILED',
    message: 'Store notification handling failed'
  });
};

export const registerStoreNotificationRoutes = (
  router: Router,
  handler: StoreNotificationHandler,
  options: {
    appleSignedNotificationDecoder?: AppleSignedNotificationDecoder;
  } = {}
) => {
  router.post('/billing/google-play/notifications', async (request, response) => {
    try {
      const event = readGooglePlayNotificationEvent(request.body);
      await handler.handle(event);

      response.json({
        status: 'ok',
        event
      });
    } catch (error) {
      handleStoreNotificationError(response, error);
    }
  });

  router.post('/billing/apple/notifications', async (request, response) => {
    if (!options.appleSignedNotificationDecoder) {
      response.status(501).json({
        status: 'error',
        code: 'APPLE_NOTIFICATION_DECODER_NOT_CONFIGURED',
        message: 'Apple App Store notification verification is not configured yet'
      });
      return;
    }

    try {
      const event = await readAppleNotificationEvent({
        body: request.body,
        decoder: options.appleSignedNotificationDecoder
      });
      await handler.handle(event);

      response.json({
        status: 'ok',
        event
      });
    } catch (error) {
      handleStoreNotificationError(response, error);
    }
  });
};
