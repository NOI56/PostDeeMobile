import { createSign } from 'node:crypto';
import {
  Environment,
  SignedDataVerifier,
  VerificationException
} from '@apple/app-store-server-library';

import {
  StorePurchaseVerificationError,
  type StorePurchaseVerifier
} from './storePurchaseService.js';

const appleProductionBaseUrl = 'https://api.storekit.apple.com';
const appleSandboxBaseUrl = 'https://api.storekit-sandbox.apple.com';
const appStoreConnectAudience = 'appstoreconnect-v1';

export type AppleAppStoreEnvironment = 'production' | 'sandbox';

export type AppleAppStoreFetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

export type AppleAppStoreFetchImpl = (
  url: string,
  init: {
    method: 'GET';
    headers: {
      Accept: 'application/json';
      Authorization: string;
    };
  }
) => Promise<AppleAppStoreFetchResponse>;

type AppleTransactionInfoResponse = {
  signedTransactionInfo?: unknown;
};

export type AppleTransactionPayload = {
  transactionId?: unknown;
  originalTransactionId?: unknown;
  productId?: unknown;
  bundleId?: unknown;
  expiresDate?: unknown;
};

export type AppleSignedTransactionInfoDecoder = (
  signedTransactionInfo: string
) => Promise<AppleTransactionPayload>;

