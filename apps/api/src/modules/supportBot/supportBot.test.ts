import { describe, expect, it, vi, type Mock } from 'vitest';
import type { AuthUser } from '../auth/authTypes.js';
import { createMemorySupportChatStore } from '../supportChat/supportChat.js';
import {
  botHandoffMessage, botLimitMessage, cacheSupportBotSettings, createMemorySupportBotSettingsStore, createSupportBot,
  createSupportBotScheduler, maxBotRepliesPerDay, normalizeBotAnswer
} from './supportBot.js';
import { scrubSupportText, supportBotFaq, supportBotSystemPrompt, type SupportBotContext } from './supportBotKnowledge.js';
import { createOpenAiSupportBotProvider, type SupportBotProvider } from './supportBotProvider.js';

const member: AuthUser = { id: 'member', provider: 'mock' };
const id = (n: number) => `7d1f9c3a-2b4e-4c8a-9f10-${String(n).padStart(12, '0')}`;
const context: SupportBotContext = { plan: 'STARTER', incidents: [{ title: 'TikTok ส่งช้า', message: 'โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ',
  platforms: ['TIKTOK'], stage: 'IDENTIFIED' }], automaticSignals: [{ area: 'การส่งโพสต์ไป TikTok', lastSeen: '2026-10-28T02:55:00.000Z' }],
  recentPosts: [] };
const setup = async ({ enabled = true, answer = vi.fn<SupportBotProvider['answer']>(async () => ({ reply: 'ตอนนี้ TikTok ส่งช้าค่ะ', handoff: false })) }:
  { enabled?: boolean; answer?: Mock<SupportBotProvider['answer']> } = {}) => {
  let second = 0;
  const now = () => new Date(Date.UTC(2026, 9, 28, 3, 0, second++));
  const store = createMemorySupportChatStore({ now });
  const settings = createMemorySupportBotSettingsStore({ now });
  if (enabled) await settings.set({ enabled: true, actorId: 'owner' });
  const provider: SupportBotProvider = { kind: 'mock', answer };
  let next = 100;
  const bot = createSupportBot({ store, settings, provider, now, loadContext: async () => context, newId: () => id(next++) });
  return { store, settings, bot, answer };
};

describe('Dot data protection', () => {
  it('removes emails, phone numbers and long number runs but keeps times and short numbers', () => {
    expect(scrubSupportText('ติดต่อ mali@example.com หรือ 081-234-5678 / +66 81 234 5678'))
      .toBe('ติดต่อ [อีเมล] หรือ [เบอร์โทร] / [เบอร์โทร]');
    expect(scrubSupportText('บัตร 4111 1111 1111 1111 โพสต์ตอน 14:05 ไป 3 ช่อง')).toBe('บัตร [ตัวเลข] โพสต์ตอน 14:05 ไป 3 ช่อง');
  });
  it('states plan facts from the enforced limits and never the retired editor', () => {
    const faq = supportBotFaq.join('\n');
    expect(faq).toContain('Basic 3, Starter 120, Pro 250');
    expect(faq).toContain('Starter up to 14 days');
    expect(faq).not.toMatch(/edit(or|ing)?|ตัดต่อ|subtitle/i);
    const prompt = supportBotSystemPrompt(context);
    expect(prompt).toContain('TikTok ส่งช้า');
    expect(prompt).toContain('"memberPlan":"STARTER"');
    expect(prompt).toContain('"automaticSignals":[{"area":"การส่งโพสต์ไป TikTok"');
    expect(prompt).toContain('"teamAlreadyNotified":false');
    expect(prompt).not.toMatch(/sentry/i);
  });
  it('fits replies to the chat limit and turns an empty reply into a handoff', () => {
    expect(normalizeBotAnswer({ reply: '  ok\u0000\n\n\n\nok  ', handoff: false })).toEqual({ reply: 'ok\n\nok', handoff: false });
    expect(normalizeBotAnswer({ reply: 'x'.repeat(1200), handoff: false }).reply).toHaveLength(1000);
    expect(normalizeBotAnswer({ reply: '   ', handoff: false })).toEqual({ reply: botHandoffMessage, handoff: true });
  });
});

