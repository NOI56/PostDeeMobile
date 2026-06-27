import { describe, expect, it } from 'vitest';

import { readServerConfig } from './env.js';

describe('readServerConfig', () => {
  it('uses safe local defaults for scaffold development', () => {
    const config = readServerConfig({});

    expect(config).toEqual({
      port: 4000,
      nodeEnv: 'development',
      databaseUrl: undefined,
      redisUrl: 'redis://localhost:6379',
      awsRegion: 'ap-southeast-1',
      awsS3Bucket: undefined,
      awsS3UploadExpiresSeconds: 900,
      cloudflareR2Bucket: undefined,
      cloudflareR2AccountId: undefined,
      cloudflareR2AccessKeyId: undefined,
      cloudflareR2SecretAccessKey: undefined,
      cloudflareR2Endpoint: undefined,
      cloudflareR2UploadExpiresSeconds: 900,
      openAiApiKey: undefined,
      groqApiKey: undefined,
      geminiApiKey: undefined,
      billingProvider: 'mock',
      revenueCatWebhookAuthToken: undefined,
      revenueCatStarterEntitlementId: 'starter',
      revenueCatProEntitlementId: 'pro',
      revenueCatStarterProductId: 'postdee_starter_monthly',
      revenueCatProProductId: 'postdee_pro_monthly',
      storeStarterMonthlyProductId: 'postdee_starter_monthly',
      storeProMonthlyProductId: 'postdee_pro_monthly',
      googlePlayPackageName: undefined,
      googlePlayServiceAccountKeyJson: undefined,
      googlePlayAccessToken: undefined,
      appleAppBundleId: undefined,
      appleAppStoreIssuerId: undefined,
      appleAppStoreKeyId: undefined,
      appleAppStorePrivateKey: undefined,
      appleAppStoreRootCertificatesBase64: undefined,
      appleAppAppleId: undefined,
      appleAppStoreEnvironment: 'sandbox',
      firebaseProjectId: undefined,
      pushSender: 'mock',
      firebaseServiceAccountJson: undefined,
      templateStore: 'memory',
      templateStoreUserId: 'local-dev-user',
      postStore: 'memory',
      subscriptionStore: 'memory',
      analyticsStore: 'memory',
      captionUsageStore: 'memory',
      publishQueue: 'memory',
      videoStorage: 'mock',
      captionProvider: 'mock',
      openAiCaptionModel: 'gpt-4o-mini',
      geminiCaptionModel: 'gemini-2.5-flash-lite',
      authProvider: 'mock',
      socialPublisher: 'mock',
      postPeerApiKey: undefined,
      postPeerApiBaseUrl: 'https://api.postpeer.dev',
      postPeerTiktokAccountId: undefined,
      postPeerYoutubeAccountId: undefined,
      postPeerInstagramAccountId: undefined,
      postPeerFacebookAccountId: undefined,
      postPeerConnectCreatePath: undefined,
      postPeerConnectCallbackUrl: undefined,
      postPeerConnectStateSecret: undefined,
      postPeerConnectCallbackSecret: undefined,
      transcriptionProvider: 'mock',
      whisperModel: 'whisper-1',
      groqTranscriptionModel: 'whisper-large-v3',
      editPlanProvider: 'mock',
      openAiEditPlanModel: 'gpt-4o-mini',
      groqEditPlanModel: 'llama-3.3-70b-versatile',
      aiEditUsageStore: 'memory',
      mockUserId: 'local-dev-user'
    });
  });

  it('reads configured service values from the environment', () => {
    const config = readServerConfig({
      PORT: '4500',
      NODE_ENV: 'production',
      DATABASE_URL: 'postgresql://user:pass@localhost:5432/postdee',
      REDIS_URL: 'redis://redis:6379',
      AWS_REGION: 'ap-southeast-7',
      AWS_S3_BUCKET: 'postdee-temp',
      AWS_S3_UPLOAD_EXPIRES_SECONDS: '1200',
      CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp',
      CLOUDFLARE_R2_ACCOUNT_ID: 'cloudflare-account-id',
      CLOUDFLARE_R2_ACCESS_KEY_ID: 'cloudflare-access-key',
      CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'cloudflare-secret-key',
      CLOUDFLARE_R2_ENDPOINT: 'https://custom-r2-endpoint.local',
      CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS: '1500',
      OPENAI_API_KEY: 'openai-key',
      GROQ_API_KEY: 'groq-key',
      GEMINI_API_KEY: 'gemini-key',
      BILLING_PROVIDER: 'store',
      STORE_STARTER_MONTHLY_PRODUCT_ID: 'postdee_starter_monthly_test',
      STORE_PRO_MONTHLY_PRODUCT_ID: 'postdee_pro_monthly_test',
      GOOGLE_PLAY_PACKAGE_NAME: 'com.postdee',
      GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON: '{"client_email":"play@example.com"}',
      GOOGLE_PLAY_ACCESS_TOKEN: 'google-play-access-token',
      APPLE_APP_BUNDLE_ID: 'com.postdee',
      APPLE_APP_STORE_ISSUER_ID: 'apple-issuer-id',
      APPLE_APP_STORE_KEY_ID: 'apple-key-id',
      APPLE_APP_STORE_PRIVATE_KEY: 'apple-private-key',
      APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64: 'apple-root-cert-base64',
      APPLE_APP_APPLE_ID: '1234567890',
      APPLE_APP_STORE_ENVIRONMENT: 'production',
      FIREBASE_PROJECT_ID: 'postdee-firebase',
      TEMPLATE_STORE: 'prisma',
      TEMPLATE_STORE_USER_ID: 'user-1',
      POST_STORE: 'prisma',
      SUBSCRIPTION_STORE: 'prisma',
      ANALYTICS_STORE: 'prisma',
      CAPTION_USAGE_STORE: 'prisma',
      PUBLISH_QUEUE: 'bullmq',
      VIDEO_STORAGE: 's3',
      CAPTION_PROVIDER: 'gemini',
      OPENAI_CAPTION_MODEL: 'gpt-4o-mini',
      GEMINI_CAPTION_MODEL: 'gemini-2.5-flash-lite',
      AUTH_PROVIDER: 'firebase',
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'postpeer-key',
      POSTPEER_API_BASE_URL: 'https://postpeer.example.com',
      POSTPEER_TIKTOK_ACCOUNT_ID: 'postpeer-tiktok',
      POSTPEER_YOUTUBE_ACCOUNT_ID: 'postpeer-youtube',
      POSTPEER_INSTAGRAM_ACCOUNT_ID: 'postpeer-instagram',
      POSTPEER_FACEBOOK_ACCOUNT_ID: 'postpeer-facebook',
      POSTPEER_CONNECT_CREATE_PATH: '/v1/connect/links',
      POSTPEER_CONNECT_CALLBACK_URL:
        'https://postdee-api.onrender.com/social-connections/postpeer/callback',
      POSTPEER_CONNECT_STATE_SECRET: 'state-secret',
      POSTPEER_CONNECT_CALLBACK_SECRET: 'callback-secret',
      TRANSCRIPTION_PROVIDER: 'groq',
      GROQ_TRANSCRIPTION_MODEL: 'whisper-large-v3',
      MOCK_USER_ID: 'mock-user-1'
    });

    expect(config).toMatchObject({
      port: 4500,
      nodeEnv: 'production',
      databaseUrl: 'postgresql://user:pass@localhost:5432/postdee',
      redisUrl: 'redis://redis:6379',
      awsRegion: 'ap-southeast-7',
      awsS3Bucket: 'postdee-temp',
      awsS3UploadExpiresSeconds: 1200,
      cloudflareR2Bucket: 'postdee-r2-temp',
      cloudflareR2AccountId: 'cloudflare-account-id',
      cloudflareR2AccessKeyId: 'cloudflare-access-key',
      cloudflareR2SecretAccessKey: 'cloudflare-secret-key',
      cloudflareR2Endpoint: 'https://custom-r2-endpoint.local',
      cloudflareR2UploadExpiresSeconds: 1500,
      openAiApiKey: 'openai-key',
      groqApiKey: 'groq-key',
      geminiApiKey: 'gemini-key',
      billingProvider: 'store',
      storeStarterMonthlyProductId: 'postdee_starter_monthly_test',
      storeProMonthlyProductId: 'postdee_pro_monthly_test',
      googlePlayPackageName: 'com.postdee',
      googlePlayServiceAccountKeyJson: '{"client_email":"play@example.com"}',
      googlePlayAccessToken: 'google-play-access-token',
      appleAppBundleId: 'com.postdee',
      appleAppStoreIssuerId: 'apple-issuer-id',
      appleAppStoreKeyId: 'apple-key-id',
      appleAppStorePrivateKey: 'apple-private-key',
      appleAppStoreRootCertificatesBase64: 'apple-root-cert-base64',
      appleAppAppleId: 1234567890,
      appleAppStoreEnvironment: 'production',
      firebaseProjectId: 'postdee-firebase',
      templateStore: 'prisma',
      templateStoreUserId: 'user-1',
      postStore: 'prisma',
      subscriptionStore: 'prisma',
      analyticsStore: 'prisma',
      captionUsageStore: 'prisma',
      publishQueue: 'bullmq',
      videoStorage: 's3',
      captionProvider: 'gemini',
      openAiCaptionModel: 'gpt-4o-mini',
      geminiCaptionModel: 'gemini-2.5-flash-lite',
      authProvider: 'firebase',
      socialPublisher: 'postpeer',
      postPeerApiKey: 'postpeer-key',
      postPeerApiBaseUrl: 'https://postpeer.example.com',
      postPeerTiktokAccountId: 'postpeer-tiktok',
      postPeerYoutubeAccountId: 'postpeer-youtube',
      postPeerInstagramAccountId: 'postpeer-instagram',
      postPeerFacebookAccountId: 'postpeer-facebook',
      postPeerConnectCreatePath: '/v1/connect/links',
      postPeerConnectCallbackUrl:
        'https://postdee-api.onrender.com/social-connections/postpeer/callback',
      postPeerConnectStateSecret: 'state-secret',
      postPeerConnectCallbackSecret: 'callback-secret',
      transcriptionProvider: 'groq',
      groqTranscriptionModel: 'whisper-large-v3',
      mockUserId: 'mock-user-1'
    });
  });

  it('rejects mock auth and billing shortcuts in production', () => {
    expect(() =>
      readServerConfig({
        NODE_ENV: 'production',
        AUTH_PROVIDER: 'mock',
        BILLING_PROVIDER: 'store'
      })
    ).toThrow('AUTH_PROVIDER=mock is not allowed when NODE_ENV=production');

    expect(() =>
      readServerConfig({
        NODE_ENV: 'production',
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-prod',
        BILLING_PROVIDER: 'mock'
      })
    ).toThrow('BILLING_PROVIDER=mock is not allowed when NODE_ENV=production');
  });

  it('rejects mock social publisher and video storage in production', () => {
    const productionBase = {
      NODE_ENV: 'production',
      AUTH_PROVIDER: 'firebase',
      FIREBASE_PROJECT_ID: 'postdee-prod',
      BILLING_PROVIDER: 'store'
    };

    expect(() =>
      readServerConfig({
        ...productionBase,
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
        // SOCIAL_PUBLISHER left at its mock default.
      })
    ).toThrow('SOCIAL_PUBLISHER=mock is not allowed when NODE_ENV=production');

    expect(() =>
      readServerConfig({
        ...productionBase,
        SOCIAL_PUBLISHER: 'postpeer',
        POSTPEER_API_KEY: 'postpeer-key'
        // VIDEO_STORAGE left at its mock default.
      })
    ).toThrow('VIDEO_STORAGE=mock is not allowed when NODE_ENV=production');
  });

  it('allows RevenueCat billing in production', () => {
    const config = readServerConfig({
      NODE_ENV: 'production',
      AUTH_PROVIDER: 'firebase',
      FIREBASE_PROJECT_ID: 'postdee-prod',
      BILLING_PROVIDER: 'revenuecat',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: 'revenuecat-webhook-token',
      REVENUECAT_STARTER_ENTITLEMENT_ID: 'starter',
      REVENUECAT_PRO_ENTITLEMENT_ID: 'pro',
      REVENUECAT_STARTER_PRODUCT_ID: 'postdee_starter_monthly',
      REVENUECAT_PRO_PRODUCT_ID: 'postdee_pro_monthly',
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'postpeer-key',
      VIDEO_STORAGE: 'r2',
      CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
    });

    expect(config).toMatchObject({
      nodeEnv: 'production',
      authProvider: 'firebase',
      billingProvider: 'revenuecat',
      revenueCatWebhookAuthToken: 'revenuecat-webhook-token',
      revenueCatStarterEntitlementId: 'starter',
      revenueCatProEntitlementId: 'pro',
      revenueCatStarterProductId: 'postdee_starter_monthly',
      revenueCatProProductId: 'postdee_pro_monthly'
    });
  });

  it('requires a RevenueCat webhook token in production RevenueCat billing mode', () => {
    expect(() =>
      readServerConfig({
        NODE_ENV: 'production',
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-prod',
        BILLING_PROVIDER: 'revenuecat'
      })
    ).toThrow(
      'REVENUECAT_WEBHOOK_AUTH_TOKEN is required when BILLING_PROVIDER=revenuecat in production'
    );
  });

  it('reads optional PostPeer connect configuration', () => {
    const config = readServerConfig({
      POSTPEER_CONNECT_CREATE_PATH: '/v1/connect/links',
      POSTPEER_CONNECT_CALLBACK_URL:
        'https://postdee-api.onrender.com/social-connections/postpeer/callback',
      POSTPEER_CONNECT_STATE_SECRET: 'state-secret',
      POSTPEER_CONNECT_CALLBACK_SECRET: 'callback-secret'
    });

    expect(config.postPeerConnectCreatePath).toBe('/v1/connect/links');
    expect(config.postPeerConnectCallbackUrl).toBe(
      'https://postdee-api.onrender.com/social-connections/postpeer/callback'
    );
    expect(config.postPeerConnectStateSecret).toBe('state-secret');
    expect(config.postPeerConnectCallbackSecret).toBe('callback-secret');
  });

  it('does not expose legacy clip review config values', () => {
    const config = readServerConfig({
      CLIP_REVIEW_PROVIDER: 'gemini',
      GEMINI_CLIP_REVIEW_MODEL: 'gemini-2.5-flash-lite-preview'
    });

    expect(config).not.toHaveProperty('clipReviewProvider');
    expect(config).not.toHaveProperty('geminiClipReviewModel');
  });

  it('rejects invalid PORT values', () => {
    expect(() => readServerConfig({ PORT: 'not-a-number' })).toThrow(
      'PORT must be a number between 1 and 65535'
    );
  });

  it('rejects invalid TEMPLATE_STORE values', () => {
    expect(() => readServerConfig({ TEMPLATE_STORE: 'database' })).toThrow(
      'TEMPLATE_STORE must be memory or prisma'
    );
  });

  it('rejects invalid POST_STORE values', () => {
    expect(() => readServerConfig({ POST_STORE: 'database' })).toThrow(
      'POST_STORE must be memory or prisma'
    );
  });

  it('rejects invalid SUBSCRIPTION_STORE values', () => {
    expect(() => readServerConfig({ SUBSCRIPTION_STORE: 'database' })).toThrow(
      'SUBSCRIPTION_STORE must be memory or prisma'
    );
  });

  it('rejects invalid BILLING_PROVIDER values', () => {
    expect(() => readServerConfig({ BILLING_PROVIDER: 'paypal' })).toThrow(
      'BILLING_PROVIDER must be mock, store, or revenuecat'
    );
  });

  it('rejects invalid APPLE_APP_STORE_ENVIRONMENT values', () => {
    expect(() => readServerConfig({ APPLE_APP_STORE_ENVIRONMENT: 'testflight' })).toThrow(
      'APPLE_APP_STORE_ENVIRONMENT must be sandbox or production'
    );
  });

  it('rejects invalid APPLE_APP_APPLE_ID values', () => {
    expect(() => readServerConfig({ APPLE_APP_APPLE_ID: '0' })).toThrow(
      'APPLE_APP_APPLE_ID must be a positive number'
    );
  });

  it('rejects invalid ANALYTICS_STORE values', () => {
    expect(() => readServerConfig({ ANALYTICS_STORE: 'external' })).toThrow(
      'ANALYTICS_STORE must be memory or prisma'
    );
  });

  it('rejects invalid CAPTION_USAGE_STORE values', () => {
    expect(() => readServerConfig({ CAPTION_USAGE_STORE: 'external' })).toThrow(
      'CAPTION_USAGE_STORE must be memory or prisma'
    );
  });

  it('rejects invalid PUBLISH_QUEUE values', () => {
    expect(() => readServerConfig({ PUBLISH_QUEUE: 'redis' })).toThrow(
      'PUBLISH_QUEUE must be memory or bullmq'
    );
  });

  it('requires the Prisma post store when BullMQ publish queue is enabled', () => {
    expect(() =>
      readServerConfig({
        PUBLISH_QUEUE: 'bullmq',
        POST_STORE: 'memory'
      })
    ).toThrow('PUBLISH_QUEUE=bullmq requires POST_STORE=prisma');
  });

  it('requires DATABASE_URL when a Prisma-backed store is enabled', () => {
    expect(() =>
      readServerConfig({
        POST_STORE: 'prisma'
      })
    ).toThrow('DATABASE_URL is required when any Prisma-backed store is enabled');
  });

  it('rejects invalid VIDEO_STORAGE values', () => {
    expect(() => readServerConfig({ VIDEO_STORAGE: 'filesystem' })).toThrow(
      'VIDEO_STORAGE must be mock, s3, or r2'
    );
  });

  it('rejects invalid AWS_S3_UPLOAD_EXPIRES_SECONDS values', () => {
    expect(() => readServerConfig({ AWS_S3_UPLOAD_EXPIRES_SECONDS: '0' })).toThrow(
      'AWS_S3_UPLOAD_EXPIRES_SECONDS must be a positive number'
    );
  });

  it('rejects invalid CAPTION_PROVIDER values', () => {
    expect(() => readServerConfig({ CAPTION_PROVIDER: 'local' })).toThrow(
      'CAPTION_PROVIDER must be mock, openai, or gemini'
    );
  });

  it('rejects invalid TRANSCRIPTION_PROVIDER values', () => {
    expect(() => readServerConfig({ TRANSCRIPTION_PROVIDER: 'local' })).toThrow(
      'TRANSCRIPTION_PROVIDER must be mock, openai, or groq'
    );
  });

  it('rejects invalid AUTH_PROVIDER values', () => {
    expect(() => readServerConfig({ AUTH_PROVIDER: 'password' })).toThrow(
      'AUTH_PROVIDER must be mock or firebase'
    );
  });
});
