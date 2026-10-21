import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser, type AuthUser } from '../auth/authTypes.js';
import type { AnalyticsStore } from '../analytics/analyticsStore.js';
import type { AiEditUsageStore } from '../aiEdits/aiEditUsageStore.js';
import type { RealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { LinkInBioStore } from '../linkInBio/linkInBioStore.js';
import type { LinkInBioImageStore } from '../linkInBio/linkInBioImageStore.js';
import type { PostStore } from '../posts/postStore.js';
import type { PublishQueue } from '../queue/publishQueue.js';
import type { PlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import type { PostPeerConnectClient } from '../socialConnections/postPeerConnectClient.js';
import type { SocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { TemplateStore } from '../templates/templateStore.js';
import type { UserStore } from '../users/userStore.js';
import type { VideoStorage } from '../storage/videoStorage.js';
import {
  ManagedUploadServiceError,
  type ManagedUploadService
} from '../uploads/managedUploadService.js';
import type { AccountIdentityDeleter } from './firebaseIdentityDeleter.js';
import type { OwnerMutationCoordinator } from './ownerMutationLock.js';
import { OwnerOperationBusyError } from './ownerOperationQueue.js';
import type { UploadSessionStore } from '../uploads/uploadSessionStore.js';

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
  monthlyAddonStore?: Pick<MonthlyAddonStore, 'deleteAllForUser'>;
  aiEditUsageStore: AiEditUsageStore;
  deviceTokenStore: DeviceTokenStore;
  linkInBioStore?: LinkInBioStore;
  linkInBioImageStore?: LinkInBioImageStore;
  socialConnectionStore?: SocialConnectionStore;
  postPeerConnectClient?: PostPeerConnectClient;
  userStore: UserStore;
  publishQueue: PublishQueue;
  platformPublishStore: PlatformPublishStore;
  videoStorage: VideoStorage;
  accountIdentityDeleter?: AccountIdentityDeleter;
  managedUploadService?: Pick<
    ManagedUploadService,
    'prepareOwnerDeletion' | 'finishOwnerDeletion'
  >;
  ownerMutationLock?: OwnerMutationCoordinator;
  ownerLifecycleStore?: Pick<UploadSessionStore,
    'beginOwnerDeletion' | 'finishOwnerDeletion' |
    'getOwnerDeletionAuthorization' | 'authorizeOwnerDeletion'> &
    Partial<Pick<UploadSessionStore, 'acquireOwnerDeletion'>>;
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
    monthlyAddonStore,
    aiEditUsageStore,
    deviceTokenStore,
    linkInBioStore,
    linkInBioImageStore,
    socialConnectionStore,
    postPeerConnectClient,
    userStore,
    publishQueue,
    platformPublishStore,
    videoStorage,
    accountIdentityDeleter,
    managedUploadService,
    ownerMutationLock,
    ownerLifecycleStore,
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

  const hasRecentAuthentication = (authUser: AuthUser) => {
    const authenticatedAt = authUser.authenticatedAtSeconds;
    const currentSeconds = nowSeconds();
    return typeof authenticatedAt === 'number' &&
      Number.isFinite(authenticatedAt) &&
      authenticatedAt <= currentSeconds + allowedAuthenticationClockSkewSeconds &&
      currentSeconds - authenticatedAt <= recentAuthenticationWindowSeconds;
  };

  const hasDeletionAuthorization = async (userId: string) => {
    const store = ownerLifecycleStore;
    if (!store || typeof store.getOwnerDeletionAuthorization !== 'function' ||
      typeof store.authorizeOwnerDeletion !== 'function' ||
      typeof store.beginOwnerDeletion !== 'function' ||
      typeof store.finishOwnerDeletion !== 'function' ||
      typeof store.acquireOwnerDeletion !== 'function') {
      throw new Error('Account deletion authorization storage is unavailable');
    }
    const proof = await store.getOwnerDeletionAuthorization(userId);
    const authorizedAt = typeof proof === 'string' ? Date.parse(proof) / 1000 : Number.NaN;
    return Number.isFinite(authorizedAt) &&
      authorizedAt <= nowSeconds() + allowedAuthenticationClockSkewSeconds;
  };

  const requireReauthentication = (response: Response) => {
    response.status(403).json({
      status: 'error', code: 'ACCOUNT_REAUTHENTICATION_REQUIRED',
      message: 'Sign in again before permanently deleting your account.'
    });
  };

  const authorizationUnavailable = (response: Response, error: unknown) => {
    const busy = error instanceof OwnerOperationBusyError;
    response.status(503).json({
      status: 'error',
      code: busy ? 'ACCOUNT_WRITE_DRAIN_FAILED' : 'ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE',
      message: busy
        ? 'Could not finish active account writes. Please try again.'
        : 'Could not verify or save account deletion authorization. Please try again.'
    });
  };

  router.get('/account/deletion-readiness', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (authUser.provider === 'firebase') {
      try {
        const authorized = await hasDeletionAuthorization(authUser.id);
        if (authUser.identityAlreadyDeleted && !authorized) {
          requireReauthentication(response);
          return;
        }
      } catch (error) {
        authorizationUnavailable(response, error);
        return;
      }
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

    if (authUser.provider === 'firebase') {
      try {
        const authorized = await hasDeletionAuthorization(userId);
        if (!authorized && (authUser.identityAlreadyDeleted || !hasRecentAuthentication(authUser))) {
          requireReauthentication(response);
          return;
        }
      } catch (error) {
        authorizationUnavailable(response, error);
        return;
      }
    }

    const releaseOwnerMutationLock = ownerMutationLock
      ? await ownerMutationLock.acquire(userId)
      : () => undefined;
    let releaseSharedDeletion: (() => Promise<void>) | undefined;

    try {

    // Recheck after waiting for the owner lock. Readiness never creates proof.
    let previouslyAuthorized = false;
    if (authUser.provider === 'firebase') {
      try {
        previouslyAuthorized = await hasDeletionAuthorization(userId);
        if (!previouslyAuthorized &&
          (authUser.identityAlreadyDeleted || !hasRecentAuthentication(authUser))) {
          requireReauthentication(response);
          return;
        }
      } catch (error) {
        authorizationUnavailable(response, error);
        return;
      }
    }

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

    if (authUser.provider === 'firebase') {
      try {
        if (!previouslyAuthorized) {
          if (authUser.identityAlreadyDeleted || !hasRecentAuthentication(authUser)) {
            requireReauthentication(response);
            return;
          }
          // The UID-bound proof and DELETING marker are one durable write.
          await ownerLifecycleStore!.authorizeOwnerDeletion(
            userId, new Date(nowSeconds() * 1000).toISOString()
          );
        } else {
          await ownerLifecycleStore!.beginOwnerDeletion(userId);
        }
      } catch (error) {
        authorizationUnavailable(response, error);
        return;
      }
      ownerMutationLock?.markDeleting(userId);
    } else {
      ownerMutationLock?.markDeleting(userId);

      // Mock/service cleanup seals the owner without creating Firebase consent.
      try {
        await ownerLifecycleStore?.beginOwnerDeletion(userId);
      } catch (error) {
        response.status(503).json({
          status: 'error',
          code: error instanceof OwnerOperationBusyError ? error.code : 'ACCOUNT_WRITE_DRAIN_FAILED',
          message: 'Could not finish active account work. Please try again.'
        });
        return;
      }
    }

    // The durable claim waits for work in every upgraded process, before any
    // provider/queue/media snapshot or cleanup. A crash leaves a private claim.
    try {
      releaseSharedDeletion = await ownerLifecycleStore?.acquireOwnerDeletion?.(userId);
    } catch {
      response.status(503).json({
        status: 'error', code: 'ACCOUNT_WRITE_DRAIN_FAILED',
        message: 'Could not finish active account work. Please try again.'
      });
      return;
    }

    // A profile admitted before sealing may have finished while we drained.
    // Refresh its cleanup scope and capability check after that work settles.
    try {
      postPeerProfileId = await readPostPeerProfileId(userId);
    } catch {
      response.status(503).json({
        status: 'error', code: 'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE',
        message: 'Could not verify connected account cleanup. Please try again.'
      });
      return;
    }
    const drainedUnavailableCode = readDeletionUnavailableCode(authUser, postPeerProfileId);
    if (drainedUnavailableCode) {
      response.status(503).json({ status: 'error', code: drainedUnavailableCode,
        message: 'Account deletion is temporarily unavailable. Please try again later.' });
      return;
    }

    // Seal the owner before draining queued/external work so concurrent upload
    // and post requests cannot recreate work after the cleanup snapshots it.
    if (managedUploadService) {
      try {
        await managedUploadService.prepareOwnerDeletion(userId);
      } catch (error) {
        if (
          error instanceof ManagedUploadServiceError &&
          error.code === 'ACCOUNT_UPLOADS_DRAINING'
        ) {
          response.status(409).json({
            status: 'error',
            code: error.code,
            message: error.message
          });
          return;
        }

        response.status(503).json({
          status: 'error',
          code: 'ACCOUNT_MEDIA_CLEANUP_FAILED',
          message: 'Could not stop active account uploads. Please try again.'
        });
        return;
      }
    }

    // Stop queued work before external cleanup so a worker cannot publish while
    // deletion is in progress. Posts remain intact until cleanup succeeds.
    const posts = await postStore.list({ userId });
    try {
      // Jobs may outlive their original row after a failed/late queue add.
      const queuedJobs = await publishQueue.list({ userId });
      const ownedPostIds = new Set([
        ...posts.map((post) => post.id),
        ...queuedJobs.filter((job) => job.userId === userId).map((job) => job.postId)
      ]);
      for (const postId of ownedPostIds) await publishQueue.remove(postId);
    } catch {
      response.status(503).json({
        status: 'error', code: 'ACCOUNT_PUBLISH_CLEANUP_FAILED',
        message: 'Could not remove account publishing work. Please try again.'
      });
      return;
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

    // Stores with explicit cleanup remove their user-scoped data. The User
    // cascade below also clears all Prisma child rows, including Link in Bio.
    const deleters = [
      postStore.deleteAllForUser,
      templateStore.deleteAllForUser,
      subscriptionStore.deleteAllForUser,
      analyticsStore.deleteAllForUser,
      realClipCaptionUsageStore.deleteAllForUser,
      monthlyAddonStore?.deleteAllForUser,
      aiEditUsageStore.deleteAllForUser,
      deviceTokenStore.deleteAllForUser,
      linkInBioStore?.deleteAllForUser,
      linkInBioImageStore?.deleteAllForUser,
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

    if (managedUploadService) {
      try {
        await managedUploadService.finishOwnerDeletion(userId);
      } catch {
        response.status(503).json({
          status: 'error',
          code: 'ACCOUNT_UPLOAD_STATE_CLEANUP_FAILED',
          message: 'Account deletion is almost complete. Please try again.'
        });
        return;
      }
    }

    try {
      await ownerLifecycleStore?.finishOwnerDeletion(userId);
    } catch {
      response.status(503).json({
        status: 'error', code: 'ACCOUNT_UPLOAD_STATE_CLEANUP_FAILED',
        message: 'Account deletion is almost complete. Please try again.'
      });
      return;
    }
    ownerMutationLock?.markDeleted(userId);
    response.json({ status: 'ok' });
    } finally {
      try {
        // Never erase a claim by owner alone, and never release on disconnect.
        await releaseSharedDeletion?.();
      } catch {
        // Its durable claim remains fail-closed if release is unconfirmed.
        console.error('Account cleanup claim release failed', { code: 'ACCOUNT_WRITE_DRAIN_FAILED' });
      } finally {
        releaseOwnerMutationLock();
      }
    }
  });
};
