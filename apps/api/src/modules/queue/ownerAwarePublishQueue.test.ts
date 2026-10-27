import { afterEach, describe, expect, it, vi } from 'vitest';

import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createInMemoryPublishQueue } from './publishQueue.js';
import { createOwnerAwarePublishQueue } from './ownerAwarePublishQueue.js';

const post = { id: 'post-1', userId: 'seller-1', caption: 'Owned post', videoS3Key: 'uploads/seller-1/clip/video.mp4', platforms: ['TIKTOK' as const], status: 'QUEUED' as const, createdAt: '2026-10-13T00:00:00.000Z' };
const deferred = () => {
  let resolve!: () => void;
  const promise = new Promise<void>((complete) => { resolve = complete; });
  return { promise, resolve };
};

afterEach(() => vi.useRealTimers());

describe('owner-aware publish admission', () => {
  it('drains admitted enqueue before deletion and rejects a stale reschedule', async () => {
    const owner = createInMemoryUploadSessionStore();
    const base = createInMemoryPublishQueue();
    const entered = deferred();
    const release = deferred();
    const queue = createOwnerAwarePublishQueue({ ...base, enqueue: async (input) => {
      entered.resolve(); await release.promise; return base.enqueue(input);
    } }, owner.runWithActiveOwner);
    const pending = queue.enqueue(post);
    await entered.promise;
    const sealed = vi.fn();
    const deletion = owner.beginOwnerDeletion(post.userId).then(sealed);
    await Promise.resolve();
    expect(sealed).not.toHaveBeenCalled();
    release.resolve();
    await Promise.all([pending, deletion]);
    await base.remove(post.id);
    await expect(queue.reschedule({ ...post, scheduledAt: '2026-10-14T00:00:00.000Z' }))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(await base.list()).toEqual([]);
  });

  it('times out the caller while retaining the drain and removes a late acknowledged add', async () => {
    vi.useFakeTimers();
    const owner = createInMemoryUploadSessionStore();
    const base = createInMemoryPublishQueue();
    const entered = deferred();
    const release = deferred();
    const remove = vi.fn(base.remove);
    const queue = createOwnerAwarePublishQueue({ ...base, remove, enqueue: async (input) => {
      entered.resolve(); await release.promise; return base.enqueue(input);
    } }, owner.runWithActiveOwner, { operationTimeoutMs: 10 });
    const failure = expect(queue.enqueue(post)).rejects.toThrow('admission timed out');
    await entered.promise;
    await vi.advanceTimersByTimeAsync(10);
    await failure;
    const deletionFailure = expect(owner.beginOwnerDeletion(post.userId)).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    await vi.advanceTimersByTimeAsync(5000);
    await deletionFailure;
    // A timed-out waiter must not clear the still-pending per-owner tail.
    const lateMutation = vi.fn(async () => undefined);
    const stillBlocked = owner.runWithActiveOwner(post.userId, lateMutation);
    expect(lateMutation).not.toHaveBeenCalled();
    release.resolve();
    await stillBlocked;
    expect(remove).toHaveBeenCalledWith(post.id);
    expect(await base.list()).toEqual([]);
    await owner.beginOwnerDeletion(post.userId);
  });

  it('never dispatches an enqueue that times out while awaiting owner admission', async () => {
    vi.useFakeTimers();
    const owner = createInMemoryUploadSessionStore();
    const entered = deferred();
    const release = deferred();
    const busy = owner.runWithActiveOwner(post.userId, async () => {
      entered.resolve(); await release.promise;
    });
    await entered.promise;
    const base = createInMemoryPublishQueue();
    const enqueue = vi.fn(base.enqueue);
    const queue = createOwnerAwarePublishQueue({ ...base, enqueue }, owner.runWithActiveOwner, { operationTimeoutMs: 10 });
    const failure = expect(queue.enqueue(post)).rejects.toThrow('admission timed out');
    await vi.advanceTimersByTimeAsync(10);
    await failure;
    release.resolve();
    await busy;
    // Flush the queued callback before observing an unchanged empty queue.
    await owner.runWithActiveOwner(post.userId, async () => undefined);
    expect(enqueue).not.toHaveBeenCalled();
    expect(await base.list()).toEqual([]);
  });
});
