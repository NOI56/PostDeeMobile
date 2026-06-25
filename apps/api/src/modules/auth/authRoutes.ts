import type { RequestHandler, Router } from 'express';

import { readAuthUser } from './authTypes.js';

export const registerAuthRoutes = (router: Router, authMiddleware: RequestHandler) => {
  router.get('/auth/me', authMiddleware, (_request, response) => {
    response.json({
      status: 'ok',
      user: readAuthUser(response.locals)
    });
  });
};
