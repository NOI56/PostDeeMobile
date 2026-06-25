import { generateKeyPairSync } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { StorePurchaseVerificationError } from './storePurchaseService.js';
import { createGoogleServiceAccountAccessTokenProvider } from './googleServiceAccountAccessTokenProvider.js';

const createServiceAccountKeyJson = () => {
  const { privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    privateKeyEncoding: {
      format: 'pem',
      type: 'pkcs8'
    },
    publicKeyEncoding: {
      format: 'pem',
      type: 'spki'
    }
  });

  return JSON.stringify({
    client_email: 'postdee-play-verifier@example.iam.gserviceaccount.com',
    private_key: privateKey,
    private_key_id: 'key-1',
    token_uri: 'https://oauth2.googleapis.com/token'
  });
};

const decodeJwtPayload = (assertion: string) => {
  const [, payload] = assertion.split('.');
  return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Record<
    string,
    unknown
  >;
};

describe('createGoogleServiceAccountAccessTokenProvider', () => {
  it('requests and caches an Android Publisher access token from a service account key', async () => {
    const requestedBodies: string[] = [];
    const provider = createGoogleServiceAccountAccessTokenProvider({
      serviceAccountKeyJson: createServiceAccountKeyJson(),
      fetchImpl: async (_url, init) => {
        requestedBodies.push(init.body);

        return {
          ok: true,
          status: 200,
          json: async () => ({
            access_token: 'google-play-access-token',
            expires_in: 3600
          })
        };
      },
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    await expect(provider()).resolves.toBe('google-play-access-token');
    await expect(provider()).resolves.toBe('google-play-access-token');

    expect(requestedBodies).toHaveLength(1);

    const tokenRequest = new URLSearchParams(requestedBodies[0]);
    expect(tokenRequest.get('grant_type')).toBe(
      'urn:ietf:params:oauth:grant-type:jwt-bearer'
    );

    const payload = decodeJwtPayload(tokenRequest.get('assertion') ?? '');
    expect(payload).toMatchObject({
      iss: 'postdee-play-verifier@example.iam.gserviceaccount.com',
      aud: 'https://oauth2.googleapis.com/token',
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      iat: 1780531200,
      exp: 1780534800
    });
  });

  it('rejects invalid service account JSON before calling Google OAuth', async () => {
    const provider = createGoogleServiceAccountAccessTokenProvider({
      serviceAccountKeyJson: '{"client_email":""}',
      fetchImpl: async () => {
        throw new Error('fetch should not be called');
      }
    });

    await expect(provider()).rejects.toMatchObject({
      statusCode: 501,
      code: 'GOOGLE_SERVICE_ACCOUNT_KEY_INVALID'
    } satisfies Partial<StorePurchaseVerificationError>);
  });
});
