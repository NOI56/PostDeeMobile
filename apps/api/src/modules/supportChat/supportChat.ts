import { AdminError } from '../admin/trialAccess.js';

// One continuous support conversation per member, like a shop chat. A member
// message reopens a closed thread; replies come from the PostDee team or from
// Dot, the AI helper. Dot answers most messages; asking for a person flags the
// thread for the team without silencing Dot, since the team may be one person.
export const supportThreadStatuses = ['WAITING_TEAM', 'WAITING_MEMBER', 'CLOSED'] as const;
export type SupportThreadStatus = typeof supportThreadStatuses[number];
export type SupportSender = 'MEMBER' | 'TEAM' | 'BOT';
export const maxSupportMessageLength = 1000;
// Member messages allowed per rolling 24 hours, so one account cannot flood the inbox.
export const maxMemberMessagesPerDay = 100;
export const supportReadPageSize = 100;
export const supportAdminThreadMessages = 200;
export const supportThreadPageSize = 50;

export type SupportMessage = { id: string; userId: string; sender: SupportSender;
  // Administrator Firebase UID for team replies; never sent to members.
  authorId: string | null; body: string; createdAt: string };
export type SupportThread = { userId: string; status: SupportThreadStatus; lastSender: SupportSender;
  lastMessageId: string; lastPreview: string; lastMessageAt: string; createdAt: string; updatedAt: string;
  // Dot may answer this thread. Only an administrator's switch turns it off; closing turns it back on.
  botEnabled: boolean;
  // Someone asked for a person. The thread stays WAITING_TEAM through Dot's
  // replies until the team answers or closes it.
  teamRequested: boolean;
  email?: string; displayName?: string | null };
