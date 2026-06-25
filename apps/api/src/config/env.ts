type EnvSource = Record<string, string | undefined>;
export type TemplateStoreKind = 'memory' | 'prisma';
export type PostStoreKind = 'memory' | 'prisma';
export type SubscriptionStoreKind = 'memory' | 'prisma';
export type AnalyticsStoreKind = 'memory' | 'prisma';
export type CaptionUsageStoreKind = 'memory' | 'prisma';
export type AiEditUsageStoreKind = 'memory' | 'prisma';
export type PublishQueueKind = 'memory' | 'bullmq';
export type VideoStorageKind = 'mock' | 's3' | 'r2';
export type CaptionProviderKind = 'mock' | 'openai' | 'gemini';
export type AuthProviderKind = 'mock' | 'firebase';
export type BillingProviderKind = 'mock' | 'store' | 'revenuecat';
export type SocialPublisherKind = 'mock' | 'postpeer';
export type TranscriptionProviderKind = 'mock' | 'openai' | 'groq';
export type EditPlanProviderKind = 'mock' | 'openai' | 'groq';
export type AppleAppStoreEnvironmentKind = 'sandbox' | 'production';

export type ServerConfig = {
  port: number;
  nodeEnv: string;
  databaseUrl?: string;
  redisUrl: string;
  awsRegion: string;
  awsS3Bucket?: string;
  awsS3UploadExpiresSeconds: number;
  cloudflareR2Bucket?: string;
  cloudflareR2AccountId?: string;
  cloudflareR2AccessKeyId?: string;
  cloudflareR2SecretAccessKey?: string;
  cloudflareR2Endpoint?: string;
  cloudflareR2UploadExpiresSeconds: number;
  openAiApiKey?: string;
  groqApiKey?: string;
  geminiApiKey?: string;
  billingProvider: BillingProviderKind;
  revenueCatWebhookAuthToken?: string;
  revenueCatStarterEntitlementId: string;
  revenueCatProEntitlementId: string;
  revenueCatStarterProductId: string;
  revenueCatProProductId: string;
  storeStarterMonthlyProductId: string;
  storeProMonthlyProductId: string;
  googlePlayPackageName?: string;
  googlePlayServiceAccountKeyJson?: string;
  googlePlayAccessToken?: string;
  appleAppBundleId?: string;
  appleAppStoreIssuerId?: string;
  appleAppStoreKeyId?: string;
  appleAppStorePrivateKey?: string;
  appleAppStoreRootCertificatesBase64?: string;
  appleAppAppleId?: number;
  appleAppStoreEnvironment: AppleAppStoreEnvironmentKind;
  firebaseProjectId?: string;
  templateStore: TemplateStoreKind;
  templateStoreUserId: string;
  postStore: PostStoreKind;
  subscriptionStore: SubscriptionStoreKind;
  analyticsStore: AnalyticsStoreKind;
  captionUsageStore: CaptionUsageStoreKind;
  publishQueue: PublishQueueKind;
  videoStorage: VideoStorageKind;
  captionProvider: CaptionProviderKind;
  openAiCaptionModel: string;
  geminiCaptionModel: string;
  authProvider: AuthProviderKind;
  socialPublisher: SocialPublisherKind;
  postPeerApiKey?: string;
  postPeerApiBaseUrl: string;
  postPeerTiktokAccountId?: string;
  postPeerYoutubeAccountId?: string;
  postPeerInstagramAccountId?: string;
  postPeerFacebookAccountId?: string;
  transcriptionProvider: TranscriptionProviderKind;
  whisperModel: string;
  groqTranscriptionModel: string;
  editPlanProvider: EditPlanProviderKind;
  openAiEditPlanModel: string;
  groqEditPlanModel: string;
  aiEditUsageStore: AiEditUsageStoreKind;
  mockUserId: string;
};

const readOptional = (env: EnvSource, key: string) => {
  const value = env[key]?.trim();
  return value && value.length > 0 ? value : undefined;
};

const readPort = (env: EnvSource) => {
  const rawPort = readOptional(env, 'PORT') ?? '4000';
  const port = Number(rawPort);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be a number between 1 and 65535');
  }

  return port;
};

