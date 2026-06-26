import type { PushMessage, PushSender } from './pushSender.js';

// `firebase-admin` is an OPTIONAL runtime dependency. It is intentionally NOT in
// package.json yet: the project ships with the mock sender by default. To enable
// real push delivery, run `npm install firebase-admin`, set PUSH_SENDER=firebase
// and provide FIREBASE_SERVICE_ACCOUNT_JSON (a service account key, kept secret).
//
// We load it via a non-literal dynamic import so the build/test pipeline does not
// require the package to be installed. Everything here is typed loosely because
// the module's types are unavailable until it is installed.

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type FirebaseMessaging = any;

const firebaseAdminModuleName = 'firebase-admin';

let cachedMessaging: FirebaseMessaging | undefined;

const loadMessaging = async (
  serviceAccountJson: string
): Promise<FirebaseMessaging> => {
  if (cachedMessaging) {
    return cachedMessaging;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let adminModule: any;
  try {
    adminModule = await import(firebaseAdminModuleName);
  } catch {
    throw new Error(
      'firebase-admin is not installed. Run `npm install firebase-admin` to enable real push delivery.'
    );
  }

  const admin = adminModule.default ?? adminModule;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let credentials: any;
  try {
    credentials = JSON.parse(serviceAccountJson);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON');
  }

  const app =
    admin.apps && admin.apps.length > 0
      ? admin.app()
      : admin.initializeApp({ credential: admin.credential.cert(credentials) });

  cachedMessaging = admin.messaging(app);
  return cachedMessaging;
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
}): PushSender => ({
  send: async ({ tokens, title, body, data }: PushMessage) => {
    if (tokens.length === 0) {
      return;
    }

    const messaging = await loadMessaging(serviceAccountJson);
    await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data
    });
  }
});