export type SupportMemberRead = { thread: SupportThread | null; messages: SupportMessage[]; cursor?: string };
export type SupportThreadPage = { rows: SupportThread[]; nextCursor?: string };
export type SupportChatStore = {
  readForMember: (userId: string, options: { after?: string }) => Promise<SupportMemberRead>;
  postFromMember: (input: { userId: string; id: string; body: string }) => Promise<SupportMessage>;
  // Internal receipt lets notification callers distinguish a new message from a retry,
  // and see whether it moved the thread into WAITING_TEAM (previousStatus; null = new
  // thread) and whether the in-app bot may answer it. Only meaningful when created.
  postFromMemberWithReceipt: (input: { userId: string; id: string; body: string }) => Promise<{
    message: SupportMessage; created: boolean; previousStatus: SupportThreadStatus | null; botEnabled: boolean }>;
  // Pending replies, not unread messages; independent of inbox filters or pages.
  countWaitingForTeam: () => Promise<number>;
  listThreads: (options: { status?: SupportThreadStatus; query?: string; cursor?: string }) => Promise<SupportThreadPage>;
  readThread: (userId: string) => Promise<{ thread: SupportThread; messages: SupportMessage[]; hasEarlier: boolean } | null>;
  // `created` is false when a retried reply already landed, so callers notify once.
  replyAsTeam: (input: { userId: string; id: string; actorId: string; body: string }) => Promise<{ message: SupportMessage; created: boolean }>;
  close: (input: { userId: string; lastMessageId: string }) => Promise<SupportThread>;
  // Stores Dot's reply only if `triggerMessageId` is still the newest message
  // and the thread's bot is on; returns null when the conversation moved on.
  replyAsBot: (input: { userId: string; id: string; body: string; handoff: boolean; triggerMessageId: string }) => Promise<SupportMessage | null>;
  // The member asked for a person: the thread waits for the team; Dot keeps helping.
  requestTeam: (userId: string) => Promise<SupportThread>;
  setBotEnabled: (input: { userId: string; enabled: boolean }) => Promise<SupportThread>;
  countSince: (input: { userId: string; sender: SupportSender; since: Date }) => Promise<number>;
  // Used by account deletion. Optional because the Prisma store relies on the User cascade.
  deleteAllForUser?: (userId: string) => Promise<void>;
};
export class SupportChatError extends Error {
  constructor(readonly code: string, readonly status = 409) { super(code); }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const readSupportMessageId = (value: unknown) => {
  if (typeof value !== 'string' || !uuidPattern.test(value)) throw new SupportChatError('SUPPORT_MESSAGE_INVALID', 400);
  return value.toLowerCase();
};
// Keeps newlines (normalized to \n) and rejects every other control character.
export const readSupportMessageBody = (value: unknown) => {
  if (typeof value !== 'string') throw new SupportChatError('SUPPORT_MESSAGE_INVALID', 400);
  const body = value.replace(/\r\n?/g, '\n').trim();
  if (!body || body.length > maxSupportMessageLength || /[\x00-\x09\x0b-\x1f\x7f]/.test(body)) {
    throw new SupportChatError('SUPPORT_MESSAGE_INVALID', 400);
  }
  return body;
};
export const supportPreview = (body: string) => body.replace(/\s+/g, ' ').slice(0, 120);
export const supportMessageCursor = (message: Pick<SupportMessage, 'createdAt' | 'id'>) =>
  Buffer.from(JSON.stringify([message.createdAt, message.id])).toString('base64url');
export const readSupportCursor = (cursor: string | undefined, invalid: () => Error) => {
  if (cursor === undefined) return;
  try {
    const [time, id] = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown[];
    if (typeof time !== 'string' || typeof id !== 'string' || !id || id.length > 128 || new Date(time).toISOString() !== time) throw new Error();
    return { time: new Date(time), id };
  } catch { throw invalid(); }
};
export const readMemberCursor = (cursor?: string) =>
  readSupportCursor(cursor, () => new SupportChatError('SUPPORT_CURSOR_INVALID', 400));
export const readAdminThreadCursor = (cursor?: string) =>
  readSupportCursor(cursor, () => new AdminError('ADMIN_FILTER_INVALID', 400));
export const supportThreadCursor = (thread: Pick<SupportThread, 'lastMessageAt' | 'userId'>) =>
  supportMessageCursor({ createdAt: thread.lastMessageAt, id: thread.userId });
// A retried send returns the stored message; a reused id with other content is a conflict.
export const replaySupportMessage = (existing: SupportMessage, expected: Pick<SupportMessage, 'userId' | 'sender' | 'body'>) => {
  if (existing.userId !== expected.userId || existing.sender !== expected.sender || existing.body !== expected.body) {
    throw new SupportChatError('SUPPORT_MESSAGE_CONFLICT');
  }
  return existing;
};
export const memberMessageView = (message: SupportMessage) =>
  ({ id: message.id, sender: message.sender, body: message.body, createdAt: message.createdAt });

const after = (a: { createdAt: string; id: string }, b: { time: Date; id: string }) =>
  a.createdAt > b.time.toISOString() || (a.createdAt === b.time.toISOString() && a.id > b.id);
const oldestFirst = (a: SupportMessage, b: SupportMessage) => a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id);

