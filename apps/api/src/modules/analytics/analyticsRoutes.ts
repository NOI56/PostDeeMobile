import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { AnalyticsStore } from './analyticsStore.js';

export const registerAnalyticsRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  subscriptionStore: SubscriptionStore,
  analyticsStore: AnalyticsStore
) => {
  router.get('/analytics/summary', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if ((await subscriptionStore.getPlan(authUser)) !== 'PRO') {
      response.status(402).json({
        status: 'error',
        code: 'PRO_REQUIRED',
        message: 'Unified Analytics requires the Pro plan'
      });
      return;
    }

    response.json({
      status: 'ok',
      summary: await analyticsStore.summaryForUser(authUser.id)
    });
  });
};
