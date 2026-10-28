import { Prisma, type PrismaClient } from '@prisma/client';
import { runActiveOwnerTransaction } from '../account/ownerLifecycle.js';
import { AdminError } from '../admin/trialAccess.js';
import {
  SupportChatError, maxMemberMessagesPerDay, readAdminThreadCursor, readMemberCursor, replaySupportMessage,
  supportAdminThreadMessages, supportMessageCursor, supportPreview, supportReadPageSize, supportThreadCursor,
  supportThreadPageSize,
  type SupportChatStore, type SupportMessage, type SupportSender, type SupportThread, type SupportThreadStatus
} from './supportChat.js';

type MessageRow = Prisma.SupportMessageGetPayload<object>;
type ThreadRow = Prisma.SupportThreadGetPayload<object> & { user?: { email: string; displayName: string | null } };
const mapMessage = (r: MessageRow): SupportMessage => ({ id: r.id, userId: r.userId, sender: r.sender as SupportSender,
  authorId: r.authorId, body: r.body, createdAt: r.createdAt.toISOString() });
const mapThread = (r: ThreadRow): SupportThread => ({ userId: r.userId, status: r.status as SupportThreadStatus,
  lastSender: r.lastSender as SupportSender, lastMessageId: r.lastMessageId, lastPreview: r.lastPreview,
  lastMessageAt: r.lastMessageAt.toISOString(), createdAt: r.createdAt.toISOString(), updatedAt: r.updatedAt.toISOString(),
  botEnabled: r.botEnabled, teamRequested: r.teamRequested,
  ...(r.user ? { email: r.user.email, displayName: r.user.displayName } : {}) });
const afterCursor = (cursor: { time: Date; id: string }): Prisma.SupportMessageWhereInput =>
  ({ OR: [{ createdAt: { gt: cursor.time } }, { createdAt: cursor.time, id: { gt: cursor.id } }] });
type ThreadChange = { status?: SupportThreadStatus; teamRequested?: boolean };
const isDuplicateId = (error: unknown) => error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';

