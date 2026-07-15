import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser, type AuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';
import {
  isSocialConnectionPlatform,
  supportedSocialConnectionPlatforms,
  type SocialConnectionStore
} from './socialConnectionStore.js';

export type SocialConnectionRouteDependencies = {
  store: SocialConnectionStore;
  connectClient: PostPeerConnectClient;
  userStore: UserStore;
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
    response.status(503).json({
      status: 'error',
      code: 'SOCIAL_CONNECTION_UNAVAILABLE',
      message: 'Social account linking is not available. Please try again later.'
    });
    return true;
  }

  if (error instanceof PostPeerConnectProviderError) {
    response.status(502).json({
      status: 'error',
      code: 'SOCIAL_CONNECTION_FAILED',
      message: 'Social account linking failed. Please try again later.'
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
  userStore: UserStore,
  authUser: AuthUser,
  inFlightCreations: Map<string, Promise<string>>
): Promise<string> => {
  const existing = await store.getProfileId(authUser.id);

  if (existing) {
    return existing;
  }

  const inFlight = inFlightCreations.get(authUser.id);

  if (inFlight) {
    return inFlight;
  }

  const creation = (async () => {
    // PostPeerProfile has a foreign key to User in Prisma. Persist the fresh
    // Firebase identity before creating the external profile so an FK failure
    // cannot leave an avoidable orphan at PostPeer.
    await userStore.ensure(authUser);

    // Another API instance may have saved a profile while the user upsert was
    // running. Re-check before making the external request.
    const profileCreatedElsewhere = await store.getProfileId(authUser.id);

    if (profileCreatedElsewhere) {
      return profileCreatedElsewhere;
    }

    const { profileId } = await connectClient.createProfile({ userId: authUser.id });
    await store.setProfileId({ userId: authUser.id, profileId });

    return profileId;
  })();

  inFlightCreations.set(authUser.id, creation);

  try {
    return await creation;
  } finally {
    if (inFlightCreations.get(authUser.id) === creation) {
      inFlightCreations.delete(authUser.id);
    }
  }
};

export const registerSocialConnectionRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  { store, connectClient, userStore }: SocialConnectionRouteDependencies
) => {
  // Coalesce same-user connect requests inside this API instance. This avoids
  // duplicate external profiles when a user double-taps or two platforms are
  // opened at nearly the same time.
  const inFlightProfileCreations = new Map<string, Promise<string>>();

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
        const profileId = await ensureProfileId(
          store,
          connectClient,
          userStore,
          authUser,
          inFlightProfileCreations
        );
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
        const integrations = (await connectClient.listIntegrations({ profileId })).filter(
          (integration) => integration.platform !== undefined
        );
        const connectedPlatforms = new Set(integrations.map(({ platform }) => platform));

        for (const integration of integrations) {
          if (!integration.platform) {
            continue;
          }

          await store.upsert({
            userId: authUser.id,
            platform: integration.platform,
            postPeerAccountId: integration.id,
            displayName: integration.displayName,
            externalAccountId: integration.platformUserId
          });
        }

        for (const platform of supportedSocialConnectionPlatforms) {
          if (!connectedPlatforms.has(platform)) {
            await store.disconnect({ userId: authUser.id, platform });
          }
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

      const connectionInput = { userId: authUser.id, platform };
      const integrationId = await store.getAccountId(connectionInput);

      // A repeated DELETE is a successful no-op. More importantly, do not
      // remove a saved connection until PostPeer confirms that the external
      // integration is gone; otherwise the next refresh can recreate it.
      if (!integrationId) {
        response.json({ status: 'ok' });
        return;
      }

      if (
        connectClient.supportsIntegrationCleanup === false ||
        !connectClient.disconnectIntegration
      ) {
        sendConnectError(response, new PostPeerConnectUnavailableError());
        return;
      }

      try {
        await connectClient.disconnectIntegration({ integrationId });
        await store.disconnect(connectionInput);
      } catch (error) {
        if (sendConnectError(response, error)) {
          return;
        }

        throw error;
      }

      response.json({ status: 'ok' });
    }
  );
};
