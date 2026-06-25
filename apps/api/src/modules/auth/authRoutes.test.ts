import { createSign, generateKeyPairSync } from 'node:crypto';

import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

const toBase64UrlJson = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');

const createSignedFirebaseToken = ({
  keyId,
  privateKey,
  projectId,
  phoneNumber,
  subject
}: {
  keyId: string;
  privateKey: string;
  projectId: string;
  phoneNumber?: string;
  subject: string;
}) => {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = toBase64UrlJson({
    alg: 'RS256',
    kid: keyId,
    typ: 'JWT'
  });
  const payload = toBase64UrlJson({
    aud: projectId,
    email: 'seller@example.com',
    exp: nowSeconds + 3600,
    iat: nowSeconds,
    iss: `https://securetoken.google.com/${projectId}`,
    name: 'Firebase Seller',
    ...(phoneNumber ? { phone_number: phoneNumber } : {}),
    sub: subject
  });
  const unsignedToken = `${header}.${payload}`;
  const signature = createSign('RSA-SHA256').update(unsignedToken).sign(privateKey).toString('base64url');

  return `${unsignedToken}.${signature}`;
};

describe('auth routes', () => {
  it('returns the current mock user from the app router', async () => {
    const app = createApp();

    const response = await request(app)
      .get('/auth/me')
      .set('x-postdee-user-id', 'seller-1')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'seller-1',
        provider: 'mock'
      }
    });
  });

  it('returns the current Firebase user from the app router', async () => {
    const firebaseVerifier = {
      verifyIdToken: vi.fn(async () => ({
        id: 'firebase-user-1',
        provider: 'firebase' as const,
        email: 'seller@example.com'
      }))
    };
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase'
      }),
      firebaseVerifier
    });

    const response = await request(app)
      .get('/auth/me')
      .set('Authorization', 'Bearer firebase-token')
      .expect(200);

    expect(firebaseVerifier.verifyIdToken).toHaveBeenCalledWith('firebase-token');
    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'firebase-user-1',
        provider: 'firebase',
        email: 'seller@example.com'
      }
    });
  });

  it('verifies Firebase ID tokens using the configured Firebase project', async () => {
    const projectId = 'postdee-test';
    const keyId = 'firebase-test-key';
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
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
    const firebaseToken = createSignedFirebaseToken({
      keyId,
      privateKey,
      projectId,
      subject: 'firebase-user-2'
    });
    const firebaseCertsFetch = vi.fn(async () => ({
      ok: true,
      headers: {
        get: (name: string) => (name.toLowerCase() === 'cache-control' ? 'public, max-age=3600' : null)
      },
      json: async () => ({
        [keyId]: publicKey
      })
    }));
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: projectId
      }),
      firebaseCertsFetch
    });

    const response = await request(app)
      .get('/auth/me')
      .set('Authorization', `Bearer ${firebaseToken}`)
      .expect(200);

    expect(firebaseCertsFetch).toHaveBeenCalledWith(
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com'
    );
    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'firebase-user-2',
        provider: 'firebase',
        email: 'seller@example.com',
        displayName: 'Firebase Seller'
      }
    });
  });

  it('marks Firebase users as phone verified when the token includes a phone number', async () => {
    const projectId = 'postdee-test';
    const keyId = 'firebase-test-key';
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
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
    const firebaseToken = createSignedFirebaseToken({
      keyId,
      privateKey,
      projectId,
      phoneNumber: '+66812345678',
      subject: 'firebase-phone-user'
    });
    const firebaseCertsFetch = vi.fn(async () => ({
      ok: true,
      headers: {
        get: (name: string) => (name.toLowerCase() === 'cache-control' ? 'public, max-age=3600' : null)
      },
      json: async () => ({
        [keyId]: publicKey
      })
    }));
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: projectId
      }),
      firebaseCertsFetch
    });

    const response = await request(app)
      .get('/auth/me')
      .set('Authorization', `Bearer ${firebaseToken}`)
      .expect(200);

    expect(response.body.user).toMatchObject({
      id: 'firebase-phone-user',
      provider: 'firebase',
      phoneNumber: '+66812345678',
      phoneVerified: true
    });
  });
});
