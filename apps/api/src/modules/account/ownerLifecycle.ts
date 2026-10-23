import { UploadSessionConflictError, type UploadOwnerStatus } from '../uploads/uploadSessionStore.js';
import { retryOwnerSerializationConflict } from './ownerSerializationRetry.js';

export type PrismaOwnerLifecycleTransaction = {
  managedUploadOwner: {
    upsert: (input: {
      where: { ownerId: string };
      create: { ownerId: string; status: UploadOwnerStatus };
      update: Record<string, never>;
    }) => Promise<{ status: UploadOwnerStatus }>;
    updateMany: (input: {
      where: { ownerId: string; status: 'ACTIVE' };
      data: { status: 'ACTIVE' };
    }) => Promise<{ count: number }>;
  };
};

export const lockActiveOwner = async (transaction: PrismaOwnerLifecycleTransaction, ownerId: string) => {
  const owner = await transaction.managedUploadOwner.upsert({
    where: { ownerId }, create: { ownerId, status: 'ACTIVE' }, update: {}
  });
  if (owner.status === 'ACTIVE') {
    // This conditional UPDATE holds the marker row lock until the same
    // transaction's final entity write commits. Tombstones are never revived.
    const locked = await transaction.managedUploadOwner.updateMany({
      where: { ownerId, status: 'ACTIVE' }, data: { status: 'ACTIVE' }
    });
    if (locked.count === 1) return;
  }
  throw new UploadSessionConflictError(
    'ACCOUNT_DELETION_IN_PROGRESS',
    'Account deletion is in progress. New account writes are disabled.'
  );
};

export const runActiveOwnerTransaction = async <T, Transaction extends PrismaOwnerLifecycleTransaction>(
  prisma: { $transaction: <Result>(operation: (transaction: Transaction) => Promise<Result>, options: {
    isolationLevel: 'Serializable'; maxWait: number; timeout: number;
  }) => Promise<Result> },
  ownerId: string,
  operation: (transaction: Transaction) => Promise<T>
): Promise<T> => {
  return retryOwnerSerializationConflict(() => prisma.$transaction(async (transaction) => {
    await lockActiveOwner(transaction, ownerId);
    return operation(transaction);
  }, { isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 }));
};
