import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

const adminAuth = vi.hoisted(() => ({
  verifyIdToken: vi.fn(async () => ({ uid: 'firebase-seller', auth_time: 1 })),
  deleteUser: vi.fn()
}));

vi.mock('./modules/auth/firebaseAdminAuth.js', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./modules/auth/firebaseAdminAuth.js')>()),
  createFirebaseAdminAuth: () => adminAuth
}));

const { createApp } = await import('./app.js');
const { readServerConfig } = await import('./config/env.js');

describe('Firebase token revocation', () => {
  it('checks revoked tokens whenever a service account is configured', async () => {
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-test',
        FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"postdee-test"}',
        FIREBASE_AUTH_DELETE_ENABLED: 'false'
      })
    });

    await request(app)
      .get('/auth/me')
      .set('Authorization', 'Bearer firebase-token')
      .expect(200);

    expect(adminAuth.verifyIdToken).toHaveBeenCalledWith('firebase-token', true);
  });
});