describe('Dot replies', () => {
  it('stays silent while the global switch is off', async () => {
    const { store, bot, answer } = await setup({ enabled: false });
    await store.postFromMember({ userId: 'member', id: id(1), body: 'โพสต์ไม่ขึ้น' });
    await bot.respond(member);
    expect(answer).not.toHaveBeenCalled();
    expect((await store.readThread('member'))!.messages).toHaveLength(1);
  });
  it('answers the member from context with scrubbed text and waits for the member', async () => {
    const { store, bot, answer } = await setup();
    await store.postFromMember({ userId: 'member', id: id(1), body: 'โพสต์ไม่ขึ้น โทร 0812345678 ได้' });
    await bot.respond(member);
    expect(answer).toHaveBeenCalledWith({ context: { ...context, teamAlreadyNotified: false },
      conversation: [{ sender: 'MEMBER', body: 'โพสต์ไม่ขึ้น โทร [เบอร์โทร] ได้' }] });
    const read = (await store.readThread('member'))!;
    expect(read.messages.map(m => [m.sender, m.body])).toEqual([['MEMBER', 'โพสต์ไม่ขึ้น โทร 0812345678 ได้'], ['BOT', 'ตอนนี้ TikTok ส่งช้าค่ะ']]);
    expect(read.thread).toMatchObject({ status: 'WAITING_MEMBER', lastSender: 'BOT', botEnabled: true, teamRequested: false });
    await bot.respond(member);
    expect(answer).toHaveBeenCalledTimes(1);
  });
  it('flags the team on a handoff and keeps helping while the chat waits for a person', async () => {
    const answer = vi.fn<SupportBotProvider['answer']>(async () => ({ reply: 'ส่งต่อให้ทีมงานแล้วค่ะ', handoff: true }));
    const { store, bot } = await setup({ answer });
    await store.postFromMember({ userId: 'member', id: id(1), body: 'ขอคืนเงิน' });
    await bot.respond(member);
    expect((await store.readThread('member'))!.thread).toMatchObject({ status: 'WAITING_TEAM', botEnabled: true, teamRequested: true });
    answer.mockResolvedValueOnce({ reply: 'ระหว่างรอ ตรวจในแอปได้ค่ะ', handoff: false });
    await store.postFromMember({ userId: 'member', id: id(2), body: 'ระหว่างรอทำอะไรได้บ้าง' });
    await bot.respond(member);
    expect(answer).toHaveBeenCalledTimes(2);
    expect(answer.mock.calls[1][0].context.teamAlreadyNotified).toBe(true);
    // Dot answered, but the chat still waits for a person.
    expect((await store.readThread('member'))!.thread).toMatchObject({ status: 'WAITING_TEAM', lastSender: 'BOT', teamRequested: true });
    const closed = await store.close({ userId: 'member', lastMessageId: (await store.readThread('member'))!.thread.lastMessageId });
    expect(closed).toMatchObject({ botEnabled: true, teamRequested: false });
  });
  it('keeps helping after a team reply; only the per-chat switch silences Dot', async () => {
    const { store, bot, answer } = await setup();
    await store.postFromMember({ userId: 'member', id: id(1), body: 'สวัสดี' });
    expect(await store.requestTeam('member')).toMatchObject({ status: 'WAITING_TEAM', botEnabled: true, teamRequested: true });
    await store.replyAsTeam({ userId: 'member', id: id(2), actorId: 'owner', body: 'ทีมงานดูให้ค่ะ' });
    expect((await store.readThread('member'))!.thread).toMatchObject({ status: 'WAITING_MEMBER', teamRequested: false, botEnabled: true });
    await store.postFromMember({ userId: 'member', id: id(3), body: 'อีกเรื่องค่ะ' });
    await bot.respond(member);
    expect(answer).toHaveBeenCalledTimes(1);
    await store.setBotEnabled({ userId: 'member', enabled: false });
    await store.postFromMember({ userId: 'member', id: id(4), body: 'อีกครั้ง' });
    await bot.respond(member);
    expect(answer).toHaveBeenCalledTimes(1);
  });
  it('hands off with a fixed message when the model fails or the daily cap is reached', async () => {
    const failing = await setup({ answer: vi.fn<SupportBotProvider['answer']>(async () => { throw new Error('timeout'); }) });
    await failing.store.postFromMember({ userId: 'member', id: id(1), body: 'ช่วยด้วย' });
    await failing.bot.respond(member);
    expect((await failing.store.readThread('member'))!.messages.at(-1)).toMatchObject({ sender: 'BOT', body: botHandoffMessage });

    const capped = await setup();
    for (let n = 0; n < maxBotRepliesPerDay; n += 1) {
      await capped.store.postFromMember({ userId: 'member', id: id(n * 2 + 1), body: `คำถาม ${n}` });
      await capped.bot.respond(member);
    }
    await capped.store.postFromMember({ userId: 'member', id: id(999), body: 'อีกคำถาม' });
    await capped.bot.respond(member);
    expect(capped.answer).toHaveBeenCalledTimes(maxBotRepliesPerDay);
    expect((await capped.store.readThread('member'))!.messages.at(-1)).toMatchObject({ sender: 'BOT', body: botLimitMessage });
    expect((await capped.store.readThread('member'))!.thread).toMatchObject({ status: 'WAITING_TEAM', teamRequested: true });
    // The limit message is sent once; later messages just wait for the team.
    await capped.store.postFromMember({ userId: 'member', id: id(1000), body: 'ยังอยู่ไหม' });
    await capped.bot.respond(member);
    expect((await capped.store.readThread('member'))!.messages.at(-1)).toMatchObject({ sender: 'MEMBER' });
  });
  it('drops a reply when the member wrote again meanwhile, and the scheduler answers the newest message', async () => {
    let release!: () => void;
    let started!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
    const firstCall = new Promise<void>(resolve => { started = resolve; });
    const answer = vi.fn<SupportBotProvider['answer']>(async ({ conversation }) => {
      if (answer.mock.calls.length === 1) { started(); await gate; }
      return { reply: `ตอบ: ${conversation.at(-1)!.body}`, handoff: false };
    });
    const { store, bot } = await setup({ answer });
    const scheduler = createSupportBotScheduler(bot);
    await store.postFromMember({ userId: 'member', id: id(1), body: 'ข้อแรก' });
    scheduler.schedule(member);
    await firstCall;
    await store.postFromMember({ userId: 'member', id: id(2), body: 'ข้อสอง' });
    scheduler.schedule(member);
    scheduler.schedule(member);
    release();
    await scheduler.drain();
    expect(answer).toHaveBeenCalledTimes(2);
    expect((await store.readThread('member'))!.messages.map(m => m.body)).toEqual(['ข้อแรก', 'ข้อสอง', 'ตอบ: ข้อสอง']);
  });
  it('caches the global switch but applies a change at once', async () => {
    let time = 0;
    const inner = createMemorySupportBotSettingsStore();
    const read = vi.spyOn(inner, 'read');
    const cached = cacheSupportBotSettings(inner, { ttlMs: 1000, now: () => time });
    await cached.read(); await cached.read();
    expect(read).toHaveBeenCalledTimes(1);
    expect((await cached.set({ enabled: true, actorId: 'owner' })).enabled).toBe(true);
    expect((await cached.read()).enabled).toBe(true);
    time = 2000; await cached.read();
    expect(read).toHaveBeenCalledTimes(2);
  });
});

