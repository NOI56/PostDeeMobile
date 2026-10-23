import express from 'express';
import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  createSentryMonitoring,
  createSentryRequestMiddleware,
  createSentryErrorMiddleware,
  createErrorOnlySentryTransport,
  reportMonitoringError,
  sanitizeSentryEvent,
  type MonitoringReporter,
  type SentryClientInitializer,
  type SentryInitializationOptions
} from './sentryMonitoring.js';

const config = { dsn: 'https://public123@o123.ingest.us.sentry.io/123456',
  environment: 'staging' as const, release: 'postdee-api@abc123' };

afterEach(async () => { await createSentryMonitoring(undefined); });

describe('Sentry error monitoring', () => {
  it('never initializes the external SDK without a DSN', async () => {
    const initialize = vi.fn();
    const reporter = await createSentryMonitoring(undefined, { initialize });
    reporter.capture(new Error('private'), { operation: 'worker.failure' });
    expect(initialize).not.toHaveBeenCalled();
  });

  it('uses an error-only configuration and scrubs before any outbound event', async () => {
    let configured: SentryInitializationOptions | undefined;
    const captureException = vi.fn();
    const initialize: SentryClientInitializer = async (options) => {
      configured = options;
      return { captureException, flush: async () => true };
    };
    await createSentryMonitoring(config, { initialize, component: 'api' });
    reportMonitoringError(new Error('provider private URL'), { operation: 'worker.failure' });
    expect(captureException).toHaveBeenCalledOnce();
    expect(configured).toMatchObject({ tracesSampleRate: 0, traceLifecycle: 'static',
      maxBreadcrumbs: 0, sendClientReports: false,
      defaultIntegrations: false, enableRuntimeChannelInjection: false,
      enableOpenTelemetrySetup: false, includeServerName: false, spotlight: false,
      tracePropagationTargets: [], dataCollection: { userInfo: false, cookies: false,
        httpHeaders: false, httpBodies: [], urlQueryParams: false,
        graphQL: { document: false, variables: false }, genAI: { inputs: false, outputs: false },
        databaseQueryData: false, queues: false, stackFrameVariables: false,
        frameContextLines: 0 } });
    const hint = { attachments: [{ filename: 'private.mp4', data: 'private-video' }] };
    configured!.beforeSend({ type: undefined, message: 'private', extra: { token: 'secret' } }, hint);
    expect(hint.attachments).toEqual([]);
    expect(configured!.beforeSendTransaction()).toBeNull();
  });

  it('allowlists error fields, preserving code locations but no personal payload', () => {
    const cleaned = sanitizeSentryEvent({
      type: undefined,
      event_id: '0123456789abcdef0123456789abcdef',
      environment: 'staging', release: 'postdee-api@abc123', level: 'error',
      message: 'caption private-caption', server_name: 'owner-private',
      user: { id: 'user-private', email: 'private@example.com', ip_address: '1.2.3.4' },
      request: { url: 'https://private.test/posts/owner-private?token=secret',
        data: { caption: 'private-caption' }, headers: { authorization: 'Bearer secret' } },
      extra: { prompt: 'private-prompt', accessToken: 'secret' },
      contexts: { os: { hostname: 'owner-private' } },
      breadcrumbs: [{ message: 'signed https://private.test/media?token=secret' }],
      tags: { component: 'api', operation: 'http.unhandled', method: 'POST',
        route: '/posts/:id', http_status: '500', userId: 'user-private' },
      exception: { values: [{ type: 'TypeError', value: 'secret private-caption',
        stacktrace: { frames: [{ filename: 'C:/Users/owner-private/repo/apps/api/src/app.ts',
          function: 'createApp', lineno: 42, colno: 5,
          vars: { token: 'secret' }, context_line: 'secret' }] } }] }
    });
    const json = JSON.stringify(cleaned);
    for (const sensitive of ['private', 'secret', '1.2.3.4', 'Bearer', 'userId', 'authorization']) {
      expect(json).not.toContain(sensitive);
    }
    expect(cleaned.exception?.values?.[0]).toMatchObject({ type: 'TypeError',
      value: 'PostDee server error', stacktrace: { frames: [
        { filename: 'src/app.ts', lineno: 42, colno: 5 }
      ] } });
    expect(cleaned.tags).toMatchObject({ route: '/posts/:id', http_status: '500' });
  });

  it('cannot add a request URL or arbitrary tag through a malformed route', () => {
    const clean = sanitizeSentryEvent({ type: undefined, tags: {
      route: 'https://private.test/?token=secret', operation: 'caption private',
      platform: 'owner-private', code: 'caption private', component: 'owner-private'
    } });
    expect(JSON.stringify(clean)).not.toMatch(/private|secret/);
  });

  it('drops untrusted source paths and dynamic function names while preserving fatal classification', () => {
    const clean = sanitizeSentryEvent({ type: undefined, level: 'fatal', exception: { values: [{
      type: 'TypeError', value: 'private-provider-message',
      mechanism: { type: 'private-provider', handled: false, data: { token: 'secret' } },
      stacktrace: { frames: [
        { filename: 'https://private.test/src/account.ts', lineno: 3 },
        { filename: '/app/src/../private-secret.ts', lineno: 4 },
        { filename: '/app/src/app.ts', function: 'privateSecretCaption', lineno: 5, colno: 2 }
      ] }
    }] } });
    expect(JSON.stringify(clean)).not.toMatch(/private|secret|Caption/);
    expect(clean.exception?.values?.[0]).toMatchObject({
      mechanism: { type: 'generic', handled: false },
      stacktrace: { frames: [{ filename: 'src/app.ts', lineno: 5, colno: 2 }] }
    });
  });

  it('allows only scrubbed error envelopes, stripping SDK trace metadata and attachments at transport', async () => {
    const send = vi.fn(async (_envelope: unknown) => ({ statusCode: 200 }));
    const transport = createErrorOnlySentryTransport({ send, flush: async () => true });
    await transport.send([{ event_id: '0123456789abcdef0123456789abcdef',
      sent_at: '2026-10-23T00:00:00Z', trace: { transaction: 'private-caption', trace_id: 'secret', public_key: 'key' }
    }, [
      [{ type: 'event' }, { type: undefined, message: 'private-caption', user: { id: 'private-owner' },
        tags: { operation: 'worker.failure' } }],
      [{ type: 'attachment', length: 6, filename: 'private-video.mp4' }, 'secret'],
      [{ type: 'profile' }, { private: 'secret' } as never]
    ]]);
    expect(send).toHaveBeenCalledOnce();
    const outbound = send.mock.calls[0]![0];
    expect(JSON.stringify(outbound)).not.toMatch(/private|secret|trace|attachment|profile/);
    expect((outbound as unknown[])[1]).toHaveLength(1);
    send.mockClear();
    await transport.send([{ sent_at: '2026-10-23T00:00:00Z' }, [[{ type: 'session' }, {} as never]]]);
    expect(send).not.toHaveBeenCalled();
  });

  it('scrubs a real SDK error envelope without contacting Sentry', async () => {
    const sdk = await import('@sentry/node');
    const outbound: unknown[] = [];
    try {
      const reporter = await createSentryMonitoring(config, { initialize: async (options) => {
        sdk.init({ ...options, integrations: [], transport: () => createErrorOnlySentryTransport({
          send: async (envelope) => { outbound.push(envelope); return { statusCode: 200 }; },
          flush: async () => true
        }) });
        return { captureException: sdk.captureException, flush: sdk.flush };
      } });
      sdk.setUser({ id: 'private-owner', email: 'private@example.com' });
      sdk.setContext('private', { token: 'secret' });
      sdk.addBreadcrumb({ message: 'private-signed-url' });
      const error = new Error('private-provider-message');
      error.stack = 'Error: private-provider-message\n    at privateCaption (/app/src/server.ts:12:3)';
      reporter.capture(error, { operation: 'worker.failure' });
      await reporter.flush();
      expect(outbound).toHaveLength(1);
      expect(JSON.stringify(outbound)).not.toMatch(/private|secret|signed|example\.com/);
      expect(JSON.stringify(outbound)).toContain('src/server.ts');
    } finally {
      sdk.setUser(null);
      sdk.setContext('private', null);
      await sdk.close(100);
    }
  });

  it('does not throw or delay callers when initialization or exporting fails', async () => {
    const disabled = await createSentryMonitoring(config, {
      initialize: async () => { throw new Error('private initialization error'); }
    });
    expect(() => disabled.capture(new Error('private'), { operation: 'worker.failure' }))
      .not.toThrow();
    const reporter = await createSentryMonitoring(config, {
      initialize: async () => ({ captureException: () => Promise.reject(new Error('private')),
        flush: () => new Promise<boolean>(() => undefined) })
    });
    expect(() => reporter.capture(new Error('private'), { operation: 'worker.failure' }))
      .not.toThrow();
    await expect(reporter.flush(10)).resolves.toBe(false);
  });
});

