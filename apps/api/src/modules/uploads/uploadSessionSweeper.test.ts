import { describe, expect, it, vi } from 'vitest';

import { createInMemoryUploadSessionStore } from './uploadSessionStore.js';
import {
  createManagedUploadService,
  type ManagedMultipartStorage
} from './managedUploadService.js';
import {
  createPrismaUploadSessionRepository,
  type PrismaUploadSessionClient
} from './prismaUploadSessionRepository.js';

const createdAt = '2026-07-13T10:00:00.000Z';
const metadata = { fileName: 'video.mp4', contentType: 'video/mp4', sizeBytes: 17 };

const createSweepFixture = () => {
  let clock = new Date(createdAt);
  let uploadCount = 0;
  const storage: ManagedMultipartStorage = {
    createUpload: vi.fn(async () => {
      uploadCount += 1;
      return {
        storageUploadId: `r2-upload-${uploadCount}`,
        videoS3Key: `uploads/seller-1/object-${uploadCount}/video.mp4`,
        createdAt
      };
    }),
    createPartUpload: vi.fn(async () => ({ uploadUrl: 'https://r2.test/part', uploadExpiresAt: createdAt })),
    completeUpload: vi.fn(async () => undefined),
    abortUpload: vi.fn(async () => undefined),
    getCompletedObjectSize: vi.fn(async () => undefined),
    listUploadsForOwner: vi.fn(async () => [])
  };
  const store = createInMemoryUploadSessionStore({ now: () => clock.toISOString() });
  let sessionCount = 0;
  const service = createManagedUploadService({
    storage,
    store,
    partSizeBytes: 8,
    sessionExpiresSeconds: 3600,
    now: () => clock,
    idFactory: () => {
      sessionCount += 1;
      return `session-${sessionCount}`;
    }
  });
  const advanceTo = (iso: string) => { clock = new Date(iso); };
  return { service, storage, store, advanceTo };
};

describe('expired upload session sweep', () => {
  it('aborts the R2 multipart upload and retires each expired UPLOADING session', async () => {
    const { service, storage, store, advanceTo } = createSweepFixture();
    await service.create(metadata, 'seller-1');
    await service.create(metadata, 'seller-1');
    await service.create(metadata, 'seller-2');

    // Sessions expire at 11:00; the sweep waits a five-minute grace period.
    advanceTo('2026-07-13T11:06:00.000Z');
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 3, failed: 0 });

    expect(storage.abortUpload).toHaveBeenCalledTimes(3);
    expect(storage.abortUpload).toHaveBeenCalledWith({
      storageUploadId: 'r2-upload-1', videoS3Key: 'uploads/seller-1/object-1/video.mp4'
    });
    for (const [id, owner] of [['session-1', 'seller-1'], ['session-2', 'seller-1'], ['session-3', 'seller-2']]) {
      expect((await store.getForOwner(id!, owner!))?.status).toBe('ABORTED');
    }
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 0, failed: 0 });
  });

  it('leaves unexpired, grace-period, completing and completed sessions alone', async () => {
    const { service, storage, store, advanceTo } = createSweepFixture();
    await service.create(metadata, 'seller-1');
    await service.create(metadata, 'seller-1');
    await store.beginCompletion({ id: 'session-2', ownerId: 'seller-1', now: createdAt });

    advanceTo('2026-07-13T10:30:00.000Z');
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 0, failed: 0 });
    advanceTo('2026-07-13T11:04:00.000Z');
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 0, failed: 0 });
    expect(storage.abortUpload).not.toHaveBeenCalled();

    advanceTo('2026-07-13T12:00:00.000Z');
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 1, failed: 0 });
    expect((await store.getForOwner('session-2', 'seller-1'))?.status).toBe('COMPLETING');
  });

  it('retires at most the requested batch per sweep', async () => {
    const { service, storage, advanceTo } = createSweepFixture();
    for (let index = 0; index < 3; index += 1) await service.create(metadata, 'seller-1');

    advanceTo('2026-07-13T12:00:00.000Z');
    await expect(service.sweepExpiredSessions({ limit: 2 })).resolves.toEqual({ retired: 2, failed: 0 });
    expect(storage.abortUpload).toHaveBeenCalledTimes(2);
    await expect(service.sweepExpiredSessions({ limit: 2 })).resolves.toEqual({ retired: 1, failed: 0 });
  });

  it('keeps a session for the next sweep when the R2 abort fails', async () => {
    const { service, storage, store, advanceTo } = createSweepFixture();
    await service.create(metadata, 'seller-1');
    await service.create(metadata, 'seller-1');
    vi.mocked(storage.abortUpload).mockRejectedValueOnce(new Error('r2 unavailable'));

    advanceTo('2026-07-13T12:00:00.000Z');
    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 1, failed: 1 });
    expect((await store.getForOwner('session-1', 'seller-1'))?.status).toBe('UPLOADING');
    expect((await store.getForOwner('session-2', 'seller-1'))?.status).toBe('ABORTED');

    await expect(service.sweepExpiredSessions()).resolves.toEqual({ retired: 1, failed: 0 });
    expect((await store.getForOwner('session-1', 'seller-1'))?.status).toBe('ABORTED');
  });
});

