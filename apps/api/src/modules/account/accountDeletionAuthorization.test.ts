import type { DecodedIdToken } from 'firebase-admin/auth';
import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createFirebaseAdminTokenVerifier } from '../auth/firebaseAdminTokenVerifier.js';
import { createOwnerMutationLock } from './ownerMutationLock.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';

// The Admin SDK result is mocked. This checks the real verifier/route pipeline,
// not signature verification or whether Firebase actually returns this result.
describe('stale-token deletion without prior authorization (isolated fixture)', () => {
  afterEach(() => vi.restoreAllMocks());

  for (const missingIdentity of [false, true]) {
    it(`requires recent authentication for an ACTIVE owner (missing identity: ${missingIdentity})`, async () => {
      const userId = `fixture-active-owner-${missingIdentity}`;
      const now = new Date('2026-10-13T16:00:00.000Z');
      // Account routes use Date.now directly, not createApp's injected clock.
      vi.spyOn(Date, 'now').mockReturnValue(now.getTime());
      const nowSeconds = Math.floor(now.getTime() / 1000);
      const staleDecodedToken: DecodedIdToken = {
        uid: userId,
        sub: userId,
        aud: 'postdee-test',
        iss: 'https://securetoken.google.com/postdee-test',
        auth_time: nowSeconds - 30 * 60,
        iat: nowSeconds - 30 * 60,
        exp: nowSeconds + 10 * 60,
        firebase: { identities: {}, sign_in_provider: 'google.com' }
      };
      const verifyIdToken = vi.fn(async (_token: string, checkRevoked?: boolean) => {
        if (missingIdentity && checkRevoked) {
          throw Object.assign(new Error('dummy identity missing'), {
            code: 'auth/user-not-found'
          });
        }
        return staleDecodedToken;
      });
      const uploadSessionStore = createInMemoryUploadSessionStore();
      await uploadSessionStore.assertOwnerActive(userId);
      const beginDeletion = vi.spyOn(uploadSessionStore, 'beginOwnerDeletion');
      const deleteAllVideosForOwner = vi.fn(async () => undefined);
      const deleteIdentity = vi.fn(async () => undefined);
      const app = createApp({
        now: () => now,
        config: readServerConfig({
          AUTH_PROVIDER: 'firebase',
          FIREBASE_PROJECT_ID: 'postdee-test',
          FIREBASE_AUTH_DELETE_ENABLED: 'true'
        }),
        // This trusted fixture-only reader seeds/inspects retained dummy data.
        firebaseVerifier: {
          verifyIdToken: vi.fn(async () => ({
            id: userId,
            provider: 'firebase' as const,
            authenticatedAtSeconds: nowSeconds
          }))
        },
        accountDeletionFirebaseVerifier: createFirebaseAdminTokenVerifier(
          { verifyIdToken, deleteUser: vi.fn() },
          { allowDeletedIdentityRetry: true }
        ),
        uploadSessionStore,
        accountIdentityDeleter: { deleteIdentity },
        videoStorage: {
          supportsOwnerCleanup: true,
          createUpload: vi.fn(),
          createDownloadAccess: vi.fn(),
          deleteVideo: vi.fn(async () => undefined),
          deleteAllVideosForOwner
        }
      });
      await request(app)
        .post('/templates')
        .set('authorization', 'Bearer fixture-seed-token')
        .send({ title: 'Retained dummy resource', body: 'Not previously deleted' })
        .expect(201);
      const before = await request(app)
        .get('/templates')
        .set('authorization', 'Bearer fixture-reader-token')
        .expect(200);
      expect(before.body.templates).toHaveLength(1);
      await expect(uploadSessionStore.assertOwnerActive(userId)).resolves.toBeUndefined();
      expect(beginDeletion).not.toHaveBeenCalled();
      expect(deleteIdentity).not.toHaveBeenCalled();

      // First DELETE only: no readiness call, reauthentication, prior authorized
      // deletion or tombstone. Token is stale but its mocked expiry is future.
      const response = await request(app)
        .delete('/account')
        .set('authorization', 'Bearer fixture-stale-token');
      const after = await request(app)
        .get('/templates')
        .set('authorization', 'Bearer fixture-reader-token')
        .expect(200);
      console.log(JSON.stringify({
        fixture: 'active-owner-stale-token-no-prior-deletion',
        mockedMissingIdentity: missingIdentity,
        deleteStatus: response.status,
        retainedBefore: before.body.templates.length,
        retainedAfter: after.body.templates.length,
        cleanupCalls: deleteAllVideosForOwner.mock.calls.length
      }));
      if (missingIdentity) {
        expect(verifyIdToken).toHaveBeenNthCalledWith(1, 'fixture-stale-token', true);
        expect(verifyIdToken).toHaveBeenNthCalledWith(2, 'fixture-stale-token', false);
      }
      expect(response.status, 'A new deletion needs recent authentication or prior action-bound authorization').toBe(403);
      expect(after.body.templates).toHaveLength(1);
      expect(beginDeletion).not.toHaveBeenCalled();
      expect(deleteAllVideosForOwner).not.toHaveBeenCalled();
      expect(deleteIdentity).not.toHaveBeenCalled();
    });
  }
});

