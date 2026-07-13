import type { DecodedIdToken } from 'firebase-admin/auth';

import type { AuthUser, FirebaseTokenVerifier } from './authTypes.js';
import type { FirebaseAdminAuth } from './firebaseAdminAuth.js';

const mapDecodedToken = (decoded: DecodedIdToken): AuthUser => {
  const authUser: AuthUser = {
    id: decoded.uid,
    provider: 'firebase',
    authenticatedAtSeconds: decoded.auth_time
  };

  if (decoded.email) {
    authUser.email = decoded.email;
  }

  if (decoded.name) {
    authUser.displayName = decoded.name;
  }

  if (decoded.phone_number) {
    authUser.phoneNumber = decoded.phone_number;
    authUser.phoneVerified = true;
  }

  return authUser;
};

const readErrorCode = (error: unknown) =>
  typeof error === 'object' &&
  error !== null &&
  'code' in error &&
  typeof error.code === 'string'
    ? error.code
    : undefined;

export const createFirebaseAdminTokenVerifier = (
  firebaseAuth: FirebaseAdminAuth,
  { allowDeletedIdentityRetry = false }: { allowDeletedIdentityRetry?: boolean } = {}
): FirebaseTokenVerifier => ({
  verifyIdToken: async (token) => {
    try {
      return mapDecodedToken(await firebaseAuth.verifyIdToken(token, true));
    } catch (error) {
      if (!allowDeletedIdentityRetry || readErrorCode(error) !== 'auth/user-not-found') {
        throw error;
      }

      const authUser = mapDecodedToken(await firebaseAuth.verifyIdToken(token, false));
      authUser.identityAlreadyDeleted = true;
      return authUser;
    }
  }
});