describe('OpenAI support bot provider', () => {
  const conversation = [{ sender: 'MEMBER' as const, body: 'โพสต์ไม่ขึ้น' }, { sender: 'TEAM' as const, body: 'ลองใหม่ค่ะ' }];
  it('sends a JSON chat request with the facts and returns the parsed answer', async () => {
    const fetchImpl = vi.fn(async (_url: string | URL | Request, _init?: RequestInit) => new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({ reply: 'TikTok ส่งช้าค่ะ', handoff: false }) } }] }), { status: 200 }));
    const provider = createOpenAiSupportBotProvider({ apiKey: 'sk-test', model: 'gpt-4o-mini', fetchImpl: fetchImpl as unknown as typeof fetch });
    expect(await provider.answer({ conversation, context })).toEqual({ reply: 'TikTok ส่งช้าค่ะ', handoff: false });
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe('https://api.openai.com/v1/chat/completions');
    expect((init!.headers as Record<string, string>).Authorization).toBe('Bearer sk-test');
    const body = JSON.parse(String(init!.body));
    expect(body).toMatchObject({ model: 'gpt-4o-mini', response_format: { type: 'json_object' }, max_tokens: 500 });
    expect(body.messages[0].content).toContain('TikTok ส่งช้า');
    expect(body.messages.slice(1)).toEqual([{ role: 'user', content: 'โพสต์ไม่ขึ้น' }, { role: 'assistant', content: '(ทีมงาน PostDee) ลองใหม่ค่ะ' }]);
  });
  it('throws on an error status or a reply that is not the expected JSON', async () => {
    for (const response of [new Response('{}', { status: 429 }),
      new Response(JSON.stringify({ choices: [{ message: { content: '{"reply":1}' } }] }), { status: 200 }),
      new Response(JSON.stringify({ choices: [{ message: { content: 'not json' } }] }), { status: 200 })]) {
      const provider = createOpenAiSupportBotProvider({ apiKey: 'sk-test', model: 'gpt-4o-mini',
        fetchImpl: (async () => response) as unknown as typeof fetch });
      await expect(provider.answer({ conversation, context })).rejects.toThrow();
    }
  });
});
