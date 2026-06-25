import type { Router } from 'express';

type HttpMethod = 'get' | 'post';

type PlannedRoute = {
  method: HttpMethod;
  path: string;
  feature: string;
  message: string;
};

const plannedRoutes: PlannedRoute[] = [];

export const registerPlannedRoutes = (router: Router) => {
  for (const route of plannedRoutes) {
    router[route.method](route.path, (_request, response) => {
      response.status(501).json({
        status: 'not_implemented',
        feature: route.feature,
        message: route.message
      });
    });
  }
};
