import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { registerAdminConsole } from './adminRoutes.js';
import { createMemoryTrialAccessStore } from './trialAccess.js';
import { toCsv } from './adminReports.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import { createMemoryServiceIncidentStore } from '../serviceStatus/serviceIncident.js';
import { createMemorySupportChatStore } from '../supportChat/supportChat.js';

const config: AdminConsoleConfig = { origin: 'http://localhost:4174', environment: 'LOCAL', ownerUids: ['owner'], viewerUids: ['viewer'],
  firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' } };
const member = { id: 'member', email: 'mali@example.com', displayName: 'Mali', paidPlan: 'BASIC' };
const now = () => new Date('2026-10-18T00:00:00Z');
const setup = (enabled = true) => {
  const app = express(); app.use(express.json());
  const trials = createMemoryTrialAccessStore({ now });
  const incidents = createMemoryServiceIncidentStore({ now });
  const support = createMemorySupportChatStore({ now });
  const notifySupportReply = vi.fn(async (_userId: string) => undefined);
  const view = vi.fn(async () => ({ rows: [member], total: 1,
    asOf: '2026-10-17T23:59:59.000Z', summary: { memberCount: 1, captionRequests: 0, editMinutes: 0,
      quotaPostUnits: 0, postUnits: 0, livePostUnits: 0, draftPostUnits: 0, otherDeliveredPostUnits: 0,
      failedPostUnits: 0, pendingPostUnits: 0, estimatedUsd: null } }));
  registerAdminConsole(app, { config: enabled ? config : undefined, trials, now, incidents, support, notifySupportReply,
    data: { member: async id => id === member.id ? member : null, view },
    authenticate: (req, res, next) => { const id = req.get('authorization')?.replace('Bearer ', '');
      if (!id) { res.sendStatus(401); return; }
      res.locals.authUser = { id: id === 'old-owner' ? 'owner' : id, provider: id === 'mock-owner' ? 'mock' : 'firebase', authenticatedAtSeconds: id === 'old-owner' ? 1 : now().getTime() / 1000 };
      next(); }
  }); return { app, trials, view, incidents, support, notifySupportReply };
};
const adminPost = (app: express.Express, role: string, path: string, body: Record<string, unknown>) => request(app)
  .post(`/admin/api/${path}`).set('Authorization', `Bearer ${role}`).set('Origin', config.origin)
  .set('X-PostDee-Admin', '1').send(body);
const chatId = (n: number) => `7d1f9c3a-2b4e-4c8a-9f10-${String(n).padStart(12, '0')}`;
const incident = { action: 'CREATE', id: '0f7c2a51-3b8d-4e7a-9c1f-5d2e6b8a9c01', title: 'TikTok ส่งช้า',
  message: 'ทีมงานกำลังตรวจสอบ', platforms: ['TIKTOK'], stage: 'INVESTIGATING' };
const postIncident = (app: express.Express, role: string, body: Record<string, unknown> = incident) => request(app)
  .post('/admin/api/incidents').set('Authorization', `Bearer ${role}`).set('Origin', config.origin)
  .set('X-PostDee-Admin', '1').send(body);
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
  it('validates report scope before accessing data and preserves snapshot metadata', async () => {
    const { app, view } = setup();
    const read = (body: Record<string, unknown>) => request(app).post('/admin/api/view')
      .set('Authorization', 'Bearer viewer').set('Origin', config.origin).set('X-PostDee-Admin', '1').send(body);
    for (const reportScope of ['PAID_ONLY', 1, {}, null]) {
      expect((await read({ view: 'reports', reportScope })).status).toBe(400);
    }
    expect(view).not.toHaveBeenCalled();
    const response = await read({ view: 'reports', reportScope: 'ALL_ACCOUNTS', from: '2026-10-01', through: '2026-10-18' });
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ total: 1, asOf: '2026-10-17T23:59:59.000Z',
      checkedAt: now().toISOString(), summary: { memberCount: 1 } });
    expect(view).toHaveBeenCalledWith('reports', expect.objectContaining({ reportScope: 'ALL_ACCOUNTS',
      from: new Date('2026-10-01T00:00:00Z'), until: new Date('2026-10-19T00:00:00Z') }));
    expect((await read({ view: 'reports', reportScope: 'LATEST_TRIAL', csv: true })).headers['content-disposition'])
      .toContain('postdee-trial-report.csv');
    expect((await read({ view: 'reports', reportScope: 'ALL_ACCOUNTS', csv: true })).headers['content-disposition'])
      .toContain('postdee-usage-report.csv');
    expect((await read({ view: 'reports', csv: true })).headers['content-disposition'])
      .toContain('postdee-trial-report.csv');
  });
  it('lets owners publish and update service notices while viewers only read them', async () => {
    const { app, incidents, view } = setup();
    expect((await postIncident(app, 'viewer')).status).toBe(403);
    expect((await postIncident(app, 'customer')).status).toBe(403);
    expect(await incidents.active()).toEqual([]);
    const created = await postIncident(app, 'owner');
    expect(created.status).toBe(200);
    expect(created.body.incident).toMatchObject({ id: incident.id, version: 1, createdBy: 'owner', stage: 'INVESTIGATING' });
    expect((await postIncident(app, 'owner')).body.incident).toEqual(created.body.incident);
    const resolved = await postIncident(app, 'owner', { ...incident, action: 'UPDATE', expectedVersion: 1, stage: 'RESOLVED' });
    expect(resolved.body.incident).toMatchObject({ version: 2, resolvedAt: now().toISOString() });
    expect((await postIncident(app, 'owner', { ...incident, action: 'UPDATE', expectedVersion: 1 })).body.code).toBe('ADMIN_INCIDENT_RESOLVED');
    const read = await request(app).post('/admin/api/view').set('Authorization', 'Bearer viewer')
      .set('Origin', config.origin).set('X-PostDee-Admin', '1').send({ view: 'incidents' });
    expect(read.status).toBe(200);
    expect(read.body).toMatchObject({ rows: [{ id: incident.id, stage: 'RESOLVED' }], checkedAt: now().toISOString() });
    expect(view).not.toHaveBeenCalled();
  });
  it('validates service notice commands before writing', async () => {
    const { app, incidents } = setup();
    for (const body of [{ ...incident, id: 'not-a-uuid' }, { ...incident, action: 'DELETE' }, { ...incident, title: 'x' },
      { ...incident, action: 'UPDATE' }, { ...incident, action: 'UPDATE', expectedVersion: -1 }, { ...incident, platforms: ['MYSPACE'] }]) {
      expect((await postIncident(app, 'owner', body)).status).toBe(400);
    }
    const csv = await request(app).post('/admin/api/view').set('Authorization', 'Bearer owner')
      .set('Origin', config.origin).set('X-PostDee-Admin', '1').send({ view: 'incidents', csv: true });
    expect(csv.status).toBe(400);
    expect(await incidents.active()).toEqual([]);
  });
  it('lets owners and viewers read and answer support chats, notifying the member', async () => {
    const { app, support, notifySupportReply } = setup();
    await support.postFromMember({ userId: 'member', id: chatId(1), body: 'โพสต์ไม่ขึ้น' });
    expect((await adminPost(app, 'customer', 'support/reply', { userId: 'member', id: chatId(2), body: 'x' })).status).toBe(403);
    const list = await adminPost(app, 'viewer', 'view', { view: 'support', status: 'WAITING_TEAM' });
    expect(list.status).toBe(200);
    expect(list.body.rows).toMatchObject([{ userId: 'member', status: 'WAITING_TEAM', lastPreview: 'โพสต์ไม่ขึ้น' }]);
    const reply = await adminPost(app, 'viewer', 'support/reply', { userId: 'member', id: chatId(2), body: 'ทีมงานกำลังดูให้ครับ' });
    expect(reply.status).toBe(200);
    expect(reply.body.message).toMatchObject({ sender: 'TEAM', byYou: true });
    expect(reply.body.message).not.toHaveProperty('authorId');
    expect(notifySupportReply).toHaveBeenCalledWith('member');
    expect((await adminPost(app, 'viewer', 'support/reply', { userId: 'member', id: chatId(2), body: 'ทีมงานกำลังดูให้ครับ' })).status).toBe(200);
    expect(notifySupportReply).toHaveBeenCalledTimes(1);
    const thread = await adminPost(app, 'owner', 'support/thread', { userId: 'member' });
    expect(thread.status).toBe(200);
    expect(thread.body).toMatchObject({ thread: { status: 'WAITING_MEMBER' }, member: { email: member.email }, hasEarlier: false });
    expect(thread.body.messages.map((m: { sender: string; byYou: boolean }) => [m.sender, m.byYou])).toEqual([['MEMBER', false], ['TEAM', false]]);
  });
  it('closes only the conversation the administrator saw and validates chat commands', async () => {
    const { app, support, notifySupportReply } = setup();
    await support.postFromMember({ userId: 'member', id: chatId(1), body: 'ช่วยด้วย' });
    expect((await adminPost(app, 'owner', 'support/close', { userId: 'member', lastMessageId: chatId(9) })).body.code).toBe('ADMIN_SUPPORT_THREAD_CHANGED');
    expect((await adminPost(app, 'viewer', 'support/close', { userId: 'member', lastMessageId: chatId(1) })).body.thread.status).toBe('CLOSED');
    for (const [path, body] of [['support/reply', { userId: 'member', id: 'bad', body: 'x' }], ['support/reply', { userId: 'member', id: chatId(3), body: ' ' }],
      ['support/thread', { userId: '' }], ['support/close', { userId: 'member' }], ['view', { view: 'support', status: 'OPEN' }]] as const) {
      expect((await adminPost(app, 'owner', path, body)).status).toBe(400);
    }
    expect((await adminPost(app, 'owner', 'support/reply', { userId: 'nobody', id: chatId(4), body: 'สวัสดี' })).status).toBe(404);
    expect((await adminPost(app, 'owner', 'support/thread', { userId: 'nobody' })).status).toBe(404);
    expect(notifySupportReply).not.toHaveBeenCalled();
  });
  it('neutralizes spreadsheet formulas and quotes CSV fields', () => {
    const csv = toCsv([{ email: '=HYPERLINK("https://evil.example")', reason: '\t+cmd', text: 'a,"b"' }]);
    expect(csv).toContain("'=HYPERLINK"); expect(csv).toContain("'\t+cmd"); expect(csv).toContain('"a,""b"""');
  });
});
