import { describe, expect, it, vi } from 'vitest';

import { readServerConfig } from './config/env.js';
import {
  logSocialPublishingStartupConfiguration,
  startPublishSchedulerWithDiagnostics
} from './startupDiagnostics.js';

describe('social publishing startup diagnostics', () => {
  it.each([
    {
      publisher: 'disabled' as const,
      expected:
        'Social publishing startup: mode=disabled; publisher=disabled; emptyBacklogGuard=not-enforced'
    },
    {
      publisher: 'postpeer' as const,
      expected:
        'Social publishing startup: mode=enabled; publisher=postpeer; emptyBacklogGuard=enforced'
    }
  ])('logs the non-secret $publisher runtime mode', ({ publisher, expected }) => {
    const log = vi.fn();
    const config = readServerConfig({
      SOCIAL_PUBLISHER: publisher,
      ...(publisher === 'postpeer'
        ? {
            POSTPEER_API_KEY: 'test-postpeer-key',
            SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG: 'true'
          }
        : {})
    });

    logSocialPublishingStartupConfiguration({ config, log });

    expect(log).toHaveBeenCalledOnce();
    expect(log).toHaveBeenCalledWith(expected);
  });

  it('logs guard success only after an enforced scheduler start completes', async () => {
    const events: string[] = [];
    const config = readServerConfig({
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'test-postpeer-key',
      SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG: 'true'
    });

    await startPublishSchedulerWithDiagnostics({
      config,
      scheduler: {
        start: async () => {
          events.push('scheduler-started');
        },
        stop: () => undefined,
        runOnce: async () => undefined
      },
      log: (message) => events.push(message)
    });

    expect(events).toEqual([
      'scheduler-started',
      'Social publishing activation guard passed: publish backlog is empty'
    ]);
  });

  it('does not claim guard success when startup fails', async () => {
    const log = vi.fn();
    const config = readServerConfig({
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'test-postpeer-key',
      SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG: 'true'
    });

    await expect(
      startPublishSchedulerWithDiagnostics({
        config,
        scheduler: {
          start: async () => {
            throw new Error('guard blocked startup');
          },
          stop: () => undefined,
          runOnce: async () => undefined
        },
        log
      })
    ).rejects.toThrow('guard blocked startup');

    expect(log).not.toHaveBeenCalled();
  });

  it('does not log guard success when the guard is not enforced', async () => {
    const log = vi.fn();
    const start = vi.fn(async () => undefined);
    const config = readServerConfig({ SOCIAL_PUBLISHER: 'disabled' });

    await startPublishSchedulerWithDiagnostics({
      config,
      scheduler: {
        start,
        stop: () => undefined,
        runOnce: async () => undefined
      },
      log
    });

    expect(start).toHaveBeenCalledOnce();
    expect(log).not.toHaveBeenCalled();
  });
});
