import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createReadinessHandler } from './readiness.js';

const createReadyApp = (options: Parameters<typeof createReadinessHandler>[0]) => {
  const app = express();
  app.get('/ready', createReadinessHandler(options));
  return app;
};

describe('operational readiness', () => {
  it('checks both dependencies before reporting ready without caching', async () => {
    const database = vi.fn(async () => undefined);
    const queue = vi.fn(async () => undefined);
    const response = await request(createReadyApp({ database, queue })).get('/ready').expect(200);
    expect(response.body).toEqual({
      status: 'ok', service: 'postdee-api', checks: { database: 'ok', queue: 'ok' }
    });
    expect(response.headers['cache-control']).toBe('no-store');
    expect(database).toHaveBeenCalledOnce();
    expect(queue).toHaveBeenCalledOnce();
  });

  it.each(['database', 'queue'] as const)('fails closed and redacts %s errors', async (dependency) => {
    const checks = { database: async () => undefined, queue: async () => undefined };
    checks[dependency] = async () => { throw new Error('postgres://secret redis://password'); };
    const response = await request(createReadyApp(checks)).get('/ready').expect(503);
    expect(response.body.status).toBe('unavailable');
    expect(response.body.checks[dependency]).toBe('unavailable');
    expect(JSON.stringify(response.body)).not.toContain('secret');
    expect(JSON.stringify(response.body)).not.toContain('password');
  });

  it('bounds a hung dependency and does not start overlapping probes', async () => {
    const database = vi.fn(() => new Promise<void>(() => {}));
    const app = createReadyApp({ database, queue: async () => undefined, timeoutMs: 20 });
    const responses = await Promise.all([request(app).get('/ready'), request(app).get('/ready')]);
    expect(responses.map((response) => response.status)).toEqual([503, 503]);
    await request(app).get('/ready').expect(503);
    expect(database).toHaveBeenCalledOnce();
  });

  it('can probe again after an underlying timed-out check eventually settles', async () => {
    let finish!: () => void;
    const database = vi.fn()
      .mockImplementationOnce(() => new Promise<void>((resolve) => { finish = resolve; }))
      .mockResolvedValue(undefined);
    const app = createReadyApp({ database, queue: async () => undefined, timeoutMs: 20 });
    await request(app).get('/ready').expect(503);
    finish();
    await new Promise<void>((resolve) => setImmediate(resolve));
    await request(app).get('/ready').expect(200);
    expect(database).toHaveBeenCalledTimes(2);
  });

  it('reports shutdown without probing dependencies', async () => {
    const database = vi.fn(async () => undefined);
    const queue = vi.fn(async () => undefined);
    await request(createReadyApp({ database, queue, isShuttingDown: () => true }))
      .get('/ready').expect(503);
    expect(database).not.toHaveBeenCalled();
    expect(queue).not.toHaveBeenCalled();
  });

  it('does not report ready if shutdown starts during a probe', async () => {
    let shuttingDown = false;
    let finish!: () => void;
    let started!: () => void;
    const pending = new Promise<void>((resolve) => { finish = resolve; });
    const probing = new Promise<void>((resolve) => { started = resolve; });
    const app = createReadyApp({
      database: async () => { started(); await pending; },
      queue: async () => undefined,
      isShuttingDown: () => shuttingDown
    });
    const response = request(app).get('/ready').then((result) => result);
    await probing;
    shuttingDown = true;
    finish();
    expect((await response).body).toEqual({
      status: 'unavailable', service: 'postdee-api',
      checks: { database: 'unavailable', queue: 'unavailable' }
    });
  });
});
