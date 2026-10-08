import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createRateLimitMiddleware } from './rateLimit.js';

const createLimitedApp = (trustedProxyHops = 0) => {
  const app = express();
  app.set('trust proxy', trustedProxyHops);

  app.use(
    createRateLimitMiddleware({
      bucket: 'test',
      windowMs: 60_000,
      maxRequests: 2,
      now: () => Date.UTC(2026, 5, 27, 12, 0, 0)
    })
  );
  app.get('/limited', (_request, response) => response.json({ status: 'ok' }));

  return app;
};

describe('rate limit middleware', () => {
  it('limits repeated requests with a neutral public error', async () => {
    const app = createLimitedApp();

    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.10').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.10').expect(200);
    const response = await request(app)
      .get('/limited')
      .set('x-forwarded-for', '203.0.113.10')
      .expect(429);

    expect(response.body).toEqual({
      status: 'error',
      code: 'RATE_LIMITED',
      message: 'Too many requests. Please try again shortly.'
    });
    expect(response.headers['retry-after']).toBe('60');
  });

  it('keeps separate buckets for different client addresses', async () => {
    const app = createLimitedApp(1);

    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.12').expect(200);
  });

  it('ignores forged forwarding headers when no proxy is trusted', async () => {
    const app = createLimitedApp();
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.10').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.12').expect(429);
  });

  it('uses the nearest untrusted address behind one trusted proxy', async () => {
    const app = createLimitedApp(1);
    for (const [index, forgedAddress] of ['198.51.100.1', '198.51.100.2', '198.51.100.3'].entries()) {
      await request(app).get('/limited')
        .set('x-forwarded-for', `${forgedAddress}, 203.0.113.10`)
        .expect(index < 2 ? 200 : 429);
    }
  });

  it('shares a bucket for IPv6 addresses in the same subnet', async () => {
    const app = createLimitedApp(1);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:abcd:1200::1').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:abcd:1200::2').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:abcd:1200::3').expect(429);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:abcd:1300::1').expect(200);
  });
});
