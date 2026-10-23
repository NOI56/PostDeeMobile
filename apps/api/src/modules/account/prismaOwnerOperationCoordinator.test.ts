import { describe, expect, it, vi } from 'vitest';

import { createPrismaOwnerOperationCoordinator, retainCurrentOwnerOperation, type PrismaOwnerOperationClient } from './prismaOwnerOperationCoordinator.js';
import { runActiveOwnerTransaction } from './ownerLifecycle.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';

const createFixture = () => {
  const owners = new Map<string, { status: 'ACTIVE' | 'DELETING' | 'DELETED' }>();
  const operations = new Map<string, { id: string; ownerId: string; startedAt: Date }>();
  const deletions = new Map<string, { ownerId: string; runId: string; startedAt: Date }>();
  const transaction = {
    managedUploadOwner: {
      upsert: vi.fn(async ({ where, create }: Parameters<PrismaOwnerOperationClient['managedUploadOwner']['upsert']>[0]) => {
        const owner = owners.get(where.ownerId) ?? { status: create.status };
        owners.set(where.ownerId, owner); return owner;
      }),
      findUnique: vi.fn(async ({ where }: { where: { ownerId: string } }) => owners.get(where.ownerId) ?? null),
      updateMany: vi.fn(async ({ where }: Parameters<PrismaOwnerOperationClient['managedUploadOwner']['updateMany']>[0]) => ({ count: owners.get(where.ownerId)?.status === where.status ? 1 : 0 }))
    },
    managedOwnerOperation: {
      create: vi.fn(async ({ data }: Parameters<PrismaOwnerOperationClient['managedOwnerOperation']['create']>[0]) => { operations.set(data.id, data); return data; }),
      count: vi.fn(async ({ where }: { where: { ownerId: string } }) => [...operations.values()].filter((row) => row.ownerId === where.ownerId).length),
      deleteMany: vi.fn(async ({ where }: { where: { id: string; ownerId: string } }) => ({ count: operations.get(where.id)?.ownerId === where.ownerId && operations.delete(where.id) ? 1 : 0 }))
    },
    managedOwnerDeletionRun: {
      findUnique: vi.fn(async ({ where }: { where: { ownerId: string } }) => deletions.get(where.ownerId) ?? null),
      create: vi.fn(async ({ data }: Parameters<PrismaOwnerOperationClient['managedOwnerDeletionRun']['create']>[0]) => { if (deletions.has(data.ownerId)) throw new Error('duplicate run'); deletions.set(data.ownerId, data); return data; }),
      deleteMany: vi.fn(async ({ where }: { where: { ownerId: string; runId: string } }) => ({ count: deletions.get(where.ownerId)?.runId === where.runId && deletions.delete(where.ownerId) ? 1 : 0 }))
    }
  };
  const prisma: PrismaOwnerOperationClient = { ...transaction, $transaction: vi.fn(async (action) => action(transaction)) };
  const coordinator = () => createPrismaOwnerOperationCoordinator({ prisma, maxWaitMs: 30, pollIntervalMs: 1 });
  return { prisma, owners, operations, deletions, coordinator };
};

