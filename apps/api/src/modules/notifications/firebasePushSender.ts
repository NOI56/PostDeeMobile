import type { Messaging } from 'firebase-admin/messaging';

import type { PushMessage, PushSender, PushSendResult } from './pushSender.js';

// The project ships with the mock sender by default. To enable real push
// delivery, set PUSH_SENDER=firebase and provide FIREBASE_SERVICE_ACCOUNT_JSON
// (a service account key, kept secret). The dynamic import keeps the sender
// lazy so local mock-mode startup does not initialize Firebase Admin.

const firebaseAdminAppName = 'postdee-backend';
// Only errors meaning the token can never deliver again; transient failures
// (quota, internal errors) keep the token for the next publish.
const invalidTokenErrorCodes = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token'
]);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const loadMessaging = async (
  serviceAccountJson: string
): Promise<Messaging> => {
  let credentials: unknown;
  try {
    credentials = JSON.parse(serviceAccountJson);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON');
  }

  if (!isRecord(credentials)) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be a JSON object');
  }

  let appModule: typeof import('firebase-admin/app');
  let messagingModule: typeof import('firebase-admin/messaging');
  try {
    [appModule, messagingModule] = await Promise.all([
      import('firebase-admin/app'),
      import('firebase-admin/messaging')
    ]);
  } catch {
    throw new Error(
      'firebase-admin is not installed. Run `npm install firebase-admin` to enable real push delivery.'
    );
  }

  const existingApp = appModule.getApps().find((app) => app.name === firebaseAdminAppName);
  const app =
    existingApp ??
    appModule.initializeApp(
      { credential: appModule.cert(credentials) },
      firebaseAdminAppName
    );

  return messagingModule.getMessaging(app);
};

/**
 * Real FCM push sender backed by firebase-admin. Sends a single multicast
 * message to all of the user's device tokens. See the note above for how to
 * enable it in production.
 */
export const createFirebasePushSender = ({
  serviceAccountJson
}: {
  serviceAccountJson: string;
}): PushSender => {
  let messagingPromise: Promise<Messaging> | undefined;

  return {
    send: async ({ tokens, title, body, data }: PushMessage): Promise<PushSendResult> => {
      if (tokens.length === 0) {
        return { invalidTokens: [] };
      }

      messagingPromise ??= loadMessaging(serviceAccountJson).catch((error) => {
        messagingPromise = undefined;
        throw error;
      });
      const messaging = await messagingPromise;
      const result = await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body },
        data
      });

      return {
        invalidTokens: tokens.filter((_token, index) => {
          const response = result.responses[index];
          return response !== undefined && !response.success &&
            invalidTokenErrorCodes.has(response.error?.code ?? '');
        })
      };
    }
  };
};
