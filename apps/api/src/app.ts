import cors from 'cors';
import express, { type RequestHandler, type ErrorRequestHandler } from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import {
  createSentryErrorMiddleware,
  createSentryRequestMiddleware,
  type MonitoringReporter
} from './monitoring/sentryMonitoring.js';
import type { PrismaClient } from '@prisma/client';
import { registerAdminConsole } from './modules/admin/adminRoutes.js';
import { createPrismaAdminDataSource, type AdminDataSource } from './modules/admin/adminDataSource.js';
import { createPrismaTrialAccessStore } from './modules/admin/prismaTrialAccessStore.js';
import type { AdminAccountDeletionStore } from './modules/admin/adminAccountDeletion.js';
import { createPrismaAdminAccountDeletionStore } from './modules/admin/prismaAdminAccountDeletionStore.js';
import type { TrialAccessStore } from './modules/admin/trialAccess.js';

import { type ServerConfig, readServerConfig } from './config/env.js';
import { createPrismaClient } from './config/prisma.js';
import {
  type PrismaAccountClient,
  registerAccountRoutes
} from './modules/account/accountRoutes.js';
import {
  createOwnerMutationLock,
  type OwnerMutationCoordinator
} from './modules/account/ownerMutationLock.js';
import {
  type AccountIdentityDeleter,
  createFirebaseIdentityDeleterFromConfig
} from './modules/account/firebaseIdentityDeleter.js';
import { registerAnalyticsRoutes } from './modules/analytics/analyticsRoutes.js';
import { registerLinkInBioRoutes } from './modules/linkInBio/linkInBioRoutes.js';
import { createLinkInBioStoreFromConfig } from './modules/linkInBio/linkInBioStoreFactory.js';
import type { LinkInBioStore } from './modules/linkInBio/linkInBioStore.js';
import type { PrismaLinkInBioClient } from './modules/linkInBio/prismaLinkInBioRepository.js';
import { createLinkInBioImageStoreFromConfig, type LinkInBioImageStore, type PrismaLinkInBioImageClient } from './modules/linkInBio/linkInBioImageStore.js';
import { createLinkInBioImageService } from './modules/linkInBio/linkInBioImageService.js';
import { registerLinkInBioImageRoutes } from './modules/linkInBio/linkInBioImageRoutes.js';
import { createAnalyticsStoreFromConfig } from './modules/analytics/analyticsStoreFactory.js';
import type { AnalyticsStore } from './modules/analytics/analyticsStore.js';
import type { PrismaAnalyticsClient } from './modules/analytics/prismaAnalyticsRepository.js';
import { createAuthMiddlewareFromConfig } from './modules/auth/authMiddlewareFactory.js';
import { registerAuthRoutes } from './modules/auth/authRoutes.js';
import { readAuthUser, type AuthUser } from './modules/auth/authTypes.js';
import type { FirebaseTokenVerifier } from './modules/auth/authTypes.js';
import {
  createFirebaseAdminAuth,
  type FirebaseAdminAuth
} from './modules/auth/firebaseAdminAuth.js';
import { createFirebaseAdminTokenVerifier } from './modules/auth/firebaseAdminTokenVerifier.js';
import {
  createFirebaseTokenVerifierFromConfig,
  type FirebaseCertificatesFetch
} from './modules/auth/firebaseTokenVerifier.js';
import { registerBillingRoutes } from './modules/billing/billingRoutes.js';
import { registerRevenueCatRestoreRoutes } from './modules/billing/revenueCatRestoreRoutes.js';
import {
  createRevenueCatSubscriberClient,
  type RevenueCatSubscriberClient
} from './modules/billing/revenueCatSubscriberClient.js';
import { registerRevenueCatWebhookRoutes } from './modules/billing/revenueCatWebhookRoutes.js';
import { createInMemoryMonthlyAddonStore, type MonthlyAddonStore } from './modules/billing/monthlyAddonStore.js';
import { createPrismaMonthlyAddonRepository, type PrismaMonthlyAddonClient } from './modules/billing/prismaMonthlyAddonRepository.js';
import { createRevenueCatAddonPurchaseClient, type RevenueCatAddonPurchaseClient } from './modules/billing/revenueCatAddonPurchaseClient.js';
import { registerAddonRoutes } from './modules/billing/addonRoutes.js';
import type {
  AppleSignedNotificationDecoder
} from './modules/billing/storeNotificationRoutes.js';
import type { StorePurchaseVerifier } from './modules/billing/storePurchaseService.js';
import {
  type CaptionGenerator,
  createCaptionGeneratorFromConfig
} from './modules/captions/captionGeneratorFactory.js';
import { createRealClipCaptionUsageStoreFromConfig } from './modules/captions/captionUsageStoreFactory.js';
import type { RealClipCaptionUsageStore } from './modules/captions/captionUsageStore.js';
import { registerCaptionRoutes } from './modules/captions/captionRoutes.js';
import {
  type RealClipCaptionProvider,
  type RealClipMediaPart,
  createRealClipCaptionProviderFromConfig
} from './modules/captions/realClipCaptionProvider.js';
import type { PrismaRealClipCaptionUsageClient } from './modules/captions/prismaRealClipCaptionUsageRepository.js';
import {
  postCoverUploadPolicy,
  registerPostRoutes
} from './modules/posts/postRoutes.js';
import { buildPlatformTarget, isSamePlatformTarget } from './modules/posts/platformTargets.js';
import type { PrismaPostClient } from './modules/posts/prismaPostRepository.js';
import {
  createInMemoryPlatformPublishStore,
  type PlatformPublishStore
} from './modules/platformPublishes/platformPublishStore.js';
import {
  type PrismaPlatformPublishClient,
  createPrismaPlatformPublishRepository
} from './modules/platformPublishes/prismaPlatformPublishRepository.js';
import { registerAiEditRoutes } from './modules/aiEdits/aiEditRoutes.js';
import { createAiEditUsageStoreFromConfig } from './modules/aiEdits/aiEditUsageStoreFactory.js';
import {
  type EditPlanProvider,
  createEditPlanProviderFromConfig
} from './modules/aiEdits/editPlanProvider.js';
import {
  type VisualEditPlanProvider,
  createVisualEditPlanProviderFromConfig
} from './modules/aiEdits/visualEditPlanProvider.js';
import {
  type SoundEffectPlanProvider,
  createSoundEffectPlanProviderFromConfig
} from './modules/aiEdits/soundEffectPlanProvider.js';
import type { PrismaAiEditUsageClient } from './modules/aiEdits/prismaAiEditUsageRepository.js';
import {
  type FetchAudio,
  type TranscriptionProvider,
  createTranscriptionProviderFromConfig
} from './modules/aiEdits/transcriptionProvider.js';
import { createPostStoreFromConfig } from './modules/posts/postStoreFactory.js';
import { createPublishQueueFromConfig } from './modules/queue/publishQueueFactory.js';
import { createOwnerAwarePublishQueue } from './modules/queue/ownerAwarePublishQueue.js';
import { OwnerOperationBusyError } from './modules/account/ownerOperationQueue.js';
import { createOwnerOperationRouter } from './modules/account/ownerOperationRouter.js';
import { createPlatformPublisherFromConfig } from './workers/platformPublisherFactory.js';
import { createPublishScheduler } from './workers/publishScheduler.js';
import {
  allowsSubscriptionPlanOverride,
  createScheduledPublishPlanReader
} from './workers/scheduledPublishPlan.js';
import { registerPublishQueueRoutes } from './modules/queue/publishQueueRoutes.js';
import {
  MediaDownloadError,
  aiEditAudioDownloadMaxBytes,
  aiMediaDownloadMaxBytes,
  readAiMediaResponseBytes,
  type AiMediaFetchOptions
} from './modules/storage/mediaDownload.js';
import type { S3VideoStorageClient, VideoStorage } from './modules/storage/videoStorage.js';
import { createVideoStorageFromConfig } from './modules/storage/videoStorageFactory.js';
import type { PrismaSubscriptionClient } from './modules/subscriptions/prismaSubscriptionRepository.js';
import { createSubscriptionStoreFromConfig } from './modules/subscriptions/subscriptionStoreFactory.js';
import { registerTemplateRoutes } from './modules/templates/templateRoutes.js';
import type { PrismaTemplateClient } from './modules/templates/prismaTemplateRepository.js';
import { createTemplateStoreFromConfig } from './modules/templates/templateStoreFactory.js';
import { registerUploadRoutes } from './modules/uploads/uploadRoutes.js';
import {
  ManagedUploadServiceError,
  createManagedUploadService,
  type ManagedUploadService
} from './modules/uploads/managedUploadService.js';
import {
  createInMemoryUploadSessionStore,
  UploadSessionConflictError,
  type UploadSessionStore
} from './modules/uploads/uploadSessionStore.js';
import {
  createPrismaUploadSessionRepository,
  type PrismaUploadSessionClient
} from './modules/uploads/prismaUploadSessionRepository.js';
import type { PrismaUserClient } from './modules/users/prismaUserRepository.js';
import { createUserStoreForPostStore } from './modules/users/userStoreFactory.js';
import { registerDeviceRoutes } from './modules/devices/deviceRoutes.js';
import { createDeviceTokenStore } from './modules/devices/deviceTokenStoreFactory.js';
import type { PrismaDeviceTokenClient } from './modules/devices/prismaDeviceTokenRepository.js';
import { createPublishNotifier } from './modules/notifications/publishNotifier.js';
import { createPushSenderFromConfig } from './modules/notifications/pushSenderFactory.js';
import {
  createPostPeerConnectClient,
  type PostPeerConnectClient
} from './modules/socialConnections/postPeerConnectClient.js';
import type { PrismaSocialConnectionClient } from './modules/socialConnections/prismaSocialConnectionRepository.js';
import { registerSocialConnectionRoutes } from './modules/socialConnections/socialConnectionRoutes.js';
import { createPostPeerTikTokClient, TikTokPublishingError, type PostPeerTikTokClient } from './modules/socialConnections/postPeerTikTokClient.js';
import { registerTikTokPublishingOptionsRoutes } from './modules/socialConnections/tikTokPublishingOptionsRoutes.js';
import { registerPublishingReadinessRoutes } from './modules/socialConnections/publishingReadinessRoutes.js';
import type { SocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';
import { createSocialConnectionStore } from './modules/socialConnections/socialConnectionStoreFactory.js';
import { registerPlannedRoutes } from './routes/plannedRoutes.js';
import { createMemoryServiceIncidentStore, type ServiceIncidentStore } from './modules/serviceStatus/serviceIncident.js';
import { createPrismaServiceIncidentStore, type PrismaServiceIncidentClient } from './modules/serviceStatus/prismaServiceIncidentStore.js';
import { registerServiceStatusRoutes } from './modules/serviceStatus/serviceStatusRoutes.js';
import { createMemorySupportChatStore, type SupportChatStore } from './modules/supportChat/supportChat.js';
import { createPrismaSupportChatStore } from './modules/supportChat/prismaSupportChatStore.js';
import { registerSupportChatRoutes } from './modules/supportChat/supportChatRoutes.js';
import { createSupportReplyNotifier } from './modules/notifications/supportReplyNotifier.js';
import { createSupportTeamNotifier } from './modules/notifications/supportTeamNotifier.js';
import type { PushSender } from './modules/notifications/pushSender.js';
import {
  cacheSupportBotSettings, createMemorySupportBotSettingsStore, createPrismaSupportBotSettingsStore, createSupportBot,
  createSupportBotScheduler, type SupportBotSettingsStore
} from './modules/supportBot/supportBot.js';
import {
  createMockSupportBotProvider, createOpenAiSupportBotProvider, type SupportBotProvider
} from './modules/supportBot/supportBotProvider.js';
import type { SupportBotContext } from './modules/supportBot/supportBotKnowledge.js';
import { adminPublishFailure } from './modules/admin/adminPublishFailure.js';
import { createSentrySignalSource, type SentrySignalSource } from './monitoring/sentrySignals.js';
import { createRateLimitMiddleware } from './modules/security/rateLimit.js';
import { createReadinessHandler } from './readiness.js';

type AppPrismaClient = PrismaTemplateClient &
  PrismaPostClient &
  PrismaUserClient &
  PrismaSubscriptionClient &
  PrismaAnalyticsClient &
  PrismaRealClipCaptionUsageClient &
  PrismaAiEditUsageClient &
  PrismaDeviceTokenClient &
  PrismaSocialConnectionClient &
  PrismaUploadSessionClient &
  // The shared client's $transaction is typed by the stores above.
  Partial<Omit<PrismaLinkInBioClient, '$transaction'> & PrismaLinkInBioImageClient>;

type AppOptions = {
  adminDataSource?: AdminDataSource;
  trialAccessStore?: TrialAccessStore;
  adminAccountDeletionStore?: AdminAccountDeletionStore;
  adminFirebaseVerifier?: FirebaseTokenVerifier;
  adminTestPreviewToken?: string;
  config?: ServerConfig;
  monitoringReporter?: MonitoringReporter;
  prisma?: AppPrismaClient;
  s3Client?: S3VideoStorageClient;
  r2Client?: S3VideoStorageClient;
  firebaseVerifier?: FirebaseTokenVerifier;
  accountDeletionFirebaseVerifier?: FirebaseTokenVerifier;
  firebaseCertsFetch?: FirebaseCertificatesFetch;
  analyticsStore?: AnalyticsStore;
  linkInBioStore?: LinkInBioStore;
  linkInBioImageStore?: LinkInBioImageStore;
  captionGenerator?: CaptionGenerator;
  realClipCaptionUsageStore?: RealClipCaptionUsageStore;
  realClipCaptionProvider?: RealClipCaptionProvider;
  fetchClipMedia?: (videoS3Key: string, options?: AiMediaFetchOptions) => Promise<RealClipMediaPart>;
  maxConcurrentAiMediaRequests?: number;
  transcriptionProvider?: TranscriptionProvider;
  editPlanProvider?: EditPlanProvider;
  soundEffectPlanProvider?: SoundEffectPlanProvider;
  visualEditPlanProvider?: VisualEditPlanProvider;
  storePurchaseVerifier?: StorePurchaseVerifier;
  revenueCatSubscriberClient?: RevenueCatSubscriberClient;
  monthlyAddonStore?: MonthlyAddonStore;
  revenueCatAddonPurchaseClient?: RevenueCatAddonPurchaseClient;
  appleSignedNotificationDecoder?: AppleSignedNotificationDecoder;
  socialConnectionStore?: SocialConnectionStore;
  postPeerConnectClient?: PostPeerConnectClient;
  postPeerTikTokClient?: PostPeerTikTokClient;
  videoStorage?: VideoStorage;
  firebaseAdminAuth?: FirebaseAdminAuth;
  accountIdentityDeleter?: AccountIdentityDeleter;
  platformPublishStore?: PlatformPublishStore;
  uploadSessionStore?: UploadSessionStore;
  managedUploadService?: ManagedUploadService;
  ownerMutationLock?: OwnerMutationCoordinator;
  serviceIncidentStore?: ServiceIncidentStore;
  supportChatStore?: SupportChatStore;
  supportPushSender?: PushSender;
  supportBotProvider?: SupportBotProvider;
  supportBotSettingsStore?: SupportBotSettingsStore;
  sentrySignalSource?: SentrySignalSource;
  now?: () => Date;
};

const readFileNameFromStorageKey = (videoS3Key: string) =>
  videoS3Key.split('/').filter(Boolean).at(-1) ?? 'clip.mp4';

export const createAccountAwareAuthMiddleware = ({
  authMiddleware,
  managedUploadService,
  ownerMutationLock,
  assertOwnerActive
}: {
  authMiddleware: RequestHandler;
  managedUploadService?: ManagedUploadService;
  ownerMutationLock?: OwnerMutationCoordinator;
  assertOwnerActive?: (ownerId: string) => Promise<void>;
}): RequestHandler => {
  if (!managedUploadService && !ownerMutationLock && !assertOwnerActive) {
    return authMiddleware;
  }

  return (request, response, next) => {
    authMiddleware(request, response, (authError?: unknown) => {
      if (authError) {
        next(authError);
        return;
      }

      // Match Express's default case-insensitive, non-strict route behavior.
      // Alternate spellings must retain the same deletion/write boundary.
      const normalizedPath = request.path.toLowerCase().replace(/\/+$/, '');
      const mutatingReadRoute =
        (request.method === 'GET' || request.method === 'HEAD') &&
        (normalizedPath === '/social-connections' ||
          normalizedPath === '/billing/subscription' ||
          /^\/uploads\/[^/]+$/.test(normalizedPath));
      if (
        !mutatingReadRoute &&
        (request.method === 'GET' || request.method === 'HEAD' || request.method === 'OPTIONS')
      ) {
        next();
        return;
      }

      const authUser = readAuthUser(response.locals);

      if (!authUser) {
        next();
        return;
      }

      void (async () => {
        const releaseOwner = ownerMutationLock
          ? await ownerMutationLock.acquireMutation(authUser.id)
          : () => undefined;
        let released = false;
        const releaseOnce = () => {
          if (!released) {
            released = true;
            releaseOwner();
          }
        };

        try {
          if (ownerMutationLock && !ownerMutationLock.isActive(authUser.id)) {
            throw new ManagedUploadServiceError(
              409,
              'ACCOUNT_DELETION_IN_PROGRESS',
              'Account deletion is in progress. New mutations are disabled.'
            );
          }
          if (assertOwnerActive) {
            await assertOwnerActive(authUser.id);
          } else {
            await managedUploadService?.assertOwnerActive(authUser.id);
          }
          const originalEnd = response.end;
          response.end = function (this: typeof response, ...args: unknown[]) {
            try {
              return originalEnd.apply(this, args as never);
            } finally {
              // `close` may fire as soon as the client disconnects while an
              // async route is still writing durable state. `end` is the
              // handler completion boundary even when the socket is gone.
              releaseOnce();
            }
          } as typeof response.end;
          response.once('finish', releaseOnce);
          next();
        } catch (error) {
          releaseOnce();
          throw error;
        }
      })().catch((error: unknown) => {
        if (error instanceof ManagedUploadServiceError) {
          response.status(error.statusCode).json({
            status: 'error',
            code: error.code,
            message: error.message
          });
          return;
        }
        if (error instanceof UploadSessionConflictError) {
          response.status(409).json({ status: 'error', code: error.code, message: error.message });
          return;
        }

        next(error);
      });
    });
  };
};

const createFetchAudioFromVideoStorage =
  (videoStorage: VideoStorage): FetchAudio =>
  async ({ mediaS3Key, mediaKind }) => {
    const access = await videoStorage.createDownloadAccess(mediaS3Key);

    if (access.accessType !== 'signed-url' || !access.downloadUrl) {
      throw new Error('Signed media download access is required for real transcription');
    }

    const response = await fetch(access.downloadUrl);

    if (!response.ok) {
      throw new Error(`Media download failed with status ${response.status}`);
    }

    const responseContentType = response.headers.get('content-type');
    const normalizedContentType = responseContentType?.split(';', 1)[0]?.trim().toLowerCase();

    if (mediaKind === 'audio' && normalizedContentType !== 'audio/mp4') {
      throw new MediaDownloadError(
        'AI edit audio must use the audio/mp4 content type',
        415,
        'AI_EDIT_AUDIO_CONTENT_TYPE_INVALID'
      );
    }

    const maxBytes =
      mediaKind === 'audio' ? aiEditAudioDownloadMaxBytes : aiMediaDownloadMaxBytes;

    return {
      data: await readAiMediaResponseBytes(response, maxBytes),
      filename: readFileNameFromStorageKey(mediaS3Key),
      contentType: mediaKind === 'audio' ? 'audio/mp4' : (responseContentType ?? 'video/mp4')
    };
  };

// Downloads a stored object (clip or frame) as bytes + mime, for sending to a
// multimodal caption provider (Gemini).
export const createFetchMediaFromVideoStorage =
  (videoStorage: VideoStorage, fetchImpl: typeof fetch = fetch) =>
  async (videoS3Key: string, mediaOptions?: AiMediaFetchOptions): Promise<RealClipMediaPart> => {
    const access = await videoStorage.createDownloadAccess(videoS3Key);

    if (access.accessType !== 'signed-url' || !access.downloadUrl) {
      throw new Error('Signed download access is required for real-clip captioning');
    }

    const response = await fetchImpl(access.downloadUrl);

    if (!response.ok) {
      throw new Error(`Media download failed with status ${response.status}`);
    }

    const contentType = response.headers.get('content-type');

    if (mediaOptions?.kind === 'frame' && !contentType?.trim().toLowerCase().startsWith('image/')) {
      await response.body?.cancel().catch(() => undefined);
      throw new MediaDownloadError(
        'AI caption frames must be images',
        415,
        'AI_CAPTION_FRAME_INVALID'
      );
    }

    if (
      mediaOptions?.kind === 'audio' &&
      contentType?.split(';', 1)[0]?.trim().toLowerCase() !== 'audio/mp4'
    ) {
      await response.body?.cancel().catch(() => undefined);
      throw new MediaDownloadError(
        'AI caption audio must use the audio/mp4 content type',
        415,
        'AI_CAPTION_MEDIA_TYPE_INVALID'
      );
    }

    return {
      data: await readAiMediaResponseBytes(response, mediaOptions?.maxBytes),
      mimeType: contentType ?? 'video/mp4'
    };
  };

export const createApp = (options: AppOptions = {}) => {
  const config = options.config ?? readServerConfig();
  const app = express();

  // Render terminates TLS at a single proxy layer; trust it so req.ip (and the
  // per-IP rate limit key) is the real client address, not the proxy's.
  app.set('trust proxy', 1);
  app.use(createSentryRequestMiddleware(options.monitoringReporter));
  app.use(helmet());
  app.use(cors());
  app.use(
    rateLimit({
      windowMs: config.rateLimitWindowMs,
      limit: config.rateLimitMaxRequests,
      standardHeaders: true,
      legacyHeaders: false,
      skip: (request) => request.path === '/health',
      handler: (_request, response) => {
        response.status(429).json({
          status: 'error',
          code: 'RATE_LIMITED',
          message: 'Too many requests. Please try again shortly.'
        });
      }
    })
  );
  app.use(
    express.json({
      limit: '1mb',
      verify: (request, _response, buffer) => {
        (request as express.Request & { rawBody?: string }).rawBody = buffer.toString('utf8');
      }
    })
  );

  app.get('/health', (_request, response) => {
    response.json({
      status: 'ok',
      service: 'postdee-api'
    });
  });

  let router = express.Router();
  const ownerMutationLock = options.ownerMutationLock ?? createOwnerMutationLock();
  const authRateLimit = createRateLimitMiddleware({
    bucket: 'auth',
    windowMs: 10 * 60 * 1000,
    maxRequests: 30
  });
  const uploadRateLimit = createRateLimitMiddleware({
    bucket: 'uploads',
    windowMs: 60 * 60 * 1000,
    maxRequests: 60
  });
  const aiRateLimit = createRateLimitMiddleware({
    bucket: 'ai',
    windowMs: 60 * 60 * 1000,
    maxRequests: 60
  });
  const socialConnectionRateLimit = createRateLimitMiddleware({
    bucket: 'social-connections',
    windowMs: 10 * 60 * 1000,
    maxRequests: 20
  });
  const revenueCatResyncRateLimit = createRateLimitMiddleware({
    bucket: 'revenuecat-resync',
    windowMs: 10 * 60 * 1000,
    maxRequests: 10
  });
  if (config.adminConsole && (!config.trialAccessEnabled || config.authProvider !== 'firebase')) {
    throw new Error('Administrator access requires Firebase and enabled trial access');
  }
  if ((config.adminConsole || config.authProvider === 'firebase') && config.firebaseServiceAccountJson &&
      JSON.parse(config.firebaseServiceAccountJson).project_id !== config.firebaseProjectId) {
    throw new Error('Firebase service account must match the API Firebase project');
  }
  // Whenever an Admin key is available, verify tokens through Firebase Admin so
  // revoked or disabled accounts are rejected, not only when deletion is on.
  const shouldCreateFirebaseAdminAuth = Boolean(config.adminConsole) ||
    (config.authProvider === 'firebase' && !options.firebaseVerifier) ||
    (config.firebaseAuthDeleteEnabled && (!options.firebaseVerifier || !options.accountIdentityDeleter));
  const firebaseAdminAuth =
    options.firebaseAdminAuth ??
    (shouldCreateFirebaseAdminAuth && config.firebaseServiceAccountJson
      ? createFirebaseAdminAuth({
          serviceAccountJson: config.firebaseServiceAccountJson
        })
      : undefined);
  const firebaseVerifier =
    options.firebaseVerifier ??
    (firebaseAdminAuth
      ? createFirebaseAdminTokenVerifier(firebaseAdminAuth)
      : createFirebaseTokenVerifierFromConfig({
          config,
          fetchCertificates: options.firebaseCertsFetch
        }));
  const authMiddleware = createAuthMiddlewareFromConfig({
    config,
    firebaseVerifier
  });
  const accountDeletionFirebaseVerifier =
    options.accountDeletionFirebaseVerifier ??
    (firebaseAdminAuth
      ? createFirebaseAdminTokenVerifier(firebaseAdminAuth, {
          allowDeletedIdentityRetry: true
        })
      : firebaseVerifier);
  const accountDeletionAuthMiddleware = createAuthMiddlewareFromConfig({
    config,
    firebaseVerifier: accountDeletionFirebaseVerifier
  });
  const requiresPrismaClient =
    (config.trialAccessEnabled && !options.trialAccessStore) ||
    config.templateStore === 'prisma' ||
    config.postStore === 'prisma' ||
    config.subscriptionStore === 'prisma' ||
    config.analyticsStore === 'prisma' ||
    config.captionUsageStore === 'prisma' ||
    config.aiEditUsageStore === 'prisma' ||
    (config.uploadProtocolMode !== 'legacy' &&
      !options.managedUploadService &&
      !options.uploadSessionStore);
  const prismaClient =
    options.prisma ??
    (requiresPrismaClient ? createPrismaClient() : undefined);
  // The owner tombstone must remain available even with legacy uploads.
  const uploadSessionStore =
    options.uploadSessionStore ??
    (prismaClient
      ? createPrismaUploadSessionRepository({ prisma: prismaClient as unknown as PrismaUploadSessionClient })
      : createInMemoryUploadSessionStore());
  const runWithActiveOwner = uploadSessionStore.runWithActiveOwner;
  const runWithOwnerLifetime = uploadSessionStore.runWithOwnerLifetime;
  router = createOwnerOperationRouter(router, runWithOwnerLifetime);
  const monthlyAddonStore = options.monthlyAddonStore ?? (prismaClient
    ? createPrismaMonthlyAddonRepository({ prisma: prismaClient as unknown as PrismaMonthlyAddonClient })
    : createInMemoryMonthlyAddonStore({ runWithActiveOwner }));
  const postStore = createPostStoreFromConfig({
    config,
    prisma: prismaClient as unknown as PrismaPostClient | undefined,
    runWithActiveOwner,
    monthlyAddonStore
  });
  const userStore = createUserStoreForPostStore({
    config,
    prisma: prismaClient,
    runWithActiveOwner
  });
  const trialAccessStore = config.trialAccessEnabled
    ? options.trialAccessStore ?? createPrismaTrialAccessStore(prismaClient as unknown as PrismaClient, options.now)
    : undefined;
  const subscriptionStore = createSubscriptionStoreFromConfig({
    config,
    prisma: prismaClient,
    runWithActiveOwner,
    trialStore: trialAccessStore,
    now: options.now
  });
  const publishQueue = createOwnerAwarePublishQueue(createPublishQueueFromConfig({ config }), runWithActiveOwner);
  const platformPublishStore =
    options.platformPublishStore ??
    (config.postStore === 'prisma' && prismaClient
      ? createPrismaPlatformPublishRepository({
          prisma: prismaClient as unknown as PrismaPlatformPublishClient
        })
      : createInMemoryPlatformPublishStore());
  const socialConnectionStore =
    options.socialConnectionStore ??
    createSocialConnectionStore({
      prisma: prismaClient
        ? (prismaClient as unknown as PrismaSocialConnectionClient)
        : undefined
    });
  const captionGenerator =
    options.captionGenerator ?? createCaptionGeneratorFromConfig({ config });
  const postPeerTikTokClient = options.postPeerTikTokClient ?? createPostPeerTikTokClient({
    apiKey: config.postPeerApiKey, baseUrl: config.postPeerApiBaseUrl
  });
  const realClipCaptionUsageStore =
    options.realClipCaptionUsageStore ??
    createRealClipCaptionUsageStoreFromConfig({
      config,
      monthlyAddonStore,
      runWithActiveOwner,
      prisma: prismaClient as unknown as PrismaRealClipCaptionUsageClient | undefined
    });
  const videoStorage =
    options.videoStorage ??
    createVideoStorageFromConfig({
      config,
      s3Client: options.s3Client,
      r2Client: options.r2Client
    });
  const managedUploadService =
    options.managedUploadService ??
    (videoStorage.multipart
      ? createManagedUploadService({
          storage: videoStorage.multipart,
          store: uploadSessionStore,
          partSizeBytes: config.multipartUploadPartSizeBytes,
          sessionExpiresSeconds: config.multipartUploadSessionExpiresSeconds
        })
      : undefined);

  if (config.uploadProtocolMode !== 'legacy' && !managedUploadService) {
    throw new Error(
      'UPLOAD_PROTOCOL_MODE requires multipart-capable object storage'
    );
  }
  const assertOwnerActive = async (ownerId: string) => {
    if (!ownerMutationLock.isActive(ownerId)) {
      throw new ManagedUploadServiceError(
        409,
        'ACCOUNT_DELETION_IN_PROGRESS',
        'Account deletion is in progress. New mutations are disabled.'
      );
    }
    await uploadSessionStore.assertOwnerActive(ownerId);
    await managedUploadService?.assertOwnerActive(ownerId);
  };
  const accountAwareAuthMiddleware = createAccountAwareAuthMiddleware({
    authMiddleware,
    managedUploadService,
    ownerMutationLock,
    assertOwnerActive
  });
  const transcriptionProvider =
    options.transcriptionProvider ??
    createTranscriptionProviderFromConfig({
      config,
      fetchAudio: createFetchAudioFromVideoStorage(videoStorage)
    });
  const templateStore = createTemplateStoreFromConfig({
    config,
    prisma: prismaClient
  });
  const analyticsStore =
    options.analyticsStore ??
    createAnalyticsStoreFromConfig({
      config,
      prisma: prismaClient as unknown as PrismaAnalyticsClient | undefined
    });
  const linkInBioStore = options.linkInBioStore ?? createLinkInBioStoreFromConfig({
    config,
    prisma: prismaClient as unknown as Partial<PrismaLinkInBioClient> | undefined,
    now: options.now
  });
  const linkInBioImageStore = options.linkInBioImageStore ?? createLinkInBioImageStoreFromConfig({
    postStore: config.postStore,
    prisma: prismaClient as unknown as Partial<PrismaLinkInBioImageClient> | undefined
  });
  const linkInBioImages = createLinkInBioImageService({
    store: linkInBioImageStore, storage: videoStorage, profiles: linkInBioStore, now: options.now
  });
  router.use('/auth', authRateLimit);
  router.use('/uploads', uploadRateLimit);
  router.use('/captions', aiRateLimit);
  router.use('/ai-edits', aiRateLimit);
  router.use('/social-connections', socialConnectionRateLimit);
  router.use('/billing/revenuecat/resync', revenueCatResyncRateLimit);

  registerAuthRoutes(router, accountAwareAuthMiddleware);
  registerUploadRoutes(router, accountAwareAuthMiddleware, videoStorage, {
    uploadMaxSizeBytes: config.uploadMaxSizeBytes,
    uploadProtocolMode: config.uploadProtocolMode,
    managedUploadService
  });
  const fetchClipMedia =
    options.fetchClipMedia ?? createFetchMediaFromVideoStorage(videoStorage);
  registerCaptionRoutes(
    router,
    captionGenerator,
    accountAwareAuthMiddleware,
    subscriptionStore,
    transcriptionProvider,
    realClipCaptionUsageStore,
    options.realClipCaptionProvider ??
      createRealClipCaptionProviderFromConfig({ config }),
    fetchClipMedia,
    videoStorage.deleteVideo,
    userStore,
    {
      monthlyAddonStore,
      billingAddonsEnabled: config.billingAddonsEnabled,
      now: options.now,
      maxConcurrentMediaRequests: options.maxConcurrentAiMediaRequests
    }
  );
  // Account deletion still clears historical AI-edit usage rows.
  const aiEditUsageStore = createAiEditUsageStoreFromConfig({
    config,
    prisma: prismaClient
  });
  if (config.aiEditingEnabled) {
    const editPlanProvider =
      options.editPlanProvider ?? createEditPlanProviderFromConfig({ config });
    const soundEffectPlanProvider =
      options.soundEffectPlanProvider ??
      createSoundEffectPlanProviderFromConfig({ config });
    const visualEditPlanProvider =
      options.visualEditPlanProvider ??
      createVisualEditPlanProviderFromConfig({ config });
    registerAiEditRoutes(
      router,
      transcriptionProvider,
      accountAwareAuthMiddleware,
      subscriptionStore,
      aiEditUsageStore,
      editPlanProvider,
      soundEffectPlanProvider,
      videoStorage.deleteVideo,
      visualEditPlanProvider,
      fetchClipMedia,
      userStore
    );
  } else {
    // AI video editing was removed from the app. Answer every legacy route
    // without reaching paid transcription or planning providers.
    router.use('/ai-edits', (_request, response) => {
      response.status(410).json({
        status: 'error',
        code: 'AI_EDITING_RETIRED',
        message: 'AI video editing is no longer available.'
      });
    });
  }
  registerPostRoutes(
    router,
    postStore,
    publishQueue,
    accountAwareAuthMiddleware,
    userStore,
    subscriptionStore,
    platformPublishStore,
    {
      allowSubscriptionPlanOverride: allowsSubscriptionPlanOverride(config),
      monthlyAddonStore,
      billingAddonsEnabled: config.billingAddonsEnabled,
      socialPublishingEnabled: config.socialPublisher !== 'disabled',
      assertOwnerActive,
      runWithOwnerLifetime,
      resolvePlatformTarget:
        config.socialPublisher === 'postpeer'
          ? async ({ userId, platform }) => {
              const connection = await socialConnectionStore.getConnection({
                userId,
                platform
              });
              return connection ? buildPlatformTarget(connection) : undefined;
            }
          : undefined,
      resolveTikTokCreatorInfo: async ({ userId, target }) => {
        const connection = await socialConnectionStore.getConnection({ userId, platform: 'TIKTOK' });
        if (!connection || !isSamePlatformTarget(target, buildPlatformTarget(connection))) {
          throw new TikTokPublishingError(
            'TIKTOK_CONNECTION_CHANGED', 409, 'The connected TikTok account changed. Review the post again.'
          );
        }
        return postPeerTikTokClient.getCreatorInfo({ accountId: connection.postPeerAccountId });
      },
      assertUploadReady: managedUploadService
        ? (ownerId, videoS3Key) =>
            managedUploadService.assertReadyForUse(ownerId, videoS3Key, {
              allowLegacy: config.uploadProtocolMode !== 'multipart'
            })
        : undefined,
      assertCoverUploadReady: managedUploadService
        ? (ownerId, coverImageS3Key) =>
            managedUploadService.assertReadyForUse(ownerId, coverImageS3Key, {
              allowLegacy: config.uploadProtocolMode === 'legacy',
              acceptedContentTypes: postCoverUploadPolicy.acceptedContentTypes,
              maxSizeBytes: postCoverUploadPolicy.maxSizeBytes
            })
        : undefined,
      createMediaDownloadUrl: async (storageKey) => {
        const access = await videoStorage.createDownloadAccess(storageKey);
        return access.accessType === 'signed-url' ? access.downloadUrl : undefined;
      },
      now: options.now
    }
  );
  registerPublishQueueRoutes(router, accountAwareAuthMiddleware, publishQueue);
  registerTemplateRoutes(router, accountAwareAuthMiddleware, templateStore, userStore);
  registerLinkInBioRoutes(router, accountAwareAuthMiddleware, linkInBioStore, userStore, {
    subscriptionStore,
    withImageMutation: linkInBioImages.withOwnerLock,
    validateImages: linkInBioImages.validateImages,
    onPublished: async (userId) => linkInBioImages.prune(userId)
  });
  registerLinkInBioImageRoutes(router, accountAwareAuthMiddleware, linkInBioImages, linkInBioStore, userStore, uploadRateLimit);
  registerAnalyticsRoutes(
    router,
    accountAwareAuthMiddleware,
    subscriptionStore,
    analyticsStore
  );
  registerBillingRoutes(
    router,
    accountAwareAuthMiddleware,
    userStore,
    subscriptionStore,
    postStore,
    {
      config,
      monthlyAddonStore,
      billingAddonsEnabled: config.billingAddonsEnabled,
      realClipCaptionUsageStore,
      storePurchaseVerifier: options.storePurchaseVerifier,
      now: options.now,
      appleSignedNotificationDecoder: options.appleSignedNotificationDecoder
    }
  );
  const revenueCatSubscriberClient =
    options.revenueCatSubscriberClient ??
    createRevenueCatSubscriberClient({
      apiKey: config.revenueCatRestApiV1Key
    });
  registerRevenueCatRestoreRoutes({
    router,
    authMiddleware: accountAwareAuthMiddleware,
    config,
    subscriberClient: revenueCatSubscriberClient,
    userStore,
    subscriptionStore,
    assertOwnerActive,
    ownerMutationLock
  });
  registerRevenueCatWebhookRoutes({
    router,
    config,
    subscriberClient: revenueCatSubscriberClient,
    userStore,
    subscriptionStore,
    ownerMutationLock,
    monthlyAddonStore
  });
  registerAddonRoutes({ router, authMiddleware: accountAwareAuthMiddleware, config, userStore,
    subscriptionStore, monthlyAddonStore, postStore, captionUsageStore: realClipCaptionUsageStore, now: options.now,
    purchaseClient: options.revenueCatAddonPurchaseClient ?? createRevenueCatAddonPurchaseClient({ apiKey: config.revenueCatRestApiV1Key }) });
  const deviceTokenStore = createDeviceTokenStore({
    prisma: prismaClient
      ? (prismaClient as unknown as PrismaDeviceTokenClient)
      : undefined
  });
  const postPeerConnectClient =
    options.postPeerConnectClient ??
    createPostPeerConnectClient({
      apiKey: config.postPeerApiKey,
      baseUrl: config.postPeerApiBaseUrl,
      legacyRecovery:
        config.postPeerLegacyRecoveryFingerprint &&
        config.postPeerLegacyRecoveryProfileId
          ? {
              fingerprint: config.postPeerLegacyRecoveryFingerprint,
              profileId: config.postPeerLegacyRecoveryProfileId
            }
          : undefined
    });
  registerDeviceRoutes(
    router,
    accountAwareAuthMiddleware,
    deviceTokenStore,
    userStore
  );
  const serviceIncidentStore =
    options.serviceIncidentStore ??
    (prismaClient
      ? createPrismaServiceIncidentStore(prismaClient as unknown as PrismaServiceIncidentClient, options.now)
      : createMemoryServiceIncidentStore({ now: options.now }));
  registerServiceStatusRoutes(router, { store: serviceIncidentStore, now: options.now });
  const supportChatStore =
    options.supportChatStore ??
    (prismaClient
      ? createPrismaSupportChatStore(prismaClient as unknown as PrismaClient, options.now)
      : createMemorySupportChatStore({ now: options.now }));
  // Dot, the AI support helper. It needs SUPPORT_BOT_PROVIDER and an owner's
  // switch in the admin console; until then it never answers.
  const supportBotProvider =
    options.supportBotProvider ??
    (config.supportBotProvider === 'openai'
      ? createOpenAiSupportBotProvider({ apiKey: config.openAiApiKey!, model: config.openAiSupportBotModel })
      : config.supportBotProvider === 'mock' ? createMockSupportBotProvider() : undefined);
  const supportBotSettings = cacheSupportBotSettings(
    options.supportBotSettingsStore ??
      (prismaClient
        ? createPrismaSupportBotSettingsStore(prismaClient as unknown as PrismaClient, options.now)
        : createMemorySupportBotSettingsStore({ now: options.now }))
  );
  const sentrySignalSource = options.sentrySignalSource ?? createSentrySignalSource({ config: config.sentrySignals, now: options.now });
  // Only what Dot needs: open notices, Sentry areas with recent errors (fixed
  // labels, never error text), the plan, and the last five posts' statuses with
  // translated failure reasons. No captions or contact details.
  const loadSupportBotContext = async (member: AuthUser): Promise<Omit<SupportBotContext, 'teamAlreadyNotified'>> => {
    const [incidents, signals, posts, plan] = await Promise.all([
      serviceIncidentStore.active(),
      sentrySignalSource.read().catch(() => undefined),
      postStore.list({ userId: member.id, limit: 5 }),
      subscriptionStore.getPlan(member).catch(() => undefined)
    ]);
    const publishes = posts.length && platformPublishStore.listForPostIds
      ? await platformPublishStore.listForPostIds(posts.map((post) => post.id))
      : [];
    return {
      plan,
      incidents: incidents.map(({ title, message, platforms, stage }) => ({ title, message, platforms, stage })),
      automaticSignals: (signals?.signals ?? []).map(({ label, lastSeen }) => ({ area: label, lastSeen })),
      recentPosts: posts.map((post) => ({
        createdAt: post.createdAt,
        ...(post.scheduledAt ? { scheduledAt: post.scheduledAt } : {}),
        status: post.status,
        platforms: post.platforms,
        failures: publishes
          .filter((publish) => publish.postId === post.id && publish.status === 'FAILED')
          .map((publish) => `${publish.platform}: ${adminPublishFailure(publish.errorMessage ?? null)}`)
      }))
    };
  };
  const supportBotScheduler = createSupportBotScheduler(
    createSupportBot({
      store: supportChatStore,
      settings: supportBotSettings,
      provider: supportBotProvider,
      loadContext: loadSupportBotContext,
      runWithOwner: runWithOwnerLifetime,
      now: options.now
    }),
    { onError: (error) => console.warn('Support bot reply failed', error instanceof Error ? error.name : 'unknown') }
  );
  app.locals.supportBotScheduler = supportBotScheduler;
  // Created on the first support push, so a misconfigured sender cannot stop boot.
  let supportPushSender = options.supportPushSender;
  const lazySupportPushSender: PushSender = {
    send: message => (supportPushSender ??= createPushSenderFromConfig({ config })).send(message)
  };
  const notifySupportReply = createSupportReplyNotifier({ deviceTokenStore, pushSender: lazySupportPushSender });
  const notifySupportTeam = config.adminConsole ? createSupportTeamNotifier({
    deviceTokenStore, pushSender: lazySupportPushSender,
    adminUserIds: [...config.adminConsole.ownerUids, ...config.adminConsole.viewerUids]
  }) : undefined;
  registerSupportChatRoutes(router, accountAwareAuthMiddleware, {
    store: supportChatStore,
    userStore,
    notifySupportTeam,
    sendRateLimit: createRateLimitMiddleware({ bucket: 'support-chat', windowMs: 60_000, maxRequests: 20 }),
    bot: {
      available: async () => Boolean(supportBotProvider) && (await supportBotSettings.read()).enabled,
      onMemberMessage: supportBotScheduler.schedule
    }
  });
  registerSocialConnectionRoutes(router, accountAwareAuthMiddleware, {
    store: socialConnectionStore,
    connectClient: postPeerConnectClient,
    userStore
  });
  registerTikTokPublishingOptionsRoutes(router, accountAwareAuthMiddleware, {
    store: socialConnectionStore, client: postPeerTikTokClient,
    assertOwnerActive, runWithOwnerLifetime
  });
  registerPublishingReadinessRoutes(router, accountAwareAuthMiddleware, {
    store: socialConnectionStore, client: postPeerConnectClient,
    assertOwnerActive, runWithOwnerLifetime, now: options.now
  });
  const accountRoutes = registerAccountRoutes(router, accountDeletionAuthMiddleware, {
    monthlyAddonStore,
    postStore,
    templateStore,
    subscriptionStore,
    analyticsStore,
    realClipCaptionUsageStore,
    aiEditUsageStore,
    deviceTokenStore,
    supportChatStore,
    linkInBioStore,
    linkInBioImageStore,
    socialConnectionStore,
    postPeerConnectClient,
    userStore,
    publishQueue,
    platformPublishStore,
    videoStorage,
    managedUploadService,
    ownerMutationLock,
    ownerLifecycleStore: uploadSessionStore,
    accountIdentityDeleter:
      options.accountIdentityDeleter ??
      createFirebaseIdentityDeleterFromConfig({
        config,
        firebaseAuth: firebaseAdminAuth
      }),
    prisma: prismaClient
      ? (prismaClient as unknown as PrismaAccountClient)
      : undefined
  });
  if (config.adminConsole) {
    const adminVerifier = options.adminFirebaseVerifier ??
      (firebaseAdminAuth ? createFirebaseAdminTokenVerifier(firebaseAdminAuth) : undefined);
    if (!adminVerifier) throw new Error('Admin console requires revocation-checked Firebase Admin authentication');
    registerAdminConsole(app, {
      config: config.adminConsole,
      authenticate: createAuthMiddlewareFromConfig({ config, firebaseVerifier: adminVerifier }),
      trials: trialAccessStore,
      data: options.adminDataSource ?? createPrismaAdminDataSource(prismaClient as unknown as PrismaClient, config.adminConsole, options.now),
      now: options.now, runWithTarget: runWithOwnerLifetime, incidents: serviceIncidentStore,
      support: supportChatStore, notifySupportReply, signals: sentrySignalSource,
      supportBot: { provider: supportBotProvider?.kind ?? 'off', settings: supportBotSettings },
      accountDeletions: options.adminAccountDeletionStore ??
        (prismaClient ? createPrismaAdminAccountDeletionStore(prismaClient as unknown as PrismaClient, options.now) : undefined),
      deleteAccount: accountRoutes.deleteAccountAsOperator,
      testOnly: config.nodeEnv === 'test', testPreviewToken: options.adminTestPreviewToken
    });
  }
  registerPlannedRoutes(router);
  app.use(router);

  // In-memory queue has no external worker, so attach an in-process scheduler.
  // It is created but NOT started here; server.ts starts it so tests that only
  // build the app never leave a timer running. (BullMQ uses a separate worker.)
  if (config.publishQueue === 'memory') {
    app.locals.publishScheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      publisher: createPlatformPublisherFromConfig({
        config,
        videoStorage,
        socialConnectionStore,
        assertOwnerActive
      }),
      storage: videoStorage,
      // Push a publish-result notification to the user's devices. Uses the real
      // FCM sender when PUSH_SENDER=firebase, otherwise a no-op mock.
      notifier: createPublishNotifier({
        deviceTokenStore,
        pushSender: createPushSenderFromConfig({ config })
      }),
      assertOwnerActive,
      runWithActiveOwner: runWithOwnerLifetime,
      ...(managedUploadService
        ? { sweepExpiredUploads: () => managedUploadService.sweepExpiredSessions() }
        : {}),
      readOwnerPlan: createScheduledPublishPlanReader({ config, subscriptionStore }),
      requireEmptyBacklogOnStart:
        config.socialPublisher === 'postpeer' &&
        config.socialPublishRequireEmptyBacklog,
      onPostSettled: (postId) => publishQueue.remove(postId)
    });
  }

  const operationalPrisma = prismaClient as unknown as {
    $queryRawUnsafe?: (query: string) => Promise<unknown>;
    $disconnect?: () => Promise<void>;
  } | undefined;
  app.get('/ready', createReadinessHandler({
    database: async () => {
      if (!operationalPrisma) return;
      if (!operationalPrisma.$queryRawUnsafe) {
        throw new Error('Database probe unavailable');
      }
      await operationalPrisma.$queryRawUnsafe('SELECT 1');
    },
    queue: async () => {
      if (config.publishQueue === 'bullmq') {
        await publishQueue.checkReady();
      } else {
        await app.locals.publishScheduler.checkReady();
      }
    },
    isShuttingDown: () => app.locals.shuttingDown === true
  }));
  app.locals.closeResources = async () => {
    const results = await Promise.allSettled([
      Promise.resolve().then(() => publishQueue.close()),
      Promise.resolve().then(() => operationalPrisma?.$disconnect?.())
    ]);
    if (results.some((result) => result.status === 'rejected')) {
      throw new Error('API resource shutdown failed');
    }
  };

  const handleOwnerLifecycleError: ErrorRequestHandler = (error, _request, response, next) => {
    if (response.headersSent) { next(error); return; }
    if (error instanceof UploadSessionConflictError || error instanceof OwnerOperationBusyError) {
      response.status(error instanceof UploadSessionConflictError ? 409 : 503)
        .json({ status: 'error', code: error.code, message: error.message });
      return;
    }
    next(error);
  };
  app.use(handleOwnerLifecycleError);
  app.use(createSentryErrorMiddleware(options.monitoringReporter));
  return app;
};
