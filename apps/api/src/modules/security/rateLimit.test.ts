import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createRateLimitMiddleware } from './rateLimit.js';

const createLimitedApp = (trustProxy: number | false = 1) => {
  const app = express();
  app.set('trust proxy', trustProxy);

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
    const app = createLimitedApp();

    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.12').expect(200);
  });

  it('does not reset a trusted client bucket by rotating a forwarded prefix', async () => {
    const app = createLimitedApp();

    await request(app)
      .get('/limited')
      .set('x-forwarded-for', '203.0.113.10, 198.51.100.20')
      .expect(200);
    await request(app)
      .get('/limited')
      .set('x-forwarded-for', '203.0.113.11, 198.51.100.20')
      .expect(200);
    await request(app)
      .get('/limited')
      .set('x-forwarded-for', '203.0.113.12, 198.51.100.20')
      .expect(429);
  });

  it('ignores forwarded addresses when the proxy is not trusted', async () => {
    const app = createLimitedApp(false);

    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.10').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.11').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '203.0.113.12').expect(429);
  });

  it('groups IPv6 clients by the same default subnet as the global limiter', async () => {
    const app = createLimitedApp();

    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:1234:5600::1').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:1234:56ff::2').expect(200);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:1234:560a::3').expect(429);
    await request(app).get('/limited').set('x-forwarded-for', '2001:db8:1234:5700::1').expect(200);
  });
});
