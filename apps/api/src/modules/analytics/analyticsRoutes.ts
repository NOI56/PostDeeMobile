import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { AnalyticsStore } from './analyticsStore.js';

export const registerAnalyticsRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  _subscriptionStore: SubscriptionStore,
  _analyticsStore: AnalyticsStore
) => {
  router.get('/analytics/summary', authMiddleware, (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    response.status(410).json({
      status: 'error',
      code: 'ANALYTICS_RETIRED',
      message: 'Post analytics has been retired'
    });
  });
};
