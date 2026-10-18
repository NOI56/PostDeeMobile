import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { registerAdminConsole } from './adminRoutes.js';
import { createMemoryTrialAccessStore } from './trialAccess.js';
import { toCsv } from './adminReports.js';
import type { AdminConsoleConfig } from './adminConfig.js';

const config: AdminConsoleConfig = { origin: 'http://localhost:4174', environment: 'LOCAL', ownerUids: ['owner'], viewerUids: ['viewer'],
  firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' } };
const member = { id: 'member', email: 'mali@example.com', displayName: 'Mali', paidPlan: 'BASIC' };
const now = () => new Date('2026-10-18T00:00:00Z');
const setup = (enabled = true) => {
  const app = express(); app.use(express.json());
  const trials = createMemoryTrialAccessStore({ now });
  registerAdminConsole(app, { config: enabled ? config : undefined, trials, now,
    data: { member: async id => id === member.id ? member : null, view: async () => ({ rows: [member], total: 1 }) },
    authenticate: (req, res, next) => { const id = req.get('authorization')?.replace('Bearer ', '');
      if (!id) { res.sendStatus(401); return; }
      res.locals.authUser = { id: id === 'old-owner' ? 'owner' : id, provider: id === 'mock-owner' ? 'mock' : 'firebase', authenticatedAtSeconds: id === 'old-owner' ? 1 : now().getTime() / 1000 };
      next(); }
  }); return { app, trials };
};
const command = { requestId: '54ce1fea-78bc-4c8e-a4e2-01bed4234420', userId: 'member', expectedEmail: 'mali@example.com',
  action: 'GRANT', plan: 'PRO', days: 7, expectedVersion: 0, reason: 'ทดลองลูกค้า' };
const post = (app: express.Express, role: string, body = command) => request(app).post('/admin/api/trials')
  .set('Authorization', `Bearer ${role}`).set('Origin', config.origin).set('X-PostDee-Admin', '1').send(body);
describe('private administrator console', () => {
  it('is absent by default', async () => {
    const { app } = setup(false); expect((await request(app).get('/admin')).status).toBe(404);
    expect((await post(app, 'owner')).status).toBe(404);
  });
  it('rejects ordinary users and viewer writes without touching trials', async () => {
    const { app, trials } = setup();
    expect((await post(app, 'customer')).status).toBe(403);
    expect((await post(app, 'viewer')).status).toBe(403);
    expect(await trials.history()).toHaveLength(0);
  });
  it('allows viewer reads but sends private no-store data', async () => {
    const { app } = setup();
    const r = await request(app).post('/admin/api/view').set('Authorization', 'Bearer viewer')
      .set('Origin', config.origin).set('X-PostDee-Admin', '1').send({ view: 'members' });
    expect(r.status).toBe(200); expect(r.headers['cache-control']).toContain('no-store');
    expect(r.body.rows[0].email).toBe(member.email);
  });
  it('requires the same origin and explicit JSON admin request header', async () => {
    const { app, trials } = setup();
    const r = await request(app).post('/admin/api/trials').set('Authorization', 'Bearer owner')
      .set('Origin', 'https://other.example').set('X-PostDee-Admin', '1').send(command);
    expect(r.status).toBe(403);
    expect((await request(app).post('/admin/api/trials').set('Authorization', 'Bearer owner').send(command)).status).toBe(403);
    expect(await trials.history()).toHaveLength(0);
  });
  it('binds the reviewed identity, audits once, and rejects stale or altered replays', async () => {
    const { app, trials } = setup();
    expect((await post(app, 'owner', { ...command, expectedEmail: 'other@example.com' })).status).toBe(409);
    expect((await post(app, 'owner')).status).toBe(200);
    expect((await post(app, 'owner')).status).toBe(200);
    expect((await post(app, 'owner', { ...command, days: 14 })).status).toBe(409);
    expect((await post(app, 'owner', { ...command, requestId: 'd6a5b748-6088-48fb-9116-d92459d0b00e' })).status).toBe(409);
    expect(await trials.history()).toHaveLength(1);
  });
  it('never accepts browser supplied actor roles or unsupported grant durations', async () => {
    const { app, trials } = setup();
    expect((await post(app, 'customer', { ...command, actorId: 'owner' } as typeof command)).status).toBe(403);
    expect((await post(app, 'owner', { ...command, days: 999 })).status).toBe(400);
    expect(await trials.history()).toHaveLength(0);
  });
  it('serves a restrictive CSP and only public Firebase configuration', async () => {
    const { app } = setup(); const page = await request(app).get('/admin');
    expect(page.status).toBe(200); expect(page.headers['content-security-policy']).toContain("object-src 'none'");
    const scriptSources = String(page.headers['content-security-policy']).split(';')
      .find(directive => directive.trim().startsWith('script-src '))!.trim().split(/\s+/).slice(1);
    // Firebase's popup resolver loads Google's api.js before opening the sign-in window.
    expect(scriptSources).toContain('https://apis.google.com');
    for (const unsafe of ['*', "'unsafe-inline'", "'unsafe-eval'"]) expect(scriptSources).not.toContain(unsafe);
    const boot = await request(app).get('/admin/config');
    expect(boot.body).not.toHaveProperty('ownerUids'); expect(boot.body).not.toHaveProperty('viewerUids');
  });
  it('requires recent owner authentication and never writes as a mock principal', async () => {
    const { app, trials } = setup();
    expect((await post(app, 'old-owner')).status).toBe(401);
    expect((await post(app, 'mock-owner')).status).toBe(403);
    expect((await request(app).get('/admin/api/session')).status).toBe(401);
    expect(await trials.history()).toHaveLength(0);
  });
  it('rejects rolled dates and reversed date windows', async () => {
    const { app } = setup();
    for (const dates of [{from:'2026-02-31'}, {from:'2026-10-20',through:'2026-10-18'}]) {
      const r = await request(app).post('/admin/api/view').set('Authorization','Bearer owner')
        .set('Origin',config.origin).set('X-PostDee-Admin','1').send({view:'posts',...dates});
      expect(r.status).toBe(400);
    }
  });
  it('neutralizes spreadsheet formulas and quotes CSV fields', () => {
    const csv = toCsv([{ email: '=HYPERLINK("https://evil.example")', reason: '\t+cmd', text: 'a,"b"' }]);
    expect(csv).toContain("'=HYPERLINK"); expect(csv).toContain("'\t+cmd"); expect(csv).toContain('"a,""b"""');
  });
});
