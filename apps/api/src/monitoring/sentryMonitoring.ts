import type { ErrorRequestHandler, Request, RequestHandler } from 'express';
import type { ErrorEvent, EventHint, NodeOptions } from '@sentry/node';

import type { SentryMonitoringConfig } from './sentryConfig.js';

const operations = new Set([
  'http.unhandled', 'http.response', 'publishing.platform', 'publishing.cleanup',
  'scheduler.poll', 'scheduler.process', 'worker.failure', 'worker.connection',
  'server.shutdown', 'server.startup', 'captions.provider', 'ai.transcription', 'ai.planning'
]);
const errorNames = new Set([
  'Error', 'TypeError', 'RangeError', 'ReferenceError', 'SyntaxError', 'URIError',
  'RetryablePublishError', 'PublishOutcomeUnknownError', 'TikTokPublishingError',
  'PrismaClientKnownRequestError', 'PrismaClientInitializationError'
]);
const methods = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']);
const platforms = new Set(['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS']);
const routeSegments = new Set([
  'posts', 'uploads', 'captions', 'ai-edits', 'templates', 'social-connections',
  'billing', 'analytics', 'devices', 'account', 'auth', 'subscriptions',
  'profile', 'link-in-bio', 'summary', 'generate', 'purchases', 'notifications',
  'addons', 'entitlements', 'thumbnail', 'cover', 'revenuecat', 'resync', 'status',
  'me', 'plan', 'publish', 'cancel', 'schedule', 'transfer', 'refresh', 'configure',
  'generate-from-clip', 'audio', 'visual-proxy', 'cleanup', 'quota', 'transcribe', 'prepare'
]);
const safeRoute = (value: unknown): string | undefined => {
  if (typeof value !== 'string' || value.length > 180 || !value.startsWith('/')) return undefined;
  const segments = value.split('/').filter(Boolean);
  return segments.length && segments.every((segment) =>
    routeSegments.has(segment) || /^:[a-zA-Z][a-zA-Z]*$/.test(segment)) ? value : undefined;
};

export type MonitoringContext = {
  operation: string;
  method?: string;
  route?: string;
  httpStatus?: number;
  platform?: string;
};

export type MonitoringReporter = {
  capture: (error: unknown, context: MonitoringContext) => void | Promise<void>;
  flush: (timeoutMs?: number) => Promise<boolean>;
};

export type SentryInitializationOptions = Pick<NodeOptions,
  'dsn' | 'environment' | 'release' | 'dataCollection' | 'defaultIntegrations' |
  'enableRuntimeChannelInjection' | 'enableOpenTelemetrySetup' | 'includeServerName' |
  'spotlight' | 'tracePropagationTargets' | 'traceLifecycle' | 'tracesSampleRate' | 'maxBreadcrumbs' |
  'sendClientReports'> & {
  beforeSend: (event: ErrorEvent, hint: EventHint) => ErrorEvent | null;
  beforeSendTransaction: () => null;
};
export type SentryClientInitializer = (options: SentryInitializationOptions) => Promise<{
  captureException: (error: unknown, context: { tags: Record<string, string> }) => unknown;
  flush: (timeoutMs: number) => Promise<boolean>;
}>;

const disabledReporter: MonitoringReporter = {
  capture: () => undefined,
  flush: async () => true
};
let activeReporter = disabledReporter;

const safeTags = (tags: Record<string, unknown> = {}): Record<string, string> => {
  const result: Record<string, string> = {};
  if (tags.component === 'api' || tags.component === 'worker') result.component = tags.component;
  if (typeof tags.operation === 'string' && operations.has(tags.operation)) result.operation = tags.operation;
  if (typeof tags.method === 'string' && methods.has(tags.method)) result.method = tags.method;
  const route = safeRoute(tags.route);
  if (route) result.route = route;
  if (typeof tags.platform === 'string' && platforms.has(tags.platform)) result.platform = tags.platform;
  if (typeof tags.http_status === 'string' && /^5\d\d$/.test(tags.http_status)) result.http_status = tags.http_status;
  return result;
};

