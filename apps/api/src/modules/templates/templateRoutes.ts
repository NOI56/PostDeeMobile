import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import type { TemplateStore } from './templateStore.js';

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

export const registerTemplateRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  store: TemplateStore,
  userStore?: UserStore
) => {
  router.get('/templates', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    response.json({
      status: 'ok',
      templates: await store.list({ userId: authUser.id })
    });
  });

  router.post('/templates', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const title = readRequiredString(request.body?.title);
    const body = readRequiredString(request.body?.body);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!title || !body) {
      response.status(400).json({
        status: 'error',
        message: 'title and body are required'
      });
      return;
    }

    await userStore?.ensure(authUser);
    const template = await store.create({ userId: authUser.id, title, body });

    response.status(201).json({
      status: 'ok',
      template
    });
  });
};
