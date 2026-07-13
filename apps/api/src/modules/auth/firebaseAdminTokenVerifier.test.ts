import { describe, expect, it, vi } from 'vitest';

import { createFirebaseAdminTokenVerifier } from './firebaseAdminTokenVerifier.js';

describe('createFirebaseAdminTokenVerifier', () => {
  it('checks revocation and maps the Firebase identity to AuthUser', async () => {
    const verifyIdToken = vi.fn(async () => ({
      uid: 'firebase-user-1',
      aud: 'postdee-test',
      auth_time: 1,
      exp: 2,
      firebase: { identities: {}, sign_in_provider: 'google.com' },
      iat: 1,
      iss: 'https://securetoken.google.com/postdee-test',
      sub: 'firebase-user-1',
      email: 'seller@example.com',
      name: 'PostDee Seller',
      phone_number: '+66812345678'
    }));
    const verifier = createFirebaseAdminTokenVerifier({
      verifyIdToken,
      deleteUser: vi.fn()
    });

    await expect(verifier.verifyIdToken('firebase-token')).resolves.toEqual({
      id: 'firebase-user-1',
      provider: 'firebase',
      authenticatedAtSeconds: 1,
      email: 'seller@example.com',
      displayName: 'PostDee Seller',
      phoneNumber: '+66812345678',
      phoneVerified: true
    });
    expect(verifyIdToken).toHaveBeenCalledWith('firebase-token', true);
  });

  it('rejects deleted or revoked Firebase users', async () => {
    const verifier = createFirebaseAdminTokenVerifier({
      verifyIdToken: vi.fn(async () => {
        throw Object.assign(new Error('revoked'), { code: 'auth/id-token-revoked' });
      }),
      deleteUser: vi.fn()
    });

    await expect(verifier.verifyIdToken('revoked-token')).rejects.toThrow('revoked');
  });

  it('allows only a deleted identity to retry the account-deletion route', async () => {
    const decodedToken = {
      uid: 'deleted-firebase-user',
      aud: 'postdee-test',
      auth_time: 123,
      exp: 456,
      firebase: { identities: {}, sign_in_provider: 'google.com' },
      iat: 123,
      iss: 'https://securetoken.google.com/postdee-test',
      sub: 'deleted-firebase-user'
    };
    const verifyIdToken = vi
      .fn()
      .mockRejectedValueOnce(
        Object.assign(new Error('user missing'), { code: 'auth/user-not-found' })
      )
      .mockResolvedValueOnce(decodedToken);
    const verifier = createFirebaseAdminTokenVerifier(
      { verifyIdToken, deleteUser: vi.fn() },
      { allowDeletedIdentityRetry: true }
    );

    await expect(verifier.verifyIdToken('deleted-user-token')).resolves.toEqual({
      id: 'deleted-firebase-user',
      provider: 'firebase',
      authenticatedAtSeconds: 123,
      identityAlreadyDeleted: true
    });
    expect(verifyIdToken).toHaveBeenNthCalledWith(1, 'deleted-user-token', true);
    expect(verifyIdToken).toHaveBeenNthCalledWith(2, 'deleted-user-token', false);
  });

  it('does not let a revoked token use the deleted-identity retry path', async () => {
    const verifyIdToken = vi.fn(async () => {
      throw Object.assign(new Error('revoked'), { code: 'auth/id-token-revoked' });
    });
    const verifier = createFirebaseAdminTokenVerifier(
      { verifyIdToken, deleteUser: vi.fn() },
      { allowDeletedIdentityRetry: true }
    );

    await expect(verifier.verifyIdToken('revoked-token')).rejects.toThrow('revoked');
    expect(verifyIdToken).toHaveBeenCalledTimes(1);
  });
});
