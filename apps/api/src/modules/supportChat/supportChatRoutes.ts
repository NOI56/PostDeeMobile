import type { RequestHandler, Response, Router } from 'express';
import { readAuthUser, type AuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import {
  SupportChatError, memberMessageView, readSupportMessageBody, readSupportMessageId, type SupportChatStore
} from './supportChat.js';

const messages: Record<string, string> = {
  SUPPORT_MESSAGE_INVALID: 'Write a message of 1-1000 characters.',
  SUPPORT_MESSAGE_CONFLICT: 'This message id was already used for another message.',
  SUPPORT_MESSAGE_LIMIT: 'Too many support messages today. Please wait for the team to reply.',
  SUPPORT_CURSOR_INVALID: 'The chat position is invalid. Reload the chat.',
  SUPPORT_THREAD_NOT_FOUND: 'Send a message first.'
};
const sendError = (response: Response, error: unknown) => {
  if (!(error instanceof SupportChatError)) throw error;
  response.status(error.status).json({ status: 'error', code: error.code, message: messages[error.code] ?? 'Support chat request failed.' });
};

/**
 * Registers the member side of the support chat: `GET /support/chat` reads
 * the member's own conversation (only messages after `after` when polling),
 * `POST /support/chat/messages` sends one message with a client-made id, and
 * `POST /support/chat/handoff` asks for a person instead of Dot.
 */
export const registerSupportChatRoutes = (router: Router, authMiddleware: RequestHandler,
  { store, userStore, sendRateLimit, bot }: { store: SupportChatStore; userStore: UserStore; sendRateLimit?: RequestHandler;
    // Dot, when configured: whether it answers now, and the hook that wakes it.
    bot?: { available: () => Promise<boolean>; onMemberMessage: (member: AuthUser) => void } }) => {
  const botAvailable = async () => { try { return await bot?.available() ?? false; } catch { return false; } };
  router.get('/support/chat', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    if (!authUser) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const after = request.query.after;
    if (after !== undefined && (typeof after !== 'string' || after.length > 200)) {
      sendError(response, new SupportChatError('SUPPORT_CURSOR_INVALID', 400)); return;
    }
    try {
      const [read, available] = await Promise.all([store.readForMember(authUser.id, { after }), botAvailable()]);
      response.set('Cache-Control', 'private, no-store');
      response.json({ status: 'ok',
        thread: read.thread ? { status: read.thread.status, lastMessageAt: read.thread.lastMessageAt, botEnabled: read.thread.botEnabled } : null,
        bot: { available },
        messages: read.messages.map(memberMessageView), ...(read.cursor ? { cursor: read.cursor } : {}) });
    } catch (error) { sendError(response, error); }
  });

  router.post('/support/chat/messages', authMiddleware, ...(sendRateLimit ? [sendRateLimit] : []), async (request, response) => {
    const authUser = readAuthUser(response.locals);
    if (!authUser) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    try {
      const id = readSupportMessageId(request.body?.id);
      const body = readSupportMessageBody(request.body?.body);
      const user = await userStore.ensure(authUser);
      const message = await store.postFromMember({ userId: user.id, id, body });
      // Dot answers after the response, so a slow model never delays the send.
      bot?.onMemberMessage({ ...authUser, id: user.id });
      response.status(201).json({ status: 'ok', message: memberMessageView(message) });
    } catch (error) { sendError(response, error); }
  });

  router.post('/support/chat/handoff', authMiddleware, ...(sendRateLimit ? [sendRateLimit] : []), async (_request, response) => {
    const authUser = readAuthUser(response.locals);
    if (!authUser) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    try {
      const thread = await store.requestTeam(authUser.id);
      response.json({ status: 'ok', thread: { status: thread.status, lastMessageAt: thread.lastMessageAt, botEnabled: thread.botEnabled } });
    } catch (error) { sendError(response, error); }
  });
};
