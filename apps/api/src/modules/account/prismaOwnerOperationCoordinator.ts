import { AsyncLocalStorage } from 'node:async_hooks';
import { randomUUID } from 'node:crypto';

import { lockActiveOwner, type PrismaOwnerLifecycleTransaction } from './ownerLifecycle.js';
import { createOwnerOperationQueue, OwnerOperationBusyError, type RunWithActiveOwner } from './ownerOperationQueue.js';
import type { UploadOwnerStatus } from '../uploads/uploadSessionStore.js';

type OwnerOperationContext = {
  coordinator: object;
  ownerId: string;
  open: boolean;
  retained: boolean;
  pending: Set<Promise<unknown>>;
};
const ownerOperationContext = new AsyncLocalStorage<OwnerOperationContext>();

// Unknown remote outcomes must survive a fulfilled HTTP/worker result. These
// records are reconciled explicitly; elapsed time never proves completion.
export const retainCurrentOwnerOperation = (ownerId: string): void => {
  const context = ownerOperationContext.getStore();
  if (context?.ownerId === ownerId) context.retained = true;
};

export const createOwnerOperationRunner = ({
  admit, release, runOwnerOperation = createOwnerOperationQueue()
}: {
  admit: (ownerId: string) => Promise<string>;
  release: (ownerId: string, operationId: string) => Promise<void>;
  runOwnerOperation?: RunWithActiveOwner;
}): RunWithActiveOwner => {
  const coordinator = {};
  return async <T>(ownerId: string, operation: () => Promise<T>): Promise<T> => {
    const parent = ownerOperationContext.getStore();
    if (parent?.coordinator === coordinator && parent.ownerId === ownerId && parent.open) {
      const nested = Promise.resolve().then(operation);
      parent.pending.add(nested);
      void nested.then(() => { parent.pending.delete(nested); }, () => {
        parent.retained = true; parent.pending.delete(nested);
      });
      return nested;
    }
    return runOwnerOperation(ownerId, async () => {
      const operationId = await admit(ownerId);
      const context: OwnerOperationContext = { coordinator, ownerId, open: true, retained: false, pending: new Set() };
      const releaseIfConfirmed = async () => {
        if (context.retained) return;
        try { await release(ownerId, operationId); } catch {
          // Keep the durable blocker without changing a remote queue's actual
          // acknowledgement or replacing the callback's original exception.
        }
      };
      try {
        return await ownerOperationContext.run(context, operation);
      } catch (error) {
        context.retained = true;
        throw error;
      } finally {
        context.open = false;
        if (context.pending.size > 0) {
          // A started, unawaited nested callback still owns this lifetime. Late
          // descendants re-admit; they cannot reuse this closed context.
          void Promise.allSettled([...context.pending]).then(releaseIfConfirmed);
        } else {
          await releaseIfConfirmed();
        }
      }
    });
  };
};

export type PrismaOwnerOperationTransaction = {
  managedUploadOwner: Omit<PrismaOwnerLifecycleTransaction['managedUploadOwner'], 'updateMany'> & {
    findUnique: (input: { where: { ownerId: string } }) => Promise<{ status: UploadOwnerStatus } | null>;
    updateMany: (input: { where: { ownerId: string; status: UploadOwnerStatus }; data: { status: UploadOwnerStatus } }) => Promise<{ count: number }>;
  };
  managedOwnerOperation: {
    create: (input: { data: { id: string; ownerId: string; startedAt: Date } }) => Promise<unknown>;
    count: (input: { where: { ownerId: string } }) => Promise<number>;
    deleteMany: (input: { where: { ownerId: string; id: string } }) => Promise<{ count: number }>;
  };
  managedOwnerDeletionRun: {
    findUnique: (input: { where: { ownerId: string } }) => Promise<{ runId: string } | null>;
    create: (input: { data: { ownerId: string; runId: string; startedAt: Date } }) => Promise<unknown>;
    deleteMany: (input: { where: { ownerId: string; runId: string } }) => Promise<{ count: number }>;
  };
};
export type PrismaOwnerOperationClient = PrismaOwnerOperationTransaction & {
  $transaction: <T>(operation: (transaction: PrismaOwnerOperationTransaction) => Promise<T>, options: {
    isolationLevel: 'Serializable'; maxWait: number; timeout: number;
  }) => Promise<T>;
};

