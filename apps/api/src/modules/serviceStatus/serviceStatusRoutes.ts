import type { Router } from 'express';
import type { ServiceIncident, ServiceIncidentStore } from './serviceIncident.js';

const publicIncident = (incident: ServiceIncident) => ({ id: incident.id, title: incident.title,
  message: incident.message, platforms: incident.platforms, stage: incident.stage,
  startedAt: incident.startedAt, updatedAt: incident.updatedAt });

/**
 * Registers `GET /support/status`, the open service notices shown in the app.
 * It needs no sign-in so the notice still reaches people while login itself
 * is failing; the body only holds what administrators wrote for customers.
 */
export const registerServiceStatusRoutes = (router: Router,
  { store, now = () => new Date() }: { store: ServiceIncidentStore; now?: () => Date }) => {
  router.get('/support/status', async (_request, response) => {
    try {
      const incidents = await store.active();
      response.set('Cache-Control', 'public, max-age=30');
      response.json({ status: 'ok', incidents: incidents.map(publicIncident), checkedAt: now().toISOString() });
    } catch {
      response.set('Cache-Control', 'no-store');
      response.status(503).json({ status: 'error', code: 'SERVICE_STATUS_UNAVAILABLE',
        message: 'Service status is temporarily unavailable.' });
    }
  });
};
