import { describe, expect, it } from 'vitest';

import {
  UploadSessionConflictError,
  createInMemoryUploadSessionStore
} from './uploadSessionStore.js';

const sessionInput = (overrides: Partial<Parameters<ReturnType<typeof createInMemoryUploadSessionStore>['createForActiveOwner']>[0]> = {}) => ({
  id: 'session-1',
  ownerId: 'seller-1',
  storageUploadId: 'r2-upload-1',
  videoS3Key: 'uploads/seller-1/session-1/video.mp4',
  fileName: 'video.mp4',
  contentType: 'video/mp4',
  sizeBytes: 20_000_000,
  partSizeBytes: 8_388_608,
  partCount: 3,
  expiresAt: '2026-07-13T12:00:00.000Z',
  ...overrides
});

describe('in-memory upload session store', () => {
  it('keeps sessions scoped to their owner', async () => {
    const store = createInMemoryUploadSessionStore();

    await store.createForActiveOwner(sessionInput());

    await expect(
      store.getForOwner('session-1', 'seller-1')
    ).resolves.toMatchObject({ id: 'session-1', ownerId: 'seller-1' });
    await expect(store.getForOwner('session-1', 'seller-2')).resolves.toBeUndefined();
  });

  it('blocks new sessions and part URLs after account deletion starts', async () => {
    const store = createInMemoryUploadSessionStore();
    await store.createForActiveOwner(sessionInput());

    await store.beginOwnerDeletion('seller-1');

    await expect(
      store.createForActiveOwner(sessionInput({ id: 'session-2', storageUploadId: 'r2-upload-2' }))
    ).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(
      store.getUploadableForOwner({
        id: 'session-1',
        ownerId: 'seller-1',
        now: '2026-07-13T11:00:00.000Z'
      })
    ).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('transitions completion atomically and remains idempotent', async () => {
    const store = createInMemoryUploadSessionStore();
    await store.createForActiveOwner(sessionInput());

    const completing = await store.beginCompletion({
      id: 'session-1',
      ownerId: 'seller-1',
      now: '2026-07-13T11:00:00.000Z'
    });
    expect(completing.status).toBe('COMPLETING');

    await expect(
      store.beginCompletion({
        id: 'session-1',
        ownerId: 'seller-1',
        now: '2026-07-13T11:00:01.000Z'
      })
    ).rejects.toMatchObject({ code: 'UPLOAD_COMPLETION_IN_PROGRESS' });

    await expect(
      store.beginAbort('session-1', 'seller-1')
    ).rejects.toMatchObject({ code: 'UPLOAD_COMPLETION_IN_PROGRESS' });

    const completed = await store.markCompleted(
      'session-1',
      '2026-07-13T11:01:00.000Z'
    );
    expect(completed.status).toBe('COMPLETED');
    await expect(store.markAborted('session-1')).resolves.toMatchObject({
      status: 'COMPLETED'
    });

    await expect(
      store.beginCompletion({
        id: 'session-1',
        ownerId: 'seller-1',
        now: '2026-07-13T11:02:00.000Z'
      })
    ).resolves.toMatchObject({ status: 'COMPLETED' });
  });

  it('claims an abort before storage cleanup and keeps it idempotent', async () => {
    const store = createInMemoryUploadSessionStore();
    await store.createForActiveOwner(sessionInput());

    await expect(store.beginAbort('session-1', 'seller-1')).resolves.toMatchObject({
      status: 'ABORTED'
    });
    await expect(store.beginAbort('session-1', 'seller-1')).resolves.toMatchObject({
      status: 'ABORTED'
    });

    await expect(
      store.beginCompletion({
        id: 'session-1',
        ownerId: 'seller-1',
        now: '2026-07-13T11:00:00.000Z'
      })
    ).rejects.toMatchObject({ code: 'UPLOAD_SESSION_NOT_ACTIVE' });
    await expect(
      store.markCompleted('session-1', '2026-07-13T11:01:00.000Z')
    ).rejects.toMatchObject({ code: 'UPLOAD_SESSION_NOT_ACTIVE' });
  });

  it('rejects expired sessions before issuing another part URL', async () => {
    const store = createInMemoryUploadSessionStore();
    await store.createForActiveOwner(sessionInput());

    await expect(
      store.getUploadableForOwner({
        id: 'session-1',
        ownerId: 'seller-1',
        now: '2026-07-13T12:00:01.000Z'
      })
    ).rejects.toEqual(
      expect.objectContaining<Partial<UploadSessionConflictError>>({
        code: 'UPLOAD_SESSION_EXPIRED'
      })
    );
  });

  it('lists open sessions for cleanup and leaves a durable deleted owner marker', async () => {
    const store = createInMemoryUploadSessionStore();
    await store.createForActiveOwner(sessionInput());
    await store.beginOwnerDeletion('seller-1');

    await expect(store.listOpenForOwner('seller-1')).resolves.toHaveLength(1);

    await store.markAborted('session-1');
    await store.finishOwnerDeletion('seller-1');

    await expect(store.listOpenForOwner('seller-1')).resolves.toEqual([]);
    await expect(
      store.createForActiveOwner(
        sessionInput({ id: 'session-after-delete', storageUploadId: 'r2-upload-after-delete' })
      )
    ).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });
});