const readPositiveInteger = (env: EnvSource, key: string, fallback: number) => {
  const rawValue = readOptional(env, key);
  const value = rawValue ? Number(rawValue) : fallback;

  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${key} must be a positive number`);
  }

  return value;
};

const readOptionalPositiveInteger = (env: EnvSource, key: string) => {
  const rawValue = readOptional(env, key);

  if (!rawValue) {
    return undefined;
  }

  const value = Number(rawValue);

  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${key} must be a positive number`);
  }

  return value;
};

const readTemplateStore = (env: EnvSource): TemplateStoreKind => {
  const value = readOptional(env, 'TEMPLATE_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('TEMPLATE_STORE must be memory or prisma');
  }

  return value;
};

const readPostStore = (env: EnvSource): PostStoreKind => {
  const value = readOptional(env, 'POST_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('POST_STORE must be memory or prisma');
  }

  return value;
};

const readSubscriptionStore = (env: EnvSource): SubscriptionStoreKind => {
  const value = readOptional(env, 'SUBSCRIPTION_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('SUBSCRIPTION_STORE must be memory or prisma');
  }

  return value;
};

const readAnalyticsStore = (env: EnvSource): AnalyticsStoreKind => {
  const value = readOptional(env, 'ANALYTICS_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('ANALYTICS_STORE must be memory or prisma');
  }

  return value;
};

const readCaptionUsageStore = (env: EnvSource): CaptionUsageStoreKind => {
  const value = readOptional(env, 'CAPTION_USAGE_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('CAPTION_USAGE_STORE must be memory or prisma');
  }

  return value;
};

const readPublishQueue = (env: EnvSource): PublishQueueKind => {
  const value = readOptional(env, 'PUBLISH_QUEUE') ?? 'memory';

  if (value !== 'memory' && value !== 'bullmq') {
    throw new Error('PUBLISH_QUEUE must be memory or bullmq');
  }

  return value;
};

const readVideoStorage = (env: EnvSource): VideoStorageKind => {
  const value = readOptional(env, 'VIDEO_STORAGE') ?? 'mock';

  if (value !== 'mock' && value !== 's3' && value !== 'r2') {
    throw new Error('VIDEO_STORAGE must be mock, s3, or r2');
  }

  return value;
};

const readCaptionProvider = (env: EnvSource): CaptionProviderKind => {
  const value = readOptional(env, 'CAPTION_PROVIDER') ?? 'mock';

  if (value !== 'mock' && value !== 'openai' && value !== 'gemini') {
    throw new Error('CAPTION_PROVIDER must be mock, openai, or gemini');
  }

  return value;
};

const readAuthProvider = (env: EnvSource): AuthProviderKind => {
  const value = readOptional(env, 'AUTH_PROVIDER') ?? 'mock';

  if (value !== 'mock' && value !== 'firebase') {
    throw new Error('AUTH_PROVIDER must be mock or firebase');
  }

  return value;
};

const readBillingProvider = (env: EnvSource): BillingProviderKind => {
  const value = readOptional(env, 'BILLING_PROVIDER') ?? 'mock';

  if (value !== 'mock' && value !== 'store' && value !== 'revenuecat') {
    throw new Error('BILLING_PROVIDER must be mock, store, or revenuecat');
  }

  return value;
};

const readAiEditUsageStore = (env: EnvSource): AiEditUsageStoreKind => {
  const value = readOptional(env, 'AI_EDIT_USAGE_STORE') ?? 'memory';

  if (value !== 'memory' && value !== 'prisma') {
    throw new Error('AI_EDIT_USAGE_STORE must be memory or prisma');
  }

  return value;
};

const readTranscriptionProvider = (env: EnvSource): TranscriptionProviderKind => {
  const value = readOptional(env, 'TRANSCRIPTION_PROVIDER') ?? 'mock';

  if (value !== 'mock' && value !== 'openai' && value !== 'groq') {
    throw new Error('TRANSCRIPTION_PROVIDER must be mock, openai, or groq');
  }

  return value;
};

const readEditPlanProvider = (env: EnvSource): EditPlanProviderKind => {
  const value = readOptional(env, 'EDIT_PLAN_PROVIDER') ?? 'mock';

  if (value !== 'mock' && value !== 'openai' && value !== 'groq') {
    throw new Error('EDIT_PLAN_PROVIDER must be mock, openai, or groq');
  }

  return value;
};

