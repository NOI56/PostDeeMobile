import 'dotenv/config';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import {
  logSocialPublishingStartupConfiguration,
  startPublishSchedulerWithDiagnostics
} from './startupDiagnostics.js';
import type { PublishScheduler } from './workers/publishScheduler.js';

const config = readServerConfig();
logSocialPublishingStartupConfiguration({ config });
const app = createApp({ config });

const publishScheduler = app.locals.publishScheduler as PublishScheduler | undefined;
await startPublishSchedulerWithDiagnostics({ config, scheduler: publishScheduler });

app.listen(config.port, () => {
  console.log(`PostDee API listening on port ${config.port}`);

  if (publishScheduler) {
    console.log('In-process publish scheduler started (PUBLISH_QUEUE=memory)');
  }
});
