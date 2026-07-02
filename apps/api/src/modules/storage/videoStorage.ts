import { randomUUID } from 'node:crypto';

import { encodeStorageOwnerId } from './storageKeyPolicy.js';

export type UploadMetadata = {
  fileName: string;
  contentType: string;
  sizeBytes: number;
  width?: number;
  height?: number;
};

export type VideoUpload = UploadMetadata & {
  id: string;
  videoS3Key: string;
  aspectRatio?: string;
  storageProvider: 'mock-s3' | 's3' | 'r2';
  uploadUrl?: string;
  uploadMethod?: 'PUT';
  uploadHeaders?: Record<string, string>;
  uploadExpiresAt?: string;
  createdAt: string;
};

export type VideoDownloadAccess = {
  videoS3Key: string;
  storageProvider: VideoUpload['storageProvider'];
  accessType: 'mock-placeholder' | 'signed-url';
  downloadUrl?: string;
  downloadMethod?: 'GET';
  downloadExpiresAt?: string;
};

export type VideoStorage = {
  createUpload: (metadata: UploadMetadata, ownerId?: string) => Promise<VideoUpload>;
  createDownloadAccess: (videoS3Key: string) => Promise<VideoDownloadAccess>;
  deleteVideo: (videoS3Key: string) => Promise<void>;
};

export type S3VideoStorageClient = {
  createPresignedUploadUrl: (input: {
    bucket: string;
    key: string;
    contentType: string;
    sizeBytes: number;
    expiresInSeconds: number;
  }) => Promise<string>;
  createPresignedDownloadUrl: (input: {
    bucket: string;
    key: string;
    expiresInSeconds: number;
  }) => Promise<string>;
  deleteObject: (input: { bucket: string; key: string }) => Promise<void>;
};

const slugifyFileName = (fileName: string) =>
  fileName
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9.]+/g, '-')
    .replace(/^-+|-+$/g, '');

const createVideoUpload = ({
  metadata,
  ownerId,
  storageProvider
}: {
  metadata: UploadMetadata;
  ownerId?: string;
  storageProvider: VideoUpload['storageProvider'];
}): VideoUpload => {
  const id = randomUUID();
  const safeFileName = slugifyFileName(metadata.fileName) || 'video-upload';
  const isVerticalNineBySixteen = metadata.width === 1080 && metadata.height === 1920;
  const ownerPrefix = ownerId ? `${encodeStorageOwnerId(ownerId)}/` : '';

  return {
    id,
    ...metadata,
    aspectRatio: isVerticalNineBySixteen ? '9:16' : undefined,
    videoS3Key: `uploads/${ownerPrefix}${id}/${safeFileName}`,
    storageProvider,
    createdAt: new Date().toISOString()
  };
};

export const createMockVideoStorage = (): VideoStorage => ({
  createUpload: async (metadata, ownerId) =>
    createVideoUpload({
      metadata,
      ownerId,
      storageProvider: 'mock-s3'
    }),
  createDownloadAccess: async (videoS3Key) => ({
    videoS3Key,
    storageProvider: 'mock-s3',
    accessType: 'mock-placeholder'
  }),
  deleteVideo: async () => undefined
});

// Downloads need to outlive the short upload window: a unified publisher
// (PostPeer) or an AI provider may fetch the media a while after we hand off the
// signed URL, so downloads get at least an hour regardless of the upload expiry.
const minimumDownloadExpiresSeconds = 3600;

const createObjectVideoStorage = ({
  bucket,
  client,
  storageProvider,
  uploadExpiresSeconds
}: {
  bucket: string;
  client: S3VideoStorageClient;
  storageProvider: Extract<VideoUpload['storageProvider'], 's3' | 'r2'>;
  uploadExpiresSeconds: number;
}): VideoStorage => ({
  createUpload: async (metadata, ownerId) => {
    const upload = createVideoUpload({
      metadata,
      ownerId,
      storageProvider
    });
    const uploadUrl = await client.createPresignedUploadUrl({
      bucket,
      key: upload.videoS3Key,
      contentType: metadata.contentType,
      sizeBytes: metadata.sizeBytes,
      expiresInSeconds: uploadExpiresSeconds
    });

    return {
      ...upload,
      uploadUrl,
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Type': metadata.contentType
      },
      uploadExpiresAt: new Date(Date.now() + uploadExpiresSeconds * 1000).toISOString()
    };
  },
  createDownloadAccess: async (videoS3Key) => {
    const downloadExpiresSeconds = Math.max(
      uploadExpiresSeconds,
      minimumDownloadExpiresSeconds
    );
    const downloadUrl = await client.createPresignedDownloadUrl({
      bucket,
      key: videoS3Key,
      expiresInSeconds: downloadExpiresSeconds
    });

    return {
      videoS3Key,
      storageProvider,
      accessType: 'signed-url',
      downloadUrl,
      downloadMethod: 'GET',
      downloadExpiresAt: new Date(
        Date.now() + downloadExpiresSeconds * 1000
      ).toISOString()
    };
  },
  deleteVideo: async (videoS3Key) => {
    await client.deleteObject({
      bucket,
      key: videoS3Key
    });
  }
});

export const createS3VideoStorage = ({
  bucket,
  client,
  uploadExpiresSeconds
}: {
  bucket: string;
  client: S3VideoStorageClient;
  uploadExpiresSeconds: number;
}): VideoStorage =>
  createObjectVideoStorage({
    bucket,
    client,
    storageProvider: 's3',
    uploadExpiresSeconds
  });

export const createR2VideoStorage = ({
  bucket,
  client,
  uploadExpiresSeconds
}: {
  bucket: string;
  client: S3VideoStorageClient;
  uploadExpiresSeconds: number;
}): VideoStorage =>
  createObjectVideoStorage({
    bucket,
    client,
    storageProvider: 'r2',
    uploadExpiresSeconds
  });