export const assertOwnerDrained = async (transaction: Pick<PrismaOwnerOperationTransaction, 'managedOwnerOperation'>, ownerId: string) => {
  const count = await transaction.managedOwnerOperation.count({ where: { ownerId } });
  if (count !== 0) throw new OwnerOperationBusyError();
};

const runSerializable = async <T>(prisma: PrismaOwnerOperationClient, operation: (transaction: PrismaOwnerOperationTransaction) => Promise<T>) => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await prisma.$transaction(operation, { isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 });
    } catch (error) {
      const conflict = typeof error === 'object' && error !== null && 'code' in error && error.code === 'P2034';
      if (!conflict || attempt === 2) throw error;
    }
  }
  throw new Error('Owner operation transaction retry exhausted');
};

export const createPrismaOwnerOperationCoordinator = ({
  prisma, runOwnerOperation, maxWaitMs = 5000, pollIntervalMs = 25
}: {
  prisma: PrismaOwnerOperationClient;
  runOwnerOperation?: RunWithActiveOwner;
  maxWaitMs?: number;
  pollIntervalMs?: number;
}) => {
  if (!Number.isFinite(maxWaitMs) || maxWaitMs < 0 || !Number.isFinite(pollIntervalMs) || pollIntervalMs <= 0) {
    throw new Error('Invalid owner operation drain limits');
  }
  const lifetime = {
    admit: (ownerId) => runSerializable(prisma, async (transaction) => {
      await lockActiveOwner(transaction, ownerId);
      const id = randomUUID();
      await transaction.managedOwnerOperation.create({ data: { id, ownerId, startedAt: new Date() } });
      return id;
    }),
    release: async (ownerId, id) => {
      await prisma.managedOwnerOperation.deleteMany({ where: { ownerId, id } });
    }
  } satisfies Pick<Parameters<typeof createOwnerOperationRunner>[0], 'admit' | 'release'>;
  const runWithActiveOwner = createOwnerOperationRunner({ ...lifetime, runOwnerOperation });
  // HTTP/worker lifetime admission is shared, not a per-owner mutex. Keep
  // explicit queue/store serialization on runWithActiveOwner separately.
  const runWithOwnerLifetime = createOwnerOperationRunner({
    ...lifetime, runOwnerOperation: async (_ownerId, operation) => operation()
  });
  const acquireOwnerDeletion = async (ownerId: string): Promise<() => Promise<void>> => {
    const deadline = Date.now() + maxWaitMs;
    const runId = randomUUID();
    for (;;) {
      try {
        await runSerializable(prisma, async (transaction) => {
          const owner = await transaction.managedUploadOwner.findUnique({ where: { ownerId } });
          if (!owner || owner.status === 'ACTIVE') throw new OwnerOperationBusyError();
          const locked = await transaction.managedUploadOwner.updateMany({ where: { ownerId, status: owner.status }, data: { status: owner.status } });
          if (locked.count !== 1) throw new OwnerOperationBusyError();
          await assertOwnerDrained(transaction, ownerId);
          if (await transaction.managedOwnerDeletionRun.findUnique({ where: { ownerId } })) throw new OwnerOperationBusyError();
          await transaction.managedOwnerDeletionRun.create({ data: { ownerId, runId, startedAt: new Date() } });
        });
        let released = false;
        return async () => {
          if (released) return;
          await prisma.managedOwnerDeletionRun.deleteMany({ where: { ownerId, runId } });
          released = true;
        };
      } catch (error) {
        if (!(error instanceof OwnerOperationBusyError) || Date.now() >= deadline) throw error;
        await new Promise((resolve) => setTimeout(resolve, Math.min(pollIntervalMs, Math.max(1, deadline - Date.now()))));
      }
    }
  };
  return { runWithActiveOwner, runWithOwnerLifetime, acquireOwnerDeletion };
};
