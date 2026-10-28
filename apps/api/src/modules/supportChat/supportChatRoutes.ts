import type { RequestHandler, Response, Router } from 'express';
import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import {
  SupportChatError, memberMessageView, readSupportMessageBody, readSupportMessageId, type SupportChatStore
} from './supportChat.js';

const messages: Record<string, string> = {
  SUPPORT_MESSAGE_INVALID: 'Write a message of 1-1000 characters.',
  SUPPORT_MESSAGE_CONFLICT: 'This message id was already used for another message.',
  SUPPORT_MESSAGE_LIMIT: 'Too many support messages today. Please wait for the team to reply.',
  SUPPORT_CURSOR_INVALID: 'The chat position is invalid. Reload the chat.'
};
const sendError = (response: Response, error: unknown) => {
  if (!(error instanceof SupportChatError)) throw error;
  response.status(error.status).json({ status: 'error', code: error.code, message: messages[error.code] ?? 'Support chat request failed.' });
};

/**
 * Registers the member side of the support chat: `GET /support/chat` reads
 * the member's own conversation (only messages after `after` when polling)
 * and `POST /support/chat/messages` sends one message with a client-made id.
 */
export const registerSupportChatRoutes = (router: Router, authMiddleware: RequestHandler,
  { store, userStore, sendRateLimit }: { store: SupportChatStore; userStore: UserStore; sendRateLimit?: RequestHandler }) => {
  router.get('/support/chat', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    if (!authUser) { response.status(401).json({ status: 'error', message: 'Authenticated user is required' }); return; }
    const after = request.query.after;
    if (after !== undefined && (typeof after !== 'string' || after.length > 200)) {
      sendError(response, new SupportChatError('SUPPORT_CURSOR_INVALID', 400)); return;
    }
    try {
      const read = await store.readForMember(authUser.id, { after });
      response.set('Cache-Control', 'private, no-store');
      response.json({ status: 'ok',
        thread: read.thread ? { status: read.thread.status, lastMessageAt: read.thread.lastMessageAt } : null,
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
      response.status(201).json({ status: 'ok', message: memberMessageView(message) });
    } catch (error) { sendError(response, error); }
  });
};
