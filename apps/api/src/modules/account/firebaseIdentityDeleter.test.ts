import { describe, expect, it, vi } from 'vitest';

import type { AuthUser } from '../auth/authTypes.js';
import { createFirebaseIdentityDeleterFromConfig } from './firebaseIdentityDeleter.js';

const firebaseUser: AuthUser = {
  id: 'firebase-user-1',
  provider: 'firebase'
};

describe('createFirebaseIdentityDeleterFromConfig', () => {
  it('is disabled unless account identity deletion is explicitly enabled', () => {
    expect(
      createFirebaseIdentityDeleterFromConfig({
        config: {
          authProvider: 'firebase',
          firebaseAuthDeleteEnabled: false,
          firebaseServiceAccountJson: undefined
        }
      })
    ).toBeUndefined();
  });

  it('deletes the authenticated Firebase UID', async () => {
    const deleteUser = vi.fn(async () => undefined);
    const deleter = createFirebaseIdentityDeleterFromConfig({
      config: {
        authProvider: 'firebase',
        firebaseAuthDeleteEnabled: true,
        firebaseServiceAccountJson: '{"project_id":"postdee-test"}'
      },
      firebaseAuth: { deleteUser }
    });

    await deleter?.deleteIdentity(firebaseUser);

    expect(deleteUser).toHaveBeenCalledWith(firebaseUser.id);
  });

  it('treats an already-deleted Firebase user as a successful retry', async () => {
    const deleteUser = vi.fn(async () => {
      throw Object.assign(new Error('missing'), { code: 'auth/user-not-found' });
    });
    const deleter = createFirebaseIdentityDeleterFromConfig({
      config: {
        authProvider: 'firebase',
        firebaseAuthDeleteEnabled: true,
        firebaseServiceAccountJson: '{"project_id":"postdee-test"}'
      },
      firebaseAuth: { deleteUser }
    });

    await expect(deleter?.deleteIdentity(firebaseUser)).resolves.toBeUndefined();
  });

  it('does not hide other Firebase Admin failures', async () => {
    const deleteUser = vi.fn(async () => {
      throw Object.assign(new Error('unavailable'), { code: 'auth/internal-error' });
    });
    const deleter = createFirebaseIdentityDeleterFromConfig({
      config: {
        authProvider: 'firebase',
        firebaseAuthDeleteEnabled: true,
        firebaseServiceAccountJson: '{"project_id":"postdee-test"}'
      },
      firebaseAuth: { deleteUser }
    });

    await expect(deleter?.deleteIdentity(firebaseUser)).rejects.toThrow('unavailable');
  });

  it('rejects unsafe enabled configurations before serving requests', () => {
    expect(() =>
      createFirebaseIdentityDeleterFromConfig({
        config: {
          authProvider: 'mock',
          firebaseAuthDeleteEnabled: true,
          firebaseServiceAccountJson: '{"project_id":"postdee-test"}'
        }
      })
    ).toThrow('AUTH_PROVIDER=firebase');

    expect(() =>
      createFirebaseIdentityDeleterFromConfig({
        config: {
          authProvider: 'firebase',
          firebaseAuthDeleteEnabled: true,
          firebaseServiceAccountJson: undefined
        }
      })
    ).toThrow('FIREBASE_SERVICE_ACCOUNT_JSON');

    expect(() =>
      createFirebaseIdentityDeleterFromConfig({
        config: {
          authProvider: 'firebase',
          firebaseAuthDeleteEnabled: true,
          firebaseServiceAccountJson: 'not-json'
        }
      })
    ).toThrow('valid JSON');
  });
});
