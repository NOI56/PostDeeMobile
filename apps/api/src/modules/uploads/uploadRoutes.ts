import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { VideoStorage } from '../storage/videoStorage.js';
import { readUploadMetadata } from './uploadService.js';

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
  storage: VideoStorage
) => {
  router.post('/uploads', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const result = readUploadMetadata(request.body);

    if (!result.ok) {
      response.status(400).json({
        status: 'error',
        message: result.message
      });
      return;
    }

    const upload = await storage.createUpload(result.metadata, authUser.id);

    response.status(201).json({
      status: 'ok',
      upload: toPublicUpload(upload)
    });
  });
};
