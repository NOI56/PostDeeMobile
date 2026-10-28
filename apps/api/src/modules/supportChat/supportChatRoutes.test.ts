import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import type { UserStore } from '../users/userStore.js';
import { createMemorySupportChatStore } from './supportChat.js';
import { registerSupportChatRoutes } from './supportChatRoutes.js';

const messageId = '7d1f9c3a-2b4e-4c8a-9f10-000000000001';
const setup = (botAvailable = false) => {
  const app = express(); app.use(express.json()); const router = express.Router();
  const store = createMemorySupportChatStore({ now: () => new Date('2026-10-28T03:00:00Z') });
  const ensured: string[] = [];
  const userStore: UserStore = { exists: async () => true, ensure: async user => {
    ensured.push(user.id);
    return { id: user.id, firebaseUid: user.id, email: `${user.id}@example.com`, createdAt: '', updatedAt: '' };
  } };
  const auth: express.RequestHandler = (req, res, next) => {
    const id = req.get('x-test-user');
    if (!id) { res.status(401).json({ status: 'error' }); return; }
    res.locals.authUser = { id, provider: 'mock' }; next();
  };
  const onMemberMessage = vi.fn();
  registerSupportChatRoutes(router, auth, { store, userStore, bot: { available: async () => botAvailable, onMemberMessage } }); app.use(router);
  return { app, store, ensured, onMemberMessage };
};
const send = (app: express.Express, user: string, body: Record<string, unknown>) =>
  request(app).post('/support/chat/messages').set('x-test-user', user).send(body);

describe('member support chat routes', () => {
  it('requires sign-in for reading and sending', async () => {
    const { app } = setup();
    await request(app).get('/support/chat').expect(401);
    await request(app).post('/support/chat/messages').send({ id: messageId, body: 'hi' }).expect(401);
  });
  it('sends a message into the member’s own thread and reads it back without team ids', async () => {
    const { app, store, ensured } = setup();
    const sent = await send(app, 'member', { id: messageId, body: 'โพสต์ไม่ขึ้นครับ' }).expect(201);
    expect(sent.body.message).toEqual({ id: messageId, sender: 'MEMBER', body: 'โพสต์ไม่ขึ้นครับ', createdAt: '2026-10-28T03:00:00.000Z' });
    expect(ensured).toEqual(['member']);
    await store.replyAsTeam({ userId: 'member', id: '7d1f9c3a-2b4e-4c8a-9f10-000000000002', actorId: 'owner-uid', body: 'ทีมงานกำลังดูให้' });
    const read = await request(app).get('/support/chat').set('x-test-user', 'member').expect(200);
    expect(read.headers['cache-control']).toBe('private, no-store');
    expect(read.body.thread).toEqual({ status: 'WAITING_MEMBER', lastMessageAt: '2026-10-28T03:00:00.000Z', botEnabled: false });
    expect(read.body.bot).toEqual({ available: false });
    expect(read.body.messages.map((m: { sender: string }) => m.sender)).toEqual(['MEMBER', 'TEAM']);
    expect(JSON.stringify(read.body)).not.toContain('owner-uid');
    const other = await request(app).get('/support/chat').set('x-test-user', 'other').expect(200);
    expect(other.body).toEqual({ status: 'ok', thread: null, bot: { available: false }, messages: [] });
  });
  it('rejects invalid input and reused ids with stable error codes', async () => {
    const { app } = setup();
    expect((await send(app, 'member', { id: 'nope', body: 'hi' }).expect(400)).body.code).toBe('SUPPORT_MESSAGE_INVALID');
    expect((await send(app, 'member', { id: messageId, body: ' ' }).expect(400)).body.code).toBe('SUPPORT_MESSAGE_INVALID');
    await send(app, 'member', { id: messageId, body: 'ครั้งแรก' }).expect(201);
    await send(app, 'member', { id: messageId, body: 'ครั้งแรก' }).expect(201);
    expect((await send(app, 'member', { id: messageId, body: 'ข้อความอื่น' }).expect(409)).body.code).toBe('SUPPORT_MESSAGE_CONFLICT');
    expect((await request(app).get('/support/chat?after=bad').set('x-test-user', 'member').expect(400)).body.code).toBe('SUPPORT_CURSOR_INVALID');
  });
  it('wakes Dot after a send, reports it, and lets the member ask for a person', async () => {
    const { app, store, onMemberMessage } = setup(true);
    expect((await request(app).post('/support/chat/handoff').set('x-test-user', 'member').expect(404)).body.code).toBe('SUPPORT_THREAD_NOT_FOUND');
    await send(app, 'member', { id: messageId, body: 'โพสต์ไม่ขึ้น' }).expect(201);
    expect(onMemberMessage).toHaveBeenCalledWith(expect.objectContaining({ id: 'member' }));
    await store.replyAsBot({ userId: 'member', id: '7d1f9c3a-2b4e-4c8a-9f10-000000000003', body: 'ลองส่งใหม่ได้ค่ะ', handoff: false, triggerMessageId: messageId });
    const read = await request(app).get('/support/chat').set('x-test-user', 'member').expect(200);
    expect(read.body).toMatchObject({ bot: { available: true }, thread: { status: 'WAITING_MEMBER', botEnabled: true } });
    expect(read.body.messages.map((m: { sender: string }) => m.sender)).toEqual(['MEMBER', 'BOT']);
    const handoff = await request(app).post('/support/chat/handoff').set('x-test-user', 'member').expect(200);
    expect(handoff.body.thread).toMatchObject({ status: 'WAITING_TEAM', botEnabled: false });
  });
});
