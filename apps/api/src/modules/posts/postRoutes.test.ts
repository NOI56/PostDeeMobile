import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { createPostStore } from './postStore.js';
import { registerPostRoutes } from './postRoutes.js';

describe('post routes', () => {
  const allPlatforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
  const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
    `uploads/${encodeURIComponent(userId)}/${uploadId}/${fileName}`;

  it('lists posts from the in-memory store', async () => {
    const app = createApp();

    const response = await request(app).get('/posts').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      posts: []
    });
  });

  it('creates a queued post for selected platforms', async () => {
    const app = createApp();

    const createResponse = await request(app)
      .post('/posts')
      .send({
        caption: 'ของดีต้องลอง #ของดีบอกต่อ',
        videoS3Key: ownedUploadKey('local-dev-user', 'demo-video.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(createResponse.body.post).toMatchObject({
      caption: 'ของดีต้องลอง #ของดีบอกต่อ',
      videoS3Key: ownedUploadKey('local-dev-user', 'demo-video.mp4'),
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      scheduledAt: '2026-06-02T10:00:00.000Z',
      status: 'QUEUED'
    });
    expect(createResponse.body.post.id).toEqual(expect.any(String));
    expect(createResponse.body.post.userId).toBe('local-dev-user');
    expect(createResponse.body.publishJob).toMatchObject({
      queueName: 'publish-posts',
      postId: createResponse.body.post.id,
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      runAt: '2026-06-02T10:00:00.000Z',
      status: 'SCHEDULED'
    });
    expect(createResponse.body.publishJob.id).toEqual(expect.any(String));

    const listResponse = await request(app).get('/posts').expect(200);

    expect(listResponse.body.posts).toEqual([createResponse.body.post]);
  });

  it('rejects post creation with media owned by another user', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Do not publish another seller media',
        videoS3Key: ownedUploadKey('seller-b', 'other-seller.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      message: 'Selected media does not belong to the authenticated user'
    });
  });

  it('does not leave a queued post behind when publish queue enqueue fails', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = {
      ...createInMemoryPublishQueue(),
      enqueue: vi.fn(async () => {
        throw new Error('redis down');
      })
    };
    const authMiddleware = (_request: express.Request, response: express.Response, next: express.NextFunction) => {
      response.locals.authUser = {
        id: 'seller-queue-down',
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };

    app.use(express.json());
    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      createSubscriptionStore()
    );
    app.use(router);

    const response = await request(app)
      .post('/posts')
      .send({
        caption: 'Queue should fail after post create',
        videoS3Key: ownedUploadKey('seller-queue-down', 'queue-down.mp4'),
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(503);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PUBLISH_QUEUE_UNAVAILABLE',
      message: 'Publish queue is temporarily unavailable. Please try again.'
    });
    expect(await postStore.list({ userId: 'seller-queue-down' })).toEqual([]);
  });

  it('keeps the original schedule when publish queue reschedule fails', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = {
      ...createInMemoryPublishQueue(),
      reschedule: vi.fn(async () => {
        throw new Error('redis down');
      })
    };
    const authMiddleware = (_request: express.Request, response: express.Response, next: express.NextFunction) => {
      response.locals.authUser = {
        id: 'seller-reschedule-down',
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };
    const originalRunAt = '2026-06-02T10:00:00.000Z';
    const post = await postStore.create({
      userId: 'seller-reschedule-down',
      caption: 'Original schedule',
      videoS3Key: ownedUploadKey('seller-reschedule-down', 'original.mp4'),
      platforms: ['TIKTOK'],
      scheduledAt: originalRunAt
    });

    app.use(express.json());
    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      createSubscriptionStore()
    );
    app.use(router);

    const response = await request(app)
      .patch(`/posts/${post.id}`)
      .send({ scheduledAt: '2026-06-03T10:00:00.000Z' })
      .expect(503);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PUBLISH_QUEUE_UNAVAILABLE',
      message: 'Publish queue is temporarily unavailable. Please try again.'
    });

    const [storedPost] = await postStore.list({ userId: 'seller-reschedule-down' });
    expect(storedPost.scheduledAt).toBe(originalRunAt);
  });

  it('rejects request-body subscription plan overrides in production', async () => {
    const app = createApp({
      config: {
        ...readServerConfig({}),
        nodeEnv: 'production'
      }
    });

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Do not trust client plan',
        videoS3Key: ownedUploadKey('local-dev-user', 'client-plan.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      code: 'SUBSCRIPTION_PLAN_OVERRIDE_DISABLED',
      message: 'subscriptionPlan overrides are only available in local mock development'
    });
  });

  it('lists only scheduled posts when requested by the calendar', async () => {
    const app = createApp();

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'calendar-seller')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Immediate clip',
        videoS3Key: ownedUploadKey('calendar-seller', 'immediate-video.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(201);

    const scheduledResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'calendar-seller')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Scheduled calendar clip',
        videoS3Key: ownedUploadKey('calendar-seller', 'scheduled-video.mp4'),
        platforms: ['YOUTUBE_SHORTS', 'INSTAGRAM_REELS'],
        scheduledAt: '2026-06-07T11:30:00.000Z'
      })
      .expect(201);

    const listResponse = await request(app)
      .get('/posts?scheduled=true')
      .set('x-postdee-user-id', 'calendar-seller')
      .expect(200);

    expect(listResponse.body.posts).toEqual([scheduledResponse.body.post]);
  });

  it('scopes post lists and Basic monthly limits by authenticated user', async () => {
    const app = createApp();

    for (let index = 0; index < 3; index += 1) {
      await request(app)
        .post('/posts')
        .set('x-postdee-user-id', 'seller-a')
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: `Seller A post ${index + 1}`,
          videoS3Key: ownedUploadKey('seller-a', `seller-a-video-${index + 1}.mp4`),
          platforms: ['TIKTOK']
        })
        .expect(201);
    }

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Seller A post 4',
        videoS3Key: ownedUploadKey('seller-a', 'seller-a-video-4.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(402);

    const sellerBCreateResponse = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-b')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Seller B first post',
        videoS3Key: ownedUploadKey('seller-b', 'seller-b-video-1.mp4'),
        platforms: ['INSTAGRAM_REELS']
      })
      .expect(201);

    expect(sellerBCreateResponse.body.post).toMatchObject({
      userId: 'seller-b',
      caption: 'Seller B first post'
    });

    const sellerAListResponse = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .expect(200);
    const sellerBListResponse = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', 'seller-b')
      .expect(200);

    expect(sellerAListResponse.body.posts).toHaveLength(3);
    expect(
      sellerAListResponse.body.posts.every((post: { userId: string }) => post.userId === 'seller-a')
    ).toBe(true);
    expect(sellerBListResponse.body.posts).toEqual([sellerBCreateResponse.body.post]);
  });

  it('upserts the auth user before creating a Prisma-backed post', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const prisma = {
      user: {
        upsert: vi.fn().mockResolvedValue({
          id: 'seller-prisma',
          firebaseUid: 'mock:seller-prisma',
          email: 'seller@example.com',
          displayName: undefined,
          createdAt,
          updatedAt: createdAt
        })
      },
      post: {
        findMany: vi.fn().mockResolvedValue([]),
        create: vi.fn().mockResolvedValue({
          id: 'post-1',
          userId: 'seller-prisma',
          caption: 'Prisma post',
          videoS3Key: ownedUploadKey('seller-prisma', 'prisma-video.mp4'),
          selectedPlatforms: ['TIKTOK'],
          scheduledAt: null,
          status: 'QUEUED',
          createdAt
        })
      },
      template: {
        findMany: vi.fn(),
        create: vi.fn()
      }
    };
    const app = createApp({
      config: readServerConfig({
        DATABASE_URL: 'postgresql://postdee:postdee_password@localhost:5432/postdee',
        POST_STORE: 'prisma'
      }),
      prisma
    });

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-prisma')
      .set('x-postdee-email', 'seller@example.com')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Prisma post',
        videoS3Key: ownedUploadKey('seller-prisma', 'prisma-video.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(201);

    expect(prisma.user.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'seller-prisma' }
      })
    );
    expect(prisma.post.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          userId: 'seller-prisma'
        })
      })
    );
    expect(response.body.post).toMatchObject({
      id: 'post-1',
      userId: 'seller-prisma'
    });
  });

  it('creates an immediate post for the Basic plan', async () => {
    const app = createApp();

    const createResponse = await request(app)
      .post('/posts')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic real-time post',
        videoS3Key: ownedUploadKey('local-dev-user', 'basic-video.mp4'),
        platforms: ['FACEBOOK_REELS']
      })
      .expect(201);

    expect(createResponse.body.post).toMatchObject({
      caption: 'Basic real-time post',
      videoS3Key: ownedUploadKey('local-dev-user', 'basic-video.mp4'),
      platforms: ['FACEBOOK_REELS'],
      status: 'QUEUED'
    });
    expect(createResponse.body.post.scheduledAt).toBeUndefined();
    expect(createResponse.body.publishJob).toMatchObject({
      postId: createResponse.body.post.id,
      runAt: expect.any(String),
      status: 'READY'
    });
  });

  it('rejects scheduled posts for the Basic plan', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic scheduled post',
        videoS3Key: ownedUploadKey('local-dev-user', 'basic-video.mp4'),
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PAID_PLAN_REQUIRED',
      message: 'Cloud Scheduling requires the Starter or Pro plan'
    });
  });

  it('allows scheduled posts for mock Starter users without a body override', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-starter')
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        caption: 'Scheduled from Starter subscription',
        videoS3Key: ownedUploadKey('seller-starter', 'starter-video.mp4'),
        platforms: ['YOUTUBE_SHORTS'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(response.body.post).toMatchObject({
      userId: 'seller-starter',
      scheduledAt: '2026-06-02T10:00:00.000Z'
    });
    expect(response.body.publishJob).toMatchObject({
      status: 'SCHEDULED'
    });
  });

  it('allows scheduled posts for mock Pro users without a body override', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-pro')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Scheduled from subscription store',
        videoS3Key: ownedUploadKey('seller-pro', 'pro-video.mp4'),
        platforms: ['YOUTUBE_SHORTS'],
        scheduledAt: '2026-06-02T10:00:00.000Z'
      })
      .expect(201);

    expect(response.body.post).toMatchObject({
      userId: 'seller-pro',
      scheduledAt: '2026-06-02T10:00:00.000Z'
    });
    expect(response.body.publishJob).toMatchObject({
      status: 'SCHEDULED'
    });
  });

  it('rejects Basic posts after the monthly free limit', async () => {
    const app = createApp();

    for (let index = 0; index < 3; index += 1) {
      await request(app)
        .post('/posts')
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: `Basic post ${index + 1}`,
          videoS3Key: ownedUploadKey('local-dev-user', `basic-video-${index + 1}.mp4`),
          platforms: ['TIKTOK']
        })
        .expect(201);
    }

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic post 4',
        videoS3Key: ownedUploadKey('local-dev-user', 'basic-video-4.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'POST_LIMIT_REACHED',
      message: 'Basic plan is limited to 3 post units per month'
    });
  });

  it('counts monthly limits by selected platform units', async () => {
    const app = createApp();

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-basic-units')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic two-unit post',
        videoS3Key: ownedUploadKey('seller-basic-units', 'basic-two-unit-video.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
      })
      .expect(201);

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-basic-units')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Basic would exceed units',
        videoS3Key: ownedUploadKey('seller-basic-units', 'basic-over-unit-video.mp4'),
        platforms: ['INSTAGRAM_REELS', 'FACEBOOK_REELS']
      })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'POST_LIMIT_REACHED',
      message: 'Basic plan is limited to 3 post units per month'
    });
  });

  it('blocks Starter posts when selected platforms would exceed 120 monthly units', async () => {
    const app = createApp();
    const userId = 'seller-starter-units';

    for (let index = 0; index < 29; index += 1) {
      await request(app)
        .post('/posts')
        .set('x-postdee-user-id', userId)
        .set('x-postdee-subscription-plan', 'STARTER')
        .send({
          caption: `Starter four-unit post ${index + 1}`,
          videoS3Key: ownedUploadKey(userId, `starter-four-unit-${index + 1}.mp4`),
          platforms: allPlatforms
        })
        .expect(201);
    }

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        caption: 'Starter three-unit post',
        videoS3Key: ownedUploadKey(userId, 'starter-three-unit.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS']
      })
      .expect(201);

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        caption: 'Starter would exceed units',
        videoS3Key: ownedUploadKey(userId, 'starter-over-unit.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
      })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'POST_LIMIT_REACHED',
      message: 'Starter plan is limited to 120 post units per month'
    });
  });

  it('blocks Pro posts when selected platforms would exceed 250 monthly units', async () => {
    const app = createApp();
    const userId = 'seller-pro-units';

    for (let index = 0; index < 62; index += 1) {
      await request(app)
        .post('/posts')
        .set('x-postdee-user-id', userId)
        .set('x-postdee-subscription-plan', 'PRO')
        .send({
          caption: `Pro four-unit post ${index + 1}`,
          videoS3Key: ownedUploadKey(userId, `pro-four-unit-${index + 1}.mp4`),
          platforms: allPlatforms
        })
        .expect(201);
    }

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Pro would exceed units',
        videoS3Key: ownedUploadKey(userId, 'pro-over-unit.mp4'),
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS']
      })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'POST_LIMIT_REACHED',
      message: 'Pro plan is limited to 250 post units per month'
    });
  });

  it('rejects Basic posts until the user verifies a phone number', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .send({
        caption: 'Unverified Basic post',
        videoS3Key: ownedUploadKey('local-dev-user', 'basic-unverified-video.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PHONE_VERIFICATION_REQUIRED',
      message: 'Phone verification is required to use the Basic free post quota'
    });
  });

  it('allows Basic posts in a new month after the previous month reached the free limit', async () => {
    vi.useFakeTimers({
      toFake: ['Date']
    });

    try {
      const app = createApp();

      vi.setSystemTime(new Date('2026-05-31T12:00:00.000Z'));

      for (let index = 0; index < 3; index += 1) {
        await request(app)
          .post('/posts')
          .set('x-postdee-user-id', 'seller-monthly-reset')
          .set('x-postdee-phone-verified', 'true')
          .send({
            caption: `May post ${index + 1}`,
            videoS3Key: ownedUploadKey('seller-monthly-reset', `may-video-${index + 1}.mp4`),
            platforms: ['TIKTOK']
          })
          .expect(201);
      }

      vi.setSystemTime(new Date('2026-06-01T12:00:00.000Z'));

      const response = await request(app)
        .post('/posts')
        .set('x-postdee-user-id', 'seller-monthly-reset')
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: 'June post 1',
          videoS3Key: ownedUploadKey('seller-monthly-reset', 'june-video-1.mp4'),
          platforms: ['TIKTOK']
        })
        .expect(201);

      expect(response.body.post).toMatchObject({
        userId: 'seller-monthly-reset',
        caption: 'June post 1'
      });

      const subscriptionResponse = await request(app)
        .get('/billing/subscription')
        .set('x-postdee-user-id', 'seller-monthly-reset')
        .set('x-postdee-phone-verified', 'true')
        .expect(200);

      expect(subscriptionResponse.body.subscription).toMatchObject({
        usedPostsThisMonth: 1,
        remainingPostsThisMonth: 2
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it('rejects posts without required fields or platforms', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .send({
        caption: '',
        videoS3Key: ownedUploadKey('local-dev-user', 'demo-video.mp4'),
        platforms: []
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'caption, videoS3Key, and at least one valid platform are required'
    });
  });

  const createScheduledPost = async (app: ReturnType<typeof createApp>) => {
    const response = await request(app)
      .post('/posts')
      .send({
        caption: 'scheduled clip',
        videoS3Key: ownedUploadKey('local-dev-user', 'scheduled.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2026-06-10T10:00:00.000Z'
      })
      .expect(201);

    return response.body.post.id as string;
  };

  it('reschedules a queued post and persists the new time', async () => {
    const app = createApp();
    const postId = await createScheduledPost(app);

    const patchResponse = await request(app)
      .patch(`/posts/${postId}`)
      .send({ scheduledAt: '2026-06-12T15:30:00.000Z' })
      .expect(200);

    expect(patchResponse.body.post.scheduledAt).toBe('2026-06-12T15:30:00.000Z');

    const listResponse = await request(app).get('/posts?scheduled=true').expect(200);
    expect(listResponse.body.posts[0].scheduledAt).toBe('2026-06-12T15:30:00.000Z');
  });

  it('reschedules the existing publish queue job when a scheduled post moves', async () => {
    const app = createApp();
    const postId = await createScheduledPost(app);

    await request(app)
      .patch(`/posts/${postId}`)
      .send({ scheduledAt: '2026-06-12T15:30:00.000Z' })
      .expect(200);

    const queueResponse = await request(app).get('/queue/jobs').expect(200);

    expect(queueResponse.body.jobs).toHaveLength(1);
    expect(queueResponse.body.jobs[0]).toMatchObject({
      postId,
      runAt: '2026-06-12T15:30:00.000Z',
      status: 'SCHEDULED'
    });
  });

  it('cancels a queued post so it no longer appears', async () => {
    const app = createApp();
    const postId = await createScheduledPost(app);

    await request(app).delete(`/posts/${postId}`).expect(200);

    const listResponse = await request(app).get('/posts').expect(200);
    expect(listResponse.body.posts).toEqual([]);
  });

  it('removes the existing publish queue job when a scheduled post is canceled', async () => {
    const app = createApp();
    const postId = await createScheduledPost(app);

    await request(app).delete(`/posts/${postId}`).expect(200);

    const queueResponse = await request(app).get('/queue/jobs').expect(200);

    expect(queueResponse.body.jobs).toEqual([]);
  });

  it('returns 404 when rescheduling a post that does not exist', async () => {
    const app = createApp();

    await request(app)
      .patch('/posts/missing-id')
      .send({ scheduledAt: '2026-06-12T15:30:00.000Z' })
      .expect(404);
  });
});
