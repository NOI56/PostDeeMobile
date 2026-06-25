import type { RequestHandler } from 'express';

import type { ServerConfig } from '../../config/env.js';
import type { AuthUser, FirebaseTokenVerifier } from './authTypes.js';

type AuthConfig = Pick<ServerConfig, 'authProvider' | 'mockUserId'>;

const readHeader = (value: string | string[] | undefined) => {
  if (Array.isArray(value)) {
    return value[0]?.trim();
  }

  return value?.trim();
};

const readBearerToken = (authorizationHeader: string | undefined) => {
  if (!authorizationHeader?.startsWith('Bearer ')) {
    return undefined;
  }

  const token = authorizationHeader.slice('Bearer '.length).trim();
  return token.length > 0 ? token : undefined;
};

const readSubscriptionPlan = (value: string | string[] | undefined) => {
  const plan = readHeader(value);
  return plan === 'BASIC' || plan === 'STARTER' || plan === 'PRO' ? plan : undefined;
};

const readBooleanHeader = (value: string | string[] | undefined) => {
  const header = readHeader(value)?.toLowerCase();
  return header === 'true' || header === '1' || header === 'yes';
};

const setAuthUser = (responseLocals: Record<string, unknown>, user: AuthUser) => {
  responseLocals.authUser = user;
};

export const createAuthMiddlewareFromConfig = ({
  config,
  firebaseVerifier
}: {
  config: AuthConfig;
  firebaseVerifier?: FirebaseTokenVerifier;
}): RequestHandler => {
  if (config.authProvider === 'firebase') {
    if (!firebaseVerifier) {
      throw new Error('Firebase auth requires a token verifier');
    }

    return async (request, response, next) => {
      const token = readBearerToken(readHeader(request.headers.authorization));

      if (!token) {
        response.status(401).json({
          status: 'error',
          message: 'Bearer token is required'
        });
        return;
      }

      try {
        setAuthUser(response.locals, await firebaseVerifier.verifyIdToken(token));
        next();
      } catch (_error) {
        response.status(401).json({
          status: 'error',
          message: 'Invalid Firebase ID token'
        });
      }
    };
  }

  return (request, response, next) => {
    const userId = readHeader(request.headers['x-postdee-user-id']) ?? config.mockUserId;
    const email = readHeader(request.headers['x-postdee-email']);
    const displayName = readHeader(request.headers['x-postdee-display-name']);
    const subscriptionPlan = readSubscriptionPlan(request.headers['x-postdee-subscription-plan']);
    const phoneNumber = readHeader(request.headers['x-postdee-phone-number']);
    const phoneVerified = readBooleanHeader(request.headers['x-postdee-phone-verified']);

    const authUser: AuthUser = {
      id: userId,
      provider: 'mock',
      email,
      displayName,
      subscriptionPlan
    };

    if (phoneNumber) {
      authUser.phoneNumber = phoneNumber;
    }

    if (phoneVerified) {
      authUser.phoneVerified = true;
    }

    setAuthUser(response.locals, authUser);
    next();
  };
};
