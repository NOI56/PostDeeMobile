import { cert, getApp, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';

const firebaseAdminAppName = 'postdee-backend';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const parseFirebaseServiceAccountJson = (serviceAccountJson: string) => {
  let serviceAccount: unknown;

  try {
    serviceAccount = JSON.parse(serviceAccountJson);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be valid JSON');
  }

  if (!isRecord(serviceAccount)) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be a JSON object');
  }

  return serviceAccount;
};

export type FirebaseAdminAuth = Pick<Auth, 'deleteUser' | 'verifyIdToken'>;

export const createFirebaseAdminAuth = ({
  serviceAccountJson
}: {
  serviceAccountJson: string;
}): FirebaseAdminAuth => {
  const serviceAccount = parseFirebaseServiceAccountJson(serviceAccountJson);
  const existingApp = getApps().find((app) => app.name === firebaseAdminAppName);
  const app =
    existingApp ??
    initializeApp(
      {
        credential: cert(serviceAccount)
      },
      firebaseAdminAppName
    );

  return getAuth(existingApp ? getApp(firebaseAdminAppName) : app);
};