const safeSourceFile = (value: unknown) => {
  if (typeof value !== 'string' || /[?#\r\n]/.test(value) || /^https?:\/\//i.test(value)) return undefined;
  const normalized = value.replace(/\\/g, '/');
  // Keep repository-relative source locations, never host usernames/absolute paths.
  const match = normalized.match(/(?:^|\/)((?:src|dist)\/[a-zA-Z0-9_./-]+\.[cm]?[jt]s)$/);
  const filename = match?.[1];
  return filename && !filename.split('/').some((segment) => segment === '.' || segment === '..')
    ? filename : undefined;
};

/** Last outbound boundary: discard all non-allowlisted request/user/provider data. */
export const sanitizeSentryEvent = (event: ErrorEvent): ErrorEvent => ({
  type: undefined,
  ...(event.event_id && /^[a-f\d]{32}$/i.test(event.event_id) ? { event_id: event.event_id } : {}),
  ...(typeof event.timestamp === 'number' ? { timestamp: event.timestamp } : {}),
  ...(event.environment && ['development', 'staging', 'production'].includes(event.environment)
    ? { environment: event.environment } : {}),
  ...(event.release && /^[a-zA-Z0-9][a-zA-Z0-9_.@+-]{0,119}$/.test(event.release)
    ? { release: event.release } : {}),
  platform: 'node',
  level: event.level === 'fatal' ? 'fatal' : 'error',
  logger: 'postdee',
  tags: safeTags(event.tags),
  exception: {
    values: (event.exception?.values ?? [{ type: 'Error' }]).slice(0, 3).map((exception) => ({
      type: exception.type && errorNames.has(exception.type) ? exception.type : 'Error',
      value: 'PostDee server error',
      ...(typeof exception.mechanism?.handled === 'boolean'
        ? { mechanism: { type: 'generic', handled: exception.mechanism.handled } } : {}),
      ...(exception.stacktrace?.frames ? { stacktrace: {
        frames: exception.stacktrace.frames.slice(-30).flatMap((frame) => {
          const filename = safeSourceFile(frame.filename);
          if (!filename) return [];
          return [{
            filename,
            ...(Number.isInteger(frame.lineno) ? { lineno: frame.lineno } : {}),
            ...(Number.isInteger(frame.colno) ? { colno: frame.colno } : {})
          }];
        })
      } } : {})
    }))
  }
});

type SentryTransport = ReturnType<NonNullable<NodeOptions['transport']>>;
type SentryEnvelope = Parameters<SentryTransport['send']>[0];

/** Also guard the envelope: SDK-added tracing metadata never bypasses beforeSend. */
export const createErrorOnlySentryTransport = (transport: SentryTransport): SentryTransport => ({
  send: async (envelope) => {
    try {
      const eventId = envelope[0].event_id;
      if (typeof eventId !== 'string' || !/^[a-f\d]{32}$/i.test(eventId)) return {};
      const items = envelope[1].flatMap(([headers, payload]) => {
        if (headers.type !== 'event' || !payload || typeof payload !== 'object' ||
            ('type' in payload && payload.type !== undefined)) return [];
        return [[{ type: 'event' }, sanitizeSentryEvent(payload as ErrorEvent)]];
      });
      if (!items.length) return {};
      return await transport.send([{ event_id: eventId, sent_at: new Date().toISOString() }, items] as SentryEnvelope);
    } catch {
      return {};
    }
  },
  flush: async (timeout) => {
    try { return await transport.flush(timeout); } catch { return false; }
  }
});

const initializeSdk: SentryClientInitializer = async (options) => {
  const sdk = await import('@sentry/node');
  sdk.init({
    ...options,
    debug: false,
    includeLocalVariables: false,
    shutdownTimeout: 1_000,
    transportOptions: { bufferSize: 30 },
    transport: (transportOptions) => createErrorOnlySentryTransport(sdk.makeNodeTransport(transportOptions)),
    // Node's default rejection policy turns every unhandled rejection into an
    // uncaught exception. The SDK rejection integration ignores named errors
    // such as AbortError, which would otherwise suppress Node's fatal exit.
    integrations: [sdk.onUncaughtExceptionIntegration()]
  });
  return { captureException: sdk.captureException, flush: sdk.flush };
};

const captureSafely = (reporter: MonitoringReporter, error: unknown, context: MonitoringContext) => {
  try {
    void Promise.resolve(reporter.capture(error, context)).catch(() => undefined);
  } catch {
    // Error reporting must never interrupt API responses or publishing safeguards.
  }
};

export const createSentryMonitoring = async (
  config: SentryMonitoringConfig | undefined,
  { initialize = initializeSdk, component = 'api' }: {
    initialize?: SentryClientInitializer;
    component?: 'api' | 'worker';
  } = {}
): Promise<MonitoringReporter> => {
  activeReporter = disabledReporter;
  if (!config) return disabledReporter;
  try {
    const client = await initialize({
      ...config,
      dataCollection: {
        userInfo: false, cookies: false, httpHeaders: false, httpBodies: [], urlQueryParams: false,
        graphQL: { document: false, variables: false }, genAI: { inputs: false, outputs: false },
        databaseQueryData: false, queues: false, stackFrameVariables: false, frameContextLines: 0
      },
      defaultIntegrations: false,
      enableRuntimeChannelInjection: false,
      enableOpenTelemetrySetup: false,
      includeServerName: false,
      spotlight: false,
      tracePropagationTargets: [],
      traceLifecycle: 'static',
      tracesSampleRate: 0,
      maxBreadcrumbs: 0,
      sendClientReports: false,
      beforeSend: (event, hint) => {
        hint.attachments = [];
        return sanitizeSentryEvent({ ...event, environment: config.environment, release: config.release });
      },
      beforeSendTransaction: () => null
    });
    const reporter: MonitoringReporter = {
      capture: (error, context) => {
        const tags = safeTags({ component, ...context, http_status: String(context.httpStatus ?? '') });
        try {
          void Promise.resolve(client.captureException(error, { tags })).catch(() => undefined);
        } catch {
          // Transport/SDK failures do not affect product behavior.
        }
      },
      flush: async (timeoutMs = 1_000) => {
        let timer: ReturnType<typeof setTimeout> | undefined;
        try {
          const bounded = Math.min(Math.max(timeoutMs, 1), 1_000);
          return await Promise.race([
            client.flush(bounded),
            new Promise<boolean>((resolve) => { timer = setTimeout(() => resolve(false), bounded); })
          ]);
        } catch {
          return false;
        } finally {
          if (timer) clearTimeout(timer);
        }
      }
    };
    activeReporter = reporter;
    return reporter;
  } catch {
    console.error('Sentry monitoring unavailable', { code: 'MONITORING_INIT_FAILED' });
    return disabledReporter;
  }
};

export const reportMonitoringError = (error: unknown, context: MonitoringContext) => {
  captureSafely(activeReporter, error, context);
};

const requestContext = (request: Request, operation: string, status: number): MonitoringContext => ({
  operation,
  ...(methods.has(request.method) ? { method: request.method } : {}),
  ...(safeRoute(request.route?.path) ? { route: safeRoute(request.route.path) } : {}),
  httpStatus: status
});
const reportedResponses = new WeakSet<object>();

export const createSentryRequestMiddleware = (reporter: MonitoringReporter = activeReporter): RequestHandler =>
  (request, response, next) => {
    response.once('finish', () => {
      if (response.statusCode < 500 || response.statusCode > 599 || reportedResponses.has(response)) return;
      // Health/readiness probes have their own availability monitoring; avoid error floods.
      if (request.route?.path === '/health' || request.route?.path === '/ready') return;
      captureSafely(reporter, new Error('HTTP server request failed'),
        requestContext(request, 'http.response', response.statusCode));
    });
    next();
  };

export const createSentryErrorMiddleware = (reporter: MonitoringReporter = activeReporter): ErrorRequestHandler =>
  (error, request, response, next) => {
    const status = typeof error?.statusCode === 'number' ? error.statusCode
      : typeof error?.status === 'number' ? error.status : 500;
    if (status >= 500 && status <= 599) {
      reportedResponses.add(response);
      captureSafely(reporter, error, requestContext(request, 'http.unhandled', status));
    }
    next(error);
  };
