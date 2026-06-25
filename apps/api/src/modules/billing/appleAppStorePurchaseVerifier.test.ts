import { generateKeyPairSync } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { StorePurchaseVerificationError } from './storePurchaseService.js';
import { createAppleAppStorePurchaseVerifier } from './appleAppStorePurchaseVerifier.js';

const createPrivateKey = () => {
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'P-256',
    privateKeyEncoding: {
      format: 'pem',
      type: 'pkcs8'
    },
    publicKeyEncoding: {
      format: 'pem',
      type: 'spki'
    }
  });

  return privateKey;
};

const encodeJson = (value: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

const createSignedTransactionInfo = (payload: Record<string, unknown>) =>
  `${encodeJson({ alg: 'ES256', typ: 'JWT' })}.${encodeJson(payload)}.signature`;

const decodeSignedTransactionInfo = async (signedTransactionInfo: string) => {
  const [, payload] = signedTransactionInfo.split('.');
  return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Record<
    string,
    unknown
  >;
};

const decodeJwtPayload = (jwt: string) => {
  const [, payload] = jwt.split('.');
  return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Record<
    string,
    unknown
  >;
};

describe('createAppleAppStorePurchaseVerifier', () => {
  it('verifies an active App Store subscription through Get Transaction Info', async () => {
    const requestedUrls: string[] = [];
    const requestedAuthHeaders: string[] = [];
    const verifier = createAppleAppStorePurchaseVerifier({
      bundleId: 'com.postdee',
      issuerId: '57246542-96fe-1a63-e053-0824d011072a',
      keyId: '2X9R4HXF34',
      privateKey: createPrivateKey(),
      environment: 'sandbox',
      signedTransactionDecoder: decodeSignedTransactionInfo,
      fetchImpl: async (url, init) => {
        requestedUrls.push(url);
        requestedAuthHeaders.push(init.headers.Authorization);

        return {
          ok: true,
          status: 200,
          json: async () => ({
            signedTransactionInfo: createSignedTransactionInfo({
              transactionId: 'ios-transaction-id',
              originalTransactionId: 'ios-original-transaction-id',
              productId: 'postdee_pro_monthly',
              bundleId: 'com.postdee',
              expiresDate: Date.parse('2026-07-04T00:00:00.000Z')
            })
          })
        };
      },
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    const purchase = await verifier.verify({
      platform: 'IOS',
      productId: 'postdee_pro_monthly',
      transactionId: 'ios-transaction-id'
    });

    expect(requestedUrls).toEqual([
      'https://api.storekit-sandbox.apple.com/inApps/v1/transactions/ios-transaction-id'
    ]);
    expect(requestedAuthHeaders[0]).toMatch(/^Bearer /);

    const jwtPayload = decodeJwtPayload(requestedAuthHeaders[0].replace('Bearer ', ''));
    expect(jwtPayload).toMatchObject({
      iss: '57246542-96fe-1a63-e053-0824d011072a',
      aud: 'appstoreconnect-v1',
      bid: 'com.postdee',
      iat: 1780531200,
      exp: 1780532100
    });
    expect(purchase).toEqual({
      provider: 'apple-app-store',
      platform: 'IOS',
      productId: 'postdee_pro_monthly',
      transactionId: 'ios-transaction-id',
      originalTransactionId: 'ios-original-transaction-id',
      verifiedAt: '2026-06-04T00:00:00.000Z'
    });
  });

  it('rejects App Store transactions for another product id', async () => {
    const verifier = createAppleAppStorePurchaseVerifier({
      bundleId: 'com.postdee',
      issuerId: 'issuer-id',
      keyId: 'key-id',
      privateKey: createPrivateKey(),
      environment: 'production',
      signedTransactionDecoder: decodeSignedTransactionInfo,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          signedTransactionInfo: createSignedTransactionInfo({
            transactionId: 'ios-transaction-id',
            productId: 'other_product',
            bundleId: 'com.postdee',
            expiresDate: Date.parse('2026-07-04T00:00:00.000Z')
          })
        })
      }),
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    await expect(
      verifier.verify({
        platform: 'IOS',
        productId: 'postdee_pro_monthly',
        transactionId: 'ios-transaction-id'
      })
    ).rejects.toMatchObject({
      statusCode: 400,
      code: 'APPLE_PRODUCT_MISMATCH'
    } satisfies Partial<StorePurchaseVerificationError>);
  });

  it('rejects expired App Store subscriptions before Pro activation', async () => {
    const verifier = createAppleAppStorePurchaseVerifier({
      bundleId: 'com.postdee',
      issuerId: 'issuer-id',
      keyId: 'key-id',
      privateKey: createPrivateKey(),
      environment: 'production',
      signedTransactionDecoder: decodeSignedTransactionInfo,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          signedTransactionInfo: createSignedTransactionInfo({
            transactionId: 'ios-transaction-id',
            productId: 'postdee_pro_monthly',
            bundleId: 'com.postdee',
            expiresDate: Date.parse('2026-06-01T00:00:00.000Z')
          })
        })
      }),
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    await expect(
      verifier.verify({
        platform: 'IOS',
        productId: 'postdee_pro_monthly',
        transactionId: 'ios-transaction-id'
      })
    ).rejects.toMatchObject({
      statusCode: 402,
      code: 'APPLE_SUBSCRIPTION_EXPIRED'
    } satisfies Partial<StorePurchaseVerificationError>);
  });
});
