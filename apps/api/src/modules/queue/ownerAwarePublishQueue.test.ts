import { afterEach, describe, expect, it, vi } from 'vitest';

import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createInMemoryPublishQueue } from './publishQueue.js';
import { createOwnerAwarePublishQueue } from './ownerAwarePublishQueue.js';

const post = { id: 'p1', userId: 'owner-a', caption: 'Private', videoS3Key: 'uploads/owner-a/a.mp4', platforms: ['TIKTOK' as const], status: 'QUEUED' as const, createdAt: '2026-10-13T00:00:00.000Z' };

describe('owner-aware queue admission', () => {
  afterEach(() => { vi.useRealTimers(); });

  it.each(['enqueue', 'ensureEnqueued', 'reschedule'] as const)('blocks %s for a deleted owner', async (method) => {
    const owners = createInMemoryUploadSessionStore();
    await owners.beginOwnerDeletion(post.userId);
    const original = createInMemoryPublishQueue();
    const operation = vi.spyOn(original, method);
    const queue = createOwnerAwarePublishQueue(original, owners.runWithActiveOwner);
    await expect(queue[method](post)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(operation).not.toHaveBeenCalled();
  });

  it('bounds deletion admission while keeping the actual queue add pending until acknowledgement', async () => {
    vi.useFakeTimers();
    const owners = createInMemoryUploadSessionStore();
    const original = createInMemoryPublishQueue();
    let release!: () => void;
    let entered!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const originalEnqueue = original.enqueue;
    original.enqueue = async (input) => { entered(); await gate; return originalEnqueue(input); };
    const queue = createOwnerAwarePublishQueue(original, owners.runWithActiveOwner);
    let acknowledged = false;
    const adding = queue.enqueue(post).then((result) => { acknowledged = true; return result; });
    await started;
    const deletion = owners.beginOwnerDeletion(post.userId).catch((error: unknown) => error);
    await vi.advanceTimersByTimeAsync(5000);
    expect(await deletion).toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    expect(acknowledged).toBe(false);
    release();
    await adding;
    await owners.beginOwnerDeletion(post.userId);
    // Account cleanup observes every owned job only after actual admission ends.
    await original.remove(post.id);
    expect(await original.list({ userId: post.userId })).toEqual([]);
  });

  it('preserves an accepted job when a held ensureEnqueued replay outlives a bounded owner admission wait', async () => {
    vi.useFakeTimers();
    const owners = createInMemoryUploadSessionStore();
    const original = createInMemoryPublishQueue();
    const accepted = await original.enqueue(post);
    let release!: () => void;
    let entered!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    original.ensureEnqueued = async () => { entered(); await gate; return accepted; };
    const queue = createOwnerAwarePublishQueue(original, owners.runWithActiveOwner);
    const replay = queue.ensureEnqueued(post);
    await started;
    const admission = owners.runWithActiveOwner(post.userId, async () => undefined).catch((error: unknown) => error);
    await vi.advanceTimersByTimeAsync(5000);
    expect(await admission).toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    release();
    expect(await replay).toEqual(accepted);
    expect(await original.list({ userId: post.userId })).toEqual([accepted]);
  });

  it('does not release a pending reschedule or trigger an early queue error', async () => {
    vi.useFakeTimers();
    const owners = createInMemoryUploadSessionStore();
    const original = createInMemoryPublishQueue();
    const accepted = await original.enqueue(post);
    const originalReschedule = original.reschedule;
    let release!: () => void;
    let entered!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    original.reschedule = async (input) => { entered(); await gate; return originalReschedule(input); };
    const queue = createOwnerAwarePublishQueue(original, owners.runWithActiveOwner);
    let settled = false;
    const rescheduling = queue.reschedule({ ...post, scheduledAt: '2026-10-14T00:00:00.000Z' })
      .then((result) => { settled = true; return result; });
    await started;
    await vi.advanceTimersByTimeAsync(10000);
    expect(settled).toBe(false);
    expect(await original.list({ userId: post.userId })).toEqual([accepted]);
    release();
    const replacement = await rescheduling;
    expect(await original.list({ userId: post.userId })).toEqual([replacement]);
  });

  it('preserves idempotent replay and reschedule replacement semantics', async () => {
    const owners = createInMemoryUploadSessionStore();
    const queue = createOwnerAwarePublishQueue(createInMemoryPublishQueue(), owners.runWithActiveOwner);
    const first = await queue.enqueue(post);
    expect(await queue.ensureEnqueued(post)).toEqual(first);
    const replacement = await queue.reschedule({ ...post, scheduledAt: '2026-10-14T00:00:00.000Z' });
    expect(await queue.list({ userId: post.userId })).toEqual([replacement]);
    await queue.checkReady();
    await queue.close();
  });
});
