import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createAuthMiddlewareFromConfig } from './authMiddlewareFactory.js';
import { registerAuthRoutes } from './authRoutes.js';

const createTestApp = (...middleware: express.RequestHandler[]) => {
  const app = express();
  const router = express.Router();

  registerAuthRoutes(router, ...middleware);
  app.use(router);

  return app;
};

describe('auth middleware', () => {
  it('uses a safe mock user by default', async () => {
    const authMiddleware = createAuthMiddlewareFromConfig({
      config: {
        authProvider: 'mock',
        mockUserId: 'local-dev-user'
      }
    });
    const app = createTestApp(authMiddleware);

    const response = await request(app).get('/auth/me').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'local-dev-user',
        provider: 'mock'
      }
    });
  });

  it('allows mock user details to be overridden by development headers', async () => {
    const authMiddleware = createAuthMiddlewareFromConfig({
      config: {
        authProvider: 'mock',
        mockUserId: 'local-dev-user'
      }
    });
    const app = createTestApp(authMiddleware);

    const response = await request(app)
      .get('/auth/me')
      .set('x-postdee-user-id', 'seller-1')
      .set('x-postdee-email', 'seller@example.com')
      .set('x-postdee-display-name', 'PostDee Seller')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'seller-1',
        provider: 'mock',
        email: 'seller@example.com',
        displayName: 'PostDee Seller'
      }
    });
  });

  it('allows mock phone verification to be overridden by development headers', async () => {
    const authMiddleware = createAuthMiddlewareFromConfig({
      config: {
        authProvider: 'mock',
        mockUserId: 'local-dev-user'
      }
    });
    const app = createTestApp(authMiddleware);

    const response = await request(app)
      .get('/auth/me')
      .set('x-postdee-phone-verified', 'true')
      .set('x-postdee-phone-number', '+66812345678')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      user: {
        id: 'local-dev-user',
        provider: 'mock',
        phoneNumber: '+66812345678',
        phoneVerified: true
      }
    });
  });

  it('verifies Firebase bearer tokens when Firebase auth is configured', async () => {
    const firebaseVerifier = {
      verifyIdToken: vi.fn(async () => ({
        id: 'firebase-user-1',
        provider: 'firebase' as const,
        email: 'seller@example.com',
        displayName: 'Firebase Seller'
      }))
    };
    const authMiddleware = createAuthMiddlewareFromConfig({
      config: {
        authProvider: 'firebase',
        mockUserId: 'local-dev-user'
      },
      firebaseVerifier
    });
    const app = createTestApp(authMiddleware);

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
        email: 'seller@example.com',
        displayName: 'Firebase Seller'
      }
    });
  });

  it('rejects Firebase auth requests without a bearer token', async () => {
    const authMiddleware = createAuthMiddlewareFromConfig({
      config: {
        authProvider: 'firebase',
        mockUserId: 'local-dev-user'
      },
      firebaseVerifier: {
        verifyIdToken: vi.fn()
      }
    });
    const app = createTestApp(authMiddleware);

    const response = await request(app).get('/auth/me').expect(401);

    expect(response.body).toEqual({
      status: 'error',
      message: 'Bearer token is required'
    });
  });

  it('requires a Firebase verifier when Firebase auth is configured', () => {
    expect(() =>
      createAuthMiddlewareFromConfig({
        config: {
          authProvider: 'firebase',
          mockUserId: 'local-dev-user'
        }
      })
    ).toThrow('Firebase auth requires a token verifier');
  });
});
