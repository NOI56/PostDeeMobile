import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from '../app.js';
import type { ManagedUploadService } from '../modules/uploads/managedUploadService.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore } from '../modules/posts/postStore.js';
import { createPublishScheduler } from './publishScheduler.js';

type Sweep = () => Promise<{ retired: number; failed: number }>;

const createScheduler = (sweepExpiredUploads: Sweep, uploadSweepIntervalMs = 60_000) =>
  createPublishScheduler({
    postStore: createPostStore(),
    platformPublishStore: createInMemoryPlatformPublishStore(),
    sweepExpiredUploads,
    uploadSweepIntervalMs
  });

describe('publish scheduler upload session sweep', () => {
  afterEach(() => { vi.useRealTimers(); });

  it('sweeps expired upload sessions on its own interval once started', async () => {
    vi.useFakeTimers();
    const sweep = vi.fn(async () => ({ retired: 0, failed: 0 }));
    const scheduler = createScheduler(sweep);

    await vi.advanceTimersByTimeAsync(120_000);
    expect(sweep).not.toHaveBeenCalled();

    await scheduler.start();
    await vi.advanceTimersByTimeAsync(59_000);
    expect(sweep).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(sweep).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(sweep).toHaveBeenCalledTimes(2);

    scheduler.stop();
    await vi.advanceTimersByTimeAsync(180_000);
    expect(sweep).toHaveBeenCalledTimes(2);
  });

  it('keeps publishing readiness when a sweep fails', async () => {
    const sweep = vi.fn<Sweep>(async () => { throw new Error('private storage detail'); });
    const scheduler = createScheduler(sweep);
    await scheduler.start();
    try {
      await expect(scheduler.sweepUploadsOnce!()).resolves.toBeUndefined();
      expect(sweep).toHaveBeenCalledTimes(1);
      await expect(scheduler.checkReady!()).resolves.toBeUndefined();
    } finally {
      scheduler.stop();
    }
  });

  it('never overlaps two sweeps and drain waits for the active one', async () => {
    let finish!: () => void;
    const sweep = vi.fn<Sweep>(() => new Promise((resolve) => {
      finish = () => resolve({ retired: 0, failed: 0 });
    }));
    const scheduler = createScheduler(sweep);

    const first = scheduler.sweepUploadsOnce!();
    const second = scheduler.sweepUploadsOnce!();
    expect(sweep).toHaveBeenCalledTimes(1);

    let drained = false;
    const drain = scheduler.drain!().then(() => { drained = true; });
    await Promise.resolve();
    expect(drained).toBe(false);
    finish();
    await Promise.all([first, second, drain]);
    expect(drained).toBe(true);
  });

  it('is wired to the managed upload service by the app', async () => {
    const sweepExpiredSessions = vi.fn(async () => ({ retired: 2, failed: 0 }));
    const app = createApp({
      managedUploadService: {
        assertOwnerActive: async () => undefined, sweepExpiredSessions
      } as unknown as ManagedUploadService
    });

    await app.locals.publishScheduler.sweepUploadsOnce();
    expect(sweepExpiredSessions).toHaveBeenCalledTimes(1);
  });
});
