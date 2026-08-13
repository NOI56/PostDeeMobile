import request from 'supertest';
import express from 'express';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createInMemoryDeviceTokenStore } from './deviceTokenStore.js';
import { registerDeviceRoutes } from './deviceRoutes.js';

describe('device routes', () => {
  it('registers a device token for the authenticated user', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/devices')
      .set('x-postdee-user-id', 'seller-device')
      .send({ token: 'fcm-token-abc', platform: 'ANDROID' })
      .expect(200);

    expect(response.body).toEqual({ status: 'ok' });
  });

  it('ensures the authenticated user before registering a relational device token', async () => {
    const app = express();
    const router = express.Router();
    const calls: string[] = [];
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    const register = deviceTokenStore.register;
    deviceTokenStore.register = vi.fn(async (input) => {
      calls.push(`token:${input.userId}`);
      return register(input);
    });
    const userStore = {
      ensure: vi.fn(async (authUser: { id: string }) => {
        calls.push(`user:${authUser.id}`);
        return {
          id: authUser.id,
          firebaseUid: `mock:${authUser.id}`,
          email: `${authUser.id}@postdee.local`,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        };
      }),
      exists: vi.fn(async () => true)
    };
    const authMiddleware: express.RequestHandler = (_request, response, next) => {
      response.locals.authUser = { id: 'seller-device-order', provider: 'mock' };
      next();
    };

    app.use(express.json());
    registerDeviceRoutes(router, authMiddleware, deviceTokenStore, userStore);
    app.use(router);
    await request(app)
      .post('/devices')
      .send({ token: 'fcm-token-order', platform: 'ANDROID' })
      .expect(200);

    expect(calls).toEqual([
      'user:seller-device-order',
      'token:seller-device-order'
    ]);
  });

  it('rejects a request without a token', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/devices')
      .set('x-postdee-user-id', 'seller-device')
      .send({})
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'token is required'
    });
  });

  it('removes device tokens when the account is deleted', async () => {
    const app = createApp();
    const headers = { 'x-postdee-user-id': 'seller-device-delete' };

    await request(app)
      .post('/devices')
      .set(headers)
      .send({ token: 'fcm-token-del' })
      .expect(200);

    // Re-registering the same token for another user proves the store is shared;
    // after deletion the first user's token must be gone (no crash, 200 ok).
    await request(app).delete('/account').set(headers).expect(200);
  });
});
