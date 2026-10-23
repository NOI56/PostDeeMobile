import { describe, expect, it, vi } from 'vitest';

import {
  createPrismaUploadSessionRepository,
  type PrismaUploadSessionClient
} from './prismaUploadSessionRepository.js';
import type { UploadOwnerStatus } from './uploadSessionStore.js';
import { createOwnerOperationFixture } from '../../../test/ownerLifecycleFixture.js';

const timestamp = new Date('2026-07-13T10:00:00.000Z');

const persistedSession: NonNullable<Awaited<ReturnType<PrismaUploadSessionClient['managedUploadSession']['findUnique']>>> = {
  id: 'session-1',
  ownerId: 'seller-1',
  storageUploadId: 'r2-upload-1',
  videoS3Key: 'uploads/seller-1/session-1/video.mp4',
  fileName: 'video.mp4',
  contentType: 'video/mp4',
  sizeBytes: 10,
  partSizeBytes: 8,
  partCount: 2,
  status: 'UPLOADING' as const,
  expiresAt: new Date('2026-07-13T11:00:00.000Z'),
  operationStartedAt: null,
  completedAt: null,
  createdAt: timestamp,
  updatedAt: timestamp
};

const createPrismaDouble = () => {
  const transaction = {
    ...createOwnerOperationFixture(),
    managedUploadOwner: {
      upsert: vi.fn<PrismaUploadSessionClient['managedUploadOwner']['upsert']>(async () => ({ ownerId: 'seller-1', status: 'ACTIVE' })),
      findUnique: vi.fn(async () => ({ ownerId: 'seller-1', status: 'ACTIVE' as const })),
      update: vi.fn(async () => ({ ownerId: 'seller-1', status: 'DELETING' as const })),
      updateMany: vi.fn(async () => ({ count: 1 }))
    },
    managedUploadSession: {
      create: vi.fn(async () => persistedSession),
      findFirst: vi.fn(async () => persistedSession),
      findUnique: vi.fn(async () => persistedSession),
      findMany: vi.fn(async () => [persistedSession]),
      update: vi.fn(async () => persistedSession),
      deleteMany: vi.fn(async () => ({ count: 1 })),
      count: vi.fn(async () => 0)
    }
  };
  const prisma = {
    ...transaction,
    $transaction: vi.fn(async (action: (client: typeof transaction) => Promise<unknown>) =>
      action(transaction)
    )
  } as unknown as PrismaUploadSessionClient;

  return { prisma, transaction };
};

type OwnerFixture = { ownerId: string; status: UploadOwnerStatus; deletionAuthorizedAt?: Date | null };

const createOwnerPrismaDouble = (initialOwners: OwnerFixture[] = []) => {
  const owners = new Map(initialOwners.map((owner) => [owner.ownerId, owner]));
  const managedUploadOwner = {
    upsert: vi.fn(async ({ where, create }: { where: { ownerId: string }; create: OwnerFixture; update: Record<string, never> }) => {
      const owner = owners.get(where.ownerId) ?? { ...create };
      owners.set(where.ownerId, owner);
      return owner;
    }),
    findUnique: vi.fn(async ({ where }: { where: { ownerId: string } }) => owners.get(where.ownerId) ?? null),
    update: vi.fn(async ({ where, data }: { where: { ownerId: string }; data: { status: UploadOwnerStatus; deletionAuthorizedAt?: Date } }) => {
      const owner = { ...owners.get(where.ownerId)!, ...data };
      owners.set(where.ownerId, owner);
      return owner;
    }),
    updateMany: vi.fn(async () => ({ count: 1 }))
  };
  const transaction = {
    ...createOwnerOperationFixture(),
    managedUploadOwner,
    managedUploadSession: {
      create: vi.fn(async () => persistedSession),
      findFirst: vi.fn(async () => persistedSession),
      findUnique: vi.fn(async () => persistedSession),
      findMany: vi.fn(async () => []),
      update: vi.fn(async () => persistedSession),
      deleteMany: vi.fn(async () => ({ count: 0 })),
      count: vi.fn(async () => 0)
    }
  };
  const $transaction = vi.fn(async (action: (client: typeof transaction) => Promise<unknown>) => action(transaction));
  const prisma = { ...transaction, $transaction } as PrismaUploadSessionClient;
  return { prisma, transaction, owners, $transaction };
};