const encodeBase64UrlJson = (value: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

const readTransactionResponse = (body: unknown): AppleTransactionInfoResponse =>
  body && typeof body === 'object' ? (body as AppleTransactionInfoResponse) : {};

const readSignedTransactionInfo = (signedTransactionInfo: unknown) => {
  if (typeof signedTransactionInfo !== 'string') {
    throw new StorePurchaseVerificationError({
      statusCode: 502,
      code: 'APPLE_SIGNED_TRANSACTION_MISSING',
      message: 'Apple transaction response is missing signedTransactionInfo'
    });
  }

  return signedTransactionInfo;
};

const createAppStoreServerJwt = ({
  bundleId,
  issuerId,
  keyId,
  privateKey,
  now
}: {
  bundleId: string;
  issuerId: string;
  keyId: string;
  privateKey: string;
  now: Date;
}) => {
  const issuedAtSeconds = Math.floor(now.getTime() / 1000);
  const expiresAtSeconds = issuedAtSeconds + 900;
  const header = encodeBase64UrlJson({
    alg: 'ES256',
    kid: keyId,
    typ: 'JWT'
  });
  const payload = encodeBase64UrlJson({
    iss: issuerId,
    iat: issuedAtSeconds,
    exp: expiresAtSeconds,
    aud: appStoreConnectAudience,
    bid: bundleId
  });
  const unsignedJwt = `${header}.${payload}`;
  const signature = createSign('SHA256')
    .update(unsignedJwt)
    .end()
    .sign(
      {
        key: privateKey,
        dsaEncoding: 'ieee-p1363'
      },
      'base64url'
    );

  return `${unsignedJwt}.${signature}`;
};

const baseUrlForEnvironment = (environment: AppleAppStoreEnvironment) =>
  environment === 'sandbox' ? appleSandboxBaseUrl : appleProductionBaseUrl;

const appleLibraryEnvironment = (environment: AppleAppStoreEnvironment) =>
  environment === 'sandbox' ? Environment.SANDBOX : Environment.PRODUCTION;

const parseRootCertificatesBase64 = (rootCertificatesBase64: string) => {
  const rootCertificates = rootCertificatesBase64
    .split(',')
    .map((certificate) => certificate.trim())
    .filter((certificate) => certificate.length > 0)
    .map((certificate) => Buffer.from(certificate, 'base64'));

  if (rootCertificates.length === 0) {
    throw new StorePurchaseVerificationError({
      statusCode: 501,
      code: 'APPLE_ROOT_CERTIFICATES_NOT_CONFIGURED',
      message: 'Apple root certificates are not configured'
    });
  }

  return rootCertificates;
};

export const createAppleSignedTransactionInfoDecoder = ({
  bundleId,
  environment,
  rootCertificatesBase64,
  appAppleId,
  enableOnlineChecks = true
}: {
  bundleId: string;
  environment: AppleAppStoreEnvironment;
  rootCertificatesBase64: string;
  appAppleId?: number;
  enableOnlineChecks?: boolean;
}): AppleSignedTransactionInfoDecoder => {
  const verifier = new SignedDataVerifier(
    parseRootCertificatesBase64(rootCertificatesBase64),
    enableOnlineChecks,
    appleLibraryEnvironment(environment),
    bundleId,
    appAppleId
  );

  return async (signedTransactionInfo) => {
    try {
      return await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
    } catch (error) {
      if (error instanceof VerificationException) {
        throw new StorePurchaseVerificationError({
          statusCode: 502,
          code: 'APPLE_SIGNED_TRANSACTION_VERIFICATION_FAILED',
          message: `Apple signed transaction verification failed: ${error.status}`
        });
      }

      throw error;
    }
  };
};

export const createAppleAppStorePurchaseVerifier = ({
  bundleId,
  issuerId,
  keyId,
  privateKey,
  environment,
  signedTransactionDecoder,
  fetchImpl = fetch as AppleAppStoreFetchImpl,
  now = () => new Date()
}: {
  bundleId: string;
  issuerId: string;
  keyId: string;
  privateKey: string;
  environment: AppleAppStoreEnvironment;
  signedTransactionDecoder: AppleSignedTransactionInfoDecoder;
  fetchImpl?: AppleAppStoreFetchImpl;
  now?: () => Date;
}): StorePurchaseVerifier => ({
  verify: async (purchase) => {
    if (purchase.platform !== 'IOS') {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'APPLE_IOS_ONLY',
        message: 'Apple App Store verifier only supports iOS purchases'
      });
    }

    if (!purchase.transactionId) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'APPLE_TRANSACTION_ID_REQUIRED',
        message: 'Apple App Store transaction id is required'
      });
    }

    const currentTime = now();
    const token = createAppStoreServerJwt({
      bundleId,
      issuerId,
      keyId,
      privateKey,
      now: currentTime
    });
    const url = `${baseUrlForEnvironment(environment)}/inApps/v1/transactions/${encodeURIComponent(
      purchase.transactionId
    )}`;
    const response = await fetchImpl(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`
      }
    });

    if (!response.ok) {
      throw new StorePurchaseVerificationError({
        statusCode: 502,
        code: 'APPLE_VERIFICATION_FAILED',
        message: `Apple App Store verification failed with status ${response.status ?? 'unknown'}`
      });
    }

    const body = readTransactionResponse(await response.json());
    const signedTransactionInfo = readSignedTransactionInfo(body.signedTransactionInfo);
    const transaction = await signedTransactionDecoder(signedTransactionInfo);

    if (transaction.transactionId !== purchase.transactionId) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'APPLE_TRANSACTION_ID_MISMATCH',
        message: 'Apple transaction id does not match the requested transaction'
      });
    }

    if (transaction.bundleId !== bundleId) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'APPLE_BUNDLE_ID_MISMATCH',
        message: 'Apple transaction bundle id does not match this app'
      });
    }

    if (transaction.productId !== purchase.productId) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'APPLE_PRODUCT_MISMATCH',
        message: 'Apple transaction product does not match the requested product'
      });
    }

    const expiresDate =
      typeof transaction.expiresDate === 'number' && Number.isFinite(transaction.expiresDate)
        ? transaction.expiresDate
        : Number.NaN;

    if (!Number.isFinite(expiresDate) || expiresDate <= currentTime.getTime()) {
      throw new StorePurchaseVerificationError({
        statusCode: 402,
        code: 'APPLE_SUBSCRIPTION_EXPIRED',
        message: 'Apple App Store subscription is expired'
      });
    }

    return {
      provider: 'apple-app-store',
      platform: 'IOS',
      productId: purchase.productId,
      transactionId: purchase.transactionId,
      originalTransactionId:
        typeof transaction.originalTransactionId === 'string'
          ? transaction.originalTransactionId
          : undefined,
      verifiedAt: currentTime.toISOString()
    };
  }
});