describe('Express monitoring adapter', () => {
  const appWithReporter = (capture: MonitoringReporter['capture']) => {
    const app = express();
    const reporter: MonitoringReporter = { capture, flush: async () => true };
    app.use(createSentryRequestMiddleware(reporter));
    app.use(express.json());
    app.post('/posts/:id', () => { throw new Error('private post body'); });
    app.get('/provider-failure', (_req, res) => { res.status(502).json({ code: 'FAILED' }); });
    app.get('/expected', () => { throw Object.assign(new Error('private'), { statusCode: 403 }); });
    app.use(createSentryErrorMiddleware(reporter));
    app.use(((error, _req, res, _next) => {
      res.status(error.statusCode ?? 500).json({ code: 'UNCHANGED_ERROR' });
    }) as express.ErrorRequestHandler);
    return app;
  };

  it('reports unexpected errors once, using route templates and unchanged responses', async () => {
    const capture = vi.fn();
    const response = await request(appWithReporter(capture))
      .post('/posts/private-id?token=secret').set('Authorization', 'Bearer secret')
      .send({ caption: 'private-caption' });
    expect(response.status).toBe(500);
    expect(response.body).toEqual({ code: 'UNCHANGED_ERROR' });
    expect(capture).toHaveBeenCalledOnce();
    expect(capture.mock.calls[0][1]).toEqual({ operation: 'http.unhandled',
      method: 'POST', route: '/posts/:id', httpStatus: 500 });
  });

  it('captures handled 5xx responses and skips expected 4xx and invalid input', async () => {
    const capture = vi.fn();
    const app = appWithReporter(capture);
    await request(app).get('/provider-failure').expect(502);
    expect(capture).toHaveBeenCalledOnce();
    capture.mockClear();
    await request(app).get('/expected').expect(403);
    await request(app).post('/posts/id').set('Content-Type', 'application/json').send('{').expect(400);
    expect(capture).not.toHaveBeenCalled();
  });

  it('keeps API responses available when the reporter itself throws', async () => {
    await request(appWithReporter(() => { throw new Error('reporter offline'); }))
      .get('/provider-failure').expect(502);
  });
});
