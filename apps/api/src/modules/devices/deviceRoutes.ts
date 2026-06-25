import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { DevicePlatform, DeviceTokenStore } from './deviceTokenStore.js';

const readPlatform = (value: unknown): DevicePlatform | undefined =>
  value === 'IOS' || value === 'ANDROID' || value === 'WEB' ? value : undefined;

/**
 * Registers `POST /devices`, which stores the caller's FCM device token so a
 * (future) backend sender can target the user's devices with push
 * notifications. The mobile app calls this with the token from the FCM gateway.
 */
export const registerDeviceRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  deviceTokenStore: DeviceTokenStore
) => {
  router.post('/devices', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const token =
      typeof request.body?.token === 'string' ? request.body.token.trim() : '';

    if (!token) {
      response.status(400).json({
        status: 'error',
        message: 'token is required'
      });
      return;
    }

    await deviceTokenStore.register({
      userId: authUser.id,
      token,
      platform: readPlatform(request.body?.platform)
    });

    response.json({ status: 'ok' });
  });
};
