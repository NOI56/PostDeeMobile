import { randomUUID } from 'node:crypto';

import type { UploadMetadata } from '../storage/videoStorage.js';
import {
  UploadSessionConflictError,
  type UploadSession,
  type UploadSessionStore
} from './uploadSessionStore.js';

export const multipartUploadProtocol = 'multipart-v1' as const;

export type CompletedUploadPart = {
  partNumber: number;
  etag: string;
};

export type ManagedUploadResult = {
  id: string;
  videoS3Key: string;
  fileName: string;
  contentType: string;
  sizeBytes: number;
  uploadProtocol: typeof multipartUploadProtocol;
  partSizeBytes: number;
  partCount: number;
  sessionExpiresAt: string;
};

export type ManagedUploadPartResult = {
  partNumber: number;
  sizeBytes: number;
  uploadUrl: string;
  uploadMethod: 'PUT';
  uploadHeaders: Record<string, string>;
  uploadExpiresAt: string;
};

export type ManagedMultipartStorage = {
  createUpload: (
    metadata: UploadMetadata,
    ownerId: string
  ) => Promise<{
    storageUploadId: string;
    videoS3Key: string;
    createdAt: string;
  }>;
  createPartUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
    partNumber: number;
    sizeBytes: number;
  }) => Promise<{
    uploadUrl: string;
    uploadExpiresAt: string;
    uploadHeaders?: Record<string, string>;
  }>;
  completeUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
    parts: Array<{ partNumber: number; eTag: string }>;
  }) => Promise<void>;
  abortUpload: (input: {
    storageUploadId: string;
    videoS3Key: string;
  }) => Promise<void>;
  getCompletedObjectSize: (videoS3Key: string) => Promise<number | undefined>;
  listUploadsForOwner: (ownerId: string) => Promise<
    Array<{
      storageUploadId: string;
      videoS3Key: string;
      createdAt?: string;
    }>
  >;
};

export type ManagedUploadService = {
  assertOwnerActive: (ownerId: string) => Promise<void>;
  create: (metadata: UploadMetadata, ownerId: string) => Promise<ManagedUploadResult>;
  createPart: (
    id: string,
    ownerId: string,
    partNumber: number
  ) => Promise<ManagedUploadPartResult>;
  complete: (
    id: string,
    ownerId: string,
    parts: CompletedUploadPart[]
  ) => Promise<ManagedUploadResult>;
  get: (id: string, ownerId: string) => Promise<{
    sessionStatus: UploadSession['status'];
    upload: ManagedUploadResult;
  }>;
  abort: (id: string, ownerId: string) => Promise<void>;
  assertReadyForUse: (
    ownerId: string,
    videoS3Key: string,
    options: { allowLegacy: boolean }
  ) => Promise<void>;
  prepareOwnerDeletion: (ownerId: string) => Promise<void>;
  finishOwnerDeletion: (ownerId: string) => Promise<void>;
};

export class ManagedUploadServiceError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string
  ) {
    super(message);
    this.name = 'ManagedUploadServiceError';
  }
}

const toUploadResult = (session: UploadSession): ManagedUploadResult => ({
  id: session.id,
  videoS3Key: session.videoS3Key,
  fileName: session.fileName,
  contentType: session.contentType,
  sizeBytes: session.sizeBytes,
  uploadProtocol: multipartUploadProtocol,
  partSizeBytes: session.partSizeBytes,
  partCount: session.partCount,
  sessionExpiresAt: session.expiresAt
});

const mapStoreError = (error: unknown): never => {
  if (!(error instanceof UploadSessionConflictError)) {
    throw error;
  }

  const statusCode = error.code === 'UPLOAD_SESSION_EXPIRED' ? 410 : 409;
  throw new ManagedUploadServiceError(statusCode, error.code, error.message);
};

const requireSession = async (
  store: UploadSessionStore,
  id: string,
  ownerId: string
) => {
  const session = await store.getForOwner(id, ownerId);

  if (!session) {
    throw new ManagedUploadServiceError(404, 'UPLOAD_SESSION_NOT_FOUND', 'Upload not found.');
  }

  return session;
};

