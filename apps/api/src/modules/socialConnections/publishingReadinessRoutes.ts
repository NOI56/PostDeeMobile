import type { RequestHandler, Router } from 'express';

import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { readAuthUser } from '../auth/authTypes.js';
import { buildPlatformTarget } from '../posts/platformTargets.js';
import { buildTikTokConnectionRevision } from '../posts/tikTokDirectSettings.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import type { PostPeerConnectClient } from './postPeerConnectClient.js';
import { supportedSocialConnectionPlatforms, type SocialConnection, type SocialConnectionStore } from './socialConnectionStore.js';

export type PublishingReadiness = {
  platform: SocialConnection['platform'];
  connectionId?: string;
  connectionRevision?: string;
  state: 'ready' | 'connected' | 'reconnect_required' | 'permission_missing' | 'not_connected' | 'unavailable';
  reasonCode?: 'NOT_CONNECTED' | 'PROVIDER_PROFILE_MISSING' | 'PROVIDER_INTEGRATION_MISSING' | 'PROVIDER_RECONNECT_REQUIRED' | 'PUBLISH_PERMISSION_MISSING' | 'PUBLISH_CAPABILITY_UNCONFIRMED';
};

const revision = (owner: string, connection: SocialConnection | undefined) => connection
  ? buildTikTokConnectionRevision({ userId: owner, target: buildPlatformTarget(connection) }) : undefined;

export const registerPublishingReadinessRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  { store, client, assertOwnerActive, runWithOwnerLifetime, now = () => new Date() }: {
    store: SocialConnectionStore;
    client: PostPeerConnectClient;
    assertOwnerActive: (userId: string) => Promise<void>;
    runWithOwnerLifetime: RunWithActiveOwner;
    now?: () => Date;
  }
) => {
  router.get('/social-connections/publishing-readiness', authMiddleware, async (_request, response) => {
    response.setHeader('Cache-Control', 'private, no-store');
    const user = readAuthUser(response.locals);
    if (!user) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }
    const sendError = (error: unknown) => {
      if (error instanceof ManagedUploadServiceError) {
        response.status(error.statusCode).json({ status: 'error', code: error.code, message: error.message });
        return;
      }
      response.status(503).json({ status: 'error', code: 'PUBLISHING_READINESS_UNAVAILABLE', message: 'Connected channel publishing access could not be checked. Please try again.' });
    };
    try {
      const result = await runWithOwnerLifetime(user.id, async () => {
        try {
          await assertOwnerActive(user.id);
          if (client.publishingReadinessConfigured === false) throw new Error('Provider unavailable');
          const profileId = await store.getProfileId(user.id);
          const connections = await Promise.all(supportedSocialConnectionPlatforms.map((platform) => store.getConnection({ userId: user.id, platform })));
          // This endpoint never creates, discovers, synchronizes, or repairs a
          // provider profile. It only reads integrations in the stored owner scope.
          const integrations = profileId && connections.some(Boolean)
            ? await client.listIntegrations({ profileId, publishingReadiness: true }) : [];
          const currentProfileId = await store.getProfileId(user.id);
          const currentConnections = await Promise.all(supportedSocialConnectionPlatforms.map((platform) => store.getConnection({ userId: user.id, platform })));
          await assertOwnerActive(user.id);
          if (profileId !== currentProfileId || connections.some((connection, index) =>
            connection?.id !== currentConnections[index]?.id || revision(user.id, connection) !== revision(user.id, currentConnections[index])
          )) {
            return { changed: true as const };
          }
          const results: PublishingReadiness[] = supportedSocialConnectionPlatforms.map((platform, index) => {
            const connection = connections[index];
            if (!connection) return { platform, state: 'not_connected', reasonCode: 'NOT_CONNECTED' };
            const identity = { platform, ...(connection.id ? { connectionId: connection.id } : {}), connectionRevision: revision(user.id, connection) };
            if (!profileId) return { ...identity, state: 'reconnect_required', reasonCode: 'PROVIDER_PROFILE_MISSING' };
            const matches = integrations.filter((integration) => integration.id === connection.postPeerAccountId && integration.platform === platform &&
              (!connection.externalAccountId || !integration.platformUserId || connection.externalAccountId === integration.platformUserId));
            if (matches.length !== 1) return { ...identity, state: 'reconnect_required', reasonCode: 'PROVIDER_INTEGRATION_MISSING' };
            const integration = matches[0]!;
            if (integration.reconnectRequired === true) return { ...identity, state: 'reconnect_required', reasonCode: 'PROVIDER_RECONNECT_REQUIRED' };
            if (integration.canPublish === false) return { ...identity, state: 'permission_missing', reasonCode: 'PUBLISH_PERMISSION_MISSING' };
            if (integration.canPublish === true) return { ...identity, state: 'ready' };
            return { ...identity, state: 'connected', reasonCode: 'PUBLISH_CAPABILITY_UNCONFIRMED' };
          });
          return { value: { status: 'ok', checkedAt: now().toISOString(), connections: results } };
        } catch (error) {
          // Read-only errors complete normally inside the owner lifetime so
          // they never retain the durable blocker used for ambiguous writes.
          return { error };
        }
      });
      if ('error' in result) sendError(result.error);
      else if ('changed' in result) response.status(409).json({ status: 'error', code: 'SOCIAL_CONNECTIONS_CHANGED', message: 'Connected accounts changed. Review the channel settings again.' });
      else response.json(result.value);
    } catch (error) { sendError(error); }
  });
};