describe('durable owner operation lifetime', () => {
  it('backs off serialization conflicts before admitting once and running remote work once', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0);
    try {
      const fixture = createFixture();
      const conflict = Object.assign(new Error('write conflict'), { code: 'P2034' });
      vi.mocked(fixture.prisma.managedUploadOwner.updateMany)
        .mockRejectedValueOnce(conflict).mockRejectedValueOnce(conflict);
      const operation = vi.fn(async () => 'provider finished');
      const result = fixture.coordinator().runWithOwnerLifetime('owner-a', operation);
      const assertion = expect(result).resolves.toBe('provider finished');

      await vi.advanceTimersByTimeAsync(0);
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(operation).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(24);
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(2);
      await vi.advanceTimersByTimeAsync(49);
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(2);
      await vi.advanceTimersByTimeAsync(1);
      await assertion;

      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(3);
      expect(operation).toHaveBeenCalledTimes(1);
      expect(fixture.prisma.managedOwnerOperation.create).toHaveBeenCalledTimes(1);
      expect(fixture.operations.size).toBe(0);
      for (const [, options] of vi.mocked(fixture.prisma.$transaction).mock.calls) {
        expect(options).toEqual({ isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 });
      }
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it('spreads a startup burst across retries without serializing their remote callbacks', async () => {
    vi.useFakeTimers();
    let randomCall = 0;
    vi.spyOn(Math, 'random').mockImplementation(() => (randomCall++ % 8) / 8);
    try {
      const fixture = createFixture();
      const originalTransaction = vi.mocked(fixture.prisma.$transaction).getMockImplementation()!;
      const conflict = Object.assign(new Error('write conflict'), { code: 'P2034' });
      let transactionOpen = false;
      vi.spyOn(fixture.prisma, '$transaction').mockImplementation(async (action, options) => {
        if (transactionOpen) throw conflict;
        transactionOpen = true;
        try {
          await new Promise((resolve) => setTimeout(resolve, 20));
          return await originalTransaction(action, options);
        } finally { transactionOpen = false; }
      });
      let release!: () => void;
      const gate = new Promise<void>((resolve) => { release = resolve; });
      const startupWrite = vi.fn(async () => 'profile loaded');
      const operation = vi.fn(async () => {
        await runActiveOwnerTransaction(fixture.prisma, 'owner-a', startupWrite);
        await gate;
        return 'provider finished';
      });
      const coordinator = fixture.coordinator();
      const result = Promise.all(Array.from({ length: 8 }, () => coordinator.runWithOwnerLifetime('owner-a', operation)))
        .then((value) => ({ value }), (error: unknown) => ({ error }));

      await vi.runAllTimersAsync();
      expect(operation).toHaveBeenCalledTimes(8);
      expect(startupWrite).toHaveBeenCalledTimes(8);
      expect(fixture.operations.size).toBe(8);
      expect(vi.mocked(fixture.prisma.$transaction).mock.calls.length).toBeLessThanOrEqual(96);
      release();
      expect(await result).toEqual({ value: Array(8).fill('provider finished') });
      expect(fixture.operations.size).toBe(0);
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it('returns the last conflict after six admissions without running remote work', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0);
    try {
      const fixture = createFixture();
      const conflict = Object.assign(new Error('write conflict'), { code: 'P2034' });
      vi.mocked(fixture.prisma.managedUploadOwner.updateMany).mockRejectedValue(conflict);
      const operation = vi.fn();
      const startedAt = Date.now();
      const result = fixture.coordinator().runWithOwnerLifetime('owner-a', operation);
      const assertion = expect(result).rejects.toBe(conflict);
      await vi.advanceTimersByTimeAsync(0);
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(1);
      await vi.runAllTimersAsync();
      await assertion;
      expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(6);
      expect(Date.now() - startedAt).toBe(575);
      expect(operation).not.toHaveBeenCalled();
      expect(fixture.operations.size).toBe(0);
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it('allows another owner to finish while the conflicting owner waits to retry', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0);
    try {
      const fixture = createFixture();
      const updateMany = fixture.prisma.managedUploadOwner.updateMany;
      let conflicts = 0;
      fixture.prisma.managedUploadOwner.updateMany = vi.fn(async (input) => {
        if (input.where.ownerId === 'owner-a' && conflicts++ < 2) {
          throw Object.assign(new Error('write conflict'), { code: 'P2034' });
        }
        return updateMany(input);
      });
      const coordinator = fixture.coordinator();
      const firstOperation = vi.fn(async () => 'first');
      const secondOperation = vi.fn(async () => 'second');
      const first = coordinator.runWithOwnerLifetime('owner-a', firstOperation);
      const second = coordinator.runWithOwnerLifetime('owner-b', secondOperation);
      await vi.advanceTimersByTimeAsync(0);
      await expect(second).resolves.toBe('second');
      expect(firstOperation).not.toHaveBeenCalled();
      expect(secondOperation).toHaveBeenCalledTimes(1);
      await vi.runAllTimersAsync();
      await expect(first).resolves.toBe('first');
      expect(firstOperation).toHaveBeenCalledTimes(1);
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it('does not replay an external callback whose error happens to carry P2034', async () => {
    const fixture = createFixture();
    const conflict = Object.assign(new Error('remote error'), { code: 'P2034' });
    const operation = vi.fn(async () => { throw conflict; });
    await expect(fixture.coordinator().runWithOwnerLifetime('owner-a', operation)).rejects.toBe(conflict);
    expect(fixture.prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(operation).toHaveBeenCalledTimes(1);
    expect(fixture.operations.size).toBe(1);
  });

  it('keeps memory lifetime admission concurrent while deletion waits for both callbacks', async () => {
    const store = createInMemoryUploadSessionStore({ ownerOperationOptions: { maxWaitMs: 100, pollIntervalMs: 1 } });
    let release!: () => void; let bothEntered!: () => void; let entered = 0;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const started = new Promise<void>((resolve) => { bothEntered = resolve; });
    const callback = async () => { entered += 1; if (entered === 2) bothEntered(); await gate; };
    const first = store.runWithOwnerLifetime('owner-a', callback);
    const second = store.runWithOwnerLifetime('owner-a', callback);
    await started; await store.beginOwnerDeletion('owner-a');
    let claimed = false;
    const claim = store.acquireOwnerDeletion('owner-a').then((unlock) => { claimed = true; return unlock; });
    await Promise.resolve(); expect(claimed).toBe(false);
    release(); await Promise.all([first, second]); await (await claim)();
  });
  it('admits concurrent same-owner lifetimes and seals without waiting for their remote callbacks', async () => {
    const fixture = createFixture(); const coordinator = fixture.coordinator();
    let release!: () => void; const gate = new Promise<void>((resolve) => { release = resolve; });
    const entered: string[] = [];
    const first = coordinator.runWithOwnerLifetime('owner-a', async () => { entered.push('first'); await gate; });
    const second = coordinator.runWithOwnerLifetime('owner-a', async () => { entered.push('second'); await gate; });
    await new Promise((resolve) => setTimeout(resolve, 5));
    expect(entered).toEqual(['first', 'second']); expect(fixture.operations.size).toBe(2);
    fixture.owners.set('owner-a', { status: 'DELETING' });
    let claimed = false;
    const claim = fixture.coordinator().acquireOwnerDeletion('owner-a').then((unlock) => { claimed = true; return unlock; });
    await new Promise((resolve) => setTimeout(resolve, 5)); expect(claimed).toBe(false);
    release(); await Promise.all([first, second]); const unlock = await claim; await unlock();
    expect(fixture.operations.size).toBe(0);
  });

  it('supports nested concurrent lifetimes and holds a started child after the outer callback returns', async () => {
    const fixture = createFixture(); const coordinator = fixture.coordinator();
    let release!: () => void; let entered!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const started = new Promise<void>((resolve) => { entered = resolve; });
    let child!: Promise<unknown>;
    await coordinator.runWithOwnerLifetime('owner-a', async () => {
      await coordinator.runWithOwnerLifetime('owner-a', async () => { expect(fixture.operations.size).toBe(1); });
      child = coordinator.runWithOwnerLifetime('owner-a', async () => { entered(); await gate; });
      await started;
    });
    fixture.owners.set('owner-a', { status: 'DELETING' }); expect(fixture.operations.size).toBe(1);
    let claimed = false;
    const claim = fixture.coordinator().acquireOwnerDeletion('owner-a').then((unlock) => { claimed = true; return unlock; });
    await new Promise((resolve) => setTimeout(resolve, 5)); expect(claimed).toBe(false);
    release(); await child; const unlock = await claim; await unlock();
    expect(fixture.operations.size).toBe(0);
  });
  it('registers before remote work and holds another coordinator behind a sealed owner', async () => {
    const fixture = createFixture(); const first = fixture.coordinator(); const second = fixture.coordinator();
    let release!: () => void; let entered!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const running = first.runWithActiveOwner('owner-a', async () => { expect(fixture.operations.size).toBe(1); entered(); await gate; return 'provider finished'; });
    await started; fixture.owners.set('owner-a', { status: 'DELETING' });
    let claimed = false;
    const claim = second.acquireOwnerDeletion('owner-a').then((unlock) => { claimed = true; return unlock; });
    await new Promise((resolve) => setTimeout(resolve, 5)); expect(claimed).toBe(false);
    await expect(second.runWithActiveOwner('owner-a', async () => undefined)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    release(); await expect(running).resolves.toBe('provider finished');
    const unlock = await claim; expect(fixture.operations.size).toBe(0); expect(fixture.deletions.size).toBe(1);
    await unlock(); expect(fixture.deletions.size).toBe(0);
  });

  it('retains ambiguous failures and old rows without expiring them', async () => {
    const fixture = createFixture(); const original = new Error('provider outcome unknown');
    await expect(fixture.coordinator().runWithActiveOwner('owner-a', async () => { throw original; })).rejects.toBe(original);
    fixture.owners.set('owner-a', { status: 'DELETING' });
    for (const row of fixture.operations.values()) row.startedAt = new Date('2000-01-01');
    await expect(fixture.coordinator().acquireOwnerDeletion('owner-a')).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    expect(fixture.operations.size).toBe(1); expect(fixture.deletions.size).toBe(0);
    await expect(fixture.coordinator().runWithActiveOwner('owner-b', async () => 'isolated')).resolves.toBe('isolated');
  });

  it('retains an explicit unknown outcome even when a worker reports a fulfilled result', async () => {
    const fixture = createFixture();
    await fixture.coordinator().runWithActiveOwner('owner-a', async () => { retainCurrentOwnerOperation('owner-a'); return { status: 'FAILED' }; });
    expect(fixture.operations.size).toBe(1);
  });

  it('preserves remote success and its durable blocker when release fails', async () => {
    const fixture = createFixture(); fixture.prisma.managedOwnerOperation.deleteMany = vi.fn(async () => { throw new Error('database unavailable'); });
    await expect(fixture.coordinator().runWithActiveOwner('owner-a', async () => 'queue acknowledged')).resolves.toBe('queue acknowledged');
    expect(fixture.operations.size).toBe(1);
  });

  it('allows awaited nesting while isolating owners and closing detached contexts', async () => {
    const fixture = createFixture(); const coordinator = fixture.coordinator(); let detached!: () => Promise<unknown>;
    let ready!: () => void; const later = new Promise<void>((resolve) => { ready = resolve; });
    let result!: Promise<unknown>;
    await coordinator.runWithActiveOwner('owner-a', async () => {
      await coordinator.runWithActiveOwner('owner-a', async () => { expect(fixture.operations.size).toBe(1); });
      await coordinator.runWithActiveOwner('owner-b', async () => { expect(fixture.operations.size).toBe(2); });
      result = later.then(() => coordinator.runWithActiveOwner('owner-a', async () => 'must not run'));
      detached = () => result;
    });
    fixture.owners.set('owner-a', { status: 'DELETED' }); ready();
    await expect(detached()).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('keeps crash claims and releases only its own exact deletion token', async () => {
    const fixture = createFixture(); fixture.owners.set('owner-a', { status: 'DELETING' });
    const unlock = await fixture.coordinator().acquireOwnerDeletion('owner-a');
    await expect(fixture.coordinator().acquireOwnerDeletion('owner-a')).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    fixture.deletions.get('owner-a')!.runId = 'replacement-claim';
    await unlock(); expect(fixture.deletions.size).toBe(1);
  });

  it('holds a started unawaited child until its actual callback settles', async () => {
    const fixture = createFixture(); const coordinator = fixture.coordinator();
    let entered!: () => void; let release!: () => void;
    const started = new Promise<void>((resolve) => { entered = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    let child!: Promise<unknown>;
    await coordinator.runWithActiveOwner('owner-a', async () => {
      child = coordinator.runWithActiveOwner('owner-a', async () => { entered(); await gate; });
      await started;
    });
    expect(fixture.operations.size).toBe(1);
    fixture.owners.set('owner-a', { status: 'DELETING' });
    let claimed = false;
    const claim = fixture.coordinator().acquireOwnerDeletion('owner-a').then((unlock) => { claimed = true; return unlock; });
    await new Promise((resolve) => setTimeout(resolve, 5)); expect(claimed).toBe(false);
    release(); await child; const unlock = await claim; await unlock();
    expect(fixture.operations.size).toBe(0);
  });
});
