import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';

describe('API rate limiting', () => {
  it('rejects requests over the configured per-window limit with 429', async () => {
    const app = createApp({
      config: readServerConfig({ RATE_LIMIT_MAX_REQUESTS: '2' })
    });

    await request(app).get('/templates').expect(200);
    await request(app).get('/templates').expect(200);

    const limitedResponse = await request(app).get('/templates').expect(429);

    expect(limitedResponse.body).toEqual({
      status: 'error',
      code: 'RATE_LIMITED',
      message: 'Too many requests. Please try again shortly.'
    });
  });

  it('does not rate limit the health check endpoint', async () => {
    const app = createApp({
      config: readServerConfig({ RATE_LIMIT_MAX_REQUESTS: '1' })
    });

    await request(app).get('/health').expect(200);
    await request(app).get('/health').expect(200);
    await request(app).get('/health').expect(200);
  });

  it('keeps normal traffic under the default limit unaffected', async () => {
    const app = createApp();

    await request(app).get('/templates').expect(200);
    await request(app).get('/templates').expect(200);
  });
});
