import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaSupportChatStore } from './prismaSupportChatStore.js';
import { maxMemberMessagesPerDay } from './supportChat.js';
import { createPrismaSupportBotSettingsStore } from '../supportBot/supportBot.js';

// Opt-in only; refuse external hosts, default Postgres ports and existing app databases.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Admin DB tests require the dedicated loopback fixture cluster on port 55439');
  }
}
describe.skipIf(!databaseUrl)('support chat in PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } } });
  let time = new Date('2026-10-28T03:00:00Z');
  const store = createPrismaSupportChatStore(prisma, () => time);
  const userIds: string[] = [];
  const member = async () => {
    const id = `support-fixture-${randomUUID()}`; userIds.push(id);
    await prisma.user.create({ data: { id, firebaseUid: id, email: `${id}@example.com` } });
    return id;
  };
  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.managedUploadOwner.deleteMany({ where: { ownerId: { in: userIds } } });
    await prisma.$disconnect();
  });

  it('stores one message per id even for concurrent sends', async () => {
    const userId = await member(); const id = randomUUID();
    const results = await Promise.all([1, 2, 3].map(() => store.postFromMember({ userId, id, body: 'โพสต์ไม่ขึ้น' })));
    expect(results.map(r => r.id)).toEqual([id, id, id]);
    expect(await prisma.supportMessage.count({ where: { userId } })).toBe(1);
    expect(await prisma.supportThread.findUnique({ where: { userId } })).toMatchObject({ status: 'WAITING_TEAM', lastMessageId: id });
    await expect(store.postFromMember({ userId, id, body: 'ข้อความอื่น' })).rejects.toThrow('SUPPORT_MESSAGE_CONFLICT');
  });
  it('polls in order, answers, closes only what was seen, and lists with member email', async () => {
    const userId = await member();
    time = new Date('2026-10-28T04:00:00Z');
    await store.postFromMember({ userId, id: randomUUID(), body: 'ช่วยดูหน่อย' });
    const first = await store.readForMember(userId, {});
    time = new Date('2026-10-28T04:01:00Z');
    const reply = await store.replyAsTeam({ userId, id: randomUUID(), actorId: 'fixture-owner', body: 'ทีมงานกำลังดูให้' });
    expect(reply.created).toBe(true);
    expect((await store.replyAsTeam({ userId, id: reply.message.id, actorId: 'fixture-owner', body: 'ทีมงานกำลังดูให้' })).created).toBe(false);
    const newer = await store.readForMember(userId, { after: first.cursor });
    expect(newer.messages.map(m => m.sender)).toEqual(['TEAM']);
    await expect(store.close({ userId, lastMessageId: first.messages[0].id })).rejects.toThrow('ADMIN_SUPPORT_THREAD_CHANGED');
    expect(await store.close({ userId, lastMessageId: reply.message.id })).toMatchObject({ status: 'CLOSED' });
    const listed = await store.listThreads({ status: 'CLOSED', query: `${userId}@example.com` });
    expect(listed.rows).toMatchObject([{ userId, email: `${userId}@example.com`, lastSender: 'TEAM' }]);
    expect((await store.readThread(userId))!.messages.map(m => m.sender)).toEqual(['MEMBER', 'TEAM']);
  });
  it('caps member messages per day', async () => {
    const userId = await member();
    await store.postFromMember({ userId, id: randomUUID(), body: 'เริ่ม' });
    await prisma.supportMessage.createMany({ data: Array.from({ length: maxMemberMessagesPerDay - 1 }, (_, n) => ({
      id: randomUUID(), userId, sender: 'MEMBER', body: `ข้อความ ${n}`, createdAt: time })) });
    await expect(store.postFromMember({ userId, id: randomUUID(), body: 'เกิน' })).rejects.toThrow('SUPPORT_MESSAGE_LIMIT');
  });
  it('refuses writes during account deletion and cascades on user delete', async () => {
    const userId = await member();
    await store.postFromMember({ userId, id: randomUUID(), body: 'ก่อนลบ' });
    await prisma.managedUploadOwner.update({ where: { ownerId: userId }, data: { status: 'DELETING' } });
    await expect(store.postFromMember({ userId, id: randomUUID(), body: 'ระหว่างลบ' })).rejects.toThrow('Account deletion is in progress');
    await expect(store.replyAsTeam({ userId, id: randomUUID(), actorId: 'fixture-owner', body: 'ระหว่างลบ' })).rejects.toThrow('Account deletion is in progress');
    await prisma.user.delete({ where: { id: userId } });
    expect(await prisma.supportThread.count({ where: { userId } })).toBe(0);
    expect(await prisma.supportMessage.count({ where: { userId } })).toBe(0);
  });
  it('enforces sender, author, and length rules in the database', async () => {
    const userId = await member();
    await store.postFromMember({ userId, id: randomUUID(), body: 'มีเธรดแล้ว' });
    for (const data of [{ sender: 'TEAM', authorId: null, body: 'ไม่มีผู้ตอบ' }, { sender: 'MEMBER', authorId: 'x', body: 'มีผู้ตอบ' },
      { sender: 'BOT', authorId: 'x', body: 'บอทไม่มีผู้ตอบ' }, { sender: 'ROBOT', authorId: null, body: 'ไม่รู้จัก' },
      { sender: 'MEMBER', authorId: null, body: 'x'.repeat(1001) }]) {
      await expect(prisma.supportMessage.create({ data: { ...data, id: randomUUID(), userId, createdAt: time } })).rejects.toThrow();
    }
    await expect(prisma.supportMessage.create({ data: { sender: 'BOT', authorId: null, body: 'Dot ตอบได้', id: randomUUID(), userId, createdAt: time } }))
      .resolves.toMatchObject({ sender: 'BOT' });
  });
  it('stores Dot only for the newest member message and tracks the per-thread switch', async () => {
    const userId = await member();
    const first = await store.postFromMember({ userId, id: randomUUID(), body: 'ข้อแรก' });
    const second = await store.postFromMember({ userId, id: randomUUID(), body: 'ข้อสอง' });
    expect(await store.replyAsBot({ userId, id: randomUUID(), body: 'ตอบข้อแรก', handoff: false, triggerMessageId: first.id })).toBeNull();
    const reply = await store.replyAsBot({ userId, id: randomUUID(), body: 'ตอบข้อสอง', handoff: false, triggerMessageId: second.id });
    expect(reply).toMatchObject({ sender: 'BOT', authorId: null });
    expect(await store.countSince({ userId, sender: 'BOT', since: new Date(time.getTime() - 86400000) })).toBe(1);
    expect((await store.readThread(userId))!.thread).toMatchObject({ status: 'WAITING_MEMBER', lastSender: 'BOT', botEnabled: true });
    const third = await store.postFromMember({ userId, id: randomUUID(), body: 'ขอคนจริง' });
    expect(await store.requestTeam(userId)).toMatchObject({ status: 'WAITING_TEAM', botEnabled: false });
    expect(await store.replyAsBot({ userId, id: randomUUID(), body: 'ไม่ควรตอบ', handoff: false, triggerMessageId: third.id })).toBeNull();
    expect((await store.setBotEnabled({ userId, enabled: true })).botEnabled).toBe(true);
    const team = await store.replyAsTeam({ userId, id: randomUUID(), actorId: 'fixture-owner', body: 'ทีมงานตอบค่ะ' });
    expect((await store.readThread(userId))!.thread.botEnabled).toBe(false);
    expect(await store.close({ userId, lastMessageId: team.message.id })).toMatchObject({ status: 'CLOSED', botEnabled: true });
    await expect(store.requestTeam(`missing-${randomUUID()}`)).rejects.toThrow('SUPPORT_THREAD_NOT_FOUND');
  });
  it('keeps Dot off until an owner saves the global switch', async () => {
    await prisma.supportBotSetting.deleteMany({});
    const settings = createPrismaSupportBotSettingsStore(prisma, () => time);
    expect(await settings.read()).toEqual({ enabled: false, updatedBy: null, updatedAt: null });
    expect(await settings.set({ enabled: true, actorId: 'fixture-owner' })).toEqual({ enabled: true, updatedBy: 'fixture-owner', updatedAt: time.toISOString() });
    expect((await settings.set({ enabled: false, actorId: 'fixture-owner' })).enabled).toBe(false);
    expect(await prisma.supportBotSetting.count()).toBe(1);
    await expect(prisma.supportBotSetting.create({ data: { id: 'second', enabled: true, updatedBy: 'x', updatedAt: time } })).rejects.toThrow();
    await prisma.supportBotSetting.deleteMany({});
  });
});
