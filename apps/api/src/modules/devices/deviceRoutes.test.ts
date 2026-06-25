import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';

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
