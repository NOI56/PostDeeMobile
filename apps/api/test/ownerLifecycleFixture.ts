import { vi } from 'vitest';

import type { PrismaOwnerLifecycleTransaction } from '../src/modules/account/ownerLifecycle.js';
import type { UploadOwnerStatus } from '../src/modules/uploads/uploadSessionStore.js';

type FixtureOwner = { ownerId: string; status: UploadOwnerStatus };
type FixtureOwnerDelegate = PrismaOwnerLifecycleTransaction['managedUploadOwner'] & {
  findUnique: (input: { where: { ownerId: string } }) => Promise<FixtureOwner | null>;
  update: (input: { where: { ownerId: string }; data: { status: UploadOwnerStatus } }) => Promise<FixtureOwner>;
};
type DefaultSessionDelegate = {
  findMany: () => Promise<never[]>;
  deleteMany: () => Promise<{ count: number }>;
};
type FixtureTransaction<T extends object> = Omit<T, '$transaction' | 'managedUploadOwner'> & {
  managedUploadOwner: FixtureOwnerDelegate;
} & (T extends { managedUploadSession: unknown } ? unknown : { managedUploadSession: DefaultSessionDelegate });
type OwnerLifecycleFixture<T extends object> = FixtureTransaction<T> & {
  $transaction: <Result>(action: (transaction: FixtureTransaction<T>) => Promise<Result>, options?: unknown) => Promise<Result>;
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
    updateMany: vi.fn(async ({ where }: { where: { ownerId: string; status: 'ACTIVE' }; data: { status: 'ACTIVE' } }) => ({
      count: owners.get(where.ownerId)?.status === where.status ? 1 : 0
    })),
    update: vi.fn(async ({ where, data }: { where: { ownerId: string }; data: { status: UploadOwnerStatus } }) => {
      const owner = { ownerId: where.ownerId, status: data.status };
      owners.set(where.ownerId, owner);
      return owner;
    })
  };
  const source = prisma as Record<string, unknown>;
  const originalTransaction = source.$transaction as ((action: (transaction: object) => Promise<unknown>, options: unknown) => Promise<unknown>) | undefined;
  const client = {
    ...prisma,
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
