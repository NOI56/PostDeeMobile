import { describe, expect, it, vi } from 'vitest';

import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { runActiveOwnerTransaction } from './ownerLifecycle.js';

const deferred = () => {
  let resolve!: () => void;
  const promise = new Promise<void>((complete) => { resolve = complete; });
  return { promise, resolve };
};

describe('owner lifecycle fences', () => {
  it('waits for admitted memory work before sealing the owner', async () => {
    const store = createInMemoryUploadSessionStore();
    const entered = deferred();
    const release = deferred();
    const write = vi.fn();
    const operation = store.runWithActiveOwner('seller-1', async () => {
      entered.resolve();
      await release.promise;
      write();
    });
    await entered.promise;
    const sealed = vi.fn();
    const deletion = store.beginOwnerDeletion('seller-1').then(sealed);
    await Promise.resolve();
    expect(sealed).not.toHaveBeenCalled();
    release.resolve();
    await Promise.all([operation, deletion]);
    expect(write).toHaveBeenCalledOnce();
    await expect(store.runWithActiveOwner('seller-1', async () => write()))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(write).toHaveBeenCalledOnce();
  });

  it('releases failed memory work and leaves a permanent deleted tombstone', async () => {
    const store = createInMemoryUploadSessionStore();
    await expect(store.runWithActiveOwner('seller-1', async () => {
      throw new Error('write failed');
    })).rejects.toThrow('write failed');
    await store.beginOwnerDeletion('seller-1');
    await store.finishOwnerDeletion('seller-1');
    await expect(store.beginOwnerDeletion('seller-1')).resolves.toBe('DELETED');
    await expect(store.runWithActiveOwner('seller-1', async () => undefined))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('does not block another owner behind a pending memory operation', async () => {
    const store = createInMemoryUploadSessionStore();
    const entered = deferred();
    const release = deferred();
    const pending = store.runWithActiveOwner('seller-1', async () => {
      entered.resolve();
      await release.promise;
    });
    await entered.promise;
    await expect(store.runWithActiveOwner('seller-2', async () => 'independent'))
      .resolves.toBe('independent');
    release.resolve();
    await pending;
  });

  it('locks the durable marker and writes through the same transaction', async () => {
    const owner = {
      upsert: vi.fn(async () => ({ status: 'ACTIVE' as const })),
      updateMany: vi.fn(async () => ({ count: 1 }))
    };
    const transaction = { managedUploadOwner: owner, write: vi.fn(async () => 'saved') };
    const prisma = {
      $transaction: async <Result>(action: (client: typeof transaction) => Promise<Result>) =>
        action(transaction)
    };
    vi.spyOn(prisma, '$transaction');
    const result = await runActiveOwnerTransaction(prisma, 'seller-1', async (client) => {
      expect(owner.updateMany).toHaveBeenCalledWith({
        where: { ownerId: 'seller-1', status: 'ACTIVE' }, data: { status: 'ACTIVE' }
      });
      return client.write();
    });
    expect(result).toBe('saved');
    expect(transaction.write).toHaveBeenCalledOnce();
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000
    });
  });

  it.each(['DELETING', 'DELETED'] as const)('rejects durable %s owners without writing', async (status) => {
    const transaction = {
      managedUploadOwner: {
        upsert: vi.fn(async () => ({ status })),
        updateMany: vi.fn(async () => ({ count: 1 }))
      },
      write: vi.fn()
    };
    const prisma = { $transaction: async <Result>(action: (client: typeof transaction) => Promise<Result>) => action(transaction) };
    await expect(runActiveOwnerTransaction(prisma, 'seller-1', async (client) => client.write()))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(transaction.write).not.toHaveBeenCalled();
    expect(transaction.managedUploadOwner.updateMany).not.toHaveBeenCalled();
  });

  it('does not write if the conditional durable lock loses to deletion', async () => {
    const transaction = {
      managedUploadOwner: {
        upsert: vi.fn(async () => ({ status: 'ACTIVE' as const })),
        updateMany: vi.fn(async () => ({ count: 0 }))
      },
      write: vi.fn()
    };
    const prisma = { $transaction: async <Result>(action: (client: typeof transaction) => Promise<Result>) => action(transaction) };
    await expect(runActiveOwnerTransaction(prisma, 'seller-1', async (client) => client.write()))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(transaction.write).not.toHaveBeenCalled();
  });

  it('rechecks the durable tombstone after a rolled-back serialization conflict', async () => {
    let status: 'ACTIVE' | 'DELETED' = 'ACTIVE';
    const transaction = {
      managedUploadOwner: {
        upsert: vi.fn(async () => ({ status })),
        updateMany: vi.fn(async () => ({ count: 1 }))
      },
      write: vi.fn(async () => undefined)
    };
    let attempts = 0;
    const prisma = { $transaction: async <Result>(action: (client: typeof transaction) => Promise<Result>) => {
      attempts += 1;
      const result = await action(transaction);
      if (attempts === 1) {
        status = 'DELETED';
        throw Object.assign(new Error('rolled back conflict'), { code: 'P2034' });
      }
      return result;
    } };
    await expect(runActiveOwnerTransaction(prisma, 'seller-1', (client) => client.write()))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(attempts).toBe(2);
    // The first write was rolled back; no replay is admitted after deletion.
    expect(transaction.write).toHaveBeenCalledOnce();
  });
});
