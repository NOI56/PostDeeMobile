import type { ServerConfig } from './config/env.js';
import type { PublishScheduler } from './workers/publishScheduler.js';

type StartupLog = (message: string) => void;

const isEmptyBacklogGuardEnforced = (config: ServerConfig) =>
  config.socialPublisher === 'postpeer' && config.socialPublishRequireEmptyBacklog;

export const logSocialPublishingStartupConfiguration = ({
  config,
  log = console.info
}: {
  config: ServerConfig;
  log?: StartupLog;
}) => {
  const mode = config.socialPublisher === 'disabled' ? 'disabled' : 'enabled';
  const emptyBacklogGuard = isEmptyBacklogGuardEnforced(config)
    ? 'enforced'
    : 'not-enforced';

  log(
    `Social publishing startup: mode=${mode}; ` +
      `publisher=${config.socialPublisher}; emptyBacklogGuard=${emptyBacklogGuard}`
  );
};

export const startPublishSchedulerWithDiagnostics = async ({
  config,
  scheduler,
  log = console.info
}: {
  config: ServerConfig;
  scheduler?: PublishScheduler;
  log?: StartupLog;
}) => {
  await scheduler?.start();

  if (scheduler && isEmptyBacklogGuardEnforced(config)) {
    log('Social publishing activation guard passed: publish backlog is empty');
  }
};
