import { describe, expect, it, vi } from 'vitest';

import {
  createPrismaUploadSessionRepository,
  type PrismaUploadSessionClient
} from './prismaUploadSessionRepository.js';

const timestamp = new Date('2026-07-13T10:00:00.000Z');

const persistedSession = {
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
    managedUploadOwner: {
      upsert: vi.fn(async () => ({ ownerId: 'seller-1', status: 'ACTIVE' as const })),
      findUnique: vi.fn(async () => ({ ownerId: 'seller-1', status: 'ACTIVE' as const })),
      update: vi.fn(async () => ({ ownerId: 'seller-1', status: 'DELETING' as const }))
    },
    managedUploadSession: {
      create: vi.fn(async () => persistedSession),
      findFirst: vi.fn(async () => persistedSession),
      findUnique: vi.fn(async () => persistedSession),
      findMany: vi.fn(async () => [persistedSession]),
      update: vi.fn(async () => persistedSession),
      deleteMany: vi.fn(async () => ({ count: 1 }))
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

describe('Prisma upload session repository', () => {
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
});
