import { describe, expect, it, vi } from 'vitest';

import { createInMemoryUploadSessionStore } from './uploadSessionStore.js';
import {
  createManagedUploadService,
  type ManagedMultipartStorage
} from './managedUploadService.js';

const createStorage = (): ManagedMultipartStorage => ({
  createUpload: vi.fn(async () => ({
    storageUploadId: 'r2-upload-1',
    videoS3Key: 'uploads/seller-1/object/video.mp4',
    createdAt: '2026-07-13T10:00:00.000Z'
  })),
  createPartUpload: vi.fn(async ({ sizeBytes }) => ({
    uploadUrl: 'https://r2.test/part',
    uploadExpiresAt: '2026-07-13T10:05:00.000Z',
    uploadHeaders: { 'Content-Length': String(sizeBytes) }
  })),
  completeUpload: vi.fn(async () => undefined),
  abortUpload: vi.fn(async () => undefined),
  getCompletedObjectSize: vi.fn(async () => undefined),
  listUploadsForOwner: vi.fn(async () => [])
});

const metadata = {
  fileName: 'video.mp4',
  contentType: 'video/mp4',
  sizeBytes: 17
};

const createService = ({ completionDrainSeconds = 120 } = {}) => {
  const storage = createStorage();
  const store = createInMemoryUploadSessionStore({
    now: () => '2026-07-13T10:00:00.000Z'
  });
  const service = createManagedUploadService({
    storage,
    store,
    partSizeBytes: 8,
    sessionExpiresSeconds: 3600,
    now: () => new Date('2026-07-13T10:00:00.000Z'),
    idFactory: () => 'session-1',
    completionDrainSeconds
  });

  return { service, storage, store };
};

