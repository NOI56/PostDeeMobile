import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import {
  ManagedUploadServiceError,
  type ManagedUploadService
} from './managedUploadService.js';

describe('upload routes', () => {
  const managedUpload = {
    id: 'managed-session-1',
    videoS3Key: 'uploads/seller-upload/managed/video.mp4',
    fileName: 'video.mp4',
    contentType: 'video/mp4',
    sizeBytes: 17,
    uploadProtocol: 'multipart-v1' as const,
    partSizeBytes: 8,
    partCount: 3,
    sessionExpiresAt: '2026-07-13T11:00:00.000Z'
  };

  const createManagedUploadService = (): ManagedUploadService => ({
    assertOwnerActive: vi.fn(async () => undefined),
    create: vi.fn(async () => managedUpload),
    createPart: vi.fn(async (_id, _ownerId, partNumber) => ({
      partNumber,
      sizeBytes: partNumber === 3 ? 1 : 8,
      uploadUrl: `https://r2.test/part-${partNumber}`,
      uploadMethod: 'PUT',
      uploadHeaders: { 'Content-Length': partNumber === 3 ? '1' : '8' },
      uploadExpiresAt: '2026-07-13T10:05:00.000Z'
    })),
    complete: vi.fn(async () => managedUpload),
    get: vi.fn(async () => ({
      sessionStatus: 'COMPLETED',
      upload: managedUpload
    })),
    abort: vi.fn(async () => undefined),
    assertReadyForUse: vi.fn(async () => undefined),
    prepareOwnerDeletion: vi.fn(async () => undefined),
    finishOwnerDeletion: vi.fn(async () => undefined)
  });

  it('requires authentication before creating upload URLs in Firebase mode', async () => {
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-test'
      }),
      firebaseVerifier: {
        verifyIdToken: async () => ({ id: 'seller-firebase', provider: 'firebase' })
      }
    });

    await request(app)
      .post('/uploads')
      .send({
        fileName: 'unauthenticated.mp4',
        contentType: 'video/mp4',
        sizeBytes: 1000
      })
      .expect(401);
  });

  it('creates a mock video upload record from metadata', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .set('x-postdee-user-id', 'seller-upload')
      .send({
        fileName: 'demo reel.mp4',
        contentType: 'video/mp4',
        sizeBytes: 12_345_678,
        width: 1080,
        height: 1920
      })
      .expect(201);

    expect(response.body).toMatchObject({
      status: 'ok',
      upload: {
        fileName: 'demo reel.mp4',
        contentType: 'video/mp4',
        sizeBytes: 12_345_678,
        width: 1080,
        height: 1920,
        aspectRatio: '9:16'
      }
    });
    expect(response.body.upload.storageProvider).toBe('private');
    expect(response.body.upload.id).toEqual(expect.any(String));
    expect(response.body.upload.videoS3Key).toMatch(
      /^uploads\/seller-upload\/.+\/demo-reel\.mp4$/
    );
  });

  it('creates an S3 upload record when S3 storage is configured', async () => {
    const app = createApp({
      config: readServerConfig({
        VIDEO_STORAGE: 's3',
        AWS_S3_BUCKET: 'postdee-video-temp',
        AWS_S3_UPLOAD_EXPIRES_SECONDS: '1200'
      }),
      s3Client: {
        createPresignedUploadUrl: async () => 'https://s3.local/upload-url',
        deleteObject: async () => undefined
      }
    });

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 's3 reel.mp4',
        contentType: 'video/mp4',
        sizeBytes: 12_345_678
      })
      .expect(201);

    expect(response.body.upload).toMatchObject({
      fileName: 's3 reel.mp4',
      uploadUrl: 'https://s3.local/upload-url',
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': 'video/mp4'
      },
      uploadExpiresAt: expect.any(String)
    });
    expect(response.body.upload.storageProvider).toBe('private');
    expect(response.body.upload.videoS3Key).toMatch(
      /^uploads\/local-dev-user\/.+\/s3-reel\.mp4$/
    );
  });

  it('accepts an image upload (used for AI caption frames)', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 'frame.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1000
      })
      .expect(201);

    expect(response.body.status).toBe('ok');
    expect(response.body.upload.contentType).toBe('image/jpeg');
  });

  it('keeps the legacy response unchanged while dual mode is enabled', async () => {
    const managedUploadService = createManagedUploadService();
    const app = createApp({
      config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'dual' }),
      managedUploadService
    });

    const response = await request(app)
      .post('/uploads')
      .send({ fileName: 'legacy.mp4', contentType: 'video/mp4', sizeBytes: 10 })
      .expect(201);

    expect(response.body.upload.uploadProtocol).toBeUndefined();
    expect(managedUploadService.create).not.toHaveBeenCalled();
  });

  it('blocks legacy upload creation after account deletion starts', async () => {
    const managedUploadService = createManagedUploadService();
    vi.mocked(managedUploadService.assertOwnerActive).mockRejectedValue(
      new ManagedUploadServiceError(
        409,
        'ACCOUNT_DELETION_IN_PROGRESS',
        'Account deletion is in progress.'
      )
    );
    const app = createApp({
      config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'dual' }),
      managedUploadService
    });

    await request(app)
      .post('/uploads')
      .set('x-postdee-user-id', 'seller-deleting')
      .send({ fileName: 'late.mp4', contentType: 'video/mp4', sizeBytes: 10 })
      .expect(409)
      .expect(({ body }) => {
        expect(body.code).toBe('ACCOUNT_DELETION_IN_PROGRESS');
      });

    expect(managedUploadService.create).not.toHaveBeenCalled();
  });

  it('fails startup when managed mode has no multipart-capable storage', () => {
    expect(() =>
      createApp({
        config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'dual' })
      })
    ).toThrow('UPLOAD_PROTOCOL_MODE requires multipart-capable object storage');
  });

  it('creates and completes an owner-scoped multipart upload when explicitly requested', async () => {
    const managedUploadService = createManagedUploadService();
    const app = createApp({
      config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'dual' }),
      managedUploadService
    });

    const created = await request(app)
      .post('/uploads')
      .set('x-postdee-user-id', 'seller-upload')
      .send({
        fileName: 'video.mp4',
        contentType: 'video/mp4',
        sizeBytes: 17,
        uploadProtocol: 'multipart-v1'
      })
      .expect(201);
    expect(created.body.upload).toMatchObject({
      id: 'managed-session-1',
      storageProvider: 'private',
      uploadProtocol: 'multipart-v1',
      partCount: 3
    });
    expect(created.body.upload.storageUploadId).toBeUndefined();

    const part = await request(app)
      .post('/uploads/managed-session-1/parts/3')
      .set('x-postdee-user-id', 'seller-upload')
      .send({})
      .expect(200);
    expect(part.body.part).toMatchObject({
      partNumber: 3,
      sizeBytes: 1,
      uploadMethod: 'PUT'
    });

    await request(app)
      .post('/uploads/managed-session-1/complete')
      .set('x-postdee-user-id', 'seller-upload')
      .send({
        parts: [
          { partNumber: 1, etag: 'etag-1' },
          { partNumber: 2, etag: 'etag-2' },
          { partNumber: 3, etag: 'etag-3' }
        ]
      })
      .expect(200)
      .expect(({ body }) => {
        expect(body.upload.storageProvider).toBe('private');
      });

    await request(app)
      .get('/uploads/managed-session-1')
      .set('x-postdee-user-id', 'seller-upload')
      .expect(200)
      .expect(({ body }) => {
        expect(body.sessionStatus).toBe('COMPLETED');
      });

    await request(app)
      .delete('/uploads/managed-session-1')
      .set('x-postdee-user-id', 'seller-upload')
      .expect(200, { status: 'ok' });

    expect(managedUploadService.createPart).toHaveBeenCalledWith(
      'managed-session-1',
      'seller-upload',
      3
    );
    expect(managedUploadService.complete).toHaveBeenCalledWith(
      'managed-session-1',
      'seller-upload',
      expect.any(Array)
    );
  });

  it('requires a current client after strict multipart mode is enabled', async () => {
    const app = createApp({
      config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'multipart' }),
      managedUploadService: createManagedUploadService()
    });

    await request(app)
      .post('/uploads')
      .send({ fileName: 'old-client.mp4', contentType: 'video/mp4', sizeBytes: 10 })
      .expect(426)
      .expect(({ body }) => {
        expect(body.code).toBe('UPLOAD_CLIENT_UPGRADE_REQUIRED');
      });
  });

  it('falls back to legacy PUT when a new client reaches a legacy server', async () => {
    const managedUploadService = createManagedUploadService();
    const app = createApp({ managedUploadService });

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 'fallback.mp4',
        contentType: 'video/mp4',
        sizeBytes: 10,
        uploadProtocol: 'multipart-v1'
      })
      .expect(201);

    expect(response.body.upload.uploadProtocol).toBeUndefined();
    expect(managedUploadService.create).not.toHaveBeenCalled();
  });

  it('rejects upload metadata larger than the configured upload limit', async () => {
    const app = createApp({
      config: readServerConfig({
        UPLOAD_MAX_SIZE_BYTES: '1000'
      })
    });

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 'too large.mp4',
        contentType: 'video/mp4',
        sizeBytes: 1001
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'File is larger than the configured upload limit of 1000 bytes.'
    });
  });

  it('rejects upload metadata with an unsupported content type', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 'notes.pdf',
        contentType: 'application/pdf',
        sizeBytes: 1000
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'fileName, a video or image contentType, and positive sizeBytes are required'
    });
  });

  it('rejects video metadata that is not vertical 9:16', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .send({
        fileName: 'landscape reel.mp4',
        contentType: 'video/mp4',
        sizeBytes: 12_345_678,
        width: 1920,
        height: 1080
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'Use a vertical 9:16 video, such as 1080x1920.'
    });
  });
});
