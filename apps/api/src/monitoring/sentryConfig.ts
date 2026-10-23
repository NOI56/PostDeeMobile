export type SentryMonitoringConfig = {
  dsn: string;
  environment: 'development' | 'staging' | 'production';
  release?: string;
};

/** A DSN is deliberately opt-in, with an explicit deployment environment. */
export const readSentryConfig = (
  env: Record<string, string | undefined>
): SentryMonitoringConfig | undefined => {
  const dsn = env.SENTRY_DSN?.trim();
  if (!dsn) return undefined;

  try {
    const url = new URL(dsn);
    if (url.protocol !== 'https:' || !/^[a-zA-Z0-9]+$/.test(url.username) ||
        url.password || url.port || url.search || url.hash ||
        !/^o\d+\.ingest\.(?:(?:us|de)\.)?sentry\.io$/i.test(url.hostname) ||
        !/^\/\d+$/.test(url.pathname)) throw new Error('Invalid DSN');
  } catch {
    // Never include the DSN, tokens or endpoint query in startup errors.
    throw new Error('SENTRY_DSN must be a valid HTTPS Sentry ingest DSN');
  }

  const environment = env.SENTRY_ENVIRONMENT?.trim();
  if (!environment) throw new Error('SENTRY_ENVIRONMENT is required when SENTRY_DSN is set');
  if (environment !== 'development' && environment !== 'staging' && environment !== 'production') {
    throw new Error('SENTRY_ENVIRONMENT must be development, staging or production');
  }

  const release = env.SENTRY_RELEASE?.trim();
  if (release && !/^[a-zA-Z0-9][a-zA-Z0-9_.@+-]{0,119}$/.test(release)) {
    throw new Error('SENTRY_RELEASE must be a safe release identifier');
  }
  return { dsn, environment, ...(release ? { release } : {}) };
};
