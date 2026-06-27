import type { Request, RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';
import type { VerifiedPostPeerConnectState } from './postPeerConnectState.js';
import {
  isSocialConnectionPlatform,
  type SocialConnectionPlatform,
  type SocialConnectionStore
} from './socialConnectionStore.js';

export type PostPeerConnectStateManager = {
  create: (input: {
    userId: string;
    platform: SocialConnectionPlatform;
  }) => { token: string; expiresAt: string };
  verify: (token: string) => VerifiedPostPeerConnectState;
};

export type SocialConnectionRouteDependencies = {
  store: SocialConnectionStore;
  connectClient: PostPeerConnectClient;
  callbackUrl?: string;
  callbackSecret?: string;
  stateManager?: PostPeerConnectStateManager;
};

const accountLinkingUnavailableMessage =
  'PostPeer account linking is not configured yet';

const readString = (value: unknown): string | undefined => {
  if (Array.isArray(value)) {
    return readString(value[0]);
  }

  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
};

const readObject = (value: unknown): Record<string, unknown> =>
  typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {};

const readPayloadValue = (
  request: Request,
  keys: string[]
): string | undefined => {
  const body = readObject(request.body);
  const query = readObject(request.query);

  for (const key of keys) {
    const value = readString(body[key]) ?? readString(query[key]);

    if (value) {
      return value;
    }
  }

  return undefined;
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

const sendAccountLinkingUnavailable = (response: Response) => {
  response.status(503).json({
    status: 'error',
    message: accountLinkingUnavailableMessage
  });
};

export const registerSocialConnectionRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  {
    store,
    connectClient,
    callbackUrl,
    callbackSecret,
    stateManager
  }: SocialConnectionRouteDependencies
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

      if (!stateManager || !callbackUrl) {
        sendAccountLinkingUnavailable(response);
        return;
      }

      const state = stateManager.create({
        userId: authUser.id,
        platform
      });

      try {
        const { connectUrl } = await connectClient.createConnectLink({
          platform,
          state: state.token,
          callbackUrl
        });

        response.json({
          status: 'ok',
          connectUrl,
          expiresAt: state.expiresAt
        });
      } catch (error) {
        if (error instanceof PostPeerConnectUnavailableError) {
          sendAccountLinkingUnavailable(response);
          return;
        }

        if (error instanceof PostPeerConnectProviderError) {
          response.status(502).json({
            status: 'error',
            message: 'PostPeer account linking provider failed'
          });
          return;
        }

        throw error;
      }
    }
  );

  const handleCallback: RequestHandler = async (request, response) => {
    if (callbackSecret) {
      const providedSecret = readString(
        request.header('x-postpeer-callback-secret')
      );

      if (providedSecret !== callbackSecret) {
        response.status(401).json({
          status: 'error',
          message: 'Invalid PostPeer callback secret'
        });
        return;
      }
    }

    if (!stateManager) {
      sendAccountLinkingUnavailable(response);
      return;
    }

    const state = readPayloadValue(request, ['state']);
    const postPeerAccountId = readPayloadValue(request, [
      'accountId',
      'postPeerAccountId',
      'integrationId'
    ]);

    if (!state || !postPeerAccountId) {
      response.status(400).json({
        status: 'error',
        message: 'state and account id are required'
      });
      return;
    }

    let verifiedState: VerifiedPostPeerConnectState;

    try {
      verifiedState = stateManager.verify(state);
    } catch {
      response.status(400).json({
        status: 'error',
        message: 'Invalid PostPeer connect state'
      });
      return;
    }

    await store.upsert({
      userId: verifiedState.userId,
      platform: verifiedState.platform,
      postPeerAccountId,
      displayName: readPayloadValue(request, ['displayName']),
      externalAccountId: readPayloadValue(request, ['externalAccountId'])
    });

    response.json({ status: 'ok' });
  };

  router.get('/social-connections/postpeer/callback', handleCallback);
  router.post('/social-connections/postpeer/callback', handleCallback);

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

      await store.disconnect({
        userId: authUser.id,
        platform
      });

      response.json({ status: 'ok' });
    }
  );
};
