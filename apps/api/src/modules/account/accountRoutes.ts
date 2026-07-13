import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { AnalyticsStore } from '../analytics/analyticsStore.js';
import type { AiEditUsageStore } from '../aiEdits/aiEditUsageStore.js';
import type { RealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { PostStore } from '../posts/postStore.js';
import type { PublishQueue } from '../queue/publishQueue.js';
import type { PlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import type { PostPeerConnectClient } from '../socialConnections/postPeerConnectClient.js';
import type { SocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { TemplateStore } from '../templates/templateStore.js';
import type { UserStore } from '../users/userStore.js';
import type { VideoStorage } from '../storage/videoStorage.js';
import type { AccountIdentityDeleter } from './firebaseIdentityDeleter.js';

/**
 * Minimal Prisma surface needed to hard-delete an account. Removing the User row
 * cascades to posts, templates, subscription, and usage rows via the schema's
 * `onDelete: Cascade` relations, so a single deleteMany clears everything.
 */
export type PrismaAccountClient = {
  user: {
    deleteMany: (args: { where: { id: string } }) => Promise<{ count: number }>;
  };
};

export type AccountRouteDependencies = {
  postStore: PostStore;
  templateStore: TemplateStore;
  subscriptionStore: SubscriptionStore;
  analyticsStore: AnalyticsStore;
  realClipCaptionUsageStore: RealClipCaptionUsageStore;
  aiEditUsageStore: AiEditUsageStore;
  deviceTokenStore: DeviceTokenStore;
  socialConnectionStore?: SocialConnectionStore;
  postPeerConnectClient?: PostPeerConnectClient;
  userStore: UserStore;
  publishQueue: PublishQueue;
  platformPublishStore: PlatformPublishStore;
  videoStorage: VideoStorage;
  accountIdentityDeleter?: AccountIdentityDeleter;
  prisma?: PrismaAccountClient;
  nowSeconds?: () => number;
};

const recentAuthenticationWindowSeconds = 5 * 60;
const allowedAuthenticationClockSkewSeconds = 60;

/**
 * Registers `DELETE /account`, the store-compliance account deletion endpoint.
 * It permanently removes every piece of data owned by the authenticated user.
 */
export const registerAccountRoutes = (
  router: Router,
  authMiddleware: RequestHandler,
  dependencies: AccountRouteDependencies
) => {
  const {
    postStore,
    templateStore,
    subscriptionStore,
    analyticsStore,
    realClipCaptionUsageStore,
    aiEditUsageStore,
    deviceTokenStore,
    socialConnectionStore,
    postPeerConnectClient,
    userStore,
    publishQueue,
    platformPublishStore,
    videoStorage,
    accountIdentityDeleter,
    prisma,
    nowSeconds = () => Math.floor(Date.now() / 1000)
  } = dependencies;

  const readDeletionUnavailableCode = (
    authUser: ReturnType<typeof readAuthUser>,
    postPeerProfileId?: string
  ) => {
    if (authUser?.provider === 'firebase' && !accountIdentityDeleter) {
      return 'ACCOUNT_DELETION_UNAVAILABLE';
    }

    if (!videoStorage.supportsOwnerCleanup) {
      return 'ACCOUNT_MEDIA_CLEANUP_UNAVAILABLE';
    }

    if (
      postPeerProfileId &&
      (!postPeerConnectClient?.supportsIntegrationCleanup ||
        !postPeerConnectClient.disconnectIntegration)
    ) {
      return 'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE';
    }

    return undefined;
  };

  const readPostPeerProfileId = async (userId: string) =>
    socialConnectionStore?.getProfileId(userId);

  router.get('/account/deletion-readiness', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    let postPeerProfileId: string | undefined;
    try {
      postPeerProfileId = await readPostPeerProfileId(authUser.id);
    } catch {
      response.status(503).json({
        status: 'error',
        code: 'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE',
        message: 'Account deletion is temporarily unavailable. Please try again later.'
      });
      return;
    }

    const unavailableCode = readDeletionUnavailableCode(authUser, postPeerProfileId);

    if (unavailableCode) {
      response.status(503).json({
        status: 'error',
        code: unavailableCode,
        message: 'Account deletion is temporarily unavailable. Please try again later.'
      });
      return;
    }

    response.json({
      status: 'ok',
      identityAlreadyDeleted: authUser.identityAlreadyDeleted === true
    });
  });

  router.delete('/account', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const userId = authUser.id;

    let postPeerProfileId: string | undefined;
    try {
      postPeerProfileId = await readPostPeerProfileId(userId);
    } catch {
      response.status(503).json({
        status: 'error',
        code: 'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE',
        message: 'Account deletion is temporarily unavailable. Please try again later.'
      });
      return;
    }

    const unavailableCode = readDeletionUnavailableCode(authUser, postPeerProfileId);

    if (unavailableCode) {
      response.status(503).json({
        status: 'error',
        code: unavailableCode,
        message: 'Account deletion is temporarily unavailable. Please try again later.'
      });
      return;
    }

    const currentSeconds = nowSeconds();

    if (
      authUser.provider === 'firebase' &&
      !authUser.identityAlreadyDeleted &&
      (typeof authUser.authenticatedAtSeconds !== 'number' ||
        authUser.authenticatedAtSeconds >
          currentSeconds + allowedAuthenticationClockSkewSeconds ||
        currentSeconds - authUser.authenticatedAtSeconds > recentAuthenticationWindowSeconds)
    ) {
      response.status(403).json({
        status: 'error',
        code: 'ACCOUNT_REAUTHENTICATION_REQUIRED',
        message: 'Sign in again before permanently deleting your account.'
      });
      return;
    }

    // Stop queued work before external cleanup so a worker cannot publish while
    // deletion is in progress. Posts remain intact until cleanup succeeds.
    const posts = await postStore.list({ userId });
    for (const post of posts) {
      await publishQueue.remove(post.id);
    }

    // Disconnect provider-side accounts before deleting local account data.
    // Attempt every id for maximum cleanup; 404 remains safe to retry.
    if (postPeerProfileId && postPeerConnectClient?.disconnectIntegration) {
      let cleanupFailed = false;

      try {
        const integrations = await postPeerConnectClient.listIntegrations({
          profileId: postPeerProfileId
        });
        const integrationIds = new Set(integrations.map(({ id }) => id));

        for (const integrationId of integrationIds) {
          try {
            await postPeerConnectClient.disconnectIntegration({ integrationId });
          } catch {
            cleanupFailed = true;
          }
        }
      } catch {
        cleanupFailed = true;
      }

      if (cleanupFailed) {
        response.status(503).json({
          status: 'error',
          code: 'ACCOUNT_SOCIAL_CLEANUP_FAILED',
          message: 'Could not remove connected social accounts. Please try again.'
        });
        return;
      }
    }

    try {
      await videoStorage.deleteAllVideosForOwner(userId);
    } catch {
      response.status(503).json({
        status: 'error',
        code: 'ACCOUNT_MEDIA_CLEANUP_FAILED',
        message: 'Could not remove account media. Please try again.'
      });
      return;
    }

    if (platformPublishStore.deleteAllForPosts) {
      await platformPublishStore.deleteAllForPosts(posts.map((post) => post.id));
    }

    // Memory-backed stores remove their own user-scoped data. Prisma-backed
    // stores leave these undefined and are cleared by the User cascade below.
    const deleters = [
      postStore.deleteAllForUser,
      templateStore.deleteAllForUser,
      subscriptionStore.deleteAllForUser,
      analyticsStore.deleteAllForUser,
      realClipCaptionUsageStore.deleteAllForUser,
      aiEditUsageStore.deleteAllForUser,
      deviceTokenStore.deleteAllForUser,
      socialConnectionStore?.deleteAllForUser,
      userStore.deleteAllForUser
    ];

    for (const deleter of deleters) {
      if (deleter) {
        await deleter(userId);
      }
    }

    // Prisma-backed stores: deleting the User row cascades to every child table.
    if (prisma) {
      await prisma.user.deleteMany({ where: { id: userId } });
    }

    if (accountIdentityDeleter) {
      try {
        await accountIdentityDeleter.deleteIdentity(authUser);
      } catch {
        response.status(503).json({
          status: 'error',
          code: 'ACCOUNT_IDENTITY_DELETE_FAILED',
          message:
            'Account data was removed, but sign-in removal is not complete. Please try again.'
        });
        return;
      }
    }

    response.json({ status: 'ok' });
  });
};