const validateParts = (parts: CompletedUploadPart[], partCount: number) => {
  if (parts.length !== partCount) {
    throw new ManagedUploadServiceError(
      400,
      'UPLOAD_PARTS_INVALID',
      'Every upload part is required before completion.'
    );
  }

  const sorted = [...parts].sort((left, right) => left.partNumber - right.partNumber);

  for (let index = 0; index < sorted.length; index += 1) {
    const part = sorted[index];
    const expectedPartNumber = index + 1;
    const etag = part?.etag.trim() ?? '';

    if (
      part?.partNumber !== expectedPartNumber ||
      etag.length === 0 ||
      etag.length > 256 ||
      /[\r\n]/.test(etag)
    ) {
      throw new ManagedUploadServiceError(
        400,
        'UPLOAD_PARTS_INVALID',
        'Upload parts must be consecutive and include valid ETags.'
      );
    }
  }

  return sorted;
};

export const createManagedUploadService = ({
  storage,
  store,
  partSizeBytes,
  sessionExpiresSeconds,
  now = () => new Date(),
  idFactory = randomUUID,
  completionDrainSeconds = 120
}: {
  storage: ManagedMultipartStorage;
  store: UploadSessionStore;
  partSizeBytes: number;
  sessionExpiresSeconds: number;
  now?: () => Date;
  idFactory?: () => string;
  completionDrainSeconds?: number;
}): ManagedUploadService => {
  const reconcileCompletion = async (session: UploadSession) => {
    if (session.status !== 'COMPLETING') {
      return session;
    }

    const completedObjectSize = await storage.getCompletedObjectSize(
      session.videoS3Key
    );

    if (completedObjectSize !== session.sizeBytes) {
      return session;
    }

    try {
      return await store.markCompleted(session.id, now().toISOString());
    } catch (error) {
      return mapStoreError(error);
    }
  };

  return {
  assertOwnerActive: async (ownerId) => {
    try {
      await store.assertOwnerActive(ownerId);
    } catch (error) {
      return mapStoreError(error);
    }
  },
  create: async (metadata, ownerId) => {
    const storageUpload = await storage.createUpload(metadata, ownerId);
    const currentTime = now();

    try {
      const session = await store.createForActiveOwner({
        id: idFactory(),
        ownerId,
        storageUploadId: storageUpload.storageUploadId,
        videoS3Key: storageUpload.videoS3Key,
        fileName: metadata.fileName,
        contentType: metadata.contentType,
        sizeBytes: metadata.sizeBytes,
        partSizeBytes,
        partCount: Math.ceil(metadata.sizeBytes / partSizeBytes),
        expiresAt: new Date(
          currentTime.getTime() + sessionExpiresSeconds * 1000
        ).toISOString()
      });

      return toUploadResult(session);
    } catch (error) {
      await storage
        .abortUpload({
          storageUploadId: storageUpload.storageUploadId,
          videoS3Key: storageUpload.videoS3Key
        })
        .catch(() => undefined);
      return mapStoreError(error);
    }
  },
  createPart: async (id, ownerId, partNumber) => {
    await requireSession(store, id, ownerId);
    let session: UploadSession;

    try {
      session = await store.getUploadableForOwner({
        id,
        ownerId,
        now: now().toISOString()
      });
    } catch (error) {
      return mapStoreError(error);
    }

    if (!Number.isInteger(partNumber) || partNumber < 1 || partNumber > session.partCount) {
      throw new ManagedUploadServiceError(
        400,
        'UPLOAD_PART_NUMBER_INVALID',
        'Upload part number is outside the session range.'
      );
    }

    const isLastPart = partNumber === session.partCount;
    const sizeBytes = isLastPart
      ? session.sizeBytes - session.partSizeBytes * (session.partCount - 1)
      : session.partSizeBytes;
    const part = await storage.createPartUpload({
      storageUploadId: session.storageUploadId,
      videoS3Key: session.videoS3Key,
      partNumber,
      sizeBytes
    });

    return {
      partNumber,
      sizeBytes,
      uploadUrl: part.uploadUrl,
      uploadMethod: 'PUT',
      uploadHeaders: {
        'Content-Length': String(sizeBytes),
        ...part.uploadHeaders
      },
      uploadExpiresAt: part.uploadExpiresAt
    };
  },
  complete: async (id, ownerId, parts) => {
    const existing = await requireSession(store, id, ownerId);

    if (existing.status === 'COMPLETED') {
      return toUploadResult(existing);
    }

    if (existing.status === 'COMPLETING') {
      const reconciled = await reconcileCompletion(existing);

      if (reconciled.status === 'COMPLETED') {
        return toUploadResult(reconciled);
      }

      throw new ManagedUploadServiceError(
        409,
        'UPLOAD_COMPLETION_IN_PROGRESS',
        'Upload completion is still in progress.'
      );
    }

    const sortedParts = validateParts(parts, existing.partCount);
    let session: UploadSession;

    try {
      session = await store.beginCompletion({
        id,
        ownerId,
        now: now().toISOString()
      });
    } catch (error) {
      return mapStoreError(error);
    }

    await storage.completeUpload({
      storageUploadId: session.storageUploadId,
      videoS3Key: session.videoS3Key,
      parts: sortedParts.map(({ partNumber, etag }) => ({
        partNumber,
        eTag: etag
      }))
    });

    try {
      return toUploadResult(await store.markCompleted(id, now().toISOString()));
    } catch (error) {
      return mapStoreError(error);
    }
  },
  get: async (id, ownerId) => {
    const session = await reconcileCompletion(
      await requireSession(store, id, ownerId)
    );
    return {
      sessionStatus: session.status,
      upload: toUploadResult(session)
    };
  },
  abort: async (id, ownerId) => {
    const existing = await requireSession(store, id, ownerId);

    if (existing.status === 'COMPLETED') {
      throw new ManagedUploadServiceError(
        409,
        'UPLOAD_ALREADY_COMPLETED',
        'Completed uploads cannot be aborted.'
      );
    }

    if (existing.status === 'COMPLETING') {
      throw new ManagedUploadServiceError(
        409,
        'UPLOAD_COMPLETION_IN_PROGRESS',
        'Upload completion is still in progress.'
      );
    }

    let session: UploadSession;

    try {
      session = await store.beginAbort(id, ownerId);
    } catch (error) {
      return mapStoreError(error);
    }

    await storage.abortUpload({
      storageUploadId: session.storageUploadId,
      videoS3Key: session.videoS3Key
    });
  },
  assertReadyForUse: async (ownerId, videoS3Key, { allowLegacy }) => {
    try {
      await store.assertOwnerActive(ownerId);
    } catch (error) {
      return mapStoreError(error);
    }

    const session = await store.findForOwnerKey(ownerId, videoS3Key);

    if (!session) {
      if (allowLegacy) {
        return;
      }

      throw new ManagedUploadServiceError(
        409,
        'UPLOAD_CONFIRMATION_REQUIRED',
        'Upload this file again before creating a post.'
      );
    }

    if (session.status !== 'COMPLETED') {
      throw new ManagedUploadServiceError(
        409,
        'UPLOAD_NOT_READY',
        'Wait for the upload to finish before creating a post.'
      );
    }
  },
  prepareOwnerDeletion: async (ownerId) => {
    await store.beginOwnerDeletion(ownerId);
    const currentTime = now();
    let openSessions = await store.listOpenForOwner(ownerId);

    for (const session of openSessions) {
      if (session.status === 'COMPLETING') {
        await reconcileCompletion(session);
      }
    }

    openSessions = await store.listOpenForOwner(ownerId);
    const freshCompletion = openSessions.find((session) => {
      if (session.status !== 'COMPLETING' || !session.operationStartedAt) {
        return false;
      }

      return (
        currentTime.getTime() - Date.parse(session.operationStartedAt) <
        completionDrainSeconds * 1000
      );
    });

    if (freshCompletion) {
      throw new ManagedUploadServiceError(
        409,
        'ACCOUNT_UPLOADS_DRAINING',
        'An upload is still being finalized. Please retry account deletion shortly.'
      );
    }

    const knownStorageIds = new Set<string>();
    for (const session of openSessions) {
      knownStorageIds.add(session.storageUploadId);
      await storage.abortUpload({
        storageUploadId: session.storageUploadId,
        videoS3Key: session.videoS3Key
      });
      await store.markAborted(session.id);
    }

    for (const upload of await storage.listUploadsForOwner(ownerId)) {
      if (knownStorageIds.has(upload.storageUploadId)) {
        continue;
      }

      await storage.abortUpload({
        storageUploadId: upload.storageUploadId,
        videoS3Key: upload.videoS3Key
      });
    }
  },
  finishOwnerDeletion: (ownerId) => store.finishOwnerDeletion(ownerId)
  };
};
