import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

const encodeGoogleNotification = (payload: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(payload), 'utf8').toString('base64');

describe('billing routes', () => {
  const googlePlayNotificationAuthToken = 'google-play-notification-token';
  const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
    'uploads/' + encodeURIComponent(userId) + '/' + uploadId + '/' + fileName;
  it('returns the current Basic subscription status', async () => {
    const app = createApp();

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-basic')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      subscription: {
        userId: 'seller-basic',
        plan: 'BASIC',
        status: 'INACTIVE',
        monthlyPostLimit: 3,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: 0,
        phoneVerified: false,
        requiresPhoneVerification: true,
        canUseFreePostQuota: false,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false,
        canUseAiAudioReview: false,
        canUseAiVideoReview: false
      }
    });
  });

  it('returns Basic free quota after phone verification', async () => {
    const app = createApp();

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-basic-phone')
      .set('x-postdee-phone-verified', 'true')
      .expect(200);

    expect(response.body.subscription).toMatchObject({
      userId: 'seller-basic-phone',
      plan: 'BASIC',
      monthlyPostLimit: 3,
      usedPostsThisMonth: 0,
      remainingPostsThisMonth: 3,
      phoneVerified: true,
      requiresPhoneVerification: false,
      canUseFreePostQuota: true
    });
  });

  it('returns Basic post usage for the current month', async () => {
    const app = createApp();

    for (let index = 0; index < 2; index += 1) {
      await request(app)
        .post('/posts')
        .set('x-postdee-user-id', 'seller-usage')
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: `Usage post ${index + 1}`,
          videoS3Key: ownedUploadKey('seller-usage', `usage-video-${index + 1}.mp4`),
          platforms: ['TIKTOK']
        })
        .expect(201);
    }

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-usage')
      .set('x-postdee-phone-verified', 'true')
      .expect(200);

    expect(response.body.subscription).toMatchObject({
      userId: 'seller-usage',
      plan: 'BASIC',
      monthlyPostLimit: 3,
      usedPostsThisMonth: 2,
      remainingPostsThisMonth: 1,
      phoneVerified: true,
      requiresPhoneVerification: false,
      canUseFreePostQuota: true
    });
  });

  it('returns Pro subscription status after mock activation', async () => {
    const app = createApp();

    await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', 'seller-pro-status')
      .send({ plan: 'PRO' })
      .expect(200);

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-pro-status')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      subscription: {
        userId: 'seller-pro-status',
        plan: 'PRO',
        status: 'ACTIVE',
        monthlyPostLimit: 250,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: 250,
        phoneVerified: false,
        requiresPhoneVerification: false,
        canUseFreePostQuota: false,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true,
        canUseAiAudioReview: false,
        canUseAiVideoReview: false
      }
    });
  });

  it('rejects mock billing activation in production', async () => {
    const app = createApp({
      config: {
        ...readServerConfig({}),
        nodeEnv: 'production'
      }
    });

    const response = await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', 'seller-production-mock')
      .send({ plan: 'PRO' })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      code: 'MOCK_BILLING_DISABLED',
      message: 'Mock billing activation is only available in local mock development'
    });
  });

  it('returns Starter subscription status after mock activation', async () => {
    const app = createApp();

    await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', 'seller-starter-status')
      .send({ plan: 'STARTER' })
      .expect(200);

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-starter-status')
      .expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      subscription: {
        userId: 'seller-starter-status',
        plan: 'STARTER',
        status: 'ACTIVE',
        monthlyPostLimit: 120,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: 120,
        phoneVerified: false,
        requiresPhoneVerification: false,
        canUseFreePostQuota: false,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false,
        canUseAiAudioReview: false,
        canUseAiVideoReview: false
      }
    });
  });

  it('returns paid post usage as selected platform units', async () => {
    const app = createApp();

    await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', 'seller-starter-unit-status')
      .send({ plan: 'STARTER' })
      .expect(200);

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-starter-unit-status')
      .send({
        caption: 'Starter multi-platform post',
        videoS3Key: ownedUploadKey('seller-starter-unit-status', 'starter-unit-status.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS']
      })
      .expect(201);

    const response = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-starter-unit-status')
      .expect(200);

    expect(response.body.subscription).toMatchObject({
      userId: 'seller-starter-unit-status',
      plan: 'STARTER',
      monthlyPostLimit: 120,
      usedPostsThisMonth: 3,
      remainingPostsThisMonth: 117,
      canSchedule: true
    });
  });

  it('does not expose legacy checkout return pages for store billing', async () => {
    const app = createApp();

    await request(app).get('/billing/return/success').expect(404);
    await request(app).get('/billing/return/cancel').expect(404);
  });

  it('does not expose a legacy checkout session route for store billing', async () => {
    const app = createApp();

    await request(app)
      .post('/billing/checkout')
      .set('x-postdee-user-id', 'seller-checkout')
      .send({
        plan: 'PRO',
        successUrl: 'https://postdee.local/billing/success',
        cancelUrl: 'https://postdee.local/billing/cancel'
      })
      .expect(404);
  });

  it('activates mock Pro billing for the authenticated user', async () => {
    const app = createApp();

    const billingResponse = await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', 'seller-pro')
      .send({ plan: 'PRO' })
      .expect(200);

    expect(billingResponse.body).toMatchObject({
      status: 'ok',
      subscription: {
        userId: 'seller-pro',
        plan: 'PRO',
        status: 'ACTIVE'
      }
    });

    const postResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-pro')
      .send({
        caption: 'Scheduled after mock Pro activation',
        videoS3Key: ownedUploadKey('seller-pro', 'pro-after-billing.mp4'),
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(postResponse.body.post).toMatchObject({
      userId: 'seller-pro',
      scheduledAt: '2026-06-02T10:00:00.000Z'
    });
  });

  it('activates Pro from a verified Android store subscription purchase', async () => {
    const app = createApp();

    const billingResponse = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-android-store')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      })
      .expect(200);

    expect(billingResponse.body).toMatchObject({
      status: 'ok',
      purchase: {
        provider: 'mock-store',
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly'
      },
      subscription: {
        userId: 'seller-android-store',
        plan: 'PRO',
        status: 'ACTIVE'
      }
    });

    const postResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-android-store')
      .send({
        caption: 'Scheduled after Android store subscription',
        videoS3Key: ownedUploadKey('seller-android-store', 'pro-after-android-store.mp4'),
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(postResponse.body.post).toMatchObject({
      userId: 'seller-android-store',
      scheduledAt: '2026-06-02T10:00:00.000Z'
    });
  });

  it('rejects Google Play notifications without the configured bearer token', async () => {
    const app = createApp({
      config: readServerConfig({
        GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN: googlePlayNotificationAuthToken
      })
    });

    await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-android-unauthorized-notification')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-unauthorized-notification-token'
      })
      .expect(200);

    const response = await request(app)
      .post('/billing/google-play/notifications')
      .send({
        message: {
          messageId: 'pubsub-message-unauthorized',
          data: encodeGoogleNotification({
            version: '1.0',
            packageName: 'com.postdee',
            eventTimeMillis: '1780531200000',
            subscriptionNotification: {
              version: '1.0',
              notificationType: 13,
              purchaseToken: 'android-unauthorized-notification-token',
              subscriptionId: 'postdee_pro_monthly'
            }
          })
        },
        subscription: 'projects/postdee/subscriptions/play-rtdn'
      })
      .expect(401);

    expect(response.body).toEqual({
      status: 'error',
      code: 'GOOGLE_PLAY_NOTIFICATION_UNAUTHORIZED',
      message: 'Google Play notification authorization is invalid'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-android-unauthorized-notification')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-android-unauthorized-notification',
      plan: 'PRO',
      status: 'ACTIVE'
    });
  });

  it('moves a verified Android store subscription back to Basic after an expired Google Play notification', async () => {
    const app = createApp({
      config: readServerConfig({
        GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN: googlePlayNotificationAuthToken
      })
    });

    await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-android-expired')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-expired-purchase-token'
      })
      .expect(200);

    await request(app)
      .post('/billing/google-play/notifications')
      .set('Authorization', 'Bearer ' + googlePlayNotificationAuthToken)
      .send({
        message: {
          messageId: 'pubsub-message-expired',
          data: encodeGoogleNotification({
            version: '1.0',
            packageName: 'com.postdee',
            eventTimeMillis: '1780531200000',
            subscriptionNotification: {
              version: '1.0',
              notificationType: 13,
              purchaseToken: 'android-expired-purchase-token',
              subscriptionId: 'postdee_pro_monthly'
            }
          })
        },
        subscription: 'projects/postdee/subscriptions/play-rtdn'
      })
      .expect(200);

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-android-expired')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-android-expired',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('moves a verified Android store subscription back to Basic after a Google Play voided purchase notification', async () => {
    const app = createApp({
      config: readServerConfig({
        GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN: googlePlayNotificationAuthToken
      })
    });

    await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-android-voided')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-voided-purchase-token'
      })
      .expect(200);

    await request(app)
      .post('/billing/google-play/notifications')
      .set('Authorization', 'Bearer ' + googlePlayNotificationAuthToken)
      .send({
        message: {
          messageId: 'pubsub-message-voided',
          data: encodeGoogleNotification({
            version: '1.0',
            packageName: 'com.postdee',
            eventTimeMillis: '1780531200000',
            voidedPurchaseNotification: {
              purchaseToken: 'android-voided-purchase-token',
              orderId: 'GPA.0000-0000-0000-00000',
              productType: 1,
              refundType: 1
            }
          })
        },
        subscription: 'projects/postdee/subscriptions/play-rtdn'
      })
      .expect(200);

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-android-voided')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-android-voided',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('activates Pro from a verified iOS store subscription purchase', async () => {
    const app = createApp();

    const billingResponse = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-ios-store')
      .send({
        platform: 'IOS',
        productId: 'postdee_pro_monthly',
        transactionId: 'ios-transaction-id'
      })
      .expect(200);

    expect(billingResponse.body).toMatchObject({
      status: 'ok',
      purchase: {
        provider: 'mock-store',
        platform: 'IOS',
        productId: 'postdee_pro_monthly'
      },
      subscription: {
        userId: 'seller-ios-store',
        plan: 'PRO',
        status: 'ACTIVE'
      }
    });
  });

  it('moves a verified iOS store subscription back to Basic after an Apple notification with original transaction id', async () => {
    const app = createApp({
      storePurchaseVerifier: {
        verify: async (purchase) => ({
          provider: 'apple-app-store',
          platform: 'IOS',
          productId: purchase.productId,
          transactionId: purchase.transactionId,
          originalTransactionId: 'ios-original-transaction-id',
          verifiedAt: '2026-06-04T00:00:00.000Z'
        })
      },
      appleSignedNotificationDecoder: async () => ({
        notificationUUID: 'apple-notification-expired',
        notificationType: 'EXPIRED',
        signedDate: 1780531200000,
        data: {
          bundleId: 'com.postdee',
          environment: 'Sandbox',
          decodedTransaction: {
            transactionId: 'ios-renewal-transaction-id',
            originalTransactionId: 'ios-original-transaction-id'
          }
        }
      })
    });

    await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-ios-expired')
      .send({
        platform: 'IOS',
        productId: 'postdee_pro_monthly',
        transactionId: 'ios-first-transaction-id'
      })
      .expect(200);

    await request(app)
      .post('/billing/apple/notifications')
      .send({
        signedPayload: 'verified-apple-signed-payload'
      })
      .expect(200);

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-ios-expired')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-ios-expired',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('accepts the configured Pro monthly store product id', async () => {
    const app = createApp({
      config: readServerConfig({
        STORE_PRO_MONTHLY_PRODUCT_ID: 'postdee_pro_monthly_test'
      })
    });

    const response = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-configured-store')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly_test',
        purchaseToken: 'android-purchase-token'
      })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      purchase: {
        provider: 'mock-store',
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly_test'
      },
      subscription: {
        userId: 'seller-configured-store',
        plan: 'PRO',
        status: 'ACTIVE'
      }
    });
  });

  it('activates Starter from the configured Starter monthly store product id', async () => {
    const app = createApp({
      config: readServerConfig({
        STORE_STARTER_MONTHLY_PRODUCT_ID: 'postdee_starter_monthly_test'
      })
    });

    const response = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-starter-store')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_starter_monthly_test',
        purchaseToken: 'android-starter-purchase-token'
      })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      purchase: {
        provider: 'mock-store',
        platform: 'ANDROID',
        productId: 'postdee_starter_monthly_test'
      },
      subscription: {
        userId: 'seller-starter-store',
        plan: 'STARTER',
        status: 'ACTIVE'
      }
    });
  });

  it('does not activate Pro in store billing mode without a real verifier', async () => {
    const app = createApp({
      config: readServerConfig({
        BILLING_PROVIDER: 'store'
      })
    });

    const response = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-store-unconfigured')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      })
      .expect(501);

    expect(response.body).toEqual({
      status: 'error',
      code: 'STORE_VERIFIER_NOT_CONFIGURED',
      message:
        'Real Apple App Store / Google Play verification is not configured yet'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-store-unconfigured')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-store-unconfigured',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('activates Pro only after the configured store verifier accepts the purchase', async () => {
    const app = createApp({
      config: readServerConfig({
        BILLING_PROVIDER: 'store'
      }),
      storePurchaseVerifier: {
        verify: async (purchase) => ({
          provider: purchase.platform === 'ANDROID' ? 'google-play' : 'apple-app-store',
          platform: purchase.platform,
          productId: purchase.productId,
          purchaseToken: purchase.purchaseToken,
          transactionId: purchase.transactionId,
          verifiedAt: '2026-06-04T00:00:00.000Z'
        })
      }
    });

    const response = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-real-verifier')
      .send({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      purchase: {
        provider: 'google-play',
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      },
      subscription: {
        userId: 'seller-real-verifier',
        plan: 'PRO',
        status: 'ACTIVE'
      }
    });
  });

  it('rejects store subscription verification for unsupported platforms', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/billing/store/verify')
      .set('x-postdee-user-id', 'seller-store')
      .send({
        platform: 'WEB',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'web-token'
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'platform must be IOS or ANDROID'
    });
  });

  it('does not expose a legacy Stripe webhook route for store billing', async () => {
    const app = createApp();

    await request(app)
      .post('/billing/webhook/stripe')
      .set('stripe-signature', 't=1780000000,v1=invalid')
      .set('Content-Type', 'application/json')
      .send({
        type: 'checkout.session.completed'
      })
      .expect(404);
  });
});
