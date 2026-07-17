import type { RequestHandler, Router } from 'express';

import type { UploadProtocolMode } from '../../config/env.js';
import { readAuthUser } from '../auth/authTypes.js';
import type { VideoStorage } from '../storage/videoStorage.js';
import {
  ManagedUploadServiceError,
  multipartUploadProtocol,
  type CompletedUploadPart,
  type ManagedUploadService
} from './managedUploadService.js';
import { readUploadMetadata } from './uploadService.js';

type UploadRouteOptions = {
  uploadMaxSizeBytes: number;
  uploadProtocolMode?: UploadProtocolMode;
  managedUploadService?: ManagedUploadService;
};

type PublicUpload = Omit<Awaited<ReturnType<VideoStorage['createUpload']>>, 'storageProvider'> & {
  storageProvider: 'private';
};

const toPublicUpload = (
  upload: Awaited<ReturnType<VideoStorage['createUpload']>>
): PublicUpload => {
  const { storageProvider: _storageProvider, ...publicUpload } = upload;

  return {
    ...publicUpload,
    storageProvider: 'private'
  };
};

export const registerUploadRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  storage: VideoStorage,
  options: UploadRouteOptions
) => {
  const uploadProtocolMode = options.uploadProtocolMode ?? 'legacy';
  const managedUploadService = options.managedUploadService;
  const readPathParameter = (value: string | string[]) =>
    Array.isArray(value) ? (value[0] ?? '') : value;

  const sendManagedUploadError = (response: Parameters<RequestHandler>[1], error: unknown) => {
    if (!(error instanceof ManagedUploadServiceError)) {
      throw error;
    }

    response.status(error.statusCode).json({
      status: 'error',
      code: error.code,
      message: error.message
    });
  };

  const requireManagedUploadService = () => {
    if (!managedUploadService) {
      throw new ManagedUploadServiceError(
        503,
        'MULTIPART_UPLOAD_UNAVAILABLE',
        'Managed uploads are temporarily unavailable.'
      );
    }

    return managedUploadService;
  };

  router.post('/uploads', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (managedUploadService) {
      try {
        await managedUploadService.assertOwnerActive(authUser.id);
      } catch (error) {
        sendManagedUploadError(response, error);
        return;
      }
    }

    const payload =
      request.body && typeof request.body === 'object'
        ? (request.body as Record<string, unknown>)
        : {};
    const requestedProtocol = payload.uploadProtocol;

    if (
      requestedProtocol !== undefined &&
      requestedProtocol !== multipartUploadProtocol
    ) {
      response.status(400).json({
        status: 'error',
        code: 'UPLOAD_PROTOCOL_INVALID',
        message: `uploadProtocol must be ${multipartUploadProtocol}`
      });
      return;
    }

    if (uploadProtocolMode === 'multipart' && requestedProtocol !== multipartUploadProtocol) {
      response.status(426).json({
        status: 'error',
        code: 'UPLOAD_CLIENT_UPGRADE_REQUIRED',
        message: 'Update PostDee before uploading another file.'
      });
      return;
    }

    const result = readUploadMetadata(payload, {
      maxSizeBytes: options.uploadMaxSizeBytes
    });

    if (!result.ok) {
      response.status(400).json({
        status: 'error',
        ...('code' in result ? { code: result.code } : {}),
        message: result.message
      });
      return;
    }

    const shouldUseMultipart =
      requestedProtocol === multipartUploadProtocol && uploadProtocolMode !== 'legacy';

    if (shouldUseMultipart) {
      try {
        const upload = await requireManagedUploadService().create(
          result.metadata,
          authUser.id
        );
        response.status(201).json({
          status: 'ok',
          upload: {
            ...upload,
            storageProvider: 'private'
          }
        });
      } catch (error) {
        sendManagedUploadError(response, error);
      }
      return;
    }

    const upload = await storage.createUpload(result.metadata, authUser.id);

    response.status(201).json({
      status: 'ok',
      upload: toPublicUpload(upload)
    });
  });

  router.post(
    '/uploads/:uploadId/parts/:partNumber',
    authMiddleware,
    async (request, response) => {
      const authUser = readAuthUser(response.locals);

      if (!authUser) {
        response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
        return;
      }

      try {
        const part = await requireManagedUploadService().createPart(
          readPathParameter(request.params.uploadId),
          authUser.id,
          Number(readPathParameter(request.params.partNumber))
        );
        response.json({ status: 'ok', part });
      } catch (error) {
        sendManagedUploadError(response, error);
      }
    }
  );

  router.post('/uploads/:uploadId/complete', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    const payload =
      request.body && typeof request.body === 'object'
        ? (request.body as Record<string, unknown>)
        : {};
    const rawParts = payload.parts;

    if (!Array.isArray(rawParts)) {
      response.status(400).json({
        status: 'error',
        code: 'UPLOAD_PARTS_INVALID',
        message: 'parts must be an array'
      });
      return;
    }

    const parts: CompletedUploadPart[] = [];
    for (const rawPart of rawParts) {
      if (!rawPart || typeof rawPart !== 'object') {
        response.status(400).json({
          status: 'error',
          code: 'UPLOAD_PARTS_INVALID',
          message: 'Every part must include partNumber and etag.'
        });
        return;
      }

      const part = rawPart as Record<string, unknown>;
      if (!Number.isInteger(part.partNumber) || typeof part.etag !== 'string') {
        response.status(400).json({
          status: 'error',
          code: 'UPLOAD_PARTS_INVALID',
          message: 'Every part must include partNumber and etag.'
        });
        return;
      }

      parts.push({
        partNumber: part.partNumber as number,
        etag: part.etag
      });
    }

    try {
      const upload = await requireManagedUploadService().complete(
        readPathParameter(request.params.uploadId),
        authUser.id,
        parts
      );
      response.json({
        status: 'ok',
        upload: {
          ...upload,
          storageProvider: 'private'
        }
      });
    } catch (error) {
      sendManagedUploadError(response, error);
    }
  });

  router.get('/uploads/:uploadId', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    try {
      const result = await requireManagedUploadService().get(
        readPathParameter(request.params.uploadId),
        authUser.id
      );
      response.json({
        status: 'ok',
        sessionStatus: result.sessionStatus,
        upload: {
          ...result.upload,
          storageProvider: 'private'
        }
      });
    } catch (error) {
      sendManagedUploadError(response, error);
    }
  });

  router.delete('/uploads/:uploadId', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }

    try {
      await requireManagedUploadService().abort(
        readPathParameter(request.params.uploadId),
        authUser.id
      );
      response.json({ status: 'ok' });
    } catch (error) {
      sendManagedUploadError(response, error);
    }
  });
};
