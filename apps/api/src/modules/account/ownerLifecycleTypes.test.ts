import { expect, expectTypeOf, it } from 'vitest';

import { runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from './ownerLifecycle.js';

it('preserves the operation result and transaction delegate types for a generic Prisma client', async () => {
  type Transaction = PrismaOwnerLifecycleTransaction & { findEntity: () => Promise<{ id: string }> };
  const transaction: Transaction = {
    managedUploadOwner: {
      upsert: async () => ({ status: 'ACTIVE' }),
      updateMany: async () => ({ count: 1 })
    },
    findEntity: async () => ({ id: 'entity-a' })
  };
  const prisma = {
    $transaction: async <Result>(operation: (client: Transaction) => Promise<Result>, _options: {
      isolationLevel: 'Serializable'; maxWait: number; timeout: number;
    }): Promise<Result> => operation(transaction)
  };

  const result = runActiveOwnerTransaction(prisma, 'owner-a', (client) => client.findEntity());

  expectTypeOf(result).toEqualTypeOf<Promise<{ id: string }>>();
  await expect(result).resolves.toEqual({ id: 'entity-a' });
});
