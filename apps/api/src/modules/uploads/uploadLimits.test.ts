import { describe, expect, it } from 'vitest';

import { readUploadMetadata } from './uploadService.js';
import { createInMemoryUploadSessionStore, UploadSessionConflictError } from './uploadSessionStore.js';

const maxSizeBytes = 500 * 1024 * 1024;
const videoBody = (overrides: Record<string, unknown> = {}) => ({
  fileName: 'clip.mp4',
  contentType: 'video/mp4',
  sizeBytes: 1024,
  ...overrides
});

// Managed upload sessions store the client fileName and stay in the shared
// database until account deletion, so admission must be bounded per field and
// per owner.
describe('upload metadata limits', () => {
  it('rejects a file name longer than 255 characters', () => {
    expect(readUploadMetadata(videoBody({ fileName: `${'a'.repeat(252)}.mp4` }), { maxSizeBytes }).ok).toBe(false);
    expect(readUploadMetadata(videoBody({ fileName: `${'a'.repeat(251)}.mp4` }), { maxSizeBytes }).ok).toBe(true);
  });

  it('accepts only the exact video and image types the app uploads', () => {
    for (const contentType of ['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png', 'image/webp']) {
      expect(readUploadMetadata(videoBody({ contentType }), { maxSizeBytes }).ok).toBe(true);
    }
    for (const contentType of ['video/x-anything', 'image/svg+xml', 'video/mp4; codecs=evil', 'image/']) {
      expect(readUploadMetadata(videoBody({ contentType }), { maxSizeBytes }).ok).toBe(false);
    }
  });
});

describe('open upload session cap', () => {
  const sessionInput = (index: number, expiresAt: string) => ({
    id: `session-${index}`,
    ownerId: 'seller-uploads',
    storageUploadId: `r2-${index}`,
    videoS3Key: `uploads/seller-uploads/session-${index}/video.mp4`,
    fileName: 'video.mp4',
    contentType: 'video/mp4',
    sizeBytes: 10,
    partSizeBytes: 8,
    partCount: 2,
    expiresAt
  });

  it('refuses an eleventh unexpired UPLOADING session for one owner', async () => {
    const now = '2026-10-24T00:00:00.000Z';
    const store = createInMemoryUploadSessionStore({ now: () => now });
    for (let index = 0; index < 10; index += 1) {
      await store.createForActiveOwner(sessionInput(index, '2026-10-24T01:00:00.000Z'));
    }

    const overCap = store.createForActiveOwner(sessionInput(10, '2026-10-24T01:00:00.000Z'));

    await expect(overCap).rejects.toBeInstanceOf(UploadSessionConflictError);
    await expect(overCap).rejects.toMatchObject({ code: 'UPLOAD_SESSION_LIMIT_REACHED' });
  });

  it('does not count expired sessions against the cap', async () => {
    const now = '2026-10-24T02:00:00.000Z';
    const store = createInMemoryUploadSessionStore({ now: () => now });
    for (let index = 0; index < 10; index += 1) {
      await store.createForActiveOwner(sessionInput(index, '2026-10-24T01:00:00.000Z'));
    }

    await expect(store.createForActiveOwner(sessionInput(10, '2026-10-24T03:00:00.000Z'))).resolves.toMatchObject({ status: 'UPLOADING' });
  });
});