describe('Prisma expired upload session sweep', () => {
  const expired = {
    id: 'session-1', ownerId: 'seller-1', storageUploadId: 'r2-upload-1',
    videoS3Key: 'uploads/seller-1/session-1/video.mp4', fileName: 'video.mp4', contentType: 'video/mp4',
    sizeBytes: 10, partSizeBytes: 8, partCount: 2, status: 'UPLOADING' as const,
    expiresAt: new Date('2026-07-13T11:00:00.000Z'), operationStartedAt: null, completedAt: null,
    createdAt: new Date(createdAt), updatedAt: new Date(createdAt)
  };

  const createPrisma = (updateCount: number) => {
    const managedUploadSession = {
      findMany: vi.fn(async () => [expired]),
      updateMany: vi.fn(async () => ({ count: updateCount }))
    };
    return { prisma: { managedUploadSession } as unknown as PrismaUploadSessionClient, managedUploadSession };
  };

  it('lists a bounded, oldest-first batch of expired UPLOADING sessions across owners', async () => {
    const { prisma, managedUploadSession } = createPrisma(1);
    const repository = createPrismaUploadSessionRepository({ prisma });

    await expect(repository.listExpiredUploading({ expiredBefore: '2026-07-13T11:05:00.000Z', limit: 25 }))
      .resolves.toEqual([expect.objectContaining({ id: 'session-1', status: 'UPLOADING' })]);
    expect(managedUploadSession.findMany).toHaveBeenCalledExactlyOnceWith({
      where: { status: 'UPLOADING', expiresAt: { lte: new Date('2026-07-13T11:05:00.000Z') } },
      orderBy: { expiresAt: 'asc' },
      take: 25
    });
  });

  it('retires a session only while it is still expired and UPLOADING', async () => {
    const retired = createPrisma(1);
    await expect(createPrismaUploadSessionRepository({ prisma: retired.prisma })
      .retireExpired({ id: 'session-1', expiredBefore: '2026-07-13T11:05:00.000Z' })).resolves.toBe(true);
    expect(retired.managedUploadSession.updateMany).toHaveBeenCalledExactlyOnceWith({
      where: { id: 'session-1', status: 'UPLOADING', expiresAt: { lte: new Date('2026-07-13T11:05:00.000Z') } },
      data: { status: 'ABORTED', operationStartedAt: null }
    });

    const raced = createPrisma(0);
    await expect(createPrismaUploadSessionRepository({ prisma: raced.prisma })
      .retireExpired({ id: 'session-1', expiredBefore: '2026-07-13T11:05:00.000Z' })).resolves.toBe(false);
  });
});
