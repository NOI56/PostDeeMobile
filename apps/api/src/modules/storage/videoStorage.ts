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

export type MultipartVideoUpload = {
  storageUploadId: string;
  videoS3Key: string;
  createdAt: string;
};

export type MultipartUploadPart = {
  partNumber: number;
  eTag: string;
};

export type MultipartVideoStorage = {
  createUpload: (
    metadata: UploadMetadata,
    ownerId: string
  ) => Promise<MultipartVideoUpload>;
  createPartUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
    partNumber: number;
    sizeBytes: number;
  }) => Promise<{
    uploadUrl: string;
    uploadExpiresAt: string;
    uploadHeaders: Record<string, string>;
  }>;
  completeUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
    parts: MultipartUploadPart[];
  }) => Promise<void>;
  abortUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
  }) => Promise<void>;
  getCompletedObjectSize: (videoS3Key: string) => Promise<number | undefined>;
  listUploadsForOwner: (ownerId: string) => Promise<MultipartVideoUpload[]>;
};

export type VideoStorage = {
  supportsOwnerCleanup?: boolean;
  multipart?: MultipartVideoStorage;
  createUpload: (metadata: UploadMetadata, ownerId?: string) => Promise<VideoUpload>;
  createDownloadAccess: (videoS3Key: string) => Promise<VideoDownloadAccess>;
  deleteVideo: (videoS3Key: string) => Promise<void>;
  deleteAllVideosForOwner: (ownerId: string) => Promise<void>;
};

export type S3MultipartVideoStorageClient = {
  createUpload: (input: {
    bucket: string;
    key: string;
    contentType: string;
  }) => Promise<{ storageUploadId: string }>;
  createPartUpload: (input: {
    bucket: string;
    key: string;
    storageUploadId: string;
    partNumber: number;
    sizeBytes: number;
    expiresInSeconds: number;
  }) => Promise<string>;
  completeUpload: (input: {
    bucket: string;
    key: string;
    storageUploadId: string;
    parts: MultipartUploadPart[];
  }) => Promise<void>;
  abortUpload: (input: {
    bucket: string;
    key: string;
    storageUploadId: string;
  }) => Promise<void>;
  getObjectSize: (input: {
    bucket: string;
    key: string;
  }) => Promise<number | undefined>;
  listUploadsByPrefix: (input: {
    bucket: string;
    prefix: string;
  }) => Promise<MultipartVideoUpload[]>;
};

export type S3VideoStorageClient = {
  multipart?: S3MultipartVideoStorageClient;
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
  listObjectKeysByPrefix?: (input: {
    bucket: string;
    prefix: string;
  }) => Promise<string[]>;
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
  supportsOwnerCleanup: true,
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
  deleteVideo: async () => undefined,
  deleteAllVideosForOwner: async () => undefined
});

// Downloads need to outlive the short upload window: a unified publisher
// (PostPeer) or an AI provider may fetch the media a while after we hand off the
// signed URL, so downloads get at least an hour regardless of the upload expiry.
const minimumDownloadExpiresSeconds = 3600;

const createMultipartVideoStorage = ({
  bucket,
  client,
  storageProvider,
  uploadExpiresSeconds
}: {
  bucket: string;
  client: S3MultipartVideoStorageClient;
  storageProvider: Extract<VideoUpload['storageProvider'], 's3' | 'r2'>;
  uploadExpiresSeconds: number;
}): MultipartVideoStorage => ({
  createUpload: async (metadata, ownerId) => {
    const upload = createVideoUpload({
      metadata,
      ownerId,
      storageProvider
    });
    const { storageUploadId } = await client.createUpload({
      bucket,
      key: upload.videoS3Key,
      contentType: metadata.contentType
    });

    return {
      storageUploadId,
      videoS3Key: upload.videoS3Key,
      createdAt: upload.createdAt
    };
  },
  createPartUpload: async ({
    storageUploadId,
    videoS3Key,
    partNumber,
    sizeBytes
  }) => {
    const uploadUrl = await client.createPartUpload({
      bucket,
      key: videoS3Key,
      storageUploadId,
      partNumber,
      sizeBytes,
      expiresInSeconds: uploadExpiresSeconds
    });

    return {
      uploadUrl,
      uploadExpiresAt: new Date(
        Date.now() + uploadExpiresSeconds * 1000
      ).toISOString(),
      uploadHeaders: {
        'Content-Length': String(sizeBytes)
      }
    };
  },
  completeUpload: async ({ storageUploadId, videoS3Key, parts }) => {
    await client.completeUpload({
      bucket,
      key: videoS3Key,
      storageUploadId,
      parts
    });
  },
  abortUpload: async ({ storageUploadId, videoS3Key }) => {
    await client.abortUpload({
      bucket,
      key: videoS3Key,
      storageUploadId
    });
  },
  getCompletedObjectSize: async (videoS3Key) =>
    client.getObjectSize({
      bucket,
      key: videoS3Key
    }),
  listUploadsForOwner: async (ownerId) =>
    client.listUploadsByPrefix({
      bucket,
      prefix: `uploads/${encodeStorageOwnerId(ownerId)}/`
    })
});

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
  supportsOwnerCleanup: Boolean(client.listObjectKeysByPrefix),
  multipart: client.multipart
    ? createMultipartVideoStorage({
        bucket,
        client: client.multipart,
        storageProvider,
        uploadExpiresSeconds
      })
    : undefined,
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
  },
  deleteAllVideosForOwner: async (ownerId) => {
    if (!client.listObjectKeysByPrefix) {
      throw new Error('Configured object storage does not support owner cleanup');
    }

    const prefix = `uploads/${encodeStorageOwnerId(ownerId)}/`;
    const keys = await client.listObjectKeysByPrefix({ bucket, prefix });
    const failures: unknown[] = [];

    for (const key of new Set(keys)) {
      try {
        await client.deleteObject({ bucket, key });
      } catch (error) {
        failures.push(error);
      }
    }

    if (failures.length > 0) {
      throw new AggregateError(
        failures,
        `Could not delete ${failures.length} account media object${
          failures.length === 1 ? '' : 's'
        }`
      );
    }
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