describe('managed upload service', () => {
  it('creates an opaque multipart session without exposing the storage upload id', async () => {
    const { service } = createService();

    await expect(service.create(metadata, 'seller-1')).resolves.toEqual({
      id: 'session-1',
      videoS3Key: 'uploads/seller-1/object/video.mp4',
      fileName: 'video.mp4',
      contentType: 'video/mp4',
      sizeBytes: 17,
      uploadProtocol: 'multipart-v1',
      partSizeBytes: 8,
      partCount: 3,
      sessionExpiresAt: '2026-07-13T11:00:00.000Z'
    });
  });

  it('calculates the final part length on the server', async () => {
    const { service, storage } = createService();
    await service.create(metadata, 'seller-1');

    const part = await service.createPart('session-1', 'seller-1', 3);

    expect(part).toMatchObject({
      partNumber: 3,
      sizeBytes: 1,
      uploadMethod: 'PUT',
      uploadHeaders: { 'Content-Length': '1' }
    });
    expect(storage.createPartUpload).toHaveBeenCalledWith(
      expect.objectContaining({ partNumber: 3, sizeBytes: 1 })
    );
  });

  it('requires every ETag before completing and sorts the storage request', async () => {
    const { service, storage } = createService();
    await service.create(metadata, 'seller-1');

    await expect(
      service.complete('session-1', 'seller-1', [
        { partNumber: 1, etag: 'etag-1' }
      ])
    ).rejects.toMatchObject({ code: 'UPLOAD_PARTS_INVALID' });

    await service.complete('session-1', 'seller-1', [
      { partNumber: 3, etag: 'etag-3' },
      { partNumber: 1, etag: 'etag-1' },
      { partNumber: 2, etag: 'etag-2' }
    ]);

    expect(storage.completeUpload).toHaveBeenCalledWith(
      expect.objectContaining({
        parts: [
          { partNumber: 1, eTag: 'etag-1' },
          { partNumber: 2, eTag: 'etag-2' },
          { partNumber: 3, eTag: 'etag-3' }
        ]
      })
    );
    await expect(service.get('session-1', 'seller-1')).resolves.toMatchObject({
      sessionStatus: 'COMPLETED'
    });
  });

  it('does not complete or abort the same upload twice while completion is in progress', async () => {
    const { service, storage } = createService();
    await service.create(metadata, 'seller-1');
    let releaseCompletion: (() => void) | undefined;
    vi.mocked(storage.completeUpload).mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          releaseCompletion = resolve;
        })
    );
    const parts = [
      { partNumber: 1, etag: 'etag-1' },
      { partNumber: 2, etag: 'etag-2' },
      { partNumber: 3, etag: 'etag-3' }
    ];

    const firstCompletion = service.complete('session-1', 'seller-1', parts);
    await vi.waitFor(() => expect(storage.completeUpload).toHaveBeenCalledOnce());

    await expect(
      service.complete('session-1', 'seller-1', parts)
    ).rejects.toMatchObject({ code: 'UPLOAD_COMPLETION_IN_PROGRESS' });
    await expect(service.abort('session-1', 'seller-1')).rejects.toMatchObject({
      code: 'UPLOAD_COMPLETION_IN_PROGRESS'
    });
    expect(storage.abortUpload).not.toHaveBeenCalled();

    releaseCompletion?.();
    await expect(firstCompletion).resolves.toMatchObject({ id: 'session-1' });
  });

  it('retries an idempotent abort cleanup without reopening the session', async () => {
    const { service, storage } = createService();
    await service.create(metadata, 'seller-1');
    vi.mocked(storage.abortUpload)
      .mockRejectedValueOnce(new Error('temporary R2 error'))
      .mockResolvedValueOnce(undefined);

    await expect(service.abort('session-1', 'seller-1')).rejects.toThrow(
      'temporary R2 error'
    );
    await expect(service.abort('session-1', 'seller-1')).resolves.toBeUndefined();

    expect(storage.abortUpload).toHaveBeenCalledTimes(2);
    await expect(service.get('session-1', 'seller-1')).resolves.toMatchObject({
      sessionStatus: 'ABORTED'
    });
  });

  it('does not let stale completion overwrite account-deletion cleanup', async () => {
    const { service, storage } = createService({ completionDrainSeconds: 0 });
    await service.create(metadata, 'seller-1');
    let releaseCompletion: (() => void) | undefined;
    vi.mocked(storage.completeUpload).mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          releaseCompletion = resolve;
        })
    );
    const completion = service.complete('session-1', 'seller-1', [
      { partNumber: 1, etag: 'etag-1' },
      { partNumber: 2, etag: 'etag-2' },
      { partNumber: 3, etag: 'etag-3' }
    ]);
    await vi.waitFor(() => expect(storage.completeUpload).toHaveBeenCalledOnce());

    await service.prepareOwnerDeletion('seller-1');
    releaseCompletion?.();

    await expect(completion).rejects.toMatchObject({
      code: 'UPLOAD_SESSION_NOT_ACTIVE'
    });
    await expect(service.get('session-1', 'seller-1')).resolves.toMatchObject({
      sessionStatus: 'ABORTED'
    });
  });

  it('reconciles a completed R2 object when the database acknowledgement failed', async () => {
    const { service, storage, store } = createService();
    await service.create(metadata, 'seller-1');
    vi.spyOn(store, 'markCompleted').mockRejectedValueOnce(
      new Error('temporary database error')
    );
    vi.mocked(storage.getCompletedObjectSize).mockResolvedValue(metadata.sizeBytes);

    await expect(
      service.complete('session-1', 'seller-1', [
        { partNumber: 1, etag: 'etag-1' },
        { partNumber: 2, etag: 'etag-2' },
        { partNumber: 3, etag: 'etag-3' }
      ])
    ).rejects.toThrow('temporary database error');

    await expect(service.get('session-1', 'seller-1')).resolves.toMatchObject({
      sessionStatus: 'COMPLETED'
    });
    expect(storage.getCompletedObjectSize).toHaveBeenCalledWith(
      'uploads/seller-1/object/video.mp4'
    );
  });

  it('blocks upload use after account deletion starts', async () => {
    const { service, store } = createService();
    await store.beginOwnerDeletion('seller-1');

    await expect(service.assertOwnerActive('seller-1')).rejects.toMatchObject({
      code: 'ACCOUNT_DELETION_IN_PROGRESS'
    });
    await expect(
      service.assertReadyForUse('seller-1', 'uploads/seller-1/legacy/video.mp4', {
        allowLegacy: true
      })
    ).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('aborts a newly-created R2 upload when account deletion wins the race', async () => {
    const { service, storage, store } = createService();
    await store.beginOwnerDeletion('seller-1');

    await expect(service.create(metadata, 'seller-1')).rejects.toMatchObject({
      code: 'ACCOUNT_DELETION_IN_PROGRESS'
    });
    expect(storage.abortUpload).toHaveBeenCalledWith({
      storageUploadId: 'r2-upload-1',
      videoS3Key: 'uploads/seller-1/object/video.mp4'
    });
  });

  it('allows downstream use only after the managed upload is completed', async () => {
    const { service } = createService();
    const upload = await service.create(metadata, 'seller-1');

    await expect(
      service.assertReadyForUse('seller-1', upload.videoS3Key, {
        allowLegacy: true
      })
    ).rejects.toMatchObject({ code: 'UPLOAD_NOT_READY' });

    await service.complete('session-1', 'seller-1', [
      { partNumber: 1, etag: 'etag-1' },
      { partNumber: 2, etag: 'etag-2' },
      { partNumber: 3, etag: 'etag-3' }
    ]);

    await expect(
      service.assertReadyForUse('seller-1', upload.videoS3Key, {
        allowLegacy: false
      })
    ).resolves.toBeUndefined();
  });

  it('allows keys without a session only during the legacy migration window', async () => {
    const { service } = createService();
    const legacyKey = 'uploads/seller-1/legacy/video.mp4';

    await expect(
      service.assertReadyForUse('seller-1', legacyKey, { allowLegacy: true })
    ).resolves.toBeUndefined();
    await expect(
      service.assertReadyForUse('seller-1', legacyKey, { allowLegacy: false })
    ).rejects.toMatchObject({ code: 'UPLOAD_CONFIRMATION_REQUIRED' });
  });

  it('aborts persisted and orphaned multipart uploads before account cleanup', async () => {
    const { service, storage } = createService();
    await service.create(metadata, 'seller-1');
    vi.mocked(storage.listUploadsForOwner).mockResolvedValue([
      {
        storageUploadId: 'r2-upload-1',
        videoS3Key: 'uploads/seller-1/object/video.mp4'
      },
      {
        storageUploadId: 'orphan-r2-upload',
        videoS3Key: 'uploads/seller-1/orphan/video.mp4'
      }
    ]);

    await service.prepareOwnerDeletion('seller-1');

    expect(storage.abortUpload).toHaveBeenCalledTimes(2);
    expect(storage.abortUpload).toHaveBeenCalledWith({
      storageUploadId: 'orphan-r2-upload',
      videoS3Key: 'uploads/seller-1/orphan/video.mp4'
    });
  });
});
