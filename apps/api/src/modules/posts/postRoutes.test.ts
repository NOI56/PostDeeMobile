import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp as createPostDeeApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import { createPostStore, type QueuedPost } from './postStore.js';
import { registerPostRoutes } from './postRoutes.js';

describe('post routes', () => {
  const allPlatforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
  const futureNow = () => new Date('2026-06-01T00:00:00.000Z');
  const createApp = (options: Parameters<typeof createPostDeeApp>[0] = {}) =>
    createPostDeeApp({ now: futureNow, ...options });
  const socialPublishingUnavailableResponse = {
    status: 'error',
    code: 'SOCIAL_PUBLISHING_UNAVAILABLE',
    message: 'Social publishing is temporarily unavailable. Please try again later.'
  };
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

    expect(listResponse.body.posts).toEqual([
      { ...createResponse.body.post, platformResults: [] }
    ]);
  });

  it('reports whether the API accepts new social publishing requests', async () => {
    const app = createApp();
    const disabledApp = createApp({
      config: readServerConfig({ SOCIAL_PUBLISHER: 'disabled' })
    });

    const readyResponse = await request(app)
      .get('/publishing/readiness')
      .expect(200)
      .expect({
        status: 'ok',
        acceptingPosts: true,
        platformSettingsVersion: 1
      });
    const disabledResponse = await request(disabledApp)
      .get('/publishing/readiness')
      .expect(503)
      .expect(socialPublishingUnavailableResponse);

    expect(readyResponse.headers['cache-control']).toBe('private, no-store');
    expect(disabledResponse.headers['cache-control']).toBe('private, no-store');
  });

  it('fails before upload-readiness, persistence, quota, or queue side effects when social publishing is disabled', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const inMemoryPublishQueue = createInMemoryPublishQueue();
    const publishQueue = {
      ...inMemoryPublishQueue,
      enqueue: vi.fn(inMemoryPublishQueue.enqueue),
      reschedule: vi.fn(inMemoryPublishQueue.reschedule)
    };
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore();
    const ensureUser = vi.spyOn(userStore, 'ensure');
    const readSubscriptionPlan = vi.spyOn(subscriptionStore, 'getPlan');
    const reschedulePost = vi.spyOn(postStore, 'reschedule');
    const assertUploadReady = vi.fn(async () => undefined);
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-publishing-disabled',
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
      userStore,
      subscriptionStore,
      createInMemoryPlatformPublishStore(),
      {
        socialPublishingEnabled: false,
        assertUploadReady
      }
    );
    app.use(router);

    await request(app)
      .get('/publishing/readiness')
      .expect(503)
      .expect(socialPublishingUnavailableResponse);

    await request(app)
      .post('/posts')
      .send({
        caption: 'Must stop before side effects',
        videoS3Key: ownedUploadKey(
          'seller-publishing-disabled',
          'publishing-disabled.mp4'
        ),
        platforms: ['TIKTOK']
      })
      .expect(503)
      .expect(socialPublishingUnavailableResponse);

    await request(app)
      .patch('/posts/not-created')
      .send({ scheduledAt: '2026-06-03T10:00:00.000Z' })
      .expect(503)
      .expect(socialPublishingUnavailableResponse);

    expect(assertUploadReady).not.toHaveBeenCalled();
    expect(readSubscriptionPlan).not.toHaveBeenCalled();
    expect(ensureUser).not.toHaveBeenCalled();
    expect(publishQueue.enqueue).not.toHaveBeenCalled();
    expect(publishQueue.reschedule).not.toHaveBeenCalled();
    expect(reschedulePost).not.toHaveBeenCalled();
    expect(await postStore.list({ userId: 'seller-publishing-disabled' })).toEqual([]);
    expect(await publishQueue.list({ userId: 'seller-publishing-disabled' })).toEqual([]);
  });

  it('redacts internal target and provider ids while exposing delivery outcome', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const post = await postStore.create({
      userId: 'seller-redaction',
      caption: 'Internal target evidence',
      videoS3Key: ownedUploadKey('seller-redaction', 'redaction.mp4'),
      platforms: ['TIKTOK'],
      platformTargets: {
        TIKTOK: {
          accountId: 'postpeer-secret-target',
          connectedAt: '2026-05-01T00:00:00.000Z'
        }
      }
    });
    await platformPublishStore.recordResults({
      postId: post.id,
      results: [
        {
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          externalPostId: 'https://tiktok.test/video/1',
          providerPostId: 'postpeer-provider-only',
          deliveryOutcome: 'PRIVATE',
          publishedAt: '2026-06-01T01:00:00.000Z'
        }
      ]
    });
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-redaction',
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
      createInMemoryPublishQueue(),
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      platformPublishStore,
      { now: futureNow }
    );
    app.use(router);

    const response = await request(app).get('/posts').expect(200);
    expect(response.body.posts[0]).not.toHaveProperty('platformTargets');
    expect(response.body.posts[0].platformResults[0]).not.toHaveProperty(
      'providerPostId'
    );
    expect(response.body.posts[0].platformResults[0]).toMatchObject({
      externalPostId: 'https://tiktok.test/video/1',
      deliveryOutcome: 'PRIVATE'
    });
  });

  it('replays the original target snapshot without rerouting to a reconnected account', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = createInMemoryPublishQueue();
    const originalTarget = {
      accountId: 'postpeer-youtube-original',
      externalAccountId: 'channel-original',
      connectedAt: '2026-05-01T10:00:00.000Z'
    };
    let currentTarget = originalTarget;
    const resolvePlatformTarget = vi.fn(async () => currentTarget);
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-target-replay',
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { resolvePlatformTarget }
    );
    app.use(router);
    const body = {
      clientRequestId: 'stable-target-replay',
      caption: 'Keep the original account',
      videoS3Key: ownedUploadKey('seller-target-replay', 'stable.mp4'),
      platforms: ['YOUTUBE_SHORTS'],
      platformSettings: {
        YOUTUBE_SHORTS: {
          title: 'Keep the original account',
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true
        }
      }
    };

    const first = await request(app).post('/posts').send(body).expect(201);
    const targetReadsAfterCreate = resolvePlatformTarget.mock.calls.length;
    currentTarget = {
      accountId: 'postpeer-youtube-reconnected',
      externalAccountId: 'channel-new',
      connectedAt: '2026-05-11T10:00:00.000Z'
    };
    const replay = await request(app).post('/posts').send(body).expect(200);

    expect(replay.body.post.id).toBe(first.body.post.id);
    expect(replay.body.idempotentReplay).toBe(true);
    expect(JSON.stringify(replay.body)).not.toContain(originalTarget.accountId);
    expect(JSON.stringify(replay.body)).not.toContain(currentTarget.accountId);
    expect(resolvePlatformTarget).toHaveBeenCalledTimes(targetReadsAfterCreate);
    expect(
      (await postStore.list({ userId: 'seller-target-replay' }))[0].platformTargets
    ).toEqual({ YOUTUBE_SHORTS: originalTarget });
  });

  it('fails before the durable write when the selected provider target changes during validation', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = createInMemoryPublishQueue();
    const userId = 'seller-target-race';
    const resolvePlatformTarget = vi
      .fn()
      .mockResolvedValueOnce({
        accountId: 'postpeer-tiktok-original',
        connectedAt: '2026-05-01T00:00:00.000Z'
      })
      .mockResolvedValueOnce({
        accountId: 'postpeer-tiktok-reconnected',
        connectedAt: '2026-05-02T00:00:00.000Z'
      });
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: userId,
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow, resolvePlatformTarget }
    );
    app.use(router);

    await request(app)
      .post('/posts')
      .send({
        clientRequestId: 'target-changed',
        caption: 'Do not reroute',
        videoS3Key: ownedUploadKey(userId, 'target-race.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(409)
      .expect(({ body }) => {
        expect(body.code).toBe('PLATFORM_TARGET_UNAVAILABLE');
      });
    expect(resolvePlatformTarget).toHaveBeenCalledTimes(2);
    expect(await postStore.list({ userId })).toEqual([]);
    expect(await publishQueue.list({ userId })).toEqual([]);
  });

  it('does not upsert a Prisma user before the app-level disabled publishing gate', async () => {
    const userUpsert = vi.fn();
    const app = createApp({
      config: readServerConfig({ SOCIAL_PUBLISHER: 'disabled' }),
      prisma: {
        user: {
          findUnique: vi.fn(),
          upsert: userUpsert
        }
      } as never
    });

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-disabled-no-user-write')
      .send({
        caption: 'Must fail before persistence',
        videoS3Key: ownedUploadKey(
          'seller-disabled-no-user-write',
          'disabled.mp4'
        ),
        platforms: ['TIKTOK']
      })
      .expect(503)
      .expect(socialPublishingUnavailableResponse);

    expect(userUpsert).not.toHaveBeenCalled();
  });

  it('still allows a queued post to be canceled when social publishing is disabled', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const inMemoryPublishQueue = createInMemoryPublishQueue();
    const publishQueue = {
      ...inMemoryPublishQueue,
      remove: vi.fn(inMemoryPublishQueue.remove)
    };
    const post = await postStore.create({
      userId: 'seller-cancel-disabled',
      caption: 'Cancel while publishing is disabled',
      videoS3Key: ownedUploadKey('seller-cancel-disabled', 'cancel.mp4'),
      platforms: ['TIKTOK'],
      scheduledAt: '2026-06-03T10:00:00.000Z'
    });
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-cancel-disabled',
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };

    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { socialPublishingEnabled: false }
    );
    app.use(router);

    await request(app).delete(`/posts/${post.id}`).expect(200).expect({ status: 'ok' });

    expect(await postStore.list({ userId: 'seller-cancel-disabled' })).toEqual([]);
    expect(publishQueue.remove).toHaveBeenCalledWith(post.id);
  });

  it('accepts schedules up to 30 days and rejects anything later', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const app = createApp({ now: () => now });
    const baseRequest = {
      caption: 'Post inside scheduling window',
      platforms: ['TIKTOK'],
      subscriptionPlan: 'PRO'
    };

    const accepted = await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'day-30.mp4'),
        scheduledAt: '2026-07-01T00:00:00.000Z'
      })
      .expect(201);

    await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'over-day-30.mp4'),
        scheduledAt: '2026-07-01T00:00:00.001Z'
      })
      .expect(400)
      .expect({
        status: 'error',
        code: 'SCHEDULE_LIMIT_EXCEEDED',
        message: 'Posts can be scheduled up to 30 days in advance'
      });

    await request(app)
      .patch(`/posts/${accepted.body.post.id}`)
      .send({ scheduledAt: '2026-07-01T00:00:00.001Z' })
      .expect(400)
      .expect({
        status: 'error',
        code: 'SCHEDULE_LIMIT_EXCEEDED',
        message: 'Posts can be scheduled up to 30 days in advance'
      });
  });

  it('rejects invalid and past schedules instead of publishing immediately', async () => {
    const app = createApp({ now: () => new Date('2026-06-10T10:00:00.000Z') });
    const baseRequest = {
      caption: 'Schedule must be valid and future',
      platforms: ['TIKTOK'],
      subscriptionPlan: 'PRO'
    };

    await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'invalid-schedule.mp4'),
        scheduledAt: 'not-a-date'
      })
      .expect(400)
      .expect({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });

    await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'past-schedule.mp4'),
        scheduledAt: '2026-06-10T10:00:00.000Z'
      })
      .expect(400)
      .expect({
        status: 'error',
        code: 'SCHEDULE_MUST_BE_FUTURE',
        message: 'scheduledAt must be in the future'
      });
  });

  it.each([
    ['an impossible calendar date', '2026-02-30T10:00:00.000Z'],
    ['a timestamp without a timezone', '2026-06-15T10:00:00'],
    ['a date-only value', '2026-06-15'],
    ['a space-separated timestamp', '2026-06-15 10:00:00Z']
  ])('rejects %s for create and reschedule', async (_label, scheduledAt) => {
    const app = createApp({ now: () => new Date('2026-06-01T00:00:00.000Z') });
    const postId = await createScheduledPost(app);

    await request(app)
      .post('/posts')
      .send({
        caption: 'Strict timestamp create',
        videoS3Key: ownedUploadKey('local-dev-user', 'strict-create.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt
      })
      .expect(400)
      .expect({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });

    await request(app)
      .patch(`/posts/${postId}`)
      .send({ scheduledAt })
      .expect(400)
      .expect({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });
  });

  it('accepts timezone offsets and valid leap dates, then normalizes them to UTC', async () => {
    const app = createApp({ now: () => new Date('2028-02-01T00:00:00.000Z') });

    const createResponse = await request(app)
      .post('/posts')
      .send({
        caption: 'Valid offset schedule',
        videoS3Key: ownedUploadKey('local-dev-user', 'offset.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2028-02-29T10:30:45.125+07:00'
      })
      .expect(201);

    expect(createResponse.body.post.scheduledAt).toBe(
      '2028-02-29T03:30:45.125Z'
    );

    await request(app)
      .patch(`/posts/${createResponse.body.post.id}`)
      .send({ scheduledAt: '2028-02-29T11:30:45+07:00' })
      .expect(200)
      .expect(({ body }) => {
        expect(body.post.scheduledAt).toBe('2028-02-29T04:30:45.000Z');
      });
  });

  it('deduplicates platforms before quota accounting, storage, and queueing', async () => {
    const app = createApp();
    const userId = 'seller-platform-dedupe';

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Unique platforms only',
        videoS3Key: ownedUploadKey(userId, 'dedupe.mp4'),
        platforms: ['TIKTOK', 'TIKTOK', 'YOUTUBE_SHORTS']
      })
      .expect(201);

    expect(response.body.post.platforms).toEqual(['TIKTOK', 'YOUTUBE_SHORTS']);
    expect(response.body.publishJob.platforms).toEqual(['TIKTOK', 'YOUTUBE_SHORTS']);
  });

  it('rejects duplicate platforms for an idempotent request without persistence', async () => {
    const app = createApp();
    const userId = 'seller-idempotent-duplicates';

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-phone-verified', 'true')
      .send({
        clientRequestId: 'duplicate-platforms',
        caption: 'Must reject ambiguous intent',
        videoS3Key: ownedUploadKey(userId, 'duplicate.mp4'),
        platforms: ['TIKTOK', 'TIKTOK']
      })
      .expect(400)
      .expect(({ body }) => {
        expect(body.code).toBe('INVALID_PLATFORMS');
      });

    await request(app)
      .get('/posts')
      .set('x-postdee-user-id', userId)
      .expect(200)
      .expect({ status: 'ok', posts: [] });
  });

  it('atomically enforces monthly post-unit quota for concurrent requests', async () => {
    const app = createApp();
    const userId = 'seller-concurrent-quota';
    const createTwoUnitPost = (suffix: string) =>
      request(app)
        .post('/posts')
        .set('x-postdee-user-id', userId)
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: `Concurrent post ${suffix}`,
          videoS3Key: ownedUploadKey(userId, `concurrent-${suffix}.mp4`),
          platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
        });

    const responses = await Promise.all([createTwoUnitPost('a'), createTwoUnitPost('b')]);

    expect(responses.map((response) => response.status).sort()).toEqual([201, 402]);
    const listResponse = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', userId)
      .expect(200);
    expect(listResponse.body.posts).toHaveLength(1);
  });

  it('serializes concurrent requests with the same client request id', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const inMemoryQueue = createInMemoryPublishQueue();
    const publishQueue = {
      ...inMemoryQueue,
      enqueue: vi.fn(inMemoryQueue.enqueue),
      ensureEnqueued: vi.fn(inMemoryQueue.ensureEnqueued)
    };
    const userId = 'seller-concurrent-idempotent';
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: userId,
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
    );
    app.use(router);
    const body = {
      clientRequestId: 'same-concurrent-request',
      caption: 'Exactly one post',
      videoS3Key: ownedUploadKey(userId, 'same.mp4'),
      platforms: ['TIKTOK']
    };

    const responses = await Promise.all([
      request(app).post('/posts').send(body),
      request(app).post('/posts').send(body)
    ]);

    expect(responses.map(({ status }) => status).sort()).toEqual([200, 201]);
    expect(responses[0].body.post.id).toBe(responses[1].body.post.id);
    expect(await postStore.list({ userId })).toHaveLength(1);
    expect(await inMemoryQueue.list({ userId })).toHaveLength(1);
    expect(publishQueue.enqueue).toHaveBeenCalledOnce();
  });

  it('stores and queues cover metadata only after both uploads are ready', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = createInMemoryPublishQueue();
    const assertUploadReady = vi.fn(async () => undefined);
    const assertCoverUploadReady = vi.fn(async () => undefined);
    const videoS3Key = ownedUploadKey('seller-cover', 'clip.mp4', 'video');
    const coverImageS3Key = ownedUploadKey(
      'seller-cover',
      'cover.jpg',
      'cover'
    );
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-cover',
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { assertUploadReady, assertCoverUploadReady }
    );
    app.use(router);

    const response = await request(app)
      .post('/posts')
      .send({
        caption: 'Cover-ready post',
        videoS3Key,
        coverImageS3Key,
        coverFrameTimeMs: 0,
        platforms: ['TIKTOK', 'INSTAGRAM_REELS']
      })
      .expect(201);

    expect(response.body.post).toMatchObject({
      videoS3Key,
      coverImageS3Key,
      coverFrameTimeMs: 0
    });
    expect(response.body.publishJob).toMatchObject({
      coverImageS3Key,
      coverFrameTimeMs: 0
    });
    expect(assertUploadReady).toHaveBeenCalledWith('seller-cover', videoS3Key);
    expect(assertCoverUploadReady).toHaveBeenCalledWith(
      'seller-cover',
      coverImageS3Key
    );
  });

  it('rejects malformed or foreign cover metadata', async () => {
    const app = createApp();
    const baseRequest = {
      caption: 'Invalid cover',
      videoS3Key: ownedUploadKey('seller-a', 'clip.mp4'),
      platforms: ['INSTAGRAM_REELS'],
      subscriptionPlan: 'PRO'
    };

    for (const invalidFields of [
      { coverImageS3Key: '' },
      { coverImageS3Key: 123 },
      { coverFrameTimeMs: -1 },
      { coverFrameTimeMs: 1.5 },
      { coverFrameTimeMs: '1000' },
      { coverFrameTimeMs: 2_147_483_648 }
    ]) {
      await request(app)
        .post('/posts')
        .set('x-postdee-user-id', 'seller-a')
        .send({ ...baseRequest, ...invalidFields })
        .expect(400);
    }

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .send({
        ...baseRequest,
        coverImageS3Key: ownedUploadKey('seller-b', 'cover.jpg'),
        coverFrameTimeMs: 1_000
      })
      .expect(403)
      .expect({
        status: 'error',
        message: 'Selected cover does not belong to the authenticated user'
      });
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

  it('returns per-platform results only for posts owned by the authenticated user', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const ownedPost = await postStore.create({
      userId: 'seller-a',
      caption: 'Owned clip',
      videoS3Key: ownedUploadKey('seller-a', 'owned.mp4'),
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
    });
    const foreignPost = await postStore.create({
      userId: 'seller-b',
      caption: 'Foreign clip',
      videoS3Key: ownedUploadKey('seller-b', 'foreign.mp4'),
      platforms: ['FACEBOOK_REELS']
    });
    const listForPostIds = vi.fn(async () => [
      {
        postId: ownedPost.id,
        platform: 'TIKTOK' as const,
        status: 'PUBLISHED' as const,
        externalPostId: 'https://tiktok.test/owned',
        publishedAt: '2026-06-02T10:00:00.000Z',
        views: 0,
        likes: 0
      },
      {
        postId: foreignPost.id,
        platform: 'FACEBOOK_REELS' as const,
        status: 'FAILED' as const,
        errorMessage: 'Must not leak',
        views: 0,
        likes: 0
      }
    ]);
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-a',
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };

    registerPostRoutes(
      router,
      postStore,
      createInMemoryPublishQueue(),
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      { recordResults: vi.fn(async () => []), listForPostIds }
    );
    app.use(router);

    const response = await request(app).get('/posts').expect(200);

    expect(listForPostIds).toHaveBeenCalledWith([ownedPost.id]);
    expect(response.body.posts).toEqual([
      {
        ...ownedPost,
        platformResults: [
          {
            postId: ownedPost.id,
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            externalPostId: 'https://tiktok.test/owned',
            publishedAt: '2026-06-02T10:00:00.000Z',
            views: 0,
            likes: 0
          }
        ]
      }
    ]);
  });

  it('does not queue a post until a managed upload is completed', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = createInMemoryPublishQueue();
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-uploading',
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      {
        assertUploadReady: vi.fn(async () => {
          throw new ManagedUploadServiceError(
            409,
            'UPLOAD_NOT_READY',
            'Wait for the upload to finish before creating a post.'
          );
        })
      }
    );
    app.use(router);

    await request(app)
      .post('/posts')
      .send({
        caption: 'Do not queue incomplete media',
        videoS3Key: ownedUploadKey('seller-uploading', 'uploading.mp4'),
        platforms: ['TIKTOK']
      })
      .expect(409)
      .expect(({ body }) => {
        expect(body.code).toBe('UPLOAD_NOT_READY');
      });

    expect(await postStore.list({ userId: 'seller-uploading' })).toEqual([]);
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
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

  it('keeps an idempotent post and repairs its missing queue job on retry', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const inMemoryQueue = createInMemoryPublishQueue();
    const enqueue = vi
      .fn(inMemoryQueue.enqueue)
      .mockRejectedValueOnce(new Error('redis down'));
    const publishQueue = { ...inMemoryQueue, enqueue };
    const userId = 'seller-queue-repair';
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: userId,
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
    );
    app.use(router);
    const body = {
      clientRequestId: 'repair-on-retry',
      caption: 'Durable create before queue repair',
      videoS3Key: ownedUploadKey(userId, 'repair.mp4'),
      platforms: ['TIKTOK']
    };

    await request(app).post('/posts').send(body).expect(503);
    expect(await postStore.list({ userId })).toHaveLength(1);

    const replay = await request(app).post('/posts').send(body).expect(200);
    expect(replay.body.idempotentReplay).toBe(true);
    expect(await postStore.list({ userId })).toHaveLength(1);
    expect(await inMemoryQueue.list({ userId })).toHaveLength(1);

    const [committedPost] = await postStore.list({ userId });
    await postStore.updateStatus({ postId: committedPost.id, status: 'FAILED' });
    await request(app)
      .post('/posts')
      .send(body)
      .expect(409)
      .expect(({ body: responseBody }) => {
        expect(responseBody.code).toBe('IDEMPOTENT_POST_FAILED');
        expect(responseBody.postId).toBe(committedPost.id);
      });
  });

  it('never rolls back a shared committed row when another instance repairs its queue job', async () => {
    const postStore = createPostStore();
    const inMemoryPublishQueue = createInMemoryPublishQueue();
    let rejectFirstEnqueue!: (error: Error) => void;
    let markFirstEnqueueStarted!: () => void;
    const firstEnqueueStarted = new Promise<void>((resolve) => {
      markFirstEnqueueStarted = resolve;
    });
    let enqueueCalls = 0;
    const remove = vi.fn(inMemoryPublishQueue.remove);
    const publishQueue = {
      ...inMemoryPublishQueue,
      remove,
      enqueue: vi.fn((post: QueuedPost) => {
        enqueueCalls += 1;
        if (enqueueCalls === 1) {
          markFirstEnqueueStarted();
          return new Promise<Awaited<ReturnType<typeof inMemoryPublishQueue.enqueue>>>(
            (_resolve, reject) => {
              rejectFirstEnqueue = reject;
            }
          );
        }
        return inMemoryPublishQueue.enqueue(post);
      })
    };
    const userId = 'seller-cross-instance';
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: userId,
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };
    const buildInstance = () => {
      const app = express();
      const router = express.Router();
      app.use(express.json());
      registerPostRoutes(
        router,
        postStore,
        publishQueue,
        authMiddleware,
        createUserStore(),
        createSubscriptionStore(),
        createInMemoryPlatformPublishStore()
      );
      app.use(router);
      return app;
    };
    const body = {
      clientRequestId: 'draft-cross-instance',
      caption: 'One durable post',
      videoS3Key: ownedUploadKey(userId, 'cross-instance.mp4'),
      platforms: ['TIKTOK']
    };

    const firstResponse = request(buildInstance())
      .post('/posts')
      .send(body)
      .then((response) => response);
    await firstEnqueueStarted;
    const repairedResponse = await request(buildInstance())
      .post('/posts')
      .send(body)
      .expect(200);
    rejectFirstEnqueue(new Error('first instance lost Redis'));

    expect((await firstResponse).status).toBe(503);
    expect(repairedResponse.body.idempotentReplay).toBe(true);
    expect(await postStore.list({ userId })).toHaveLength(1);
    expect(await publishQueue.list({ userId })).toHaveLength(1);
    expect(remove).not.toHaveBeenCalled();
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
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

    expect(listResponse.body.posts).toEqual([
      { ...scheduledResponse.body.post, platformResults: [] }
    ]);
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
    expect(sellerBListResponse.body.posts).toEqual([
      { ...sellerBCreateResponse.body.post, platformResults: [] }
    ]);
  });

  it('upserts the auth user before creating a Prisma-backed post', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const post = {
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
    };
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
      post,
      $transaction: vi.fn(
        async (operation: (client: { post: typeof post }) => Promise<unknown>) =>
          operation({ post })
      ),
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
      const app = createApp({ now: () => new Date() });

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

  it('persists publish-now before a ready queue worker can claim the post', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const inMemoryPublishQueue = createInMemoryPublishQueue();
    const originalRunAt = '2026-06-03T10:00:00.000Z';
    const post = await postStore.create({
      userId: 'seller-publish-now-order',
      caption: 'Persist before ready queue',
      videoS3Key: ownedUploadKey('seller-publish-now-order', 'ordering.mp4'),
      platforms: ['TIKTOK'],
      scheduledAt: originalRunAt
    });
    await inMemoryPublishQueue.enqueue(post);
    const publishQueue = {
      ...inMemoryPublishQueue,
      reschedule: vi.fn(async (readyPost: QueuedPost) => {
        expect((await postStore.list({ userId: post.userId }))[0].scheduledAt).toBeUndefined();
        expect(
          await postStore.claimForPublish({
            postId: post.id,
            expectedRunAt: '2026-06-01T00:00:00.000Z'
          })
        ).toBe(true);
        return inMemoryPublishQueue.reschedule(readyPost);
      })
    };
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: post.userId,
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };
    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
    );
    app.use(router);

    await request(app)
      .post(`/posts/${post.id}/publish-now`)
      .expect(200)
      .expect(({ body }) => {
        expect(body.publishJob).toMatchObject({ postId: post.id, status: 'READY' });
      });
    const [storedAfterClaim] = await postStore.list({ userId: post.userId });
    expect(storedAfterClaim).toMatchObject({ status: 'PUBLISHING' });
    expect(storedAfterClaim.scheduledAt).toBeUndefined();
  });

  it('does not roll a publish-now compensation back over a worker claim', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const originalRunAt = '2026-06-03T10:00:00.000Z';
    const post = await postStore.create({
      userId: 'seller-publish-now-claimed',
      caption: 'Worker claims during queue transition',
      videoS3Key: ownedUploadKey('seller-publish-now-claimed', 'claimed.mp4'),
      platforms: ['TIKTOK'],
      scheduledAt: originalRunAt
    });
    const publishQueue = {
      ...createInMemoryPublishQueue(),
      reschedule: vi.fn(async () => {
        expect(
          await postStore.claimForPublish({
            postId: post.id,
            expectedRunAt: '2026-06-01T00:00:00.000Z'
          })
        ).toBe(true);
        throw new Error('queue acknowledgement lost after worker claim');
      })
    };
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: post.userId,
        provider: 'mock',
        phoneVerified: true,
        subscriptionPlan: 'PRO'
      };
      next();
    };
    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
    );
    app.use(router);

    await request(app).post(`/posts/${post.id}/publish-now`).expect(503);
    const [storedPost] = await postStore.list({ userId: post.userId });
    expect(storedPost).toMatchObject({ status: 'PUBLISHING' });
    expect(storedPost.scheduledAt).toBeUndefined();
  });

  it('does not let another user publish an owned scheduled post now', async () => {
    const app = createApp();
    const ownerHeaders = {
      'x-postdee-user-id': 'publish-now-owner',
      'x-postdee-phone-verified': 'true'
    };
    const created = await request(app)
      .post('/posts')
      .set(ownerHeaders)
      .send({
        clientRequestId: 'publish-now-owner-request',
        caption: 'Owner schedule',
        videoS3Key: ownedUploadKey('publish-now-owner', 'owner.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt: '2026-06-02T12:00:00.000Z'
      })
      .expect(201);

    await request(app)
      .post(`/posts/${created.body.post.id}/publish-now`)
      .set('x-postdee-user-id', 'publish-now-other-user')
      .expect(404);
    const ownerPosts = await request(app).get('/posts').set(ownerHeaders).expect(200);
    expect(ownerPosts.body.posts[0].scheduledAt).toBe('2026-06-02T12:00:00.000Z');
  });

  it('serializes reschedule and publish-now queue transitions for one post', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const originalRunAt = '2026-06-02T10:00:00.000Z';
    const replacementRunAt = '2026-06-03T10:00:00.000Z';
    const post = await postStore.create({
      userId: 'seller-reschedule-publish-now',
      caption: 'Serialize publish now',
      videoS3Key: ownedUploadKey(
        'seller-reschedule-publish-now',
        'serialize-publish-now.mp4'
      ),
      platforms: ['YOUTUBE_SHORTS'],
      scheduledAt: originalRunAt
    });
    const inMemoryPublishQueue = createInMemoryPublishQueue();
    await inMemoryPublishQueue.enqueue(post);
    let releaseFirstQueue!: () => void;
    const firstQueueGate = new Promise<void>((resolve) => {
      releaseFirstQueue = resolve;
    });
    let markFirstQueueStarted!: () => void;
    const firstQueueStarted = new Promise<void>((resolve) => {
      markFirstQueueStarted = resolve;
    });
    let rescheduleCalls = 0;
    const publishQueue = {
      ...inMemoryPublishQueue,
      reschedule: vi.fn(async (queuedPost: QueuedPost) => {
        rescheduleCalls += 1;
        if (rescheduleCalls === 1) {
          markFirstQueueStarted();
          await firstQueueGate;
        }
        return inMemoryPublishQueue.reschedule(queuedPost);
      })
    };
    let markPublishNowAuthenticated!: () => void;
    const publishNowAuthenticated = new Promise<void>((resolve) => {
      markPublishNowAuthenticated = resolve;
    });
    const authMiddleware = (
      request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      if (request.header('x-request-label') === 'publish-now') {
        markPublishNowAuthenticated();
      }
      response.locals.authUser = {
        id: post.userId,
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
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { now: futureNow }
    );
    app.use(router);

    const rescheduleResponse = request(app)
      .patch(`/posts/${post.id}`)
      .send({ scheduledAt: replacementRunAt })
      .then((response) => response);
    await firstQueueStarted;
    const publishNowResponse = request(app)
      .post(`/posts/${post.id}/publish-now`)
      .set('x-request-label', 'publish-now')
      .send({})
      .then((response) => response);
    await publishNowAuthenticated;
    await new Promise<void>((resolve) => setImmediate(resolve));
    expect(publishQueue.reschedule).toHaveBeenCalledOnce();

    releaseFirstQueue();
    expect((await rescheduleResponse).status).toBe(200);
    expect((await publishNowResponse).status).toBe(200);
    expect(publishQueue.reschedule).toHaveBeenCalledTimes(2);
    const [storedPost] = await postStore.list({ userId: post.userId });
    expect(storedPost.scheduledAt).toBeUndefined();
    expect(await inMemoryPublishQueue.list({ userId: post.userId })).toEqual([
      expect.objectContaining({ postId: post.id, status: 'READY' })
    ]);
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
