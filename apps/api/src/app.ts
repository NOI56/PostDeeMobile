import cors from 'cors';
import express, { type RequestHandler } from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';

import { type ServerConfig, readServerConfig } from './config/env.js';
import { createPrismaClient } from './config/prisma.js';
import {
  type PrismaAccountClient,
  registerAccountRoutes
} from './modules/account/accountRoutes.js';
import {
  type AccountIdentityDeleter,
  createFirebaseIdentityDeleterFromConfig
} from './modules/account/firebaseIdentityDeleter.js';
import { registerAnalyticsRoutes } from './modules/analytics/analyticsRoutes.js';
import { createAnalyticsStoreFromConfig } from './modules/analytics/analyticsStoreFactory.js';
import type { AnalyticsStore } from './modules/analytics/analyticsStore.js';
import type { PrismaAnalyticsClient } from './modules/analytics/prismaAnalyticsRepository.js';
import { createAuthMiddlewareFromConfig } from './modules/auth/authMiddlewareFactory.js';
import { registerAuthRoutes } from './modules/auth/authRoutes.js';
import { readAuthUser } from './modules/auth/authTypes.js';
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
import { registerPostRoutes } from './modules/posts/postRoutes.js';
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
import type { PrismaAiEditUsageClient } from './modules/aiEdits/prismaAiEditUsageRepository.js';
import {
  type FetchAudio,
  type TranscriptionProvider,
  createTranscriptionProviderFromConfig
} from './modules/aiEdits/transcriptionProvider.js';
import { createPostStoreFromConfig } from './modules/posts/postStoreFactory.js';
import { createPublishQueueFromConfig } from './modules/queue/publishQueueFactory.js';
import { createPlatformPublisherFromConfig } from './workers/platformPublisherFactory.js';
import { createPublishScheduler } from './workers/publishScheduler.js';
import { registerPublishQueueRoutes } from './modules/queue/publishQueueRoutes.js';
import {
  MediaDownloadError,
  aiEditAudioDownloadMaxBytes,
  aiMediaDownloadMaxBytes,
  readAiMediaResponseBytes
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
import type { SocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';
import { createSocialConnectionStore } from './modules/socialConnections/socialConnectionStoreFactory.js';
import { registerPlannedRoutes } from './routes/plannedRoutes.js';
import { createRateLimitMiddleware } from './modules/security/rateLimit.js';

type AppPrismaClient = PrismaTemplateClient &
  PrismaPostClient &
  PrismaUserClient &
  PrismaSubscriptionClient &
  PrismaAnalyticsClient &
  PrismaRealClipCaptionUsageClient &
  PrismaAiEditUsageClient &
  PrismaDeviceTokenClient &
  PrismaSocialConnectionClient &
  PrismaUploadSessionClient;

type AppOptions = {
  config?: ServerConfig;
  prisma?: AppPrismaClient;
  s3Client?: S3VideoStorageClient;
  r2Client?: S3VideoStorageClient;
  firebaseVerifier?: FirebaseTokenVerifier;
  accountDeletionFirebaseVerifier?: FirebaseTokenVerifier;
  firebaseCertsFetch?: FirebaseCertificatesFetch;
  analyticsStore?: AnalyticsStore;
  captionGenerator?: CaptionGenerator;
  realClipCaptionUsageStore?: RealClipCaptionUsageStore;
  realClipCaptionProvider?: RealClipCaptionProvider;
  fetchClipMedia?: (videoS3Key: string) => Promise<RealClipMediaPart>;
  transcriptionProvider?: TranscriptionProvider;
  editPlanProvider?: EditPlanProvider;
  storePurchaseVerifier?: StorePurchaseVerifier;
  revenueCatSubscriberClient?: RevenueCatSubscriberClient;
  appleSignedNotificationDecoder?: AppleSignedNotificationDecoder;
  socialConnectionStore?: SocialConnectionStore;
  postPeerConnectClient?: PostPeerConnectClient;
  videoStorage?: VideoStorage;
  firebaseAdminAuth?: FirebaseAdminAuth;
  accountIdentityDeleter?: AccountIdentityDeleter;
  platformPublishStore?: PlatformPublishStore;
  uploadSessionStore?: UploadSessionStore;
  managedUploadService?: ManagedUploadService;
};

const readFileNameFromStorageKey = (videoS3Key: string) =>
  videoS3Key.split('/').filter(Boolean).at(-1) ?? 'clip.mp4';

const createAccountAwareAuthMiddleware = ({
  authMiddleware,
  managedUploadService
}: {
  authMiddleware: RequestHandler;
  managedUploadService?: ManagedUploadService;
}): RequestHandler => {
  if (!managedUploadService) {
    return authMiddleware;
  }

  return (request, response, next) => {
    authMiddleware(request, response, (authError?: unknown) => {
      if (authError) {
        next(authError);
        return;
      }

      if (request.method === 'GET' || request.method === 'HEAD' || request.method === 'OPTIONS') {
        next();
        return;
      }

      const authUser = readAuthUser(response.locals);

      if (!authUser) {
        next();
        return;
      }

      void managedUploadService.assertOwnerActive(authUser.id).then(
        () => next(),
        (error: unknown) => {
          if (error instanceof ManagedUploadServiceError) {
            response.status(error.statusCode).json({
              status: 'error',
              code: error.code,
              message: error.message
            });
            return;
          }

          next(error);
        }
      );
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
const createFetchMediaFromVideoStorage =
  (videoStorage: VideoStorage) =>
  async (videoS3Key: string): Promise<RealClipMediaPart> => {
    const access = await videoStorage.createDownloadAccess(videoS3Key);

    if (access.accessType !== 'signed-url' || !access.downloadUrl) {
      throw new Error('Signed download access is required for real-clip captioning');
    }

    const response = await fetch(access.downloadUrl);

    if (!response.ok) {
      throw new Error(`Media download failed with status ${response.status}`);
    }

    return {
      data: await readAiMediaResponseBytes(response),
      mimeType: response.headers.get('content-type') ?? 'video/mp4'
    };
  };

export const createApp = (options: AppOptions = {}) => {
  const config = options.config ?? readServerConfig();
  const app = express();

  // Render terminates TLS at a single proxy layer; trust it so req.ip (and the
  // per-IP rate limit key) is the real client address, not the proxy's.
  app.set('trust proxy', 1);
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

  const router = express.Router();
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
  const shouldCreateFirebaseAdminAuth =
    config.firebaseAuthDeleteEnabled &&
    (!options.firebaseVerifier || !options.accountIdentityDeleter);
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
  const prismaClient =
    options.prisma ??
    (config.templateStore === 'prisma' ||
    config.postStore === 'prisma' ||
    config.subscriptionStore === 'prisma' ||
    config.analyticsStore === 'prisma' ||
    config.captionUsageStore === 'prisma' ||
    config.aiEditUsageStore === 'prisma' ||
    config.uploadProtocolMode !== 'legacy'
      ? createPrismaClient()
      : undefined);
  const postStore = createPostStoreFromConfig({
    config,
    prisma: prismaClient as unknown as PrismaPostClient | undefined
  });
  const userStore = createUserStoreForPostStore({
    config,
    prisma: prismaClient
  });
  const subscriptionStore = createSubscriptionStoreFromConfig({
    config,
    prisma: prismaClient
  });
  const publishQueue = createPublishQueueFromConfig({ config });
  const platformPublishStore =
    options.platformPublishStore ??
    (prismaClient
      ? createPrismaPlatformPublishRepository({
          prisma: prismaClient as unknown as PrismaPlatformPublishClient
        })
      : createInMemoryPlatformPublishStore());
  const captionGenerator =
    options.captionGenerator ?? createCaptionGeneratorFromConfig({ config });
  const realClipCaptionUsageStore =
    options.realClipCaptionUsageStore ??
    createRealClipCaptionUsageStoreFromConfig({
      config,
      prisma: prismaClient as unknown as PrismaRealClipCaptionUsageClient | undefined
    });
  const videoStorage =
    options.videoStorage ??
    createVideoStorageFromConfig({
      config,
      s3Client: options.s3Client,
      r2Client: options.r2Client
    });
  const uploadSessionStore =
    options.uploadSessionStore ??
    (prismaClient
      ? createPrismaUploadSessionRepository({
          prisma: prismaClient as unknown as PrismaUploadSessionClient
        })
      : createInMemoryUploadSessionStore());
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
  const accountAwareAuthMiddleware = createAccountAwareAuthMiddleware({
    authMiddleware,
    managedUploadService
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
  registerCaptionRoutes(
    router,
    captionGenerator,
    accountAwareAuthMiddleware,
    subscriptionStore,
    transcriptionProvider,
    realClipCaptionUsageStore,
    options.realClipCaptionProvider ??
      createRealClipCaptionProviderFromConfig({ config }),
    options.fetchClipMedia ?? createFetchMediaFromVideoStorage(videoStorage),
    videoStorage.deleteVideo
  );
  const aiEditUsageStore = createAiEditUsageStoreFromConfig({
    config,
    prisma: prismaClient
  });
  const editPlanProvider =
    options.editPlanProvider ?? createEditPlanProviderFromConfig({ config });
  registerAiEditRoutes(
    router,
    transcriptionProvider,
    accountAwareAuthMiddleware,
    subscriptionStore,
    aiEditUsageStore,
    editPlanProvider,
    videoStorage.deleteVideo
  );
  registerPostRoutes(
    router,
    postStore,
    publishQueue,
    accountAwareAuthMiddleware,
    userStore,
    subscriptionStore,
    platformPublishStore,
    {
      allowSubscriptionPlanOverride:
        config.nodeEnv !== 'production' && config.authProvider === 'mock',
      assertUploadReady: managedUploadService
        ? (ownerId, videoS3Key) =>
            managedUploadService.assertReadyForUse(ownerId, videoS3Key, {
              allowLegacy: config.uploadProtocolMode !== 'multipart'
            })
        : undefined
    }
  );
  registerPublishQueueRoutes(router, accountAwareAuthMiddleware, publishQueue);
  registerTemplateRoutes(router, accountAwareAuthMiddleware, templateStore, userStore);
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
      storePurchaseVerifier: options.storePurchaseVerifier,
      appleSignedNotificationDecoder: options.appleSignedNotificationDecoder
    }
  );
  registerRevenueCatRestoreRoutes({
    router,
    authMiddleware: accountAwareAuthMiddleware,
    config,
    subscriberClient:
      options.revenueCatSubscriberClient ??
      createRevenueCatSubscriberClient({
        apiKey: config.revenueCatRestApiV1Key
      }),
    userStore,
    subscriptionStore
  });
  registerRevenueCatWebhookRoutes({
    router,
    config,
    userStore,
    subscriptionStore
  });
  const deviceTokenStore = createDeviceTokenStore({
    prisma: prismaClient
      ? (prismaClient as unknown as PrismaDeviceTokenClient)
      : undefined
  });
  const socialConnectionStore =
    options.socialConnectionStore ??
    createSocialConnectionStore({
      prisma: prismaClient
        ? (prismaClient as unknown as PrismaSocialConnectionClient)
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
  registerDeviceRoutes(router, accountAwareAuthMiddleware, deviceTokenStore);
  registerSocialConnectionRoutes(router, accountAwareAuthMiddleware, {
    store: socialConnectionStore,
    connectClient: postPeerConnectClient,
    userStore
  });
  registerAccountRoutes(router, accountDeletionAuthMiddleware, {
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
    managedUploadService,
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
        socialConnectionStore
      }),
      storage: videoStorage,
      // Push a publish-result notification to the user's devices. Uses the real
      // FCM sender when PUSH_SENDER=firebase, otherwise a no-op mock.
      notifier: createPublishNotifier({
        deviceTokenStore,
        pushSender: createPushSenderFromConfig({ config })
      }),
      assertOwnerActive: managedUploadService?.assertOwnerActive
    });
  }

  return app;
};
