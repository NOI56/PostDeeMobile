import { describe, expect, it, vi } from 'vitest';

import { createVideoStorageFromConfig } from './videoStorageFactory.js';

describe('createVideoStorageFromConfig', () => {
  it('uses mock video storage by default', async () => {
    const storage = createVideoStorageFromConfig({
      config: {
        videoStorage: 'mock',
        awsS3Bucket: undefined,
        awsS3UploadExpiresSeconds: 900
      }
    });

    const upload = await storage.createUpload({
      fileName: 'demo reel.mp4',
      contentType: 'video/mp4',
      sizeBytes: 12_345_678,
      width: 1080,
      height: 1920
    });
    const downloadAccess = await storage.createDownloadAccess(upload.videoS3Key);

    expect(upload).toMatchObject({
      fileName: 'demo reel.mp4',
      contentType: 'video/mp4',
      sizeBytes: 12_345_678,
      width: 1080,
      height: 1920,
      aspectRatio: '9:16',
      storageProvider: 'mock-s3'
    });
    expect(upload.videoS3Key).toMatch(/^uploads\/.+\/demo-reel\.mp4$/);
    expect(downloadAccess).toEqual({
      videoS3Key: upload.videoS3Key,
      storageProvider: 'mock-s3',
      accessType: 'mock-placeholder'
    });
  });

  it('scopes new upload keys to the authenticated owner when provided', async () => {
    const storage = createVideoStorageFromConfig({
      config: {
        videoStorage: 'mock',
        awsS3Bucket: undefined,
        awsS3UploadExpiresSeconds: 900
      }
    });

    const upload = await storage.createUpload(
      {
        fileName: 'seller clip.mp4',
        contentType: 'video/mp4',
        sizeBytes: 12_345
      },
      'seller-a'
    );

    expect(upload.videoS3Key).toMatch(/^uploads\/seller-a\/.+\/seller-clip\.mp4$/);
  });

  it('uses S3 video storage when configured with a client and bucket', async () => {
    const s3Client = {
      createPresignedUploadUrl: vi.fn(async () => 'https://s3.local/upload-url'),
      createPresignedDownloadUrl: vi.fn(async () => 'https://s3.local/download-url'),
      deleteObject: vi.fn(async () => undefined)
    };
    const storage = createVideoStorageFromConfig({
      config: {
        videoStorage: 's3',
        awsS3Bucket: 'postdee-video-temp',
        awsS3UploadExpiresSeconds: 1200
      },
      s3Client
    });

    const upload = await storage.createUpload({
      fileName: 'launch video.mp4',
      contentType: 'video/mp4',
      sizeBytes: 8_000_000
    });
    const downloadAccess = await storage.createDownloadAccess(upload.videoS3Key);
    await storage.deleteVideo(upload.videoS3Key);

    expect(upload).toMatchObject({
      fileName: 'launch video.mp4',
      storageProvider: 's3',
      uploadUrl: 'https://s3.local/upload-url',
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': 'video/mp4'
      },
      uploadExpiresAt: expect.any(String)
    });
    expect(upload.videoS3Key).toMatch(/^uploads\/.+\/launch-video\.mp4$/);
    expect(s3Client.createPresignedUploadUrl).toHaveBeenCalledWith({
      bucket: 'postdee-video-temp',
      key: upload.videoS3Key,
      contentType: 'video/mp4',
      sizeBytes: 8_000_000,
      expiresInSeconds: 1200
    });
    expect(downloadAccess).toMatchObject({
      videoS3Key: upload.videoS3Key,
      storageProvider: 's3',
      accessType: 'signed-url',
      downloadUrl: 'https://s3.local/download-url',
      downloadMethod: 'GET',
      downloadExpiresAt: expect.any(String)
    });
    expect(s3Client.createPresignedDownloadUrl).toHaveBeenCalledWith({
      bucket: 'postdee-video-temp',
      key: upload.videoS3Key,
      // Downloads use at least a 1h window even though uploads expire in 1200s.
      expiresInSeconds: 3600
    });
    expect(s3Client.deleteObject).toHaveBeenCalledWith({
      bucket: 'postdee-video-temp',
      key: upload.videoS3Key
    });
  });

  it('uses R2 video storage when configured with a client and bucket', async () => {
    const r2Client = {
      createPresignedUploadUrl: vi.fn(async () => 'https://r2.local/upload-url'),
      createPresignedDownloadUrl: vi.fn(async () => 'https://r2.local/download-url'),
      deleteObject: vi.fn(async () => undefined)
    };
    const storage = createVideoStorageFromConfig({
      config: {
        videoStorage: 'r2',
        awsS3Bucket: undefined,
        awsS3UploadExpiresSeconds: 900,
        cloudflareR2Bucket: 'postdee-r2-temp',
        cloudflareR2AccountId: undefined,
        cloudflareR2AccessKeyId: undefined,
        cloudflareR2SecretAccessKey: undefined,
        cloudflareR2Endpoint: undefined,
        cloudflareR2UploadExpiresSeconds: 1500
      },
      r2Client
    });

    const upload = await storage.createUpload({
      fileName: 'r2 launch video.mp4',
      contentType: 'video/mp4',
      sizeBytes: 8_000_000
    });
    const downloadAccess = await storage.createDownloadAccess(upload.videoS3Key);
    await storage.deleteVideo(upload.videoS3Key);

    expect(upload).toMatchObject({
      fileName: 'r2 launch video.mp4',
      storageProvider: 'r2',
      uploadUrl: 'https://r2.local/upload-url',
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': 'video/mp4'
      },
      uploadExpiresAt: expect.any(String)
    });
    expect(upload.videoS3Key).toMatch(/^uploads\/.+\/r2-launch-video\.mp4$/);
    expect(r2Client.createPresignedUploadUrl).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: upload.videoS3Key,
      contentType: 'video/mp4',
      sizeBytes: 8_000_000,
      expiresInSeconds: 1500
    });
    expect(downloadAccess).toMatchObject({
      videoS3Key: upload.videoS3Key,
      storageProvider: 'r2',
      accessType: 'signed-url',
      downloadUrl: 'https://r2.local/download-url',
      downloadMethod: 'GET',
      downloadExpiresAt: expect.any(String)
    });
    expect(r2Client.createPresignedDownloadUrl).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: upload.videoS3Key,
      // Downloads use at least a 1h window even though uploads expire in 1500s.
      expiresInSeconds: 3600
    });
    expect(r2Client.deleteObject).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: upload.videoS3Key
    });
  });

  it('requires an R2 bucket when R2 storage is configured', () => {
    expect(() =>
      createVideoStorageFromConfig({
        config: {
          videoStorage: 'r2',
          awsS3Bucket: undefined,
          awsS3UploadExpiresSeconds: 900,
          cloudflareR2Bucket: undefined,
          cloudflareR2AccountId: undefined,
          cloudflareR2AccessKeyId: undefined,
          cloudflareR2SecretAccessKey: undefined,
          cloudflareR2Endpoint: undefined,
          cloudflareR2UploadExpiresSeconds: 900
        },
        r2Client: {
          createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
          createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
          deleteObject: async () => undefined
        }
      })
    ).toThrow('CLOUDFLARE_R2_BUCKET is required when VIDEO_STORAGE is r2');
  });

  it('creates an R2 S3-compatible client from configured credentials', async () => {
    const storage = createVideoStorageFromConfig({
      config: {
        videoStorage: 'r2',
        awsS3Bucket: undefined,
        awsS3UploadExpiresSeconds: 900,
        cloudflareR2Bucket: 'postdee-r2-temp',
        cloudflareR2AccountId: 'cloudflare-account-id',
        cloudflareR2AccessKeyId: 'cloudflare-access-key',
        cloudflareR2SecretAccessKey: 'cloudflare-secret-key',
        cloudflareR2Endpoint: undefined,
        cloudflareR2UploadExpiresSeconds: 1500
      }
    });

    const upload = await storage.createUpload({
      fileName: 'r2 configured video.mp4',
      contentType: 'video/mp4',
      sizeBytes: 8_000_000
    });

    expect(upload).toMatchObject({
      fileName: 'r2 configured video.mp4',
      storageProvider: 'r2',
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': 'video/mp4'
      }
    });
    expect(upload.uploadUrl).toContain('r2.cloudflarestorage.com');
    expect(upload.uploadUrl).toContain('X-Amz-Signature=');
    const signedUrl = new URL(upload.uploadUrl ?? '');
    expect(signedUrl.searchParams.get('X-Amz-SignedHeaders')).toContain('content-length');
    expect(signedUrl.searchParams.get('X-Amz-SignedHeaders')).toContain('content-type');
  });

  it('requires R2 credentials when R2 storage is configured without an injected client', () => {
    expect(() =>
      createVideoStorageFromConfig({
        config: {
          videoStorage: 'r2',
          awsS3Bucket: undefined,
          awsS3UploadExpiresSeconds: 900,
          cloudflareR2Bucket: 'postdee-r2-temp',
          cloudflareR2AccountId: undefined,
          cloudflareR2AccessKeyId: undefined,
          cloudflareR2SecretAccessKey: undefined,
          cloudflareR2Endpoint: undefined,
          cloudflareR2UploadExpiresSeconds: 900
        }
      })
    ).toThrow(
      'CLOUDFLARE_R2_ACCOUNT_ID, CLOUDFLARE_R2_ACCESS_KEY_ID, and CLOUDFLARE_R2_SECRET_ACCESS_KEY are required when VIDEO_STORAGE is r2'
    );
  });

  it('requires an S3 bucket when S3 storage is configured', () => {
    expect(() =>
      createVideoStorageFromConfig({
      config: {
        videoStorage: 's3',
        awsS3Bucket: undefined,
        awsS3UploadExpiresSeconds: 900
      },
      s3Client: {
        createPresignedUploadUrl: async () => 'https://s3.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://s3.local/download-url',
        deleteObject: async () => undefined
      }
      })
    ).toThrow('AWS_S3_BUCKET is required when VIDEO_STORAGE is s3');
  });
});
