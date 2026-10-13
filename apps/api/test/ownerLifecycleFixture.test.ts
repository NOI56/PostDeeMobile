import { describe, expect, it, vi } from 'vitest';

import { withOwnerLifecycleFixture } from './ownerLifecycleFixture.js';

describe('owner lifecycle fixture', () => {
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
});