const readSocialPublisher = (env: EnvSource): SocialPublisherKind => {
  const value = readOptional(env, 'SOCIAL_PUBLISHER') ?? 'mock';

  if (value !== 'mock' && value !== 'postpeer') {
    throw new Error('SOCIAL_PUBLISHER must be mock or postpeer');
  }

  return value;
};

const readAppleAppStoreEnvironment = (env: EnvSource): AppleAppStoreEnvironmentKind => {
  const value = readOptional(env, 'APPLE_APP_STORE_ENVIRONMENT') ?? 'sandbox';

  if (value !== 'sandbox' && value !== 'production') {
    throw new Error('APPLE_APP_STORE_ENVIRONMENT must be sandbox or production');
  }

  return value;
};

const assertProductionSafeConfig = (config: ServerConfig) => {
  if (config.nodeEnv !== 'production') {
    return;
  }

  if (config.authProvider === 'mock') {
    throw new Error('AUTH_PROVIDER=mock is not allowed when NODE_ENV=production');
  }

  if (config.billingProvider === 'mock') {
    throw new Error('BILLING_PROVIDER=mock is not allowed when NODE_ENV=production');
  }

  if (config.billingProvider === 'revenuecat' && !config.revenueCatWebhookAuthToken) {
    throw new Error(
      'REVENUECAT_WEBHOOK_AUTH_TOKEN is required when BILLING_PROVIDER=revenuecat in production'
    );
  }
};

const usesPrismaBackedStore = (config: ServerConfig) =>
  config.templateStore === 'prisma' ||
  config.postStore === 'prisma' ||
  config.subscriptionStore === 'prisma' ||
  config.analyticsStore === 'prisma' ||
  config.captionUsageStore === 'prisma' ||
  config.aiEditUsageStore === 'prisma';

const assertRuntimeStoreConfig = (config: ServerConfig) => {
  if (config.publishQueue === 'bullmq' && config.postStore !== 'prisma') {
    throw new Error('PUBLISH_QUEUE=bullmq requires POST_STORE=prisma');
  }

  if (usesPrismaBackedStore(config) && !config.databaseUrl) {
    throw new Error('DATABASE_URL is required when any Prisma-backed store is enabled');
  }
};