describe('Prisma upload session repository', () => {
  it('does not finish an unsealed owner or erase unresolved operation blockers', async () => {
    const { prisma, transaction, owners } = createOwnerPrismaDouble([{ ownerId: 'seller-1', status: 'ACTIVE' }]);
    const repository = createPrismaUploadSessionRepository({ prisma });
    await expect(repository.finishOwnerDeletion('seller-1')).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    expect(transaction.managedUploadSession.deleteMany).not.toHaveBeenCalled();
    owners.set('seller-1', { ownerId: 'seller-1', status: 'DELETING' });
    await prisma.managedOwnerOperation.create({ data: { id: 'unresolved', ownerId: 'seller-1', startedAt: new Date('2000-01-01') } });
    await expect(repository.finishOwnerDeletion('seller-1')).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
    expect(transaction.managedUploadSession.deleteMany).not.toHaveBeenCalled();
    await expect(prisma.managedOwnerOperation.count({ where: { ownerId: 'seller-1' } })).resolves.toBe(1);
    expect(owners.get('seller-1')?.status).toBe('DELETING');
  });
  it('persists a session only while its owner is active', async () => {
    const { prisma, transaction } = createPrismaDouble();
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(
      repository.createForActiveOwner({
        id: 'session-1',
        ownerId: 'seller-1',
        storageUploadId: 'r2-upload-1',
        videoS3Key: 'uploads/seller-1/session-1/video.mp4',
        fileName: 'video.mp4',
        contentType: 'video/mp4',
        sizeBytes: 10,
        partSizeBytes: 8,
        partCount: 2,
        expiresAt: '2026-07-13T11:00:00.000Z'
      })
    ).resolves.toMatchObject({ id: 'session-1', status: 'UPLOADING' });

    expect(transaction.managedUploadSession.create).toHaveBeenCalledOnce();
  });

  it('refuses a new session once the owner holds the open-session cap', async () => {
    const { prisma, transaction } = createPrismaDouble();
    transaction.managedUploadSession.count.mockResolvedValue(10);
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(
      repository.createForActiveOwner({
        id: 'session-11',
        ownerId: 'seller-1',
        storageUploadId: 'r2-upload-11',
        videoS3Key: 'uploads/seller-1/session-11/video.mp4',
        fileName: 'video.mp4',
        contentType: 'video/mp4',
        sizeBytes: 10,
        partSizeBytes: 8,
        partCount: 2,
        expiresAt: '2026-07-13T11:00:00.000Z'
      })
    ).rejects.toMatchObject({ code: 'UPLOAD_SESSION_LIMIT_REACHED' });

    expect(transaction.managedUploadSession.count).toHaveBeenCalledWith({
      where: { ownerId: 'seller-1', status: 'UPLOADING', expiresAt: { gt: expect.any(Date) } }
    });
    expect(transaction.managedUploadSession.create).not.toHaveBeenCalled();
  });

  it('does not reactivate a deleted owner', async () => {
    const { prisma, transaction } = createPrismaDouble();
    transaction.managedUploadOwner.upsert.mockResolvedValue({
      ownerId: 'seller-1',
      status: 'DELETED'
    });
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(
      repository.createForActiveOwner({
        id: 'session-2',
        ownerId: 'seller-1',
        storageUploadId: 'r2-upload-2',
        videoS3Key: 'uploads/seller-1/session-2/video.mp4',
        fileName: 'video.mp4',
        contentType: 'video/mp4',
        sizeBytes: 10,
        partSizeBytes: 8,
        partCount: 2,
        expiresAt: '2026-07-13T11:00:00.000Z'
      })
    ).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });

    expect(transaction.managedUploadSession.create).not.toHaveBeenCalled();
  });

  it('retries a serializable transaction conflict', async () => {
    const { prisma } = createPrismaDouble();
    const transaction = vi.mocked(prisma.$transaction);
    transaction
      .mockRejectedValueOnce(Object.assign(new Error('write conflict'), { code: 'P2034' }))
      .mockImplementationOnce(async (action) => action(prisma));
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(repository.beginOwnerDeletion('seller-1')).resolves.toBe('DELETING');
    expect(transaction).toHaveBeenCalledTimes(2);
  });

  it('does not overwrite a terminal upload status during cleanup races', async () => {
    const { prisma, transaction } = createPrismaDouble();
    const repository = createPrismaUploadSessionRepository({ prisma });
    transaction.managedUploadSession.findUnique.mockResolvedValue({
      ...persistedSession,
      status: 'ABORTED'
    });

    await expect(
      repository.markCompleted('session-1', '2026-07-13T10:01:00.000Z')
    ).rejects.toMatchObject({ code: 'UPLOAD_SESSION_NOT_ACTIVE' });
    expect(transaction.managedUploadSession.update).not.toHaveBeenCalled();

    transaction.managedUploadSession.findUnique.mockResolvedValue({
      ...persistedSession,
      status: 'COMPLETED',
      completedAt: timestamp
    });
    await expect(repository.markAborted('session-1')).resolves.toMatchObject({
      status: 'COMPLETED'
    });
    expect(transaction.managedUploadSession.update).not.toHaveBeenCalled();
  });

  it.each([
    { status: 'ACTIVE', deletionAuthorizedAt: timestamp },
    { status: 'DELETING', deletionAuthorizedAt: null },
    { status: 'DELETED' },
    { status: 'DELETING', deletionAuthorizedAt: new Date('invalid') },
    { status: 'DELETED', deletionAuthorizedAt: new Date('invalid') }
  ] satisfies Array<Omit<OwnerFixture, 'ownerId'>>)(
    'does not infer authorization from an incomplete marker %#', async (marker) => {
      const { prisma } = createOwnerPrismaDouble([{ ownerId: 'seller-1', ...marker }]);
      const repository = createPrismaUploadSessionRepository({ prisma });
      await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBeUndefined();
    }
  );

  it('returns only a valid authorization for the requested owner, including across new repository views', async () => {
    const authorization = new Date('2026-10-13T18:00:00.000Z');
    const { prisma, transaction } = createOwnerPrismaDouble([
      { ownerId: 'seller-1', status: 'DELETING', deletionAuthorizedAt: authorization },
      { ownerId: 'seller-2', status: 'DELETED', deletionAuthorizedAt: authorization }
    ]);
    const first = createPrismaUploadSessionRepository({ prisma });
    const restarted = createPrismaUploadSessionRepository({ prisma });
    await expect(first.getOwnerDeletionAuthorization('seller-1')).resolves.toBe(authorization.toISOString());
    await expect(restarted.getOwnerDeletionAuthorization('seller-2')).resolves.toBe(authorization.toISOString());
    await expect(restarted.getOwnerDeletionAuthorization('seller-3')).resolves.toBeUndefined();
    transaction.managedUploadOwner.findUnique.mockResolvedValueOnce({
      ownerId: 'seller-1', status: 'DELETED', deletionAuthorizedAt: authorization
    });
    await expect(restarted.getOwnerDeletionAuthorization('seller-2')).resolves.toBeUndefined();
  });

  it('writes authorization and a new deleting marker together in a serializable transaction', async () => {
    const { prisma, transaction, owners, $transaction } = createOwnerPrismaDouble();
    const repository = createPrismaUploadSessionRepository({ prisma });
    await repository.authorizeOwnerDeletion('seller-1', '2026-10-14T01:00:00+07:00');

    expect(owners.get('seller-1')).toEqual({
      ownerId: 'seller-1', status: 'DELETING', deletionAuthorizedAt: new Date('2026-10-13T18:00:00.000Z')
    });
    expect(transaction.managedUploadOwner.upsert).toHaveBeenCalledWith({
      where: { ownerId: 'seller-1' },
      create: { ownerId: 'seller-1', status: 'DELETING', deletionAuthorizedAt: new Date('2026-10-13T18:00:00.000Z') },
      update: {}
    });
    expect($transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: 'Serializable', maxWait: 5_000, timeout: 10_000
    });
  });

  it('changes an active marker and records its proof in the same write', async () => {
    const { prisma, transaction, owners } = createOwnerPrismaDouble([
      { ownerId: 'seller-1', status: 'ACTIVE', deletionAuthorizedAt: null }
    ]);
    const repository = createPrismaUploadSessionRepository({ prisma });
    await repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:00:00.000Z');

    expect(transaction.managedUploadOwner.update).toHaveBeenCalledWith({
      where: { ownerId: 'seller-1' },
      data: { status: 'DELETING', deletionAuthorizedAt: new Date('2026-10-13T18:00:00.000Z') }
    });
    expect(owners.get('seller-1')?.status).toBe('DELETING');
    await expect(repository.assertOwnerActive('seller-1'))
      .rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('retains the original proof through begin, finish, and later authorization without reviving the owner', async () => {
    const { prisma, owners } = createOwnerPrismaDouble();
    const repository = createPrismaUploadSessionRepository({ prisma });
    const firstAuthorization = '2026-10-13T18:00:00.000Z';
    await repository.authorizeOwnerDeletion('seller-1', firstAuthorization);
    await repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:01:00.000Z');
    await repository.beginOwnerDeletion('seller-1');
    await repository.finishOwnerDeletion('seller-1');
    const restarted = createPrismaUploadSessionRepository({ prisma });
    await restarted.authorizeOwnerDeletion('seller-1', '2026-10-13T18:02:00.000Z');

    expect(owners.get('seller-1')?.status).toBe('DELETED');
    await expect(restarted.getOwnerDeletionAuthorization('seller-1')).resolves.toBe(firstAuthorization);
    await expect(restarted.beginOwnerDeletion('seller-1')).resolves.toBe('DELETED');
  });

  it('leaves legacy begin and finish markers without authorization', async () => {
    const { prisma, owners } = createOwnerPrismaDouble();
    const repository = createPrismaUploadSessionRepository({ prisma });
    await repository.beginOwnerDeletion('seller-1');
    await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBeUndefined();
    await repository.finishOwnerDeletion('seller-1');
    expect(owners.get('seller-1')).toEqual({ ownerId: 'seller-1', status: 'DELETED' });
    await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBeUndefined();
  });

  it.each(['', 'not-a-date', '999999-12-31T00:00:00.000Z'])(
    'rejects invalid authorization %j before touching persistence', async (invalidTimestamp) => {
      const { prisma, owners, $transaction } = createOwnerPrismaDouble();
      const repository = createPrismaUploadSessionRepository({ prisma });
      await expect(repository.authorizeOwnerDeletion('seller-1', invalidTimestamp)).rejects.toThrow();
      expect($transaction).not.toHaveBeenCalled();
      expect(owners.size).toBe(0);
    }
  );

  it('retries serialization conflicts and retains a concurrently completed marker', async () => {
    const firstAuthorization = new Date('2026-10-13T18:00:00.000Z');
    const { prisma, owners, $transaction } = createOwnerPrismaDouble([
      { ownerId: 'seller-1', status: 'DELETING', deletionAuthorizedAt: firstAuthorization }
    ]);
    $transaction.mockImplementationOnce(async () => {
      owners.set('seller-1', { ownerId: 'seller-1', status: 'DELETED', deletionAuthorizedAt: firstAuthorization });
      throw Object.assign(new Error('write conflict'), { code: 'P2034' });
    });
    const repository = createPrismaUploadSessionRepository({ prisma });
    await repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:02:00.000Z');

    expect($transaction).toHaveBeenCalledTimes(2);
    expect(owners.get('seller-1')).toEqual({ ownerId: 'seller-1', status: 'DELETED', deletionAuthorizedAt: firstAuthorization });
    await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBe(firstAuthorization.toISOString());
  });

  it('queues authorization and finish behind active owner work without losing proof', async () => {
    const { prisma, owners } = createOwnerPrismaDouble([{ ownerId: 'seller-1', status: 'ACTIVE' }]);
    const repository = createPrismaUploadSessionRepository({ prisma });
    let releaseWrite!: () => void;
    let startWrite!: () => void;
    const started = new Promise<void>((resolve) => { startWrite = resolve; });
    const heldWrite = new Promise<void>((resolve) => { releaseWrite = resolve; });
    const write = repository.runWithActiveOwner('seller-1', async () => {
      startWrite();
      await heldWrite;
    });
    await started;
    const authorize = repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:00:00.000Z');
    const finish = repository.finishOwnerDeletion('seller-1');
    expect(owners.get('seller-1')?.status).toBe('ACTIVE');
    releaseWrite();
    await Promise.all([write, authorize, finish]);

    expect(owners.get('seller-1')?.status).toBe('DELETED');
    await expect(repository.getOwnerDeletionAuthorization('seller-1'))
      .resolves.toBe('2026-10-13T18:00:00.000Z');
  });

  it('does not mint proof if serializable conflicts exhaust the retry budget', async () => {
    const { prisma, owners, $transaction } = createOwnerPrismaDouble();
    const conflict = Object.assign(new Error('write conflict'), { code: 'P2034' });
    $transaction.mockRejectedValue(conflict);
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:00:00.000Z'))
      .rejects.toBe(conflict);
    expect($transaction).toHaveBeenCalledTimes(3);
    expect(owners.size).toBe(0);
    await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBeUndefined();
  });

  it('never writes proof for authorization that timed out behind owner work', async () => {
    vi.useFakeTimers();
    let releaseWrite!: () => void;
    try {
      const { prisma, owners, $transaction } = createOwnerPrismaDouble([
        { ownerId: 'seller-1', status: 'ACTIVE', deletionAuthorizedAt: null }
      ]);
      const repository = createPrismaUploadSessionRepository({ prisma });
      let startWrite!: () => void;
      const started = new Promise<void>((resolve) => { startWrite = resolve; });
      const heldWrite = new Promise<void>((resolve) => { releaseWrite = resolve; });
      const write = repository.runWithActiveOwner('seller-1', async () => {
        startWrite();
        await heldWrite;
      });
      await started;
      const authorization = repository.authorizeOwnerDeletion('seller-1', '2026-10-13T18:00:00.000Z');
      const rejected = expect(authorization).rejects.toMatchObject({ code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
      await vi.advanceTimersByTimeAsync(5_001);
      await rejected;
      releaseWrite();
      await write;
      await repository.runWithActiveOwner('seller-1', async () => undefined);

      // Only the two active-work admissions ran; timed-out authorization never
      // entered its proof-writing transaction.
      expect($transaction).toHaveBeenCalledTimes(2);
      expect(prisma.managedUploadOwner.update).not.toHaveBeenCalled();
      expect(owners.get('seller-1')).toEqual({ ownerId: 'seller-1', status: 'ACTIVE', deletionAuthorizedAt: null });
      await expect(repository.getOwnerDeletionAuthorization('seller-1')).resolves.toBeUndefined();
    } finally {
      releaseWrite?.();
      vi.useRealTimers();
    }
  });
});
