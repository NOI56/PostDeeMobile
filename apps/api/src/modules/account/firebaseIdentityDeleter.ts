import type { ServerConfig } from '../../config/env.js';
import type { AuthUser } from '../auth/authTypes.js';
import {
  createFirebaseAdminAuth,
  parseFirebaseServiceAccountJson,
  type FirebaseAdminAuth
} from '../auth/firebaseAdminAuth.js';

type FirebaseIdentityDeleteConfig = Pick<
  ServerConfig,
  'authProvider' | 'firebaseAuthDeleteEnabled' | 'firebaseServiceAccountJson'
>;

export type AccountIdentityDeleter = {
  deleteIdentity: (authUser: AuthUser) => Promise<void>;
};

const readErrorCode = (error: unknown) =>
  typeof error === 'object' &&
  error !== null &&
  'code' in error &&
  typeof error.code === 'string'
    ? error.code
    : undefined;

export const createFirebaseIdentityDeleterFromConfig = ({
  config,
  firebaseAuth
}: {
  config: FirebaseIdentityDeleteConfig;
  firebaseAuth?: Pick<FirebaseAdminAuth, 'deleteUser'>;
}): AccountIdentityDeleter | undefined => {
  if (!config.firebaseAuthDeleteEnabled) {
    return undefined;
  }

  if (config.authProvider !== 'firebase') {
    throw new Error(
      'AUTH_PROVIDER=firebase is required when FIREBASE_AUTH_DELETE_ENABLED=true'
    );
  }

  if (!config.firebaseServiceAccountJson) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON is required when FIREBASE_AUTH_DELETE_ENABLED=true'
    );
  }

  parseFirebaseServiceAccountJson(config.firebaseServiceAccountJson);
  const configuredAuth =
    firebaseAuth ??
    createFirebaseAdminAuth({
      serviceAccountJson: config.firebaseServiceAccountJson
    });

  return {
    deleteIdentity: async (authUser) => {
      try {
        await configuredAuth.deleteUser(authUser.id);
      } catch (error) {
        if (readErrorCode(error) === 'auth/user-not-found') {
          return;
        }

        throw error;
      }
    }
  };
};