const createAuthorizationFixture = (userId = 'firebase-authorization-owner') => {
  const now = new Date('2026-10-14T00:00:00.000Z');
  vi.spyOn(Date, 'now').mockReturnValue(now.getTime());
  const nowSeconds = Math.floor(now.getTime() / 1000);
  let missingIdentity = false;
  let authAgeSeconds = 0;
  let identityError: string | undefined;
  const verifyIdToken = vi.fn(async (_token: string, checkRevoked?: boolean) => {
    if (identityError && checkRevoked) {
      throw Object.assign(new Error('dummy rejected credential'), { code: identityError });
    }
    if (missingIdentity && checkRevoked) {
      throw Object.assign(new Error('dummy identity missing'), { code: 'auth/user-not-found' });
    }
    return {
      uid: userId, sub: userId, aud: 'postdee-test',
      iss: 'https://securetoken.google.com/postdee-test',
      auth_time: nowSeconds - authAgeSeconds, iat: nowSeconds - authAgeSeconds,
      exp: nowSeconds + 600,
      firebase: { identities: {}, sign_in_provider: 'google.com' }
    };
  });
  const ownerStore = createInMemoryUploadSessionStore();
  const ownerMutationLock = createOwnerMutationLock();
  const deleteAllVideosForOwner = vi.fn(async () => undefined);
  const deleteIdentity = vi.fn(async () => undefined);
  const create = () => createApp({
    config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'postdee-test', FIREBASE_AUTH_DELETE_ENABLED: 'true' }),
    firebaseVerifier: { verifyIdToken: vi.fn(async () => ({ id: userId, provider: 'firebase' as const, authenticatedAtSeconds: nowSeconds })) },
    accountDeletionFirebaseVerifier: createFirebaseAdminTokenVerifier({ verifyIdToken, deleteUser: vi.fn() }, { allowDeletedIdentityRetry: true }),
    uploadSessionStore: ownerStore,
    ownerMutationLock,
    accountIdentityDeleter: { deleteIdentity },
    videoStorage: { supportsOwnerCleanup: true, createUpload: vi.fn(), createDownloadAccess: vi.fn(), deleteVideo: vi.fn(async () => undefined), deleteAllVideosForOwner }
  });
  const app = create();
  return { app, create, ownerStore, ownerMutationLock, now, deleteAllVideosForOwner, deleteIdentity,
    missing: () => { missingIdentity = true; },
    age: (seconds: number) => { authAgeSeconds = seconds; },
    credentialError: (code: string) => { identityError = code; },
    seed: () => request(app).post('/templates').set('authorization', 'Bearer fixture-reader').send({ title: 'Retained owner data', body: 'Keep until authorized' }).expect(201),
    templates: () => request(app).get('/templates').set('authorization', 'Bearer fixture-reader').expect(200),
    remove: () => request(app).delete('/account').set('authorization', 'Bearer fixture-action'),
    ready: () => request(app).get('/account/deletion-readiness').set('authorization', 'Bearer fixture-action')
  };
};