export const createPrismaSupportChatStore = (prisma: PrismaClient, now: () => Date = () => new Date()): SupportChatStore => {
  // Writes take the member's active-owner lock, so no chat row lands while the
  // account is being deleted; a racing duplicate id replays the stored message.
  const append = async (message: Omit<SupportMessage, 'createdAt'>, status: SupportThreadStatus,
    guard: (tx: Prisma.TransactionClient, time: Date) => Promise<ThreadChange | void>, change: ThreadChange = {}) => {
    const expected = { userId: message.userId, sender: message.sender, body: message.body };
    try {
      return await runActiveOwnerTransaction(prisma, message.userId, async tx => {
        const existing = await tx.supportMessage.findUnique({ where: { id: message.id } });
        if (existing) return { message: replaySupportMessage(mapMessage(existing), expected), created: false };
        const time = now();
        // A guard may decide the final thread state from the locked row.
        const { status: finalStatus = status, ...flags } = { ...change, ...await guard(tx, time) };
        const last = { status: finalStatus, lastSender: message.sender, lastMessageId: message.id,
          lastPreview: supportPreview(message.body), lastMessageAt: time, updatedAt: time, ...flags };
        await tx.supportThread.upsert({ where: { userId: message.userId }, update: last,
          create: { userId: message.userId, ...last, createdAt: time } });
        return { message: mapMessage(await tx.supportMessage.create({ data: { ...message, createdAt: time } })), created: true };
      });
    } catch (error) {
      if (!isDuplicateId(error)) throw error;
      const existing = await prisma.supportMessage.findUnique({ where: { id: message.id } });
      if (!existing) throw error;
      return { message: replaySupportMessage(mapMessage(existing), expected), created: false };
    }
  };
  const postFromMemberWithReceipt: SupportChatStore['postFromMemberWithReceipt'] = ({ userId, id, body }) =>
    append({ id, userId, sender: 'MEMBER', authorId: null, body }, 'WAITING_TEAM', async (tx, time) => {
      const recent = await tx.supportMessage.count({ where: { userId, sender: 'MEMBER',
        createdAt: { gt: new Date(time.getTime() - 86400000) } } });
      if (recent >= maxMemberMessagesPerDay) throw new SupportChatError('SUPPORT_MESSAGE_LIMIT', 429);
    });
  return {
    readForMember: async (userId, options) => {
      const cursor = readMemberCursor(options.after);
      const thread = await prisma.supportThread.findUnique({ where: { userId } });
      const messages = cursor
        ? (await prisma.supportMessage.findMany({ where: { userId, ...afterCursor(cursor) },
          orderBy: [{ createdAt: 'asc' }, { id: 'asc' }], take: supportReadPageSize })).map(mapMessage)
        : (await prisma.supportMessage.findMany({ where: { userId },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: supportReadPageSize })).map(mapMessage).reverse();
      const last = messages.at(-1);
      return { thread: thread ? mapThread(thread) : null, messages,
        ...(last ? { cursor: supportMessageCursor(last) } : options.after ? { cursor: options.after } : {}) };
    },
    postFromMember: async input => (await postFromMemberWithReceipt(input)).message,
    postFromMemberWithReceipt,
    countWaitingForTeam: () => prisma.supportThread.count({ where: { status: 'WAITING_TEAM' } }),
    replyAsTeam: ({ userId, id, actorId, body }) => append({ id, userId, sender: 'TEAM', authorId: actorId, body },
      'WAITING_MEMBER', async tx => {
        if (!await tx.supportThread.findUnique({ where: { userId }, select: { userId: true } })) {
          throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
        }
      }, { teamRequested: false }),
    replyAsBot: async ({ userId, id, body, handoff, triggerMessageId }) => {
      try {
        // The guard runs in the same owner-locked transaction as the insert, so
        // a member message that lands first makes this reply a no-op.
        const result = await append({ id, userId, sender: 'BOT', authorId: null, body }, 'WAITING_MEMBER',
          async tx => {
            const thread = await tx.supportThread.findUnique({ where: { userId },
              select: { botEnabled: true, lastMessageId: true, teamRequested: true } });
            if (!thread?.botEnabled || thread.lastMessageId !== triggerMessageId) throw new SupportChatError('SUPPORT_BOT_SKIPPED');
            // A thread already waiting for a person keeps waiting through Dot's answers.
            const teamRequested = handoff || thread.teamRequested;
            return { status: teamRequested ? 'WAITING_TEAM' : 'WAITING_MEMBER', teamRequested };
          });
        return result.created ? result.message : null;
      } catch (error) {
        if (error instanceof SupportChatError && error.code === 'SUPPORT_BOT_SKIPPED') return null;
        throw error;
      }
    },
    requestTeam: async userId => {
      const { count } = await prisma.supportThread.updateMany({ where: { userId },
        data: { status: 'WAITING_TEAM', teamRequested: true, updatedAt: now() } });
      const thread = count === 1 ? await prisma.supportThread.findUnique({ where: { userId } }) : null;
      if (!thread) throw new SupportChatError('SUPPORT_THREAD_NOT_FOUND', 404);
      return mapThread(thread);
    },
    setBotEnabled: async ({ userId, enabled }) => {
      const { count } = await prisma.supportThread.updateMany({ where: { userId }, data: { botEnabled: enabled, updatedAt: now() } });
      const thread = count === 1 ? await prisma.supportThread.findUnique({ where: { userId } }) : null;
      if (!thread) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      return mapThread(thread);
    },
    countSince: ({ userId, sender, since }) =>
      prisma.supportMessage.count({ where: { userId, sender, createdAt: { gt: since } } }),
    listThreads: async ({ status, query, cursor }) => {
      const before = readAdminThreadCursor(cursor);
      const literal = query?.replace(/[\\%_]/g, '\\$&');
      const rows = await prisma.supportThread.findMany({
        where: { ...(status ? { status } : {}),
          ...(literal ? { user: { OR: [{ email: { contains: literal, mode: 'insensitive' } },
            { displayName: { contains: literal, mode: 'insensitive' } }] } } : {}),
          ...(before ? { OR: [{ lastMessageAt: { lt: before.time } }, { lastMessageAt: before.time, userId: { lt: before.id } }] } : {}) },
        include: { user: { select: { email: true, displayName: true } } },
        orderBy: [{ lastMessageAt: 'desc' }, { userId: 'desc' }], take: supportThreadPageSize + 1 });
      const page = rows.slice(0, supportThreadPageSize).map(mapThread);
      return { rows: page, ...(rows.length > supportThreadPageSize ? { nextCursor: supportThreadCursor(page.at(-1)!) } : {}) };
    },
    readThread: async userId => {
      const thread = await prisma.supportThread.findUnique({ where: { userId } });
      if (!thread) return null;
      const rows = await prisma.supportMessage.findMany({ where: { userId }, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: supportAdminThreadMessages + 1 });
      return { thread: mapThread(thread), messages: rows.slice(0, supportAdminThreadMessages).map(mapMessage).reverse(),
        hasEarlier: rows.length > supportAdminThreadMessages };
    },
    close: async ({ userId, lastMessageId }) => {
      const { count } = await prisma.supportThread.updateMany({ where: { userId, lastMessageId },
        data: { status: 'CLOSED', botEnabled: true, teamRequested: false, updatedAt: now() } });
      const thread = await prisma.supportThread.findUnique({ where: { userId } });
      if (!thread) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      if (count !== 1) throw new AdminError('ADMIN_SUPPORT_THREAD_CHANGED');
      return mapThread(thread);
    }
    // No deleteAllForUser: deleting the User row cascades the whole conversation.
  };
};
