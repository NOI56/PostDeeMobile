import 'dotenv/config';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import {
  logSocialPublishingStartupConfiguration,
  startPublishSchedulerWithDiagnostics
} from './startupDiagnostics.js';
import type { PublishScheduler } from './workers/publishScheduler.js';
import { createGracefulShutdown } from './shutdown.js';
import { createSentryMonitoring, reportMonitoringError } from './monitoring/sentryMonitoring.js';

const config = readServerConfig();
const monitoring = await createSentryMonitoring(config.sentry);
logSocialPublishingStartupConfiguration({ config });
const app = createApp({ config });

const publishScheduler = app.locals.publishScheduler as PublishScheduler | undefined;
await startPublishSchedulerWithDiagnostics({ config, scheduler: publishScheduler });

const server = app.listen(config.port, () => {
  console.log(`PostDee API listening on port ${config.port}`);

  if (publishScheduler) {
    console.log('In-process publish scheduler started (PUBLISH_QUEUE=memory)');
  }
});

const shutdown = createGracefulShutdown({
  markUnavailable: () => { app.locals.shuttingDown = true; },
  stopScheduling: () => { publishScheduler?.stop(); },
  stopAcceptingRequests: () => new Promise<void>((resolve, reject) => {
    server.close((error) => { if (error) reject(error); else resolve(); });
  }),
  drainPublishing: async () => { await publishScheduler?.drain?.(); },
  closeResources: async () => {
    try { await app.locals.closeResources(); }
    finally { await monitoring.flush(); }
  }
});
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    void shutdown().then(() => {
      console.log('PostDee API shutdown completed');
      process.exitCode = 0;
    }, async (error: unknown) => {
      reportMonitoringError(error, { operation: 'server.shutdown' });
      console.error('PostDee API shutdown did not complete', { code: 'SHUTDOWN_FAILED' });
      server.closeAllConnections();
      await monitoring.flush();
      process.exit(1);
    });
  });
}