describe('account deletion authorization', () => {
  afterEach(() => vi.restoreAllMocks());

  it('does not treat a newly missing identity with a fresh token as prior authorization', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    fixture.missing();
    await fixture.remove().expect(403);
    expect((await fixture.templates()).body.templates).toHaveLength(1);
    expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
  });

  it('keeps ordinary readiness available before reauthentication without authorizing deletion', async () => {
    const fixture = createAuthorizationFixture();
    fixture.age(1800);
    await fixture.ready().expect(200, { status: 'ok', identityAlreadyDeleted: false });
    await expect(fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).resolves.toBeUndefined();
    await fixture.remove().expect(403);
  });

  it('rejects missing-identity readiness without a previous authorized action', async () => {
    const fixture = createAuthorizationFixture();
    fixture.missing();
    await fixture.ready().expect(403);
    expect(fixture.deleteIdentity).not.toHaveBeenCalled();
  });

  for (const status of ['DELETING', 'DELETED'] as const) {
    it(`does not upgrade a legacy ${status} marker into deletion authorization`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      await fixture.ownerStore.beginOwnerDeletion('firebase-authorization-owner');
      if (status === 'DELETED') await fixture.ownerStore.finishOwnerDeletion('firebase-authorization-owner');
      fixture.missing();
      fixture.age(1800);
      await fixture.ready().expect(403);
      await fixture.remove().expect(403);
      expect((await fixture.templates()).body.templates).toHaveLength(1);
      expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
    });
  }

  it('cannot use another UID authorization to delete retained data', async () => {
    const fixture = createAuthorizationFixture('firebase-owner-b');
    await fixture.seed();
    await fixture.ownerStore.authorizeOwnerDeletion('firebase-owner-a', fixture.now.toISOString());
    fixture.missing();
    fixture.age(1800);
    await fixture.remove().expect(403);
    expect((await fixture.templates()).body.templates).toHaveLength(1);
    expect(fixture.deleteIdentity).not.toHaveBeenCalled();
  });

  it('retains authorization across app reconstruction and missing-identity retry', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    await fixture.remove().expect(200);
    const proof = await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner');
    expect(proof).toBe(fixture.now.toISOString());
    fixture.missing();
    fixture.age(1800);
    const restartedApp = fixture.create();
    await request(restartedApp).get('/account/deletion-readiness').set('authorization', 'Bearer fixture-action').expect(200, { status: 'ok', identityAlreadyDeleted: true });
    await request(restartedApp).delete('/account').set('authorization', 'Bearer fixture-action').expect(200);
    expect(await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).toBe(proof);
  });

  it('allows an authorized stale retry after media cleanup fails while retaining original proof', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    fixture.deleteAllVideosForOwner.mockRejectedValueOnce(new Error('dummy media failure'));
    await fixture.remove().expect(503);
    const proof = await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner');
    expect(proof).toBe(fixture.now.toISOString());
    expect((await fixture.templates()).body.templates).toHaveLength(1);
    fixture.age(1800);
    await fixture.remove().expect(200);
    expect((await fixture.templates()).body.templates).toHaveLength(0);
    expect(await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).toBe(proof);
  });

  it('allows missing-identity cleanup to finish after a previously authorized identity deletion fails', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    fixture.deleteIdentity.mockRejectedValueOnce(new Error('dummy identity failure'));
    await fixture.remove().expect(503);
    const proof = await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner');
    expect(proof).toBe(fixture.now.toISOString());
    fixture.missing();
    fixture.age(1800);
    await fixture.ready().expect(200, { status: 'ok', identityAlreadyDeleted: true });
    await fixture.remove().expect(200);
    expect(await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).toBe(proof);
  });

  for (const badProof of ['not-a-date', '2026-10-14T00:01:01.000Z']) {
    it(`rejects invalid or future authorization: ${badProof}`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      vi.spyOn(fixture.ownerStore, 'getOwnerDeletionAuthorization').mockResolvedValue(badProof);
      fixture.missing();
      await fixture.remove().expect(403);
      expect((await fixture.templates()).body.templates).toHaveLength(1);
      expect(fixture.deleteIdentity).not.toHaveBeenCalled();
    });
  }

  for (const phase of ['read', 'write'] as const) {
    it(`fails closed before cleanup on authorization ${phase} storage failure`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      const markDeleting = vi.spyOn(fixture.ownerStore, 'beginOwnerDeletion');
      if (phase === 'read') vi.spyOn(fixture.ownerStore, 'getOwnerDeletionAuthorization').mockRejectedValue(new Error('dummy unavailable'));
      else vi.spyOn(fixture.ownerStore, 'authorizeOwnerDeletion').mockRejectedValue(new Error('dummy unavailable'));
      const response = await fixture.remove().expect(503);
      expect(response.body.code).toBe('ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE');
      expect(markDeleting).not.toHaveBeenCalled();
      expect((await fixture.templates()).body.templates).toHaveLength(1);
      expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
      await fixture.seed();
    });
  }

  it('does not persist authorization when cleanup capability is unavailable', async () => {
    const fixture = createAuthorizationFixture();
    const unavailableApp = createApp({
      config: readServerConfig({ AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'postdee-test', FIREBASE_AUTH_DELETE_ENABLED: 'false' }),
      firebaseVerifier: { verifyIdToken: vi.fn(async () => ({ id: 'firebase-authorization-owner', provider: 'firebase' as const, authenticatedAtSeconds: Math.floor(Date.now() / 1000) })) },
      uploadSessionStore: fixture.ownerStore
    });
    await request(unavailableApp).delete('/account').set('authorization', 'Bearer fixture-action').expect(503);
    await expect(fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).resolves.toBeUndefined();
  });

  for (const invalidAge of [Number.NaN, Number.NEGATIVE_INFINITY, -61]) {
    it(`requires a valid recent authentication timestamp: ${invalidAge}`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      fixture.age(invalidAge);
      await fixture.remove().expect(403);
      expect((await fixture.templates()).body.templates).toHaveLength(1);
      expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
    });
  }

  for (const missingMethod of ['getOwnerDeletionAuthorization', 'authorizeOwnerDeletion', 'beginOwnerDeletion', 'finishOwnerDeletion']) {
    it(`rejects unavailable authorization storage capability: ${missingMethod}`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      Reflect.deleteProperty(fixture.ownerStore, missingMethod);
      const readiness = await fixture.ready().expect(503);
      expect(readiness.body.code).toBe('ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE');
      await fixture.remove().expect(503);
      expect((await fixture.templates()).body.templates).toHaveLength(1);
      expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
    });
  }

  it('does not accept caller-supplied authorization or a different owner header', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    fixture.missing();
    await fixture.remove().set('x-postdee-user-id', 'another-owner')
      .send({ userId: 'another-owner', deletionAuthorizedAt: fixture.now.toISOString(), identityAlreadyDeleted: true }).expect(403);
    expect((await fixture.templates()).body.templates).toHaveLength(1);
    expect(fixture.deleteIdentity).not.toHaveBeenCalled();
  });

  it('rechecks recent authentication after waiting for an owner mutation', async () => {
    const fixture = createAuthorizationFixture();
    await fixture.seed();
    const releaseMutation = await fixture.ownerMutationLock.acquireMutation('firebase-authorization-owner');
    const lookup = vi.spyOn(fixture.ownerStore, 'getOwnerDeletionAuthorization');
    const pending = fixture.remove().then((response) => response);
    for (let attempts = 0; lookup.mock.calls.length === 0 && attempts < 100; attempts++) {
      await new Promise<void>((resolve) => setImmediate(resolve));
    }
    expect(lookup).toHaveBeenCalled();
    vi.spyOn(Date, 'now').mockReturnValue(fixture.now.getTime() + 6 * 60 * 1000);
    releaseMutation();
    expect((await pending).status).toBe(403);
    expect((await fixture.templates()).body.templates).toHaveLength(1);
    expect(fixture.deleteAllVideosForOwner).not.toHaveBeenCalled();
    await expect(fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).resolves.toBeUndefined();
  });

  for (const code of ['auth/id-token-revoked', 'auth/id-token-expired']) {
    it(`never replaces SDK credential validation with stored proof: ${code}`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.ownerStore.authorizeOwnerDeletion('firebase-authorization-owner', fixture.now.toISOString());
      fixture.credentialError(code);
      await fixture.ready().expect(401);
      await fixture.remove().expect(401);
      expect(fixture.deleteIdentity).not.toHaveBeenCalled();
    });
  }

  for (const authAge of [300, -60]) {
    it(`preserves the recent-authentication boundary: ${authAge}`, async () => {
      const fixture = createAuthorizationFixture();
      await fixture.seed();
      fixture.age(authAge);
      await fixture.remove().expect(200);
      expect(await fixture.ownerStore.getOwnerDeletionAuthorization('firebase-authorization-owner')).toBe(fixture.now.toISOString());
    });
  }
});
