import { createHash, randomBytes } from 'node:crypto';

import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser, type AuthUser } from '../auth/authTypes.js';
import type { UserStore } from '../users/userStore.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  postPeerReturnUriByTarget,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';
import {
  PostPeerProfileOwnershipConflictError,
  SocialAccountAlreadyLinkedError,
  isSocialConnectionPlatform,
  supportedSocialConnectionPlatforms,
  type SocialConnectionStore
} from './socialConnectionStore.js';

export type SocialConnectionRouteDependencies = {
  store: SocialConnectionStore;
  connectClient: PostPeerConnectClient;
  userStore: UserStore;
  now?: () => Date;
};

const connectAttemptLifetimeMs = 15 * 60 * 1_000;
const hashNonce = (nonce: string): string =>
  createHash('sha256').update(nonce).digest('hex');

const sendAttemptExpired = (response: Response) => {
  response.status(409).json({
    status: 'error',
    code: 'SOCIAL_CONNECTION_ATTEMPT_EXPIRED',
    message: 'This connection attempt is no longer available. Please connect again.'
  });
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
  if (error instanceof SocialAccountAlreadyLinkedError) {
    response.status(409).json({
      status: 'error',
      code: 'SOCIAL_ACCOUNT_ALREADY_LINKED',
      message: 'This social account is already linked to another user.'
    });
    return true;
  }

  if (error instanceof PostPeerProfileOwnershipConflictError) {
    response.status(409).json({
      status: 'error',
      code: 'SOCIAL_CONNECTION_CONFLICT',
      message: 'Social account linking could not be completed. Please contact support.'
    });
    return true;
  }

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
    return store.setProfileId({ userId: authUser.id, profileId });
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
  { store, connectClient, userStore, now = () => new Date() }: SocialConnectionRouteDependencies
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

      const payload =
        request.body && typeof request.body === 'object'
          ? (request.body as Record<string, unknown>)
          : {};
      const returnTarget = payload.returnTarget;

      if (
        returnTarget !== undefined &&
        returnTarget !== 'android' &&
        returnTarget !== 'android-staging'
      ) {
        response.status(400).json({
          status: 'error',
          code: 'SOCIAL_CONNECTION_RETURN_TARGET_INVALID',
          message: 'returnTarget must be android or android-staging when provided'
        });
        return;
      }

      const redirectUri =
        returnTarget === undefined ? undefined : postPeerReturnUriByTarget[returnTarget];

      try {
        const profileId = await ensureProfileId(
          store,
          connectClient,
          userStore,
          authUser,
          inFlightProfileCreations
        );
        // Snapshot before issuing the URL. Pre-existing integrations cannot
        // prove completion of this authenticated user's new connect attempt.
        const integrations = await connectClient.listIntegrations({ profileId });
        const nonce = randomBytes(32).toString('base64url');
        const nonceHash = hashNonce(nonce);
        const expiresAt = new Date(now().getTime() + connectAttemptLifetimeMs).toISOString();
        await store.beginConnectAttempt({
          userId: authUser.id,
          platform,
          profileId,
          nonceHash,
          expiresAt,
          baselineIntegrationIds: [...new Set(integrations.map(({ id }) => id))]
        });

        try {
          const { connectUrl } = await connectClient.createConnectUrl({
            platform,
            profileId,
            ...(redirectUri === undefined ? {} : { redirectUri })
          });

          response.set('Cache-Control', 'private, no-store');
          response.json({ status: 'ok', connectUrl, nonce, expiresAt });
        } catch (error) {
          // A failed older request must not cancel a newer concurrent attempt.
          await store.cancelConnectAttempt({ userId: authUser.id, platform, nonceHash });
          throw error;
        }
      } catch (error) {
        if (sendConnectError(response, error)) {
          return;
        }

        throw error;
      }
    }
  );

  // The app retains the nonce from connect in its authenticated session. A
  // browser return URI alone never authorizes importing an integration.
  router.post('/social-connections/refresh', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      sendUnauthorized(response);
      return;
    }

    const payload = request.body && typeof request.body === 'object'
      ? request.body as Record<string, unknown> : {};
    const nonce = payload.nonce;
    if (nonce !== undefined &&
        (typeof nonce !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(nonce))) {
      response.status(400).json({
        status: 'error',
        code: 'SOCIAL_CONNECTION_ATTEMPT_INVALID',
        message: 'A valid connection attempt nonce is required.'
      });
      return;
    }

    try {
      const nonceHash = typeof nonce === 'string' ? hashNonce(nonce) : undefined;
      const attempt = nonceHash === undefined ? undefined :
        await store.getConnectAttempt({ userId: authUser.id, nonceHash });
      if (nonceHash !== undefined &&
          (!attempt || !Number.isFinite(Date.parse(attempt.expiresAt)) ||
            Date.parse(attempt.expiresAt) <= now().getTime())) {
        sendAttemptExpired(response);
        return;
      }

      let profileId = await store.getProfileId(authUser.id);

      if (!profileId && connectClient.findProfile) {
        const recoveredProfile = await connectClient.findProfile({ userId: authUser.id });

        if (recoveredProfile) {
          await userStore.ensure(authUser);
          profileId = await store.setProfileId({
            userId: authUser.id,
            profileId: recoveredProfile.profileId
          });
        }
      }

      if (attempt && attempt.profileId !== profileId) {
        sendAttemptExpired(response);
        return;
      }

      let connectAttemptConsumed = false;
      if (profileId) {
        // Capture known identities before polling. A provider response can be
        // stale by the time it arrives; never apply it to a connection that
        // completed while this refresh was awaiting PostPeer.
        const existingConnections = await Promise.all(
          supportedSocialConnectionPlatforms.map((platform) =>
            store.getConnection({ userId: authUser.id, platform })
          )
        );
        const integrations = (await connectClient.listIntegrations({ profileId })).filter(
          (integration) => integration.platform !== undefined
        );
        if (attempt && nonceHash) {
          const candidates = integrations.filter((integration) =>
            integration.platform === attempt.platform &&
            !attempt.baselineIntegrationIds.includes(integration.id)
          );
          if (candidates.length > 1) {
            response.status(409).json({
              status: 'error',
              code: 'SOCIAL_CONNECTION_COMPLETION_AMBIGUOUS',
              message: 'More than one new social account was found. Please connect again.'
            });
            return;
          }

          const integration = candidates[0];
          if (integration) {
            const completed = await store.completeConnectAttempt({
              userId: authUser.id,
              platform: attempt.platform,
              profileId,
              nonceHash,
              integration: {
                postPeerAccountId: integration.id,
                displayName: integration.displayName,
                externalAccountId: integration.platformUserId
              },
              now: now().toISOString()
            });
            if (!completed) {
              sendAttemptExpired(response);
              return;
            }
            connectAttemptConsumed = true;
          }
        }

        // Legacy refreshes remain useful for known connections, but cannot
        // import or silently replace any provider/external account identity.
        for (const existing of existingConnections) {
          if (!existing || (connectAttemptConsumed && existing.platform === attempt?.platform)) {
            continue;
          }
          const integration = integrations.find((candidate) =>
            candidate.platform === existing.platform &&
            candidate.id === existing.postPeerAccountId &&
            candidate.platformUserId === existing.externalAccountId
          );
          // The store compares the current identity atomically. An older
          // refresh cannot overwrite/remove a newer completed connection or
          // cancel a pending connect attempt during ordinary reconciliation.
          await store.reconcileExistingConnection({
            userId: authUser.id,
            platform: existing.platform,
            expectedPostPeerAccountId: existing.postPeerAccountId,
            expectedExternalAccountId: existing.externalAccountId,
            ...(integration ? {
              integration: {
                postPeerAccountId: existing.postPeerAccountId,
                externalAccountId: existing.externalAccountId,
                displayName: integration.displayName
              }
            } : {})
          });
        }
      }

      response.set('Cache-Control', 'private, no-store');
      response.json({
        status: 'ok',
        connections: await store.listForUser(authUser.id),
        ...(nonceHash === undefined ? {} : { connectAttemptConsumed })
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
      // Snapshot both identities before waiting for the provider. Conditional
      // cleanup below cannot remove a later connection or connect attempt.
      const { connection, nonceHash } = await store.getDisconnectSnapshot(connectionInput);
      const cancelCapturedAttempt = async () => {
        if (nonceHash) {
          await store.cancelConnectAttempt({ ...connectionInput, nonceHash });
        }
      };

      // A repeated DELETE is a successful no-op. More importantly, do not
      // remove a saved connection until PostPeer confirms that the external
      // integration is gone; otherwise the next refresh can recreate it.
      if (!connection) {
        await cancelCapturedAttempt();
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
        await connectClient.disconnectIntegration({ integrationId: connection.postPeerAccountId });
        await store.reconcileExistingConnection({
          ...connectionInput,
          expectedPostPeerAccountId: connection.postPeerAccountId,
          expectedExternalAccountId: connection.externalAccountId
        });
        await cancelCapturedAttempt();
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
