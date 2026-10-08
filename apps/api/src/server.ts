import 'dotenv/config';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import {
  logSocialPublishingStartupConfiguration,
  startPublishSchedulerWithDiagnostics
} from './startupDiagnostics.js';
import type { PublishScheduler } from './workers/publishScheduler.js';
import { createGracefulShutdown } from './shutdown.js';

const config = readServerConfig();
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
  closeResources: async () => { await app.locals.closeResources(); }
});
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    void shutdown().then(() => {
      console.log('PostDee API shutdown completed');
      process.exitCode = 0;
    }, () => {
      console.error('PostDee API shutdown did not complete', { code: 'SHUTDOWN_FAILED' });
      server.closeAllConnections();
      process.exit(1);
    });
  });
}