export const readServerConfig = (env: EnvSource = process.env): ServerConfig => {
  const config: ServerConfig = {
    port: readPort(env),
    nodeEnv: readOptional(env, 'NODE_ENV') ?? 'development',
    databaseUrl: readOptional(env, 'DATABASE_URL'),
    redisUrl: readOptional(env, 'REDIS_URL') ?? 'redis://localhost:6379',
    awsRegion: readOptional(env, 'AWS_REGION') ?? 'ap-southeast-1',
    awsS3Bucket: readOptional(env, 'AWS_S3_BUCKET'),
    awsS3UploadExpiresSeconds: readPositiveInteger(env, 'AWS_S3_UPLOAD_EXPIRES_SECONDS', 900),
    cloudflareR2Bucket: readOptional(env, 'CLOUDFLARE_R2_BUCKET'),
    cloudflareR2AccountId: readOptional(env, 'CLOUDFLARE_R2_ACCOUNT_ID'),
    cloudflareR2AccessKeyId: readOptional(env, 'CLOUDFLARE_R2_ACCESS_KEY_ID'),
    cloudflareR2SecretAccessKey: readOptional(env, 'CLOUDFLARE_R2_SECRET_ACCESS_KEY'),
    cloudflareR2Endpoint: readOptional(env, 'CLOUDFLARE_R2_ENDPOINT'),
    cloudflareR2UploadExpiresSeconds: readPositiveInteger(
      env,
      'CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS',
      900
    ),
    openAiApiKey: readOptional(env, 'OPENAI_API_KEY'),
    groqApiKey: readOptional(env, 'GROQ_API_KEY'),
    geminiApiKey: readOptional(env, 'GEMINI_API_KEY'),
    billingProvider: readBillingProvider(env),
    revenueCatWebhookAuthToken: readOptional(env, 'REVENUECAT_WEBHOOK_AUTH_TOKEN'),
    revenueCatStarterEntitlementId:
      readOptional(env, 'REVENUECAT_STARTER_ENTITLEMENT_ID') ?? 'starter',
    revenueCatProEntitlementId: readOptional(env, 'REVENUECAT_PRO_ENTITLEMENT_ID') ?? 'pro',
    revenueCatStarterProductId:
      readOptional(env, 'REVENUECAT_STARTER_PRODUCT_ID') ?? 'postdee_starter_monthly',
    revenueCatProProductId:
      readOptional(env, 'REVENUECAT_PRO_PRODUCT_ID') ?? 'postdee_pro_monthly',
    storeStarterMonthlyProductId:
      readOptional(env, 'STORE_STARTER_MONTHLY_PRODUCT_ID') ?? 'postdee_starter_monthly',
    storeProMonthlyProductId:
      readOptional(env, 'STORE_PRO_MONTHLY_PRODUCT_ID') ?? 'postdee_pro_monthly',
    googlePlayPackageName: readOptional(env, 'GOOGLE_PLAY_PACKAGE_NAME'),
    googlePlayServiceAccountKeyJson: readOptional(env, 'GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON'),
    googlePlayAccessToken: readOptional(env, 'GOOGLE_PLAY_ACCESS_TOKEN'),
    appleAppBundleId: readOptional(env, 'APPLE_APP_BUNDLE_ID'),
    appleAppStoreIssuerId: readOptional(env, 'APPLE_APP_STORE_ISSUER_ID'),
    appleAppStoreKeyId: readOptional(env, 'APPLE_APP_STORE_KEY_ID'),
    appleAppStorePrivateKey: readOptional(env, 'APPLE_APP_STORE_PRIVATE_KEY'),
    appleAppStoreRootCertificatesBase64: readOptional(
      env,
      'APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64'
    ),
    appleAppAppleId: readOptionalPositiveInteger(env, 'APPLE_APP_APPLE_ID'),
    appleAppStoreEnvironment: readAppleAppStoreEnvironment(env),
    firebaseProjectId: readOptional(env, 'FIREBASE_PROJECT_ID'),
    templateStore: readTemplateStore(env),
    templateStoreUserId: readOptional(env, 'TEMPLATE_STORE_USER_ID') ?? 'local-dev-user',
    postStore: readPostStore(env),
    subscriptionStore: readSubscriptionStore(env),
    analyticsStore: readAnalyticsStore(env),
    captionUsageStore: readCaptionUsageStore(env),
    publishQueue: readPublishQueue(env),
    videoStorage: readVideoStorage(env),
    captionProvider: readCaptionProvider(env),
    openAiCaptionModel: readOptional(env, 'OPENAI_CAPTION_MODEL') ?? 'gpt-4o-mini',
    geminiCaptionModel: readOptional(env, 'GEMINI_CAPTION_MODEL') ?? 'gemini-2.5-flash-lite',
    authProvider: readAuthProvider(env),
    socialPublisher: readSocialPublisher(env),
    postPeerApiKey: readOptional(env, 'POSTPEER_API_KEY'),
    postPeerApiBaseUrl:
      readOptional(env, 'POSTPEER_API_BASE_URL') ?? 'https://api.postpeer.dev',
    postPeerTiktokAccountId: readOptional(env, 'POSTPEER_TIKTOK_ACCOUNT_ID'),
    postPeerYoutubeAccountId: readOptional(env, 'POSTPEER_YOUTUBE_ACCOUNT_ID'),
    postPeerInstagramAccountId: readOptional(env, 'POSTPEER_INSTAGRAM_ACCOUNT_ID'),
    postPeerFacebookAccountId: readOptional(env, 'POSTPEER_FACEBOOK_ACCOUNT_ID'),
    transcriptionProvider: readTranscriptionProvider(env),
    whisperModel: readOptional(env, 'WHISPER_MODEL') ?? 'whisper-1',
    groqTranscriptionModel: readOptional(env, 'GROQ_TRANSCRIPTION_MODEL') ?? 'whisper-large-v3',
    editPlanProvider: readEditPlanProvider(env),
    openAiEditPlanModel: readOptional(env, 'OPENAI_EDIT_PLAN_MODEL') ?? 'gpt-4o-mini',
    groqEditPlanModel:
      readOptional(env, 'GROQ_EDIT_PLAN_MODEL') ?? 'llama-3.3-70b-versatile',
    aiEditUsageStore: readAiEditUsageStore(env),
    mockUserId: readOptional(env, 'MOCK_USER_ID') ?? 'local-dev-user'
  };

  assertRuntimeStoreConfig(config);
  assertProductionSafeConfig(config);
  return config;
};
