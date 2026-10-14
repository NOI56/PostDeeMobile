import { vi } from 'vitest';

import type { PrismaOwnerLifecycleTransaction } from '../src/modules/account/ownerLifecycle.js';
import type { PrismaOwnerOperationTransaction } from '../src/modules/account/prismaOwnerOperationCoordinator.js';
import type { UploadOwnerStatus } from '../src/modules/uploads/uploadSessionStore.js';

type FixtureOwner = { ownerId: string; status: UploadOwnerStatus; deletionAuthorizedAt?: Date | null };
type FixtureOwnerDelegate = Omit<PrismaOwnerLifecycleTransaction['managedUploadOwner'], 'upsert' | 'updateMany'> & {
  upsert: (input: { where: { ownerId: string }; create: FixtureOwner; update: Record<string, never> }) => Promise<FixtureOwner>;
  findUnique: (input: { where: { ownerId: string } }) => Promise<FixtureOwner | null>;
  update: (input: { where: { ownerId: string }; data: { status: UploadOwnerStatus; deletionAuthorizedAt?: Date | null } }) => Promise<FixtureOwner>;
  updateMany: (input: { where: { ownerId: string; status: UploadOwnerStatus }; data: { status: UploadOwnerStatus } }) => Promise<{ count: number }>;
};
type DefaultSessionDelegate = {
  findMany: () => Promise<never[]>;
  deleteMany: () => Promise<{ count: number }>;
};
type OperationDelegates = Pick<PrismaOwnerOperationTransaction, 'managedOwnerOperation' | 'managedOwnerDeletionRun'>;
type FixtureTransaction<T extends object> = Omit<T, '$transaction' | 'managedUploadOwner' | 'managedOwnerOperation' | 'managedOwnerDeletionRun'> & OperationDelegates & {
  managedUploadOwner: FixtureOwnerDelegate;
} & (T extends { managedUploadSession: unknown } ? unknown : { managedUploadSession: DefaultSessionDelegate });
type OwnerLifecycleFixture<T extends object> = FixtureTransaction<T> & {
  $transaction: <Result>(action: (transaction: FixtureTransaction<T>) => Promise<Result>, options?: unknown) => Promise<Result>;
};

export const createOwnerOperationFixture = (): OperationDelegates => {
  const operations = new Map<string, { id: string; ownerId: string; startedAt: Date }>();
  const deletionRuns = new Map<string, { ownerId: string; runId: string; startedAt: Date }>();
  return {
    managedOwnerOperation: {
      create: vi.fn(async ({ data }) => { if (operations.has(data.id)) throw new Error('Duplicate operation fixture'); operations.set(data.id, data); return data; }),
      count: vi.fn(async ({ where }) => [...operations.values()].filter((row) => row.ownerId === where.ownerId).length),
      deleteMany: vi.fn(async ({ where }) => ({ count: operations.get(where.id)?.ownerId === where.ownerId && operations.delete(where.id) ? 1 : 0 }))
    },
    managedOwnerDeletionRun: {
      create: vi.fn(async ({ data }) => { if (deletionRuns.has(data.ownerId)) throw new Error('Duplicate deletion fixture'); deletionRuns.set(data.ownerId, data); return data; }),
      findUnique: vi.fn(async ({ where }) => deletionRuns.get(where.ownerId) ?? null),
      deleteMany: vi.fn(async ({ where }) => ({ count: deletionRuns.get(where.ownerId)?.runId === where.runId && deletionRuns.delete(where.ownerId) ? 1 : 0 }))
    }
  };
};

// Extend deliberately partial repository/route doubles with the lifecycle
// surface. Production code never falls back when a Prisma marker is missing.
export const withOwnerLifecycleFixture = <T extends object>(prisma: T): OwnerLifecycleFixture<T> => {
  const owners = new Map<string, FixtureOwner>();
  const managedUploadOwner = {
    upsert: vi.fn(async ({ where, create }: { where: { ownerId: string }; create: FixtureOwner; update: Record<string, never> }) => {
      const existing = owners.get(where.ownerId);
      if (existing) return existing;
      owners.set(where.ownerId, create);
      return create;
    }),
    findUnique: vi.fn(async ({ where }: { where: { ownerId: string } }) => owners.get(where.ownerId) ?? null),
    updateMany: vi.fn(async ({ where }: { where: { ownerId: string; status: UploadOwnerStatus }; data: { status: UploadOwnerStatus } }) => ({
      count: owners.get(where.ownerId)?.status === where.status ? 1 : 0
    })),
    update: vi.fn(async ({ where, data }: { where: { ownerId: string }; data: { status: UploadOwnerStatus; deletionAuthorizedAt?: Date | null } }) => {
      const owner = { ...owners.get(where.ownerId), ownerId: where.ownerId, ...data };
      owners.set(where.ownerId, owner);
      return owner;
    })
  };
  const source = prisma as Record<string, unknown>;
  const defaultOperations = createOwnerOperationFixture();
  const originalTransaction = source.$transaction as ((action: (transaction: object) => Promise<unknown>, options: unknown) => Promise<unknown>) | undefined;
  const client = {
    ...prisma,
    managedOwnerOperation: source.managedOwnerOperation ?? defaultOperations.managedOwnerOperation,
    managedOwnerDeletionRun: source.managedOwnerDeletionRun ?? defaultOperations.managedOwnerDeletionRun,
    managedUploadOwner,
    managedUploadSession: source.managedUploadSession ?? {
      findMany: vi.fn(async (): Promise<never[]> => []), deleteMany: vi.fn(async () => ({ count: 0 }))
    },
    $transaction: vi.fn(async <Result>(action: (transaction: FixtureTransaction<T>) => Promise<Result>, options?: unknown): Promise<Result> => {
      const invoke = (transaction: object) => action({ ...client, ...transaction, managedUploadOwner } as FixtureTransaction<T>);
      if (originalTransaction) {
        return await originalTransaction.call(prisma, invoke, options) as Result;
      }
      return invoke(client);
    })
  };
  return client as OwnerLifecycleFixture<T>;
};
