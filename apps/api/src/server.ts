import 'dotenv/config';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import type { PublishScheduler } from './workers/publishScheduler.js';

const config = readServerConfig();
const app = createApp();

const publishScheduler = app.locals.publishScheduler as PublishScheduler | undefined;
publishScheduler?.start();

app.listen(config.port, () => {
  console.log(`PostDee API listening on port ${config.port}`);

  if (publishScheduler) {
    console.log('In-process publish scheduler started (PUBLISH_QUEUE=memory)');
  }
});
