import cors from 'cors';
import express from 'express';
import helmet from 'helmet';

import { type ServerConfig, readServerConfig } from './config/env.js';
import { createPrismaClient } from './config/prisma.js';
import {
  type PrismaAccountClient,
  registerAccountRoutes
} from './modules/account/accountRoutes.js';
import { registerAnalyticsRoutes } from './modules/analytics/analyticsRoutes.js';
import { createAnalyticsStoreFromConfig } from './modules/analytics/analyticsStoreFactory.js';
import type { AnalyticsStore } from './modules/analytics/analyticsStore.js';
import type { PrismaAnalyticsClient } from './modules/analytics/prismaAnalyticsRepository.js';
import { createAuthMiddlewareFromConfig } from './modules/auth/authMiddlewareFactory.js';
import { registerAuthRoutes } from './modules/auth/authRoutes.js';
import type { FirebaseTokenVerifier } from './modules/auth/authTypes.js';
import {
  createFirebaseTokenVerifierFromConfig,
  type FirebaseCertificatesFetch
} from './modules/auth/firebaseTokenVerifier.js';
import { registerBillingRoutes } from './modules/billing/billingRoutes.js';
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
import { createInMemoryPlatformPublishStore } from './modules/platformPublishes/platformPublishStore.js';
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
import { readAiMediaResponseBytes } from './modules/storage/mediaDownload.js';
import type { S3VideoStorageClient, VideoStorage } from './modules/storage/videoStorage.js';
import { createVideoStorageFromConfig } from './modules/storage/videoStorageFactory.js';
import type { PrismaSubscriptionClient } from './modules/subscriptions/prismaSubscriptionRepository.js';
import { createSubscriptionStoreFromConfig } from './modules/subscriptions/subscriptionStoreFactory.js';
import { registerTemplateRoutes } from './modules/templates/templateRoutes.js';
import type { PrismaTemplateClient } from './modules/templates/prismaTemplateRepository.js';
import { createTemplateStoreFromConfig } from './modules/templates/templateStoreFactory.js';
import { registerUploadRoutes } from './modules/uploads/uploadRoutes.js';
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
import { createPostPeerConnectStateManager } from './modules/socialConnections/postPeerConnectState.js';
import type { PrismaSocialConnectionClient } from './modules/socialConnections/prismaSocialConnectionRepository.js';
import {
  type PostPeerConnectStateManager,
  registerSocialConnectionRoutes
} from './modules/socialConnections/socialConnectionRoutes.js';
import type { SocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';
import { createSocialConnectionStore } from './modules/socialConnections/socialConnectionStoreFactory.js';
import { registerPlannedRoutes } from './routes/plannedRoutes.js';

type AppPrismaClient = PrismaTemplateClient &
  PrismaPostClient &
  PrismaUserClient &
  PrismaSubscriptionClient &
  PrismaAnalyticsClient &
  PrismaRealClipCaptionUsageClient &
  PrismaAiEditUsageClient &
  PrismaDeviceTokenClient &
  PrismaSocialConnectionClient;

type AppOptions = {
  config?: ServerConfig;
  prisma?: AppPrismaClient;
  s3Client?: S3VideoStorageClient;
  r2Client?: S3VideoStorageClient;
  firebaseVerifier?: FirebaseTokenVerifier;
  firebaseCertsFetch?: FirebaseCertificatesFetch;
  analyticsStore?: AnalyticsStore;
  captionGenerator?: CaptionGenerator;
  realClipCaptionUsageStore?: RealClipCaptionUsageStore;
  realClipCaptionProvider?: RealClipCaptionProvider;
  fetchClipMedia?: (videoS3Key: string) => Promise<RealClipMediaPart>;
  transcriptionProvider?: TranscriptionProvider;
  editPlanProvider?: EditPlanProvider;
  storePurchaseVerifier?: StorePurchaseVerifier;
  appleSignedNotificationDecoder?: AppleSignedNotificationDecoder;
  socialConnectionStore?: SocialConnectionStore;
  postPeerConnectClient?: PostPeerConnectClient;
  postPeerConnectStateManager?: PostPeerConnectStateManager;
};

const readFileNameFromStorageKey = (videoS3Key: string) =>
  videoS3Key.split('/').filter(Boolean).at(-1) ?? 'clip.mp4';

const createFetchAudioFromVideoStorage =
  (videoStorage: VideoStorage): FetchAudio =>
  async (videoS3Key) => {
    const access = await videoStorage.createDownloadAccess(videoS3Key);

    if (access.accessType !== 'signed-url' || !access.downloadUrl) {
      throw new Error('Signed video download access is required for real transcription');
    }

    const response = await fetch(access.downloadUrl);

    if (!response.ok) {
      throw new Error(`Video download failed with status ${response.status}`);
    }

    return {
      data: await readAiMediaResponseBytes(response),
      filename: readFileNameFromStorageKey(videoS3Key),
      contentType: response.headers.get('content-type') ?? 'video/mp4'
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

  app.use(helmet());
  app.use(cors());
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
  const firebaseVerifier =
    options.firebaseVerifier ??
    createFirebaseTokenVerifierFromConfig({
      config,
      fetchCertificates: options.firebaseCertsFetch
    });
  const authMiddleware = createAuthMiddlewareFromConfig({
    config,
    firebaseVerifier
  });
  const prismaClient =
    options.prisma ??
    (config.templateStore === 'prisma' ||
    config.postStore === 'prisma' ||
    config.subscriptionStore === 'prisma' ||
    config.analyticsStore === 'prisma' ||
    config.captionUsageStore === 'prisma' ||
    config.aiEditUsageStore === 'prisma'
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
  const platformPublishStore = prismaClient
    ? createPrismaPlatformPublishRepository({
        prisma: prismaClient as unknown as PrismaPlatformPublishClient
      })
    : createInMemoryPlatformPublishStore();
  const captionGenerator =
    options.captionGenerator ?? createCaptionGeneratorFromConfig({ config });
  const realClipCaptionUsageStore =
    options.realClipCaptionUsageStore ??
    createRealClipCaptionUsageStoreFromConfig({
      config,
      prisma: prismaClient as unknown as PrismaRealClipCaptionUsageClient | undefined
    });
  const videoStorage = createVideoStorageFromConfig({
    config,
    s3Client: options.s3Client,
    r2Client: options.r2Client
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
  registerAuthRoutes(router, authMiddleware);
  registerUploadRoutes(router, authMiddleware, videoStorage);
  registerCaptionRoutes(
    router,
    captionGenerator,
    authMiddleware,
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
    authMiddleware,
    subscriptionStore,
    aiEditUsageStore,
    editPlanProvider
  );
  registerPostRoutes(
    router,
    postStore,
    publishQueue,
    authMiddleware,
    userStore,
    subscriptionStore,
    {
      allowSubscriptionPlanOverride:
        config.nodeEnv !== 'production' && config.authProvider === 'mock'
    }
  );
  registerPublishQueueRoutes(router, authMiddleware, publishQueue);
  registerTemplateRoutes(router, authMiddleware, templateStore, userStore);
  registerAnalyticsRoutes(router, authMiddleware, subscriptionStore, analyticsStore);
  registerBillingRoutes(
    router,
    authMiddleware,
    userStore,
    subscriptionStore,
    postStore,
    {
      config,
      storePurchaseVerifier: options.storePurchaseVerifier,
      appleSignedNotificationDecoder: options.appleSignedNotificationDecoder
    }
  );
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
      createPath: config.postPeerConnectCreatePath
    });
  const postPeerConnectStateManager =
    options.postPeerConnectStateManager ??
    (config.postPeerConnectStateSecret
      ? createPostPeerConnectStateManager({
          secret: config.postPeerConnectStateSecret
        })
      : undefined);
  registerDeviceRoutes(router, authMiddleware, deviceTokenStore);
  registerSocialConnectionRoutes(router, authMiddleware, {
    store: socialConnectionStore,
    connectClient: postPeerConnectClient,
    callbackUrl: config.postPeerConnectCallbackUrl,
    callbackSecret: config.postPeerConnectCallbackSecret,
    stateManager: postPeerConnectStateManager
  });
  registerAccountRoutes(router, authMiddleware, {
    postStore,
    templateStore,
    subscriptionStore,
    analyticsStore,
    realClipCaptionUsageStore,
    aiEditUsageStore,
    deviceTokenStore,
    socialConnectionStore,
    userStore,
    publishQueue,
    prisma: prismaClient
      ? (prismaClient as unknown as PrismaAccountClient)
      : undefined
  });
  registerPlannedRoutes(router);
  app.use(router);

  // In-memory queue has no external worker, so attach an in-process scheduler.
  // It is created but NOT started here — server.ts starts it so tests that only
  // build the app never leave a timer running. (BullMQ uses a separate worker.)
  if (config.publishQueue === 'memory') {
    app.locals.publishScheduler = createPublishScheduler({
      postStore,
      platformPublishStore,
      publisher: createPlatformPublisherFromConfig({ config, videoStorage }),
      storage: videoStorage,
      // Push a publish-result notification to the user's devices. Uses the real
      // FCM sender when PUSH_SENDER=firebase, otherwise a no-op mock.
      notifier: createPublishNotifier({
        deviceTokenStore,
        pushSender: createPushSenderFromConfig({ config })
      })
    });
  }

  return app;
};
