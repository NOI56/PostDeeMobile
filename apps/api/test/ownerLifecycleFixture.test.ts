import { describe, expect, it, vi } from 'vitest';

import { withOwnerLifecycleFixture } from './ownerLifecycleFixture.js';

describe('owner lifecycle fixture', () => {
  it('preserves explicitly supplied operation delegates', async () => {
    const managedOwnerOperation = { count: vi.fn(async () => 9) };
    const managedOwnerDeletionRun = { findUnique: vi.fn(async () => ({ runId: 'supplied-run' })) };
    const fixture = withOwnerLifecycleFixture({ managedOwnerOperation, managedOwnerDeletionRun });
    expect(fixture.managedOwnerOperation).toBe(managedOwnerOperation);
    expect(fixture.managedOwnerDeletionRun).toBe(managedOwnerDeletionRun);
  });
  it('keeps operation and deletion tokens isolated and removes only exact tokens', async () => {
    const fixture = withOwnerLifecycleFixture({});
    await fixture.managedOwnerOperation.create({ data: { id: 'operation-a', ownerId: 'owner-a', startedAt: new Date() } });
    await expect(fixture.managedOwnerOperation.count({ where: { ownerId: 'owner-b' } })).resolves.toBe(0);
    await fixture.managedOwnerOperation.deleteMany({ where: { id: 'operation-a', ownerId: 'owner-b' } });
    await expect(fixture.managedOwnerOperation.count({ where: { ownerId: 'owner-a' } })).resolves.toBe(1);
    await fixture.managedOwnerDeletionRun.create({ data: { ownerId: 'owner-a', runId: 'run-a', startedAt: new Date() } });
    await fixture.managedOwnerDeletionRun.deleteMany({ where: { ownerId: 'owner-a', runId: 'run-b' } });
    await expect(fixture.managedOwnerDeletionRun.findUnique({ where: { ownerId: 'owner-a' } })).resolves.toMatchObject({ runId: 'run-a' });
  });
  it('preserves supplied upload sessions and invokes the original transaction with its delegates', async () => {
    const managedUploadSession = { findMany: vi.fn(async () => [{ id: 'existing-session' }]) };
    const originalUser = { name: 'root-user' };
    const transactionUser = { name: 'transaction-user' };
    const transaction = { user: transactionUser, managedUploadSession };
    const originalTransaction = vi.fn(async (action: (client: typeof transaction) => Promise<string>, _options: unknown) =>
      action(transaction)
    );
    const prisma = { user: originalUser, managedUploadSession, $transaction: originalTransaction };
    const fixture = withOwnerLifecycleFixture(prisma);
    const options = { isolationLevel: 'Serializable' as const, maxWait: 5000, timeout: 10000 };

    const result = await fixture.$transaction(async (client) => {
      expect(client.user).toBe(transactionUser);
      expect(client.managedUploadSession).toBe(managedUploadSession);
      expect(client.managedUploadOwner).toBe(fixture.managedUploadOwner);
      await client.managedUploadOwner.upsert({
        where: { ownerId: 'owner-a' }, create: { ownerId: 'owner-a', status: 'ACTIVE' }, update: {}
      });
      return client.user.name;
    }, options);

    expect(result).toBe('transaction-user');
    expect(fixture.managedUploadSession).toBe(managedUploadSession);
    expect(originalTransaction).toHaveBeenCalledWith(expect.any(Function), options);
    expect(originalTransaction.mock.contexts[0]).toBe(prisma);
    await expect(fixture.managedUploadOwner.findUnique({ where: { ownerId: 'owner-a' } }))
      .resolves.toEqual({ ownerId: 'owner-a', status: 'ACTIVE' });
  });

  it('preserves optional deletion authorization through status-only upserts and updates', async () => {
    const fixture = withOwnerLifecycleFixture({});
    const deletionAuthorizedAt = new Date('2026-10-13T18:00:00.000Z');
    await fixture.managedUploadOwner.upsert({
      where: { ownerId: 'owner-a' },
      create: { ownerId: 'owner-a', status: 'DELETING', deletionAuthorizedAt }, update: {}
    });
    await fixture.managedUploadOwner.upsert({
      where: { ownerId: 'owner-a' }, create: { ownerId: 'owner-a', status: 'ACTIVE' }, update: {}
    });
    await fixture.managedUploadOwner.update({ where: { ownerId: 'owner-a' }, data: { status: 'DELETED' } });

    await expect(fixture.managedUploadOwner.findUnique({ where: { ownerId: 'owner-a' } }))
      .resolves.toEqual({ ownerId: 'owner-a', status: 'DELETED', deletionAuthorizedAt });
    await expect(fixture.managedUploadOwner.findUnique({ where: { ownerId: 'owner-b' } })).resolves.toBeNull();
  });
});
