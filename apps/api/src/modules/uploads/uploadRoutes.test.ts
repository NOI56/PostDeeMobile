import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

describe('upload routes', () => {
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
        aspectRatio: '9:16',
        storageProvider: 'mock-s3'
      }
    });
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
      storageProvider: 's3',
      uploadUrl: 'https://s3.local/upload-url',
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': 'video/mp4'
      },
      uploadExpiresAt: expect.any(String)
    });
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
