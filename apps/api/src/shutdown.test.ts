import { describe, expect, it, vi } from 'vitest';

import { createGracefulShutdown } from './shutdown.js';

describe('graceful shutdown', () => {
  it('marks unavailable and stops intake before waiting, then closes resources after drain', async () => {
    const events: string[] = [];
    let finish!: () => void;
    const pending = new Promise<void>((resolve) => { finish = resolve; });
    const shutdown = createGracefulShutdown({
      markUnavailable: () => { events.push('unavailable'); },
      stopScheduling: () => { events.push('stop-scheduling'); },
      stopAcceptingRequests: async () => { events.push('stop-http'); await pending; },
      drainPublishing: async () => { events.push('drain'); await pending; },
      closeResources: async () => { events.push('close'); }
    });
    const first = shutdown();
    expect(shutdown()).toBe(first);
    expect(events).toEqual(['unavailable', 'stop-scheduling', 'stop-http', 'drain']);
    finish();
    await first;
    expect(events.at(-1)).toBe('close');
  });

  it('bounds a hung publish without closing its database underneath it', async () => {
    const closeResources = vi.fn();
    const shutdown = createGracefulShutdown({
      markUnavailable: vi.fn(), stopScheduling: vi.fn(),
      stopAcceptingRequests: async () => undefined,
      drainPublishing: () => new Promise<void>(() => {}),
      closeResources, timeoutMs: 20
    });
    await expect(shutdown()).rejects.toThrow('Graceful shutdown timed out');
    expect(closeResources).not.toHaveBeenCalled();
  });

  it('redacts resource failures and preserves its failed result on repeated signals', async () => {
    const closeResources = vi.fn(async () => { throw new Error('database password'); });
    const shutdown = createGracefulShutdown({
      markUnavailable: vi.fn(), stopScheduling: vi.fn(),
      stopAcceptingRequests: async () => undefined,
      drainPublishing: async () => undefined,
      closeResources
    });
    await expect(shutdown()).rejects.toThrow('Graceful shutdown failed');
    await expect(shutdown()).rejects.not.toThrow('password');
    expect(closeResources).toHaveBeenCalledOnce();
  });
});
