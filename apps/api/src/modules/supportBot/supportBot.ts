import { randomUUID } from 'node:crypto';
import type { PrismaClient } from '@prisma/client';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { AuthUser } from '../auth/authTypes.js';
import { maxSupportMessageLength, type SupportChatStore } from '../supportChat/supportChat.js';
import { scrubSupportText, type SupportBotContext } from './supportBotKnowledge.js';
import type { SupportBotAnswer, SupportBotProvider } from './supportBotProvider.js';

// Dot replies allowed per member per rolling 24 hours; after that the thread
// goes to the team without calling the model, which also caps cost.
export const maxBotRepliesPerDay = 20;
export const botConversationTurns = 20;
export const botHandoffMessage = 'ส่งเรื่องต่อให้ทีมงาน PostDee แล้วค่ะ ทีมงานจะตอบในแชทนี้ และแจ้งเตือนเมื่อมีคำตอบ';

export type SupportBotSettings = { enabled: boolean; updatedBy: string | null; updatedAt: string | null };
export type SupportBotSettingsStore = {
  read: () => Promise<SupportBotSettings>;
  set: (input: { enabled: boolean; actorId: string }) => Promise<SupportBotSettings>;
};
const off: SupportBotSettings = { enabled: false, updatedBy: null, updatedAt: null };

export const createMemorySupportBotSettingsStore = ({ now = () => new Date() }: { now?: () => Date } = {}): SupportBotSettingsStore => {
  let current = off;
  return {
    read: async () => ({ ...current }),
    set: async ({ enabled, actorId }) => ({ ...(current = { enabled, updatedBy: actorId, updatedAt: now().toISOString() }) })
  };
};
export const createPrismaSupportBotSettingsStore = (prisma: Pick<PrismaClient, 'supportBotSetting'>,
  now: () => Date = () => new Date()): SupportBotSettingsStore => {
  const map = (row: { enabled: boolean; updatedBy: string; updatedAt: Date } | null): SupportBotSettings =>
    row ? { enabled: row.enabled, updatedBy: row.updatedBy, updatedAt: row.updatedAt.toISOString() } : off;
  return {
    read: async () => map(await prisma.supportBotSetting.findUnique({ where: { id: 'global' } })),
    set: async ({ enabled, actorId }) => {
      const data = { enabled, updatedBy: actorId, updatedAt: now() };
      return map(await prisma.supportBotSetting.upsert({ where: { id: 'global' }, create: { id: 'global', ...data }, update: data }));
    }
  };
};
// Member polls read the switch every few seconds; a short cache keeps that off
// the database. Turning Dot off takes effect here immediately.
export const cacheSupportBotSettings = (store: SupportBotSettingsStore,
  { ttlMs = 10_000, now = Date.now }: { ttlMs?: number; now?: () => number } = {}): SupportBotSettingsStore => {
  let cached: { value: SupportBotSettings; at: number } | undefined;
  return {
    read: async () => {
      if (cached && now() - cached.at < ttlMs) return { ...cached.value };
      const value = await store.read();
      cached = { value, at: now() };
      return { ...value };
    },
    set: async input => {
      const value = await store.set(input);
      cached = { value, at: now() };
      return { ...value };
    }
  };
};

// Trims, removes control characters and fits the chat's message limit; an
// empty reply becomes a handoff so the member is never left with nothing.
export const normalizeBotAnswer = (answer: SupportBotAnswer): SupportBotAnswer => {
  const reply = answer.reply.replace(/\r\n?/g, '\n').replace(/[\x00-\x09\x0b-\x1f\x7f]/g, '')
    .replace(/\n{3,}/g, '\n\n').trim();
  if (!reply) return { reply: botHandoffMessage, handoff: true };
  return { reply: reply.length > maxSupportMessageLength ? `${reply.slice(0, maxSupportMessageLength - 1)}…` : reply,
    handoff: answer.handoff };
};

export type SupportBot = { respond: (member: AuthUser) => Promise<void> };
export const createSupportBot = ({ store, settings, provider, loadContext, runWithOwner, now = () => new Date(),
  newId = randomUUID }: {
  store: SupportChatStore; settings: SupportBotSettingsStore; provider?: SupportBotProvider;
  loadContext: (member: AuthUser) => Promise<SupportBotContext>;
  runWithOwner?: RunWithActiveOwner; now?: () => Date; newId?: () => string;
}): SupportBot => ({
  respond: async member => {
    if (!provider || !(await settings.read()).enabled) return;
    const read = await store.readThread(member.id);
    const thread = read?.thread;
    if (!read || !thread || !thread.botEnabled || thread.lastSender !== 'MEMBER') return;
    let answer: SupportBotAnswer;
    const since = new Date(now().getTime() - 86400000);
    if (await store.countSince({ userId: member.id, sender: 'BOT', since }) >= maxBotRepliesPerDay) {
      answer = { reply: botHandoffMessage, handoff: true };
    } else {
      try {
        const conversation = read.messages.slice(-botConversationTurns)
          .map(message => ({ sender: message.sender, body: scrubSupportText(message.body) }));
        answer = normalizeBotAnswer(await provider.answer({ conversation, context: await loadContext(member) }));
      } catch {
        answer = { reply: botHandoffMessage, handoff: true };
      }
    }
    // Only the write holds the owner lifetime, so account deletion never waits on the model.
    const write = () => store.replyAsBot({ userId: member.id, id: newId(), body: answer.reply,
      handoff: answer.handoff, triggerMessageId: thread.lastMessageId });
    await (runWithOwner ? runWithOwner(member.id, write) : write());
  }
});

/**
 * Runs Dot after a member message without delaying the send. One reply runs
 * per member at a time; messages sent meanwhile trigger one more pass that
 * answers the newest message with the whole conversation.
 */
export const createSupportBotScheduler = (bot: SupportBot, { onError }: { onError?: (error: unknown) => void } = {}) => {
  const running = new Map<string, Promise<void>>();
  const again = new Map<string, AuthUser>();
  const run = async (member: AuthUser) => {
    let next: AuthUser | undefined = member;
    while (next) {
      again.delete(member.id);
      try { await bot.respond(next); } catch (error) { onError?.(error); }
      next = again.get(member.id);
    }
    running.delete(member.id);
  };
  return {
    schedule: (member: AuthUser) => {
      if (running.has(member.id)) { again.set(member.id, member); return; }
      running.set(member.id, run(member));
    },
    // Tests and shutdown wait for in-flight replies.
    drain: async () => { while (running.size) await Promise.all([...running.values()]); }
  };
};
