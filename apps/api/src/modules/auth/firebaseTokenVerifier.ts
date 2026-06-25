import { createVerify } from 'node:crypto';

import type { ServerConfig } from '../../config/env.js';
import type { AuthUser, FirebaseTokenVerifier } from './authTypes.js';

const FIREBASE_CERTIFICATES_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
const DEFAULT_CERTIFICATE_CACHE_MS = 300_000;
const MAX_SUBJECT_LENGTH = 128;

export type FirebaseCertificatesResponse = {
  ok: boolean;
  headers: {
    get: (name: string) => string | null;
  };
  json: () => Promise<unknown>;
};

export type FirebaseCertificatesFetch = (url: string) => Promise<FirebaseCertificatesResponse>;

type FirebaseVerifierConfig = Pick<ServerConfig, 'authProvider' | 'firebaseProjectId'>;

type JwtHeader = {
  alg?: unknown;
  kid?: unknown;
};

type FirebaseTokenPayload = {
  aud?: unknown;
  email?: unknown;
  exp?: unknown;
  iat?: unknown;
  iss?: unknown;
  name?: unknown;
  phone_number?: unknown;
  sub?: unknown;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const decodeJsonSegment = <T>(segment: string) => {
  try {
    return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8')) as T;
  } catch (_error) {
    throw new Error('Invalid Firebase ID token');
  }
};

const readCertificateCacheMilliseconds = (cacheControl: string | null) => {
  const maxAgeMatch = cacheControl?.match(/max-age=(\d+)/i);

  if (!maxAgeMatch) {
    return DEFAULT_CERTIFICATE_CACHE_MS;
  }

  const maxAgeSeconds = Number(maxAgeMatch[1]);
  return Number.isInteger(maxAgeSeconds) && maxAgeSeconds > 0
    ? maxAgeSeconds * 1000
    : DEFAULT_CERTIFICATE_CACHE_MS;
};

const readCertificates = async (fetchCertificates: FirebaseCertificatesFetch) => {
  const response = await fetchCertificates(FIREBASE_CERTIFICATES_URL);

  if (!response.ok) {
    throw new Error('Unable to fetch Firebase certificates');
  }

  const body = await response.json();

  if (!isRecord(body)) {
    throw new Error('Firebase certificates response must be an object');
  }

  const certificates = Object.fromEntries(
    Object.entries(body).filter(
      (entry): entry is [string, string] =>
        typeof entry[0] === 'string' && typeof entry[1] === 'string' && entry[1].trim().length > 0
    )
  );

  if (Object.keys(certificates).length === 0) {
    throw new Error('Firebase certificates response did not include certificates');
  }

  return {
    certificates,
    cacheMilliseconds: readCertificateCacheMilliseconds(response.headers.get('cache-control'))
  };
};

const validatePayload = ({
  payload,
  projectId,
  nowSeconds
}: {
  payload: FirebaseTokenPayload;
  projectId: string;
  nowSeconds: number;
}) => {
  if (payload.aud !== projectId) {
    throw new Error('Firebase ID token audience does not match the configured project');
  }

  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error('Firebase ID token issuer does not match the configured project');
  }

  if (typeof payload.exp !== 'number' || payload.exp <= nowSeconds) {
    throw new Error('Firebase ID token is expired');
  }

  if (typeof payload.iat !== 'number' || payload.iat > nowSeconds) {
    throw new Error('Firebase ID token issued-at time is invalid');
  }

  if (
    typeof payload.sub !== 'string' ||
    payload.sub.length === 0 ||
    payload.sub.length > MAX_SUBJECT_LENGTH
  ) {
    throw new Error('Firebase ID token subject is invalid');
  }

  return payload.sub;
};

export const createFirebaseTokenVerifier = ({
  projectId,
  fetchCertificates
}: {
  projectId: string;
  fetchCertificates: FirebaseCertificatesFetch;
}): FirebaseTokenVerifier => {
  let certificateCache:
    | {
        certificates: Record<string, string>;
        expiresAt: number;
      }
    | undefined;

  const loadCertificates = async () => {
    const now = Date.now();

    if (certificateCache && certificateCache.expiresAt > now) {
      return certificateCache.certificates;
    }

    const { certificates, cacheMilliseconds } = await readCertificates(fetchCertificates);
    certificateCache = {
      certificates,
      expiresAt: now + cacheMilliseconds
    };

    return certificates;
  };

  return {
    verifyIdToken: async (token: string): Promise<AuthUser> => {
      const [encodedHeader, encodedPayload, encodedSignature, extraSegment] = token.split('.');

      if (!encodedHeader || !encodedPayload || !encodedSignature || extraSegment) {
        throw new Error('Invalid Firebase ID token');
      }

      const header = decodeJsonSegment<JwtHeader>(encodedHeader);

      if (header.alg !== 'RS256' || typeof header.kid !== 'string' || header.kid.length === 0) {
        throw new Error('Invalid Firebase ID token header');
      }

      const certificates = await loadCertificates();
      const certificate = certificates[header.kid];

      if (!certificate) {
        throw new Error('Firebase certificate is not available for the token key');
      }

      const verifier = createVerify('RSA-SHA256');
      verifier.update(`${encodedHeader}.${encodedPayload}`);
      verifier.end();

      if (!verifier.verify(certificate, Buffer.from(encodedSignature, 'base64url'))) {
        throw new Error('Firebase ID token signature is invalid');
      }

      const payload = decodeJsonSegment<FirebaseTokenPayload>(encodedPayload);
      const userId = validatePayload({
        payload,
        projectId,
        nowSeconds: Math.floor(Date.now() / 1000)
      });
      const authUser: AuthUser = {
        id: userId,
        provider: 'firebase'
      };

      if (typeof payload.email === 'string' && payload.email.length > 0) {
        authUser.email = payload.email;
      }

      if (typeof payload.name === 'string' && payload.name.length > 0) {
        authUser.displayName = payload.name;
      }

      if (typeof payload.phone_number === 'string' && payload.phone_number.length > 0) {
        authUser.phoneNumber = payload.phone_number;
        authUser.phoneVerified = true;
      }

      return authUser;
    }
  };
};

export const createFirebaseTokenVerifierFromConfig = ({
  config,
  fetchCertificates
}: {
  config: FirebaseVerifierConfig;
  fetchCertificates?: FirebaseCertificatesFetch;
}) => {
  if (config.authProvider !== 'firebase') {
    return undefined;
  }

  if (!config.firebaseProjectId) {
    throw new Error('FIREBASE_PROJECT_ID is required when AUTH_PROVIDER=firebase');
  }

  const configuredFetch =
    fetchCertificates ??
    (typeof globalThis.fetch === 'function'
      ? ((url: string) => globalThis.fetch(url) as Promise<FirebaseCertificatesResponse>)
      : undefined);

  if (!configuredFetch) {
    throw new Error('Firebase auth requires a fetch implementation');
  }

  return createFirebaseTokenVerifier({
    projectId: config.firebaseProjectId,
    fetchCertificates: configuredFetch
  });
};
