import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { PublishQueue } from './publishQueue.js';

export const registerPublishQueueRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  publishQueue: PublishQueue
) => {
  router.get('/queue/jobs', authMiddleware, async (_request, response) => {
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
      jobs: await publishQueue.list({ userId: authUser.id })
    });
  });
};
