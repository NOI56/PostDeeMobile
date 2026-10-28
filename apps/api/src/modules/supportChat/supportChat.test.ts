import { describe, expect, it } from 'vitest';
import { createMemorySupportChatStore, maxMemberMessagesPerDay, readSupportMessageBody, readSupportMessageId } from './supportChat.js';

const id = (n: number) => `7d1f9c3a-2b4e-4c8a-9f10-${String(n).padStart(12, '0')}`;

describe('support message input', () => {
  it('normalizes newlines and trims, rejecting empty, long, or control text', () => {
    expect(readSupportMessageBody('  โพสต์ไม่ขึ้น\r\nช่วยดูหน่อย  ')).toBe('โพสต์ไม่ขึ้น\nช่วยดูหน่อย');
    for (const body of ['', '   ', 'x'.repeat(1001), 'bad\u0000text', 'tab\there', 7]) {
      expect(() => readSupportMessageBody(body)).toThrow('SUPPORT_MESSAGE_INVALID');
    }
    expect(readSupportMessageId(id(1).toUpperCase())).toBe(id(1));
    expect(() => readSupportMessageId('not-a-uuid')).toThrow('SUPPORT_MESSAGE_INVALID');
  });
});

describe('memory support chat store', () => {
  it('reports only the first member write as created without changing the compatibility message', async () => {
    const store = createMemorySupportChatStore();
    const input = { userId: 'member', id: id(901), body: 'A new support message' };
    const writes = await Promise.all([1, 2, 3].map(() => store.postFromMemberWithReceipt(input)));
    expect(writes.filter(write => write.created)).toHaveLength(1);
    expect(writes.map(write => write.message.id)).toEqual([input.id, input.id, input.id]);
    expect(await store.postFromMember(input)).toEqual(writes[0].message);
    await expect(store.postFromMemberWithReceipt({ ...input, body: 'Changed retry' })).rejects.toThrow('SUPPORT_MESSAGE_CONFLICT');
  });
  it('reports the thread status before each member write so callers can tell when it starts waiting', async () => {
    const store = createMemorySupportChatStore();
    expect(await store.postFromMemberWithReceipt({ userId: 'member', id: id(931), body: 'First' }))
      .toMatchObject({ created: true, previousStatus: null, botEnabled: true });
    expect((await store.postFromMemberWithReceipt({ userId: 'member', id: id(932), body: 'Second' })).previousStatus).toBe('WAITING_TEAM');
    await store.replyAsTeam({ userId: 'member', id: id(933), actorId: 'admin', body: 'Answer' });
    await store.setBotEnabled({ userId: 'member', enabled: false });
    expect(await store.postFromMemberWithReceipt({ userId: 'member', id: id(934), body: 'Third' }))
      .toMatchObject({ created: true, previousStatus: 'WAITING_MEMBER', botEnabled: false });
  });
  it('counts all threads waiting for the team through Dot, handoff, reply, close, and account cleanup', async () => {
    const store = createMemorySupportChatStore();
    expect(await store.countWaitingForTeam()).toBe(0);
    for (let n = 1; n <= 52; n++) await store.postFromMember({ userId: `member-${n}`, id: id(1000 + n), body: 'Help' });
    expect((await store.listThreads({})).rows).toHaveLength(50);
    expect(await store.countWaitingForTeam()).toBe(52);
    await store.replyAsBot({ userId: 'member-1', id: id(2001), body: 'Dot answer', handoff: false, triggerMessageId: id(1001) });
    expect(await store.countWaitingForTeam()).toBe(51);
    await store.requestTeam('member-1');
    expect(await store.countWaitingForTeam()).toBe(52);
    await store.replyAsTeam({ userId: 'member-1', id: id(2002), actorId: 'admin', body: 'Team answer' });
    await store.close({ userId: 'member-2', lastMessageId: id(1002) });
    await store.deleteAllForUser!('member-3');
    expect(await store.countWaitingForTeam()).toBe(49);
  });
  it('opens a thread on the first member message and replays retried sends', async () => {
    const store = createMemorySupportChatStore({ now: () => new Date('2026-10-28T03:00:00Z') });
    expect(await store.readForMember('member', {})).toEqual({ thread: null, messages: [] });
    const sent = await store.postFromMember({ userId: 'member', id: id(1), body: 'โพสต์ TikTok ไม่ขึ้น' });
    expect(sent).toMatchObject({ sender: 'MEMBER', authorId: null, createdAt: '2026-10-28T03:00:00.000Z' });
    expect(await store.postFromMember({ userId: 'member', id: id(1), body: 'โพสต์ TikTok ไม่ขึ้น' })).toEqual(sent);
    await expect(store.postFromMember({ userId: 'member', id: id(1), body: 'อีกเรื่อง' })).rejects.toThrow('SUPPORT_MESSAGE_CONFLICT');
    await expect(store.postFromMember({ userId: 'other', id: id(1), body: 'โพสต์ TikTok ไม่ขึ้น' })).rejects.toThrow('SUPPORT_MESSAGE_CONFLICT');
    const read = await store.readForMember('member', {});
    expect(read.thread).toMatchObject({ status: 'WAITING_TEAM', lastSender: 'MEMBER', lastMessageId: id(1) });
    expect(read.messages.map(m => m.id)).toEqual([id(1)]);
    expect((await store.readForMember('other', {})).messages).toEqual([]);
  });
  it('returns only newer messages after a cursor so polling stays small', async () => {
    let second = 0;
    const store = createMemorySupportChatStore({ now: () => new Date(Date.UTC(2026, 9, 28, 3, 0, second++)) });
    await store.postFromMember({ userId: 'member', id: id(1), body: 'สวัสดี' });
    const first = await store.readForMember('member', {});
    await store.replyAsTeam({ userId: 'member', id: id(2), actorId: 'owner', body: 'ทีมงานรับเรื่องแล้ว' });
    const newer = await store.readForMember('member', { after: first.cursor });
    expect(newer.messages.map(m => m.body)).toEqual(['ทีมงานรับเรื่องแล้ว']);
    const idle = await store.readForMember('member', { after: newer.cursor });
    expect(idle).toMatchObject({ messages: [], cursor: newer.cursor });
    await expect(store.readForMember('member', { after: 'garbage' })).rejects.toThrow('SUPPORT_CURSOR_INVALID');
  });
  it('caps member messages per day but never team replies', async () => {
    const store = createMemorySupportChatStore({ now: () => new Date('2026-10-28T03:00:00Z') });
    for (let n = 0; n < maxMemberMessagesPerDay; n += 1) await store.postFromMember({ userId: 'member', id: id(n), body: `ข้อความ ${n}` });
    await expect(store.postFromMember({ userId: 'member', id: id(500), body: 'อีก' })).rejects.toThrow('SUPPORT_MESSAGE_LIMIT');
    await expect(store.replyAsTeam({ userId: 'member', id: id(501), actorId: 'owner', body: 'ตอบได้' })).resolves.toMatchObject({ created: true, message: { sender: 'TEAM' } });
  });
  it('moves status with each side and closes only the conversation the admin saw', async () => {
    let minute = 0;
    const store = createMemorySupportChatStore({ now: () => new Date(Date.UTC(2026, 9, 28, 3, minute++)) });
    await expect(store.replyAsTeam({ userId: 'member', id: id(9), actorId: 'owner', body: 'ทักก่อน' })).rejects.toThrow('ADMIN_SUPPORT_THREAD_NOT_FOUND');
    await store.postFromMember({ userId: 'member', id: id(1), body: 'ช่วยด้วย' });
    const reply = await store.replyAsTeam({ userId: 'member', id: id(2), actorId: 'owner', body: 'ลองใหม่อีกครั้งได้เลย' });
    expect(reply).toMatchObject({ created: true, message: { authorId: 'owner' } });
    expect((await store.replyAsTeam({ userId: 'member', id: id(2), actorId: 'owner', body: 'ลองใหม่อีกครั้งได้เลย' })).created).toBe(false);
    expect((await store.readThread('member'))!.thread.status).toBe('WAITING_MEMBER');
    await store.postFromMember({ userId: 'member', id: id(3), body: 'ได้แล้ว ขอบคุณ' });
    await expect(store.close({ userId: 'member', lastMessageId: id(2) })).rejects.toThrow('ADMIN_SUPPORT_THREAD_CHANGED');
    expect(await store.close({ userId: 'member', lastMessageId: id(3) })).toMatchObject({ status: 'CLOSED' });
    expect((await store.listThreads({ status: 'CLOSED' })).rows.map(r => r.userId)).toEqual(['member']);
    await store.postFromMember({ userId: 'member', id: id(4), body: 'มีอีกเรื่อง' });
    expect((await store.listThreads({ status: 'WAITING_TEAM' })).rows.map(r => r.userId)).toEqual(['member']);
  });
  it('lists newest conversations first and deletes everything for an account', async () => {
    let minute = 0;
    const store = createMemorySupportChatStore({ now: () => new Date(Date.UTC(2026, 9, 28, 3, minute++)) });
    await store.postFromMember({ userId: 'first', id: id(1), body: 'หนึ่ง' });
    await store.postFromMember({ userId: 'second', id: id(2), body: 'สอง' });
    expect((await store.listThreads({})).rows.map(r => r.userId)).toEqual(['second', 'first']);
    await expect(store.listThreads({ cursor: 'garbage' })).rejects.toThrow('ADMIN_FILTER_INVALID');
    await store.deleteAllForUser!('second');
    expect((await store.listThreads({})).rows.map(r => r.userId)).toEqual(['first']);
    expect(await store.readThread('second')).toBeNull();
    await expect(store.postFromMember({ userId: 'first', id: id(2), body: 'สอง' })).resolves.toMatchObject({ userId: 'first' });
  });
});