export const createMemorySupportChatStore = ({ now = () => new Date() }: { now?: () => Date } = {}): SupportChatStore => {
  const threads = new Map<string, SupportThread>();
  const messages = new Map<string, SupportMessage>();
  const threadMessages = (userId: string) => [...messages.values()].filter(m => m.userId === userId).sort(oldestFirst);
  const append = (message: SupportMessage, status: SupportThreadStatus, teamRequested?: boolean) => {
    const previous = threads.get(message.userId);
    messages.set(message.id, message);
    threads.set(message.userId, { userId: message.userId, status, lastSender: message.sender, lastMessageId: message.id,
      lastPreview: supportPreview(message.body), lastMessageAt: message.createdAt,
      createdAt: previous?.createdAt ?? message.createdAt, updatedAt: message.createdAt,
      botEnabled: previous?.botEnabled ?? true, teamRequested: teamRequested ?? previous?.teamRequested ?? false });
    return structuredClone(message);
  };
  const update = (userId: string, change: Partial<SupportThread>) => {
    const thread = threads.get(userId);
    if (!thread) throw new SupportChatError('SUPPORT_THREAD_NOT_FOUND', 404);
    const next = { ...thread, ...change, updatedAt: now().toISOString() };
    threads.set(userId, next);
    return structuredClone(next);
  };
  const postFromMemberWithReceipt: SupportChatStore['postFromMemberWithReceipt'] = async ({ userId, id, body }) => {
    const existing = messages.get(id);
    const previous = threads.get(userId);
    const before = { previousStatus: previous?.status ?? null, botEnabled: previous?.botEnabled ?? true };
    if (existing) return { message: structuredClone(replaySupportMessage(existing, { userId, sender: 'MEMBER', body })), created: false, ...before };
    const time = now();
    const since = new Date(time.getTime() - 86400000).toISOString();
    if (threadMessages(userId).filter(m => m.sender === 'MEMBER' && m.createdAt > since).length >= maxMemberMessagesPerDay) {
      throw new SupportChatError('SUPPORT_MESSAGE_LIMIT', 429);
    }
    return { message: append({ id, userId, sender: 'MEMBER', authorId: null, body, createdAt: time.toISOString() }, 'WAITING_TEAM'),
      created: true, ...before };
  };
  return {
    readForMember: async (userId, options) => {
      const cursor = readMemberCursor(options.after);
      const all = threadMessages(userId);
      const page = cursor ? all.filter(m => after(m, cursor)).slice(0, supportReadPageSize) : all.slice(-supportReadPageSize);
      const last = page.at(-1);
      return structuredClone({ thread: threads.get(userId) ?? null, messages: page,
        ...(last ? { cursor: supportMessageCursor(last) } : options.after ? { cursor: options.after } : {}) });
    },
    postFromMember: async input => (await postFromMemberWithReceipt(input)).message,
    postFromMemberWithReceipt,
    countWaitingForTeam: async () => [...threads.values()].filter(thread => thread.status === 'WAITING_TEAM').length,
    listThreads: async ({ status, query, cursor }) => {
      const before = readAdminThreadCursor(cursor);
      const text = query?.trim().toLowerCase();
      const rows = [...threads.values()]
        .filter(t => (!status || t.status === status) && (!text || t.userId.toLowerCase().includes(text)))
        .sort((a, b) => b.lastMessageAt.localeCompare(a.lastMessageAt) || b.userId.localeCompare(a.userId))
        .filter(t => !before || t.lastMessageAt < before.time.toISOString() ||
          (t.lastMessageAt === before.time.toISOString() && t.userId < before.id));
      const page = rows.slice(0, supportThreadPageSize);
      return structuredClone({ rows: page,
        ...(rows.length > supportThreadPageSize ? { nextCursor: supportThreadCursor(page.at(-1)!) } : {}) });
    },
    readThread: async userId => {
      const thread = threads.get(userId);
      if (!thread) return null;
      const all = threadMessages(userId);
      return structuredClone({ thread, messages: all.slice(-supportAdminThreadMessages), hasEarlier: all.length > supportAdminThreadMessages });
    },
    replyAsTeam: async ({ userId, id, actorId, body }) => {
      const existing = messages.get(id);
      if (existing) return { message: structuredClone(replaySupportMessage(existing, { userId, sender: 'TEAM', body })), created: false };
      if (!threads.has(userId)) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      return { message: append({ id, userId, sender: 'TEAM', authorId: actorId, body, createdAt: now().toISOString() }, 'WAITING_MEMBER', false), created: true };
    },
    close: async ({ userId, lastMessageId }) => {
      const thread = threads.get(userId);
      if (!thread) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      if (thread.lastMessageId !== lastMessageId) throw new AdminError('ADMIN_SUPPORT_THREAD_CHANGED');
      return update(userId, { status: 'CLOSED', botEnabled: true, teamRequested: false });
    },
    replyAsBot: async ({ userId, id, body, handoff, triggerMessageId }) => {
      const thread = threads.get(userId);
      if (!thread || !thread.botEnabled || thread.lastMessageId !== triggerMessageId || messages.has(id)) return null;
      const teamRequested = handoff || thread.teamRequested;
      return append({ id, userId, sender: 'BOT', authorId: null, body, createdAt: now().toISOString() },
        teamRequested ? 'WAITING_TEAM' : 'WAITING_MEMBER', teamRequested);
    },
    requestTeam: async userId => update(userId, { status: 'WAITING_TEAM', teamRequested: true }),
    setBotEnabled: async ({ userId, enabled }) => {
      if (!threads.has(userId)) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      return update(userId, { botEnabled: enabled });
    },
    countSince: async ({ userId, sender, since }) =>
      threadMessages(userId).filter(m => m.sender === sender && m.createdAt > since.toISOString()).length,
    deleteAllForUser: async userId => {
      threads.delete(userId);
      for (const [id, message] of messages) if (message.userId === userId) messages.delete(id);
    }
  };
};
