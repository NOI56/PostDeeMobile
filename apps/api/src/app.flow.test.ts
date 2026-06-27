import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import { createInMemorySocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';

afterEach(() => {
  vi.unstubAllGlobals();
});
describe('PostDee mock publishing flow', () => {
  it('creates an upload, generates a caption, queues a post, and exposes the queue job', async () => {
    const app = createApp();

    const uploadResponse = await request(app)
      .post('/uploads')
      .send({
        fileName: 'launch video.mp4',
        contentType: 'video/mp4',
        sizeBytes: 8_000_000,
        width: 1080,
        height: 1920
      })
      .expect(201);

    const captionResponse = await request(app)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ keywords: ['skincare', 'sale'] })
      .expect(200);

    const postResponse = await request(app)
      .post('/posts')
      .send({
        caption: captionResponse.body.caption,
        videoS3Key: uploadResponse.body.upload.videoS3Key,
        platforms: ['TIKTOK', 'INSTAGRAM_REELS'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(postResponse.body.post).toMatchObject({
      caption: captionResponse.body.caption,
      videoS3Key: uploadResponse.body.upload.videoS3Key,
      platforms: ['TIKTOK', 'INSTAGRAM_REELS'],
      status: 'QUEUED'
    });
    expect(postResponse.body.publishJob).toMatchObject({
      postId: postResponse.body.post.id,
      platforms: ['TIKTOK', 'INSTAGRAM_REELS'],
      status: 'SCHEDULED'
    });

    const queueResponse = await request(app)
      .get('/queue/jobs')
      .set('x-postdee-user-id', 'local-dev-user')
      .expect(200);

    expect(queueResponse.body.jobs).toEqual([postResponse.body.publishJob]);
  });

  it('updates Basic remaining post usage after upload and real-time post creation', async () => {
    const app = createApp();

    const uploadResponse = await request(app)
      .post('/uploads')
      .send({
        fileName: 'basic launch.mp4',
        contentType: 'video/mp4',
        sizeBytes: 6_000_000,
        width: 1080,
        height: 1920
      })
      .expect(201);

    const postResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-basic-flow')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic real-time launch post',
        videoS3Key: uploadResponse.body.upload.videoS3Key,
        platforms: ['TIKTOK']
      })
      .expect(201);

    expect(postResponse.body.post).toMatchObject({
      userId: 'seller-basic-flow',
      caption: 'Basic real-time launch post',
      videoS3Key: uploadResponse.body.upload.videoS3Key,
      platforms: ['TIKTOK'],
      status: 'QUEUED'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-basic-flow')
      .set('x-postdee-phone-verified', 'true')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-basic-flow',
      plan: 'BASIC',
      monthlyPostLimit: 3,
      usedPostsThisMonth: 1,
      remainingPostsThisMonth: 2,
      phoneVerified: true,
      requiresPhoneVerification: false,
      canUseFreePostQuota: true,
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false
    });
  });

  it('activates Pro and creates a scheduled queue job', async () => {
    const app = createApp();
    const userId = 'seller-pro-flow';
    const scheduledAt = '2026-06-05T10:00:00.000Z';

    const uploadResponse = await request(app)
      .post('/uploads')
      .send({
        fileName: 'pro scheduled launch.mp4',
        contentType: 'video/mp4',
        sizeBytes: 9_000_000,
        width: 1080,
        height: 1920
      })
      .expect(201);

    const activationResponse = await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', userId)
      .send({ plan: 'PRO' })
      .expect(200);

    expect(activationResponse.body.subscription).toMatchObject({
      userId,
      plan: 'PRO',
      status: 'ACTIVE'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', userId)
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId,
      plan: 'PRO',
      canSchedule: true
    });

    const postResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({
        caption: 'Pro scheduled launch post',
        videoS3Key: uploadResponse.body.upload.videoS3Key,
        platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'],
        scheduledAt
      })
      .expect(201);

    expect(postResponse.body.post).toMatchObject({
      userId,
      caption: 'Pro scheduled launch post',
      videoS3Key: uploadResponse.body.upload.videoS3Key,
      platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'],
      scheduledAt,
      status: 'QUEUED'
    });
    expect(postResponse.body.publishJob).toMatchObject({
      postId: postResponse.body.post.id,
      platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'],
      runAt: scheduledAt,
      status: 'SCHEDULED'
    });

    const queueResponse = await request(app)
      .get('/queue/jobs')
      .set('x-postdee-user-id', userId)
      .expect(200);

    expect(queueResponse.body.jobs).toEqual([postResponse.body.publishJob]);
  });

  it('blocks Basic AI captions and allows them after Pro activation', async () => {
    const app = createApp();
    const userId = 'seller-caption-flow';

    const basicResponse = await request(app)
      .post('/captions/generate')
      .set('x-postdee-user-id', userId)
      .send({ keywords: ['skincare'] })
      .expect(402);

    expect(basicResponse.body).toEqual({
      status: 'error',
      code: 'PRO_REQUIRED',
      message: 'AI Caption Assistant requires a paid plan'
    });

    await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', userId)
      .send({ plan: 'PRO' })
      .expect(200);

    const proResponse = await request(app)
      .post('/captions/generate')
      .set('x-postdee-user-id', userId)
      .send({ keywords: ['skincare', 'sale'] })
      .expect(200);

    expect(proResponse.body).toMatchObject({
      status: 'ok',
      model: 'local-template',
      affiliateLinkPlaceholder: expect.any(String)
    });
    expect(proResponse.body.caption).toContain('skincare');
    expect(proResponse.body.caption).toContain('sale');
    expect(proResponse.body.hashtags).toHaveLength(5);
  });

  it('blocks Basic analytics and allows analytics after Pro activation', async () => {
    const app = createApp();
    const userId = 'seller-analytics-flow';

    const basicResponse = await request(app)
      .get('/analytics/summary')
      .set('x-postdee-user-id', userId)
      .expect(402);

    expect(basicResponse.body).toEqual({
      status: 'error',
      code: 'PRO_REQUIRED',
      message: 'Unified Analytics requires the Pro plan'
    });

    await request(app)
      .post('/billing/mock-success')
      .set('x-postdee-user-id', userId)
      .send({ plan: 'PRO' })
      .expect(200);

    const proResponse = await request(app)
      .get('/analytics/summary')
      .set('x-postdee-user-id', userId)
      .expect(200);

    expect(proResponse.body).toEqual({
      status: 'ok',
      summary: {
        totalViews: 0,
        totalLikes: 0,
        platforms: [
          { platform: 'TIKTOK', label: 'TikTok', views: 0, likes: 0 },
          { platform: 'YOUTUBE_SHORTS', label: 'YouTube Shorts', views: 0, likes: 0 },
          { platform: 'INSTAGRAM_REELS', label: 'Instagram Reels', views: 0, likes: 0 },
          { platform: 'FACEBOOK_REELS', label: 'Facebook Reels', views: 0, likes: 0 }
        ]
      }
    });
  });
  it('publishes with the post owner social connection account id', async () => {
    const postPeerCalls: { body: { platforms?: Array<{ accountId?: string }> } }[] = [];
    vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
      postPeerCalls.push({
        body: JSON.parse(String(init.body))
      });
      return {
        ok: true,
        status: 200,
        json: async () => ({ externalPostId: 'pp-seller-a-post' })
      };
    });

    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.upsert({
      userId: 'seller-a',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-seller-a-tiktok'
    });
    await socialConnectionStore.upsert({
      userId: 'seller-b',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-seller-b-tiktok'
    });

    const app = createApp({
      config: readServerConfig({
        SOCIAL_PUBLISHER: 'postpeer',
        POSTPEER_API_KEY: 'pp-key',
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-test-videos',
        CLOUDFLARE_R2_ACCOUNT_ID: 'account-id',
        CLOUDFLARE_R2_ACCESS_KEY_ID: 'access-key',
        CLOUDFLARE_R2_SECRET_ACCESS_KEY: 'secret-key'
      }),
      socialConnectionStore,
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.test/upload',
        createPresignedDownloadUrl: async ({ key }) =>
          `https://r2.test/signed/${encodeURIComponent(key)}`,
        deleteObject: async () => undefined
      }
    });

    const postResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .send({
        caption: 'seller A launch',
        videoS3Key: 'uploads/seller-a/clip.mp4',
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO'
      })
      .expect(201);

    await app.locals.publishScheduler.runOnce();

    expect(postPeerCalls).toHaveLength(1);
    expect(postPeerCalls[0].body.platforms?.[0]?.accountId).toBe(
      'acct-seller-a-tiktok'
    );

    const postsResponse = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);
    expect(postsResponse.body.posts.find(
      (post: { id: string }) => post.id === postResponse.body.post.id
    )?.status).toBe('PUBLISHED');
  });
});
