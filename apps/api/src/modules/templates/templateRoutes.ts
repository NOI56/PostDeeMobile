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

// Templates are inserted into post captions, so the body shares the caption
// limit. The count cap bounds what one account can store.
export const templateTitleMaxLength = 80;
export const templateBodyMaxLength = 2200;
export const maxTemplatesPerUser = 30;

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

    if (
      [...title].length > templateTitleMaxLength ||
      [...body].length > templateBodyMaxLength
    ) {
      response.status(400).json({
        status: 'error',
        code: 'TEMPLATE_TOO_LONG',
        message: `title must be ${templateTitleMaxLength} and body ${templateBodyMaxLength} characters or fewer`
      });
      return;
    }

    // A count-then-create race can let a burst exceed the cap by a few rows,
    // which is acceptable for this storage bound.
    if ((await store.list({ userId: authUser.id })).length >= maxTemplatesPerUser) {
      response.status(409).json({
        status: 'error',
        code: 'TEMPLATE_LIMIT_REACHED',
        message: `Each account can save up to ${maxTemplatesPerUser} templates`
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

  router.delete('/templates/:id', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const removed = await store.remove({
      userId: authUser.id,
      templateId: String(request.params.id)
    });

    if (!removed) {
      response.status(404).json({
        status: 'error',
        message: 'Template not found'
      });
      return;
    }

    response.json({ status: 'ok' });
  });
};
