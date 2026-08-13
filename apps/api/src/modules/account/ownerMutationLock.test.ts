import { describe, expect, it } from 'vitest';

import { createOwnerMutationLock } from './ownerMutationLock.js';

describe('owner mutation coordinator', () => {
  it('allows concurrent mutations while making deletion a fair exclusive barrier', async () => {
    const coordinator = createOwnerMutationLock();
    const releaseFirst = await coordinator.acquireMutation('seller-1');
    const releaseSecond = await coordinator.acquireMutation('seller-1');
    const events: string[] = [];

    const deletion = coordinator.acquire('seller-1').then((release) => {
      events.push('deletion');
      coordinator.markDeleting('seller-1');
      release();
    });
    const lateMutation = coordinator.acquireMutation('seller-1').then((release) => {
      events.push(coordinator.isActive('seller-1') ? 'late-active' : 'late-blocked');
      release();
    });

    await Promise.resolve();
    expect(events).toEqual([]);
    releaseFirst();
    await Promise.resolve();
    expect(events).toEqual([]);
    releaseSecond();
    await Promise.all([deletion, lateMutation]);

    expect(events).toEqual(['deletion', 'late-blocked']);
  });

  it('releases idle per-owner coordination state without clearing deletion tombstones', async () => {
    const coordinator = createOwnerMutationLock();

    for (let index = 0; index < 100; index += 1) {
      const release = await coordinator.acquireMutation(`seller-${index}`);
      release();
    }

    expect(coordinator.debugStateSize()).toBe(0);

    const releaseDeletion = await coordinator.acquire('seller-deleted');
    coordinator.markDeleted('seller-deleted');
    releaseDeletion();

    expect(coordinator.debugStateSize()).toBe(0);
    expect(coordinator.isActive('seller-deleted')).toBe(false);
  });
});
