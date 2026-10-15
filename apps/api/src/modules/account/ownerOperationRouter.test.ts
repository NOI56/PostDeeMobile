import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createOwnerOperationRouter } from './ownerOperationRouter.js';
import type { RunWithActiveOwner } from './ownerOperationQueue.js';
import { createOwnerOperationRunner } from './prismaOwnerOperationCoordinator.js';

const deferred = () => {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
};

describe('owner operation route lifetime', () => {
  const fixture = () => {
    const entered = vi.fn();
    const completed = vi.fn();
    const run: RunWithActiveOwner = async (_ownerId, operation) => {
      entered();
      try { return await operation(); } finally { completed(); }
    };
    const app = express();
    const router = createOwnerOperationRouter(express.Router(), run);
    const auth: express.RequestHandler = (_request, response, next) => {
      response.locals.authUser = { id: 'owner-a', provider: 'mock' };
      next();
    };
    app.use(router);
    return { app, router, auth, entered, completed };
  };

  it('keeps ownership after response.end until async finally cleanup settles', async () => {
    const { app, router, auth, entered, completed } = fixture();
    const gate = deferred();
    const started = deferred();
    router.post('/ai-edits/plan', auth, async (_request, response) => {
      try { response.json({ status: 'ok' }); } finally {
        started.resolve();
        await gate.promise;
      }
    });
    const response = await request(app).post('/ai-edits/plan');
    await started.promise;
    expect(response.status).toBe(200);
    expect(entered).toHaveBeenCalledOnce();
    expect(completed).not.toHaveBeenCalled();
    gate.resolve();
    await vi.waitFor(() => expect(completed).toHaveBeenCalledOnce());
  });

  it.each(['/AUTH/ME/', '/SOCIAL-CONNECTIONS/', '/BILLING/SUBSCRIPTION/', '/UPLOADS/session-a/'])
  ('tracks the full handler of mutating GET %s', async (path) => {
    const { app, router, auth, entered, completed } = fixture();
    router.get(path, auth, async (_request, response) => { response.json({ status: 'ok' }); });
    await request(app).get(path).expect(200);
    expect(entered).toHaveBeenCalledOnce();
    await vi.waitFor(() => expect(completed).toHaveBeenCalledOnce());
  });

  it('does not acquire an active-operation ticket for deletion or readiness', async () => {
    const { app, router, auth, entered } = fixture();
    router.delete('/ACCOUNT/', auth, async (_request, response) => { response.json({ status: 'ok' }); });
    router.get('/ACCOUNT/DELETION-READINESS/', auth, async (_request, response) => { response.json({ status: 'ok' }); });
    await request(app).delete('/ACCOUNT/').expect(200);
    await request(app).get('/ACCOUNT/DELETION-READINESS/').expect(200);
    expect(entered).not.toHaveBeenCalled();
  });

  it('rejects admission before calling the route', async () => {
    const app = express();
    const denied: RunWithActiveOwner = async () => { throw new Error('denied'); };
    const router = createOwnerOperationRouter(express.Router(), denied);
    const work = vi.fn();
    router.post('/uploads', (_request, response, next) => {
      response.locals.authUser = { id: 'owner-a', provider: 'mock' }; next();
    }, work);
    app.use(router);
    app.use((_error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
      response.status(409).json({ status: 'error' });
    });
    await request(app).post('/uploads').expect(409);
    expect(work).not.toHaveBeenCalled();
  });
  it.each([
    ['/POSTS/SUBMISSIONS/RECOVER/', false],
    ['/posts/submissions/recover-extra', true]
  ])('only the exact read-only recovery route releases a 503 ticket: %s', async (path, retained) => {
    const release = vi.fn(async () => undefined);
    const run = createOwnerOperationRunner({ admit: async () => 'read-ticket', release });
    const app = express();
    const router = createOwnerOperationRouter(express.Router(), run);
    router.post(path, (_request, response, next) => {
      response.locals.authUser = { id: 'owner', provider: 'mock' }; next();
    }, async (_request, response) => { response.status(503).json({ code: 'POST_SUBMISSION_RECOVERY_UNAVAILABLE' }); });
    app.use(router);
    await request(app).post(path).expect(503);
    if (retained) expect(release).not.toHaveBeenCalled();
    else await vi.waitFor(() => expect(release).toHaveBeenCalledExactlyOnceWith('owner', 'read-ticket'));
  });

  it('protects chained route registrations too', async () => {
    const { app, router, auth, entered } = fixture();
    const handler: express.RequestHandler = async (_request, response) => { response.json({ status: 'ok' }); };
    router.post('/first', auth, handler).post('/second', auth, handler);
    await request(app).post('/first').expect(200);
    await request(app).post('/second').expect(200);
    expect(entered).toHaveBeenCalledTimes(2);
  });

  it.each([
    ['SOCIAL_CONNECTION_UNAVAILABLE', false],
    ['STORE_VERIFIER_NOT_CONFIGURED', false],
    ['REVENUECAT_RESYNC_NOT_CONFIGURED', false],
    ['GOOGLE_PLAY_ACCESS_TOKEN_NOT_CONFIGURED', false],
    ['APPLE_ROOT_CERTIFICATES_NOT_CONFIGURED', false],
    ['TIKTOK_PUBLISHING_UNAVAILABLE', false],
    ['TIKTOK_CREATOR_INFO_UNAVAILABLE', false],
    ['TIKTOK_CREATOR_INFO_INVALID', false],
    ['PUBLISH_OUTCOME_UNKNOWN', true],
    ['SOCIAL_CONNECTION_FAILED', true]
  ])('retains only uncertain remote error %s', async (code, retained) => {
    const release = vi.fn(async () => undefined);
    const run = createOwnerOperationRunner({ admit: async () => 'operation-a', release });
    const app = express();
    const router = createOwnerOperationRouter(express.Router(), run);
    router.post('/action', (_request, response, next) => {
      response.locals.authUser = { id: 'owner-a', provider: 'mock' }; next();
    }, async (_request, response) => { response.status(503).json({ status: 'error', code }); });
    app.use(router);
    await request(app).post('/action').expect(503);
    if (retained) expect(release).not.toHaveBeenCalled();
    else await vi.waitFor(() => expect(release).toHaveBeenCalledOnce());
  });

  it('does not release running handler work when the HTTP client disconnects', async () => {
    const { app, router, auth, completed } = fixture();
    const gate = deferred();
    const started = deferred();
    router.post('/uploads', auth, async (_request, response) => {
      started.resolve();
      await gate.promise;
      response.json({ status: 'ok' });
    });
    const call = request(app).post('/uploads');
    const outcome = call.then(() => 'complete', () => 'disconnected');
    try {
      await started.promise;
      call.abort();
      await outcome;
      expect(completed).not.toHaveBeenCalled();
    } finally {
      gate.resolve();
    }
    await vi.waitFor(() => expect(completed).toHaveBeenCalledOnce());
  });
});
