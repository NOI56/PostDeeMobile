import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createMemoryServiceIncidentStore, type ServiceIncidentStore } from './serviceIncident.js';
import { registerServiceStatusRoutes } from './serviceStatusRoutes.js';

const now = () => new Date('2026-10-28T03:00:00Z');
const draft = { title: 'TikTok ส่งช้า', message: 'ทีมงานกำลังตรวจสอบ', platforms: ['TIKTOK' as const], stage: 'INVESTIGATING' as const };
const setup = (store: ServiceIncidentStore = createMemoryServiceIncidentStore({ now })) => {
  const app = express(); const router = express.Router();
  registerServiceStatusRoutes(router, { store, now }); app.use(router);
  return { app, store };
};

describe('public service status', () => {
  it('answers without sign-in so the notice still shows while login is failing', async () => {
    const { app } = setup();
    const response = await request(app).get('/support/status').expect(200);
    expect(response.body).toEqual({ status: 'ok', incidents: [], checkedAt: '2026-10-28T03:00:00.000Z' });
  });
  it('lists only open incidents and never exposes administrator ids', async () => {
    const { app, store } = setup();
    await store.create({ id: '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e01', actorId: 'owner-uid', draft });
    const closed = await store.create({ id: '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e02', actorId: 'owner-uid', draft });
    await store.update({ id: closed.id, actorId: 'owner-uid', expectedVersion: 1, draft: { ...draft, stage: 'RESOLVED' } });
    const response = await request(app).get('/support/status').expect(200);
    expect(response.body.incidents).toEqual([{ id: '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e01', ...draft,
      startedAt: '2026-10-28T03:00:00.000Z', updatedAt: '2026-10-28T03:00:00.000Z' }]);
    expect(JSON.stringify(response.body)).not.toContain('owner-uid');
    expect(response.headers['cache-control']).toBe('public, max-age=30');
  });
  it('reports an unavailable store without caching the failure', async () => {
    const failing = { ...createMemoryServiceIncidentStore(), active: async () => { throw new Error('database down'); } };
    const response = await request(setup(failing).app).get('/support/status').expect(503);
    expect(response.body.code).toBe('SERVICE_STATUS_UNAVAILABLE');
    expect(response.headers['cache-control']).toBe('no-store');
  });
});
