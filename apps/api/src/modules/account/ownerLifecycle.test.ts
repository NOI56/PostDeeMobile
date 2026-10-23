import { describe, expect, it, vi } from 'vitest';

import { lockActiveOwner, runActiveOwnerTransaction } from './ownerLifecycle.js';

describe('owner lifecycle transaction fence', () => {
  it('waits before rechecking the marker and preserves deletion fences after a conflict', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0);
    try {
      const operation = vi.fn();
      const prisma = { $transaction: vi.fn()
        .mockRejectedValueOnce(Object.assign(new Error('serialization conflict'), { code: 'P2034' }))
        .mockImplementationOnce((action) => action({ managedUploadOwner: {
          upsert: vi.fn(async () => ({ status: 'DELETED' })), updateMany: vi.fn()
        } })) };
      const result = runActiveOwnerTransaction(prisma, 'owner-a', operation);
      const assertion = expect(result).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
      await vi.advanceTimersByTimeAsync(0);
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(24);
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      await assertion;
      expect(prisma.$transaction).toHaveBeenCalledTimes(2);
      expect(operation).not.toHaveBeenCalled();
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it.each(['DELETING', 'DELETED'] as const)('never revives an owner marked %s', async (status) => {
    const updateMany = vi.fn();
    const operation = vi.fn();
    const transaction = { managedUploadOwner: { upsert: vi.fn(async () => ({ status })), updateMany } };
    const prisma = { $transaction: vi.fn(async (action) => action(transaction)) };

    await expect(runActiveOwnerTransaction(prisma, 'owner-a', operation))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(updateMany).not.toHaveBeenCalled();
    expect(operation).not.toHaveBeenCalled();
    expect(transaction.managedUploadOwner.upsert).toHaveBeenCalledWith({
      where: { ownerId: 'owner-a' }, create: { ownerId: 'owner-a', status: 'ACTIVE' }, update: {}
    });
  });

  it('locks the ACTIVE marker before the final write in the same transaction', async () => {
    const order: string[] = [];
    const transaction = { managedUploadOwner: {
      upsert: vi.fn(async () => ({ status: 'ACTIVE' as const })),
      updateMany: vi.fn(async () => { order.push('lock'); return { count: 1 }; })
    } };
    const prisma = { $transaction: vi.fn(async (action) => action(transaction)) };
    const result = await runActiveOwnerTransaction(prisma, 'owner-a', async (client) => {
      expect(client).toBe(transaction);
      order.push('write');
      return 'saved';
    });
    expect(result).toBe('saved');
    expect(order).toEqual(['lock', 'write']);
    expect(transaction.managedUploadOwner.updateMany).toHaveBeenCalledWith({
      where: { ownerId: 'owner-a', status: 'ACTIVE' }, data: { status: 'ACTIVE' }
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000
    });
  });

  it('rejects an owner changed after the ACTIVE snapshot', async () => {
    await expect(lockActiveOwner({ managedUploadOwner: {
      upsert: vi.fn(async () => ({ status: 'ACTIVE' as const })),
      updateMany: vi.fn(async () => ({ count: 0 }))
    } }, 'owner-a')).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('rechecks the marker after a serialization retry', async () => {
    const operation = vi.fn();
    const prisma = { $transaction: vi.fn()
      .mockRejectedValueOnce(Object.assign(new Error('serialization conflict'), { code: 'P2034' }))
      .mockImplementationOnce((action) => action({ managedUploadOwner: {
        upsert: vi.fn(async () => ({ status: 'DELETED' })), updateMany: vi.fn()
      } })) };
    await expect(runActiveOwnerTransaction(prisma, 'owner-a', operation))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(operation).not.toHaveBeenCalled();
  });
});
