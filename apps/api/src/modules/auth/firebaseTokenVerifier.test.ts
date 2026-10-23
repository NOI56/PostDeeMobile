import { createSign, generateKeyPairSync } from 'node:crypto';

import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  createFirebaseTokenVerifier,
  createFirebaseTokenVerifierFromConfig,
  type FirebaseCertificatesFetch
} from './firebaseTokenVerifier.js';

const projectId = 'postdee-test';
const keyId = 'test-key';
const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { format: 'pem', type: 'pkcs8' },
  publicKeyEncoding: { format: 'pem', type: 'spki' }
});

const toBase64UrlJson = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');

const signToken = (claims: Record<string, unknown>) => {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const unsignedToken = `${toBase64UrlJson({ alg: 'RS256', kid: keyId, typ: 'JWT' })}.${toBase64UrlJson({
    aud: projectId,
    exp: nowSeconds + 3600,
    iat: nowSeconds,
    iss: `https://securetoken.google.com/${projectId}`,
    sub: 'firebase-user-1',
    ...claims
  })}`;
  const signature = createSign('RSA-SHA256').update(unsignedToken).sign(privateKey).toString('base64url');
  return `${unsignedToken}.${signature}`;
};

const certificatesResponse = () => ({
  ok: true,
  headers: { get: (name: string) => (name === 'cache-control' ? 'public, max-age=3600' : null) },
  json: async () => ({ [keyId]: publicKey })
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

// User.email is globally unique, so only an address Firebase has verified for
// this UID may be stored; an unverified claim could squat another person's email.
describe('Firebase ID token email claim', () => {
  it('drops an email the token does not mark as verified', async () => {
    const verifier = createFirebaseTokenVerifier({ projectId, fetchCertificates: vi.fn(async () => certificatesResponse()) });

    const missing = await verifier.verifyIdToken(signToken({ email: 'victim@example.test' }));
    const unverified = await verifier.verifyIdToken(signToken({ email: 'victim@example.test', email_verified: false }));

    expect(missing.email).toBeUndefined();
    expect(unverified.email).toBeUndefined();
  });

  it('keeps an email the token marks as verified', async () => {
    const verifier = createFirebaseTokenVerifier({ projectId, fetchCertificates: vi.fn(async () => certificatesResponse()) });

    const authUser = await verifier.verifyIdToken(signToken({ email: 'seller@example.test', email_verified: true }));

    expect(authUser.email).toBe('seller@example.test');
  });
});

// Unsigned tokens reach loadCertificates before any signature check, so a cold
// or expired cache must not let concurrent requests multiply outbound fetches.
describe('Firebase certificate refresh', () => {
  it('shares one certificate fetch between concurrent cold verifications', async () => {
    let releaseFetch!: () => void;
    const fetchGate = new Promise<void>((release) => { releaseFetch = release; });
    const fetchCertificates = vi.fn<FirebaseCertificatesFetch>(async () => {
      await fetchGate;
      return certificatesResponse();
    });
    const verifier = createFirebaseTokenVerifier({ projectId, fetchCertificates });
    const token = signToken({});

    const verifications = Array.from({ length: 5 }, () => verifier.verifyIdToken(token));
    releaseFetch();
    await Promise.all(verifications);

    expect(fetchCertificates).toHaveBeenCalledTimes(1);
  });

  it('briefly reuses a failed refresh instead of refetching on every request', async () => {
    const startedAt = Date.now();
    const clock = vi.spyOn(Date, 'now').mockReturnValue(startedAt);
    const fetchCertificates = vi.fn<FirebaseCertificatesFetch>(async () => ({
      ok: false,
      headers: { get: () => null },
      json: async () => ({})
    }));
    const verifier = createFirebaseTokenVerifier({ projectId, fetchCertificates });
    const token = signToken({});

    await expect(verifier.verifyIdToken(token)).rejects.toThrow('Unable to fetch Firebase certificates');
    await expect(verifier.verifyIdToken(token)).rejects.toThrow('Unable to fetch Firebase certificates');
    expect(fetchCertificates).toHaveBeenCalledTimes(1);

    clock.mockReturnValue(startedAt + 60_000);
    await expect(verifier.verifyIdToken(token)).rejects.toThrow('Unable to fetch Firebase certificates');
    expect(fetchCertificates).toHaveBeenCalledTimes(2);
  });

  it('bounds the default certificate fetch with an abort timeout', async () => {
    const fetchSpy = vi.fn(async (_url: string, _init?: RequestInit) => new Response(JSON.stringify({ [keyId]: publicKey })));
    vi.stubGlobal('fetch', fetchSpy);
    const verifier = createFirebaseTokenVerifierFromConfig({
      config: { authProvider: 'firebase', firebaseProjectId: projectId }
    });

    await verifier?.verifyIdToken(signToken({}));

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(fetchSpy.mock.calls[0]?.[1]?.signal).toBeInstanceOf(AbortSignal);
  });
});
