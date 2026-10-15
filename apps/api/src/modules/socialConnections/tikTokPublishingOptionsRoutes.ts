import type { RequestHandler, Router } from 'express';

import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { readAuthUser } from '../auth/authTypes.js';
import { buildPlatformTarget, isSamePlatformTarget } from '../posts/platformTargets.js';
import { buildTikTokConnectionRevision } from '../posts/tikTokDirectSettings.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import { TikTokPublishingError, type PostPeerTikTokClient } from './postPeerTikTokClient.js';
import type { SocialConnectionStore } from './socialConnectionStore.js';

export const registerTikTokPublishingOptionsRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  { store, client, assertOwnerActive, runWithOwnerLifetime }: {
    store: SocialConnectionStore;
    client: PostPeerTikTokClient;
    assertOwnerActive: (userId: string) => Promise<void>;
    runWithOwnerLifetime: RunWithActiveOwner;
  }
) => {
  router.get('/social-connections/TIKTOK/publishing-options', authMiddleware, async (_request, response) => {
    response.setHeader('Cache-Control', 'private, no-store');
    const user = readAuthUser(response.locals);
    if (!user) {
      response.status(401).json({ status: 'error', message: 'Authenticated user is required' });
      return;
    }
    const sendError = (error: unknown) => {
      if (error instanceof TikTokPublishingError || error instanceof ManagedUploadServiceError) {
        response.status(error.statusCode)
          .json({ status: 'error', code: error.code, message: error.message });
        return;
      }
      response.status(503).json({
        status: 'error', code: 'TIKTOK_CREATOR_INFO_UNAVAILABLE',
        message: 'TikTok publishing options could not be checked. Please try again.'
      });
    };
    try {
      const outcome = await runWithOwnerLifetime(user.id, async () => {
        try {
          await assertOwnerActive(user.id);
          const connection = await store.getConnection({ userId: user.id, platform: 'TIKTOK' });
          if (!connection?.id) throw new TikTokPublishingError(
            'TIKTOK_CONNECTION_UNAVAILABLE', 409, 'Connect a TikTok account before reviewing publishing options.'
          );
          const target = buildPlatformTarget(connection);
          const creatorInfoRevision = buildTikTokConnectionRevision({ userId: user.id, target });
          const creatorInfo = await client.getCreatorInfo({ accountId: target.accountId });
          await assertOwnerActive(user.id);
          const current = await store.getConnection({ userId: user.id, platform: 'TIKTOK' });
          if (
            !current || current.id !== connection.id ||
            !isSamePlatformTarget(target, buildPlatformTarget(current)) ||
            creatorInfoRevision !== buildTikTokConnectionRevision({ userId: user.id, target: buildPlatformTarget(current) })
          ) {
            throw new TikTokPublishingError(
              'TIKTOK_CONNECTION_CHANGED', 409, 'The connected TikTok account changed. Review the post again.'
            );
          }
          return { value: { status: 'ok', connectionId: connection.id, creatorInfoRevision, creatorInfo } };
        } catch (error) {
          // This lookup only reads provider capabilities. Complete the lifetime
          // normally so a failed GET never retains a publish-uncertainty ticket.
          return { error };
        }
      });
      if ('error' in outcome) sendError(outcome.error);
      else response.json(outcome.value);
    } catch (error) {
      sendError(error);
    }
  });
};
