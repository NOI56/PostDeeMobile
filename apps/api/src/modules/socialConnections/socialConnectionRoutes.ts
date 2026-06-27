import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';
import {
  isSocialConnectionPlatform,
  type SocialConnectionStore
} from './socialConnectionStore.js';

export type SocialConnectionRouteDependencies = {
  store: SocialConnectionStore;
  connectClient: PostPeerConnectClient;
};

const sendUnauthorized = (response: Response) => {
  response.status(401).json({
    status: 'error',
    message: 'Authenticated user is required'
  });
};

const sendUnsupportedPlatform = (response: Response) => {
  response.status(400).json({
    status: 'error',
    message: 'Unsupported social connection platform'
  });
};

// Maps PostPeer connect failures to API responses. Returns true when handled.
const sendConnectError = (response: Response, error: unknown): boolean => {
  if (error instanceof PostPeerConnectUnavailableError) {
    response.status(503).json({ status: 'error', message: error.message });
    return true;
  }

  if (error instanceof PostPeerConnectProviderError) {
    response.status(502).json({
      status: 'error',
      message: 'PostPeer account linking provider failed'
    });
    return true;
  }

  return false;
};

// PostPeer groups a user's connected accounts under one profile id. Create it
// once per user and reuse it for connect URLs and integration polling.
const ensureProfileId = async (
  store: SocialConnectionStore,
  connectClient: PostPeerConnectClient,
  userId: string
): Promise<string> => {
  const existing = await store.getProfileId(userId);

  if (existing) {
    return existing;
  }

  const { profileId } = await connectClient.createProfile();
  await store.setProfileId({ userId, profileId });

  return profileId;
};

export const registerSocialConnectionRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  { store, connectClient }: SocialConnectionRouteDependencies
) => {
  router.get('/social-connections', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      sendUnauthorized(response);
      return;
    }

    response.json({
      status: 'ok',
      connections: await store.listForUser(authUser.id)
    });
  });

  router.post(
    '/social-connections/:platform/connect',
    authMiddleware,
    async (request, response) => {
      const authUser = readAuthUser(response.locals);
      const platform = request.params.platform;

      if (!authUser) {
        sendUnauthorized(response);
        return;
      }

      if (!isSocialConnectionPlatform(platform)) {
        sendUnsupportedPlatform(response);
        return;
      }

      try {
        const profileId = await ensureProfileId(store, connectClient, authUser.id);
        const { connectUrl } = await connectClient.createConnectUrl({
          platform,
          profileId
        });

        response.json({ status: 'ok', connectUrl });
      } catch (error) {
        if (sendConnectError(response, error)) {
          return;
        }

        throw error;
      }
    }
  );

  // Called after the user finishes the PostPeer OAuth flow in the browser.
  // PostPeer does not call back, so the backend polls the profile's
  // integrations and stores each connected account id.
  router.post('/social-connections/refresh', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      sendUnauthorized(response);
      return;
    }

    try {
      const profileId = await store.getProfileId(authUser.id);

      if (profileId) {
        const integrations = await connectClient.listIntegrations({ profileId });

        for (const integration of integrations) {
          await store.upsert({
            userId: authUser.id,
            platform: integration.platform,
            postPeerAccountId: integration.id,
            displayName: integration.displayName,
            externalAccountId: integration.platformUserId
          });
        }
      }

      response.json({
        status: 'ok',
        connections: await store.listForUser(authUser.id)
      });
    } catch (error) {
      if (sendConnectError(response, error)) {
        return;
      }

      throw error;
    }
  });

  router.delete(
    '/social-connections/:platform',
    authMiddleware,
    async (request, response) => {
      const authUser = readAuthUser(response.locals);
      const platform = request.params.platform;

      if (!authUser) {
        sendUnauthorized(response);
        return;
      }

      if (!isSocialConnectionPlatform(platform)) {
        sendUnsupportedPlatform(response);
        return;
      }

      await store.disconnect({ userId: authUser.id, platform });

      response.json({ status: 'ok' });
    }
  );
};
