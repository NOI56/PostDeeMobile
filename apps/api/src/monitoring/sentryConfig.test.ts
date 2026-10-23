import { describe, expect, it } from 'vitest';

import { readSentryConfig } from './sentryConfig.js';
import { readServerConfig } from '../config/env.js';

const dsn = 'https://public123@o123.ingest.us.sentry.io/123456';

describe('Sentry configuration', () => {
  it('does not enable reporting without an explicit DSN', () => {
    expect(readSentryConfig({})).toBeUndefined();
    expect(readServerConfig({}).sentry).toBeUndefined();
  });

  it('requires an explicit deployment environment instead of inferring NODE_ENV', () => {
    expect(() => readSentryConfig({ SENTRY_DSN: dsn, NODE_ENV: 'production' }))
      .toThrow('SENTRY_ENVIRONMENT is required');
    expect(readSentryConfig({ SENTRY_DSN: dsn, SENTRY_ENVIRONMENT: 'staging',
      SENTRY_RELEASE: 'postdee-api@abc123' })).toEqual({
      dsn, environment: 'staging', release: 'postdee-api@abc123'
    });
  });

  it.each([
    'http://public123@o123.ingest.sentry.io/123',
    'https://public123:secret@o123.ingest.sentry.io/123',
    'https://public123@other.test/123',
    'https://public123@o123.ingest.sentry.io/123?token=private',
    'https://public123@o123.ingest.sentry.io/123#private'
  ])('rejects unsafe DSNs without echoing their value: %s', (value) => {
    expect(() => readSentryConfig({ SENTRY_DSN: value, SENTRY_ENVIRONMENT: 'staging' }))
      .toThrow(/^SENTRY_DSN must be a valid HTTPS Sentry ingest DSN$/);
  });

  it('does not silently accept an unknown environment or unsafe release', () => {
    expect(() => readSentryConfig({ SENTRY_DSN: dsn, SENTRY_ENVIRONMENT: 'prod' }))
      .toThrow('SENTRY_ENVIRONMENT must be development, staging or production');
    expect(() => readSentryConfig({ SENTRY_DSN: dsn, SENTRY_ENVIRONMENT: 'staging',
      SENTRY_RELEASE: 'private@example.com?token=value' })).toThrow('SENTRY_RELEASE');
  });
});
