import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import {
  ManagedUploadServiceError,
  createManagedUploadService,
  type ManagedMultipartStorage
} from '../uploads/managedUploadService.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createPostStore } from './postStore.js';
import { registerPostRoutes } from './postRoutes.js';

describe('post routes', () => {
  const allPlatforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
  const futureNow = () => new Date('2026-06-01T00:00:00.000Z');
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
    const app = createApp({ now: futureNow });

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

  it('accepts schedules up to 30 days and rejects anything later', async () => {
    const now = new Date('2026-06-01T00:00:00.000Z');
    const app = createApp({ now: () => now });
    const baseRequest = {
      caption: 'โพสต์ภายในกรอบเวลา',
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

    const response = await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'over-day-30.mp4'),
        scheduledAt: '2026-07-01T00:00:00.001Z'
      })
      .expect(400);

    expect(response.body).toEqual({
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

  it('stores an optional YouTube title separately from the full caption', async () => {
    const app = createApp({ now: futureNow });
    const caption = 'คำอธิบายเต็ม\nพร้อมรายละเอียด #สินค้า';
    const response = await request(app).post('/posts').send({
      caption,
      youtubeTitle: '  kkkkk  ',
      videoS3Key: ownedUploadKey('local-dev-user', 'youtube-title.mp4'),
      platforms: ['YOUTUBE_SHORTS', 'TIKTOK'],
      subscriptionPlan: 'PRO'
    }).expect(201);

    expect(response.body.post).toMatchObject({ caption, youtubeTitle: 'kkkkk' });
    const listed = await request(app).get('/posts').expect(200);
    expect(listed.body.posts[0]).toMatchObject({ caption, youtubeTitle: 'kkkkk' });
  });

  it('allows a title-only YouTube post and preserves its empty description', async () => {
    const response = await request(createApp({ now: futureNow })).post('/posts').send({
      caption: '',
      youtubeTitle: 'ชื่อคลิป',
      videoS3Key: ownedUploadKey('local-dev-user', 'youtube-title-only.mp4'),
      platforms: ['YOUTUBE_SHORTS'],
      subscriptionPlan: 'PRO'
    }).expect(201);

    expect(response.body.post).toMatchObject({ caption: '', youtubeTitle: 'ชื่อคลิป' });
  });

  it.each([null, 123, {}, [], '<ชื่อคลิป>', 'ชื่อ>คลิป', '😀'.repeat(101)]
    .map((youtubeTitle) => ({ youtubeTitle })))(
    'rejects an invalid YouTube title %j', async ({ youtubeTitle }) => {
      const response = await request(createApp()).post('/posts').send({
        caption: 'คำอธิบาย', youtubeTitle,
        videoS3Key: ownedUploadKey('local-dev-user', 'invalid-title.mp4'),
        platforms: ['YOUTUBE_SHORTS']
      }).expect(400);

      expect(response.body.code).toBe('INVALID_YOUTUBE_TITLE');
    }
  );

  it('rejects a caption over 2,200 Unicode code points before using quota', async () => {
    const app = createApp();
    const createPost = (caption: string, fileName: string) => request(app).post('/posts').send({
      caption,
      videoS3Key: ownedUploadKey('local-dev-user', fileName),
      platforms: ['INSTAGRAM_REELS'],
      subscriptionPlan: 'PRO'
    });

    const tooLong = await createPost('😀'.repeat(2201), 'caption-too-long.mp4').expect(400);
    expect(tooLong.body).toMatchObject({ status: 'error', code: 'CAPTION_TOO_LONG' });
    await createPost('😀'.repeat(2200), 'caption-at-limit.mp4').expect(201);

    const posts = await request(app).get('/posts').expect(200);
    expect(posts.body.posts).toHaveLength(1);
  });

  describe('YouTube caption limits', () => {
    const createPost = (
      app: ReturnType<typeof createApp>,
      caption: string,
      platforms: string[],
      fileName: string
    ) => request(app).post('/posts').send({
      caption,
      videoS3Key: ownedUploadKey('local-dev-user', fileName),
      platforms,
      subscriptionPlan: 'PRO'
    });

    it('lets a YouTube-only caption exceed 2,200 characters up to 5,000 bytes', async () => {
      const app = createApp();

      await createPost(app, 'a'.repeat(5000), ['YOUTUBE_SHORTS'], 'yt-ascii.mp4').expect(201);
      await createPost(app, 'ก'.repeat(1666), ['YOUTUBE_SHORTS'], 'yt-thai.mp4').expect(201);
    });

    it('rejects a YouTube caption over 5,000 UTF-8 bytes', async () => {
      const app = createApp();

      // 1,667 Thai characters are 5,001 bytes.
      const response = await createPost(
        app, 'ก'.repeat(1667), ['YOUTUBE_SHORTS'], 'yt-too-long.mp4'
      ).expect(400);
      expect(response.body).toMatchObject({ code: 'CAPTION_TOO_LONG' });
    });

    it('keeps the 2,200 character limit when YouTube is posted with others', async () => {
      const response = await createPost(
        createApp(), 'a'.repeat(3000), ['YOUTUBE_SHORTS', 'INSTAGRAM_REELS'], 'yt-mixed.mp4'
      ).expect(400);
      expect(response.body).toMatchObject({ code: 'CAPTION_TOO_LONG' });
    });

    it('rejects angle brackets only when the caption goes to YouTube', async () => {
      const app = createApp();

      const response = await createPost(
        app, 'ชอบมาก <3', ['YOUTUBE_SHORTS', 'TIKTOK'], 'yt-brackets.mp4'
      ).expect(400);
      expect(response.body).toMatchObject({ code: 'CAPTION_INVALID_FOR_YOUTUBE' });
      await createPost(app, 'ชอบมาก <3', ['TIKTOK'], 'tiktok-brackets.mp4').expect(201);
    });
  });

  it('accepts 100 Unicode code points and treats a blank optional title as omitted', async () => {
    const app = createApp();
    const createPost = (youtubeTitle: string) => request(app).post('/posts').send({
      caption: 'คำอธิบาย', youtubeTitle,
      videoS3Key: ownedUploadKey('local-dev-user', 'title-boundary.mp4'),
      platforms: ['YOUTUBE_SHORTS'], subscriptionPlan: 'PRO'
    }).expect(201);

    expect((await createPost('😀'.repeat(100))).body.post.youtubeTitle).toBe('😀'.repeat(100));
    expect((await createPost('  ')).body.post).not.toHaveProperty('youtubeTitle');
  });

  it('rejects a YouTube title when YouTube is not selected', async () => {
    const response = await request(createApp()).post('/posts').send({
      caption: 'คำอธิบาย', youtubeTitle: 'ชื่อคลิป',
      videoS3Key: ownedUploadKey('local-dev-user', 'wrong-platform-title.mp4'),
      platforms: ['TIKTOK']
    }).expect(400);

    expect(response.body.code).toBe('YOUTUBE_TITLE_PLATFORM_REQUIRED');
  });

  it.each([
    { caption: '', youtubeTitle: 'ชื่อคลิป', platforms: ['YOUTUBE_SHORTS', 'TIKTOK'] },
    { caption: '', platforms: ['YOUTUBE_SHORTS'] },
    { caption: '', youtubeTitle: '  ', platforms: ['YOUTUBE_SHORTS'] },
    { youtubeTitle: 'ชื่อคลิป', platforms: ['YOUTUBE_SHORTS'] }
  ])('retains required caption validation outside title-only YouTube posts: %j', async (input) => {
    await request(createApp()).post('/posts').send({
      ...input, videoS3Key: ownedUploadKey('local-dev-user', 'missing-caption.mp4')
    }).expect(400);
  });

  it('rejects an invalid scheduledAt instead of treating it as post now', async () => {
    const app = createApp({ now: () => new Date('2026-06-01T00:00:00.000Z') });

    const response = await request(app)
      .post('/posts')
      .send({
        caption: 'Invalid schedule',
        videoS3Key: ownedUploadKey('local-dev-user', 'invalid-schedule.mp4'),
        platforms: ['TIKTOK'],
        subscriptionPlan: 'PRO',
        scheduledAt: 'not-a-date'
      })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'scheduledAt must be a valid ISO date'
    });

    await request(app).get('/posts').expect(200).expect({ status: 'ok', posts: [] });
    await request(app).get('/queue/jobs').expect(200).expect({ status: 'ok', jobs: [] });
  });

  it('rejects past schedules when creating and rescheduling posts', async () => {
    const app = createApp({ now: () => new Date('2026-06-10T10:00:00.000Z') });
    const baseRequest = {
      caption: 'Schedule must be future',
      platforms: ['TIKTOK'],
      subscriptionPlan: 'PRO'
    };

    await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'past-schedule.mp4'),
        scheduledAt: '2026-06-10T09:59:59.999Z'
      })
      .expect(400)
      .expect({
        status: 'error',
        code: 'SCHEDULE_MUST_BE_FUTURE',
        message: 'scheduledAt must be in the future'
      });

    const created = await request(app)
      .post('/posts')
      .send({
        ...baseRequest,
        videoS3Key: ownedUploadKey('local-dev-user', 'future-schedule.mp4'),
        scheduledAt: '2026-06-11T10:00:00.000Z'
      })
      .expect(201);

    await request(app)
      .patch(`/posts/${created.body.post.id}`)
      .send({ scheduledAt: '2026-06-10T10:00:00.000Z' })
      .expect(400)
      .expect({
        status: 'error',
        code: 'SCHEDULE_MUST_BE_FUTURE',
        message: 'scheduledAt must be in the future'
      });
  });

  it('deduplicates platforms before quota accounting, storage, and queueing', async () => {
    const app = createApp();
    const userId = 'seller-platform-dedupe';

    const first = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'One unique platform',
        videoS3Key: ownedUploadKey(userId, 'dedupe-one.mp4'),
        platforms: ['TIKTOK', 'TIKTOK']
      })
      .expect(201);

    expect(first.body.post.platforms).toEqual(['TIKTOK']);
    expect(first.body.publishJob.platforms).toEqual(['TIKTOK']);

    const second = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Two more unique platforms',
        videoS3Key: ownedUploadKey(userId, 'dedupe-two.mp4'),
        platforms: ['YOUTUBE_SHORTS', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS']
      })
      .expect(201);

    expect(second.body.post.platforms).toEqual(['YOUTUBE_SHORTS', 'INSTAGRAM_REELS']);
    expect(second.body.publishJob.platforms).toEqual([
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS'
    ]);
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
    expect(responses.find((response) => response.status === 402)?.body).toEqual({
      status: 'error',
      code: 'POST_LIMIT_REACHED',
      message: 'Basic plan is limited to 3 post units per month'
    });

    const listResponse = await request(app)
      .get('/posts')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-phone-verified', 'true')
      .expect(200);
    expect(listResponse.body.posts).toHaveLength(1);
  });

  it('stores and queues optional cover metadata for owned completed uploads', async () => {
    const app = express();
    const router = express.Router();
    const assertUploadReady = vi.fn(async () => undefined);
    const assertCoverUploadReady = vi.fn(async () => undefined);
    const videoS3Key = ownedUploadKey('seller-cover', 'clip.mp4', 'video');
    const coverImageS3Key = ownedUploadKey('seller-cover', 'cover.jpg', 'cover');
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
      createPostStore(),
      createInMemoryPublishQueue(),
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
    expect(assertUploadReady).toHaveBeenCalledOnce();
    expect(assertUploadReady).toHaveBeenCalledWith('seller-cover', videoS3Key);
    expect(assertCoverUploadReady).toHaveBeenCalledOnce();
    expect(assertCoverUploadReady).toHaveBeenCalledWith('seller-cover', coverImageS3Key);
  });

  it('requires a managed cover in dual mode while preserving pure legacy compatibility', async () => {
    const userId = 'seller-dual-cover';
    const now = '2026-07-16T10:00:00.000Z';
    const managedCoverImageS3Key = ownedUploadKey(userId, 'cover.jpg', 'managed-cover');
    const legacyCoverImageS3Key = ownedUploadKey(userId, 'legacy-cover.webp', 'legacy-cover');
    const storage: ManagedMultipartStorage = {
      createUpload: vi.fn(async () => ({
        storageUploadId: 'storage-cover-1',
        videoS3Key: managedCoverImageS3Key,
        createdAt: now
      })),
      createPartUpload: vi.fn(async () => ({
        uploadUrl: 'https://r2.test/cover-part',
        uploadExpiresAt: '2026-07-16T10:05:00.000Z'
      })),
      completeUpload: vi.fn(async () => undefined),
      abortUpload: vi.fn(async () => undefined),
      getCompletedObjectSize: vi.fn(async () => undefined),
      listUploadsForOwner: vi.fn(async () => [])
    };
    const managedUploadService = createManagedUploadService({
      storage,
      store: createInMemoryUploadSessionStore({ now: () => now }),
      partSizeBytes: 3 * 1024 * 1024,
      sessionExpiresSeconds: 3_600,
      now: () => new Date(now),
      idFactory: () => 'managed-cover-session'
    });
    const managedCover = await managedUploadService.create(
      {
        fileName: 'cover.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1_024
      },
      userId
    );
    await managedUploadService.complete(managedCover.id, userId, [
      { partNumber: 1, etag: 'etag-cover-1' }
    ]);
    const app = createApp({
      config: readServerConfig({
        UPLOAD_PROTOCOL_MODE: 'dual',
        DATABASE_URL: 'postgresql://postdee:postdee_password@localhost:5432/postdee'
      }),
      managedUploadService
    });
    const baseRequest = {
      caption: 'Dual mode cover policy',
      videoS3Key: ownedUploadKey(userId, 'legacy-video.mp4', 'legacy-video'),
      coverFrameTimeMs: 1_000,
      platforms: ['INSTAGRAM_REELS'],
      subscriptionPlan: 'PRO'
    };

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({ ...baseRequest, coverImageS3Key: legacyCoverImageS3Key })
      .expect(409)
      .expect(({ body }) => {
        expect(body.code).toBe('UPLOAD_CONFIRMATION_REQUIRED');
      });

    await request(app)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({ ...baseRequest, coverImageS3Key: managedCover.videoS3Key })
      .expect(201);

    const legacyApp = createApp({
      config: readServerConfig({ UPLOAD_PROTOCOL_MODE: 'legacy' }),
      managedUploadService
    });
    await request(legacyApp)
      .post('/posts')
      .set('x-postdee-user-id', userId)
      .send({ ...baseRequest, coverImageS3Key: legacyCoverImageS3Key })
      .expect(201);
  });

  it('rejects malformed cover metadata without creating a post', async () => {
    const app = createApp();
    const baseRequest = {
      caption: 'Invalid cover',
      videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4'),
      platforms: ['TIKTOK'],
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
        .send({ ...baseRequest, ...invalidFields })
        .expect(400);
    }

    const listResponse = await request(app).get('/posts').expect(200);
    expect(listResponse.body.posts).toEqual([]);
  });

  it('rejects a cover image owned by another user', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/posts')
      .set('x-postdee-user-id', 'seller-a')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'Do not use another seller cover',
        videoS3Key: ownedUploadKey('seller-a', 'clip.mp4'),
        coverImageS3Key: ownedUploadKey('seller-b', 'cover.jpg'),
        coverFrameTimeMs: 1_000,
        platforms: ['INSTAGRAM_REELS']
      })
      .expect(403);

    expect(response.body).toEqual({
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

  it('returns signed preview media only for the authenticated user when requested', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const ownedVideoS3Key = ownedUploadKey('seller-a', 'owned.mp4', 'video');
    const ownedCoverImageS3Key = ownedUploadKey('seller-a', 'cover.jpg', 'cover');
    const foreignVideoS3Key = ownedUploadKey('seller-b', 'foreign.mp4', 'video');
    const ownedPost = await postStore.create({
      userId: 'seller-a',
      caption: 'Owned clip with preview',
      videoS3Key: ownedVideoS3Key,
      coverImageS3Key: ownedCoverImageS3Key,
      platforms: ['YOUTUBE_SHORTS']
    });
    await postStore.create({
      userId: 'seller-b',
      caption: 'Foreign clip',
      videoS3Key: foreignVideoS3Key,
      platforms: ['TIKTOK']
    });
    const createMediaDownloadUrl = vi.fn(async (storageKey: string) =>
      `https://media.test/${encodeURIComponent(storageKey)}`
    );
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

    app.use(express.json());
    registerPostRoutes(
      router,
      postStore,
      createInMemoryPublishQueue(),
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { createMediaDownloadUrl }
    );
    app.use(router);

    const response = await request(app).get('/posts?includeMedia=true').expect(200);

    expect(response.body.posts).toEqual([
      expect.objectContaining({
        id: ownedPost.id,
        userId: 'seller-a',
        videoS3Key: ownedVideoS3Key,
        coverImageS3Key: ownedCoverImageS3Key,
        videoUrl: `https://media.test/${encodeURIComponent(ownedVideoS3Key)}`,
        coverImageUrl: `https://media.test/${encodeURIComponent(ownedCoverImageS3Key)}`,
        platformResults: []
      })
    ]);
    expect(createMediaDownloadUrl).toHaveBeenCalledTimes(2);
    expect(createMediaDownloadUrl).toHaveBeenCalledWith(ownedVideoS3Key);
    expect(createMediaDownloadUrl).toHaveBeenCalledWith(ownedCoverImageS3Key);
    expect(createMediaDownloadUrl).not.toHaveBeenCalledWith(foreignVideoS3Key);

    await request(app).get('/posts').expect(200);
    expect(createMediaDownloadUrl).toHaveBeenCalledTimes(2);

    createMediaDownloadUrl.mockImplementation(async (storageKey: string) => {
      if (storageKey === ownedCoverImageS3Key) {
        throw new Error('temporary cover signing outage');
      }
      return `https://media.test/${encodeURIComponent(storageKey)}`;
    });
    const partialMediaResponse = await request(app)
      .get('/posts?includeMedia=true')
      .expect(200);
    expect(partialMediaResponse.body.posts).toEqual([
      expect.objectContaining({
        id: ownedPost.id,
        videoUrl: `https://media.test/${encodeURIComponent(ownedVideoS3Key)}`
      })
    ]);
    expect(partialMediaResponse.body.posts[0]).not.toHaveProperty('coverImageUrl');
  });

  it('limits newest posts before creating preview media URLs', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const oldestPost = await postStore.create({
      userId: 'seller-a',
      caption: 'Oldest clip',
      videoS3Key: ownedUploadKey('seller-a', 'oldest.mp4', 'oldest'),
      platforms: ['YOUTUBE_SHORTS']
    });
    const newestPost = await postStore.create({
      userId: 'seller-a',
      caption: 'Newest clip',
      videoS3Key: ownedUploadKey('seller-a', 'newest.mp4', 'newest'),
      platforms: ['YOUTUBE_SHORTS']
    });
    const middlePost = await postStore.create({
      userId: 'seller-a',
      caption: 'Middle clip',
      videoS3Key: ownedUploadKey('seller-a', 'middle.mp4', 'middle'),
      platforms: ['YOUTUBE_SHORTS']
    });
    oldestPost.createdAt = '2026-06-01T00:00:00.000Z';
    middlePost.createdAt = '2026-06-02T00:00:00.000Z';
    newestPost.createdAt = '2026-06-03T00:00:00.000Z';
    vi.spyOn(postStore, 'list').mockResolvedValue([oldestPost, newestPost, middlePost]);
    const createMediaDownloadUrl = vi.fn(async (storageKey: string) =>
      `https://media.test/${encodeURIComponent(storageKey)}`
    );
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

    app.use(express.json());
    registerPostRoutes(
      router,
      postStore,
      createInMemoryPublishQueue(),
      authMiddleware,
      createUserStore(),
      createSubscriptionStore(),
      createInMemoryPlatformPublishStore(),
      { createMediaDownloadUrl }
    );
    app.use(router);

    const response = await request(app)
      .get('/posts?includeMedia=true&limit=2')
      .expect(200);

    expect(response.body.posts.map((post: { id: string }) => post.id)).toEqual([
      newestPost.id,
      middlePost.id
    ]);
    expect(createMediaDownloadUrl).toHaveBeenCalledTimes(2);
    expect(createMediaDownloadUrl).toHaveBeenCalledWith(newestPost.videoS3Key);
    expect(createMediaDownloadUrl).toHaveBeenCalledWith(middlePost.videoS3Key);
    expect(createMediaDownloadUrl).not.toHaveBeenCalledWith(oldestPost.videoS3Key);
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

  it('does not queue a post until its cover upload is completed', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const videoS3Key = ownedUploadKey('seller-cover-uploading', 'clip.mp4', 'video');
    const coverImageS3Key = ownedUploadKey(
      'seller-cover-uploading',
      'cover.jpg',
      'cover'
    );
    const authMiddleware = (
      _request: express.Request,
      response: express.Response,
      next: express.NextFunction
    ) => {
      response.locals.authUser = {
        id: 'seller-cover-uploading',
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
      createInMemoryPlatformPublishStore(),
      {
        assertUploadReady: vi.fn(async () => undefined),
        assertCoverUploadReady: vi.fn(async () => {
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
        caption: 'Do not queue an incomplete cover',
        videoS3Key,
        coverImageS3Key,
        coverFrameTimeMs: 1_000,
        platforms: ['INSTAGRAM_REELS']
      })
      .expect(409)
      .expect(({ body }) => {
        expect(body.code).toBe('UPLOAD_NOT_READY');
      });

    expect(await postStore.list({ userId: 'seller-cover-uploading' })).toEqual([]);
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
      },
      now: futureNow
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
    const app = createApp({ now: futureNow });

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
    const unusedPrismaMethod = vi.fn(async () => {
      throw new Error('Unexpected Prisma operation in post creation test');
    });
    const prismaPost = {
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
      }),
      update: unusedPrismaMethod,
      updateMany: unusedPrismaMethod,
      deleteMany: unusedPrismaMethod,
      findFirst: unusedPrismaMethod
    };
    const managedUploadOwner = {
      findUnique: vi.fn().mockResolvedValue({ ownerId: 'seller-prisma', status: 'ACTIVE' }),
      upsert: vi.fn().mockResolvedValue({ ownerId: 'seller-prisma', status: 'ACTIVE' }),
      updateMany: vi.fn().mockResolvedValue({ count: 1 }),
      update: unusedPrismaMethod
    };
    const prismaUser = {
      findUnique: vi.fn(async () => ({
        id: 'seller-prisma', lastRevenueCatEventTimestampMs: null, lastRevenueCatEventId: null
      })),
      update: unusedPrismaMethod,
      upsert: vi.fn().mockResolvedValue({
        id: 'seller-prisma',
        firebaseUid: 'mock:seller-prisma',
        email: 'seller@example.com',
        displayName: undefined,
        createdAt,
        updatedAt: createdAt
      })
    };
    const transaction = {
      managedUploadOwner,
      user: prismaUser,
      post: prismaPost,
      template: {
        findMany: unusedPrismaMethod,
        create: unusedPrismaMethod,
        deleteMany: unusedPrismaMethod
      },
      subscription: {
        findUnique: unusedPrismaMethod, upsert: unusedPrismaMethod, update: unusedPrismaMethod
      },
      platformPublish: { findMany: unusedPrismaMethod },
      realClipCaptionUsage: { count: unusedPrismaMethod, create: unusedPrismaMethod },
      aiEditUsage: {
        aggregate: unusedPrismaMethod, create: unusedPrismaMethod, findFirst: unusedPrismaMethod,
        update: unusedPrismaMethod, deleteMany: unusedPrismaMethod
      },
      deviceToken: {
        upsert: unusedPrismaMethod, findMany: unusedPrismaMethod, deleteMany: unusedPrismaMethod
      },
      socialConnection: {
        findMany: unusedPrismaMethod, findUnique: unusedPrismaMethod,
        upsert: unusedPrismaMethod, deleteMany: unusedPrismaMethod
      },
      postPeerProfile: {
        findUnique: unusedPrismaMethod, create: unusedPrismaMethod, deleteMany: unusedPrismaMethod
      },
      managedUploadSession: {
        create: unusedPrismaMethod, findFirst: unusedPrismaMethod, findUnique: unusedPrismaMethod,
        findMany: unusedPrismaMethod, update: unusedPrismaMethod, deleteMany: unusedPrismaMethod
      }
    };
    const prisma = {
      ...transaction,
      $transaction: async <Result>(operation: (client: typeof transaction) => Promise<Result>) =>
        operation(transaction)
    } satisfies NonNullable<NonNullable<Parameters<typeof createApp>[0]>['prisma']>;
    const app = createApp({
      config: readServerConfig({
        DATABASE_URL: 'postgresql://postdee:postdee_password@localhost:5432/postdee',
        POST_STORE: 'prisma'
      }),
      prisma,
      now: futureNow
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
    expect(prismaPost.create).toHaveBeenCalledWith(
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
    const app = createApp({ now: futureNow });

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
    const app = createApp({ now: futureNow });

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
    const app = createApp({ now: futureNow });

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

  const activatePaidPlan = async (
    app: ReturnType<typeof createApp>,
    plan: 'STARTER' | 'PRO'
  ) => {
    await request(app).post('/billing/mock-success').send({ plan }).expect(200);
  };

  it.each([undefined, 'STARTER', 'PRO'])(
    'rejects scheduling a verified Basic immediate post with body plan %s without changing the post or job',
    async (subscriptionPlan) => {
      const app = createApp({ now: futureNow });
      const created = await request(app)
        .post('/posts')
        .set('x-postdee-phone-verified', 'true')
        .send({
          caption: 'Basic immediate post',
          videoS3Key: ownedUploadKey('local-dev-user', 'basic-immediate.mp4'),
          platforms: ['TIKTOK']
        })
        .expect(201);

      expect(created.body.post.status).toBe('QUEUED');
      expect(created.body.post.scheduledAt).toBeUndefined();
      expect(created.body.publishJob.status).toBe('READY');

      await request(app)
        .patch(`/posts/${created.body.post.id}`)
        .set('x-postdee-phone-verified', 'true')
        .send({ scheduledAt: '2026-06-12T15:30:00.000Z', subscriptionPlan })
        .expect(402)
        .expect({
          status: 'error',
          code: 'PAID_PLAN_REQUIRED',
          message: 'Cloud Scheduling requires the Starter or Pro plan'
        });

      const listResponse = await request(app).get('/posts').expect(200);
      expect(listResponse.body.posts).toEqual([
        { ...created.body.post, platformResults: [] }
      ]);
      const queueResponse = await request(app).get('/queue/jobs').expect(200);
      expect(queueResponse.body.jobs).toEqual([created.body.publishJob]);
    }
  );

  it.each(['STARTER', 'PRO'] as const)(
    'allows a stored %s subscriber to schedule an immediate queued post',
    async (plan) => {
      const app = createApp({ now: futureNow });
      await activatePaidPlan(app, plan);
      const created = await request(app)
        .post('/posts')
        .send({
          caption: 'Paid immediate post',
          videoS3Key: ownedUploadKey('local-dev-user', 'paid-immediate.mp4'),
          platforms: ['TIKTOK']
        })
        .expect(201);
      const scheduledAt = '2026-06-12T15:30:00.000Z';

      const patchResponse = await request(app)
        .patch(`/posts/${created.body.post.id}`)
        .send({ scheduledAt, subscriptionPlan: 'BASIC' })
        .expect(200);

      expect(patchResponse.body.post).toEqual({ ...created.body.post, scheduledAt });
      const listResponse = await request(app).get('/posts?scheduled=true').expect(200);
      expect(listResponse.body.posts).toEqual([
        { ...patchResponse.body.post, platformResults: [] }
      ]);
      const queueResponse = await request(app).get('/queue/jobs').expect(200);
      expect(queueResponse.body.jobs).toHaveLength(1);
      expect(queueResponse.body.jobs[0]).toMatchObject({
        postId: created.body.post.id,
        runAt: scheduledAt,
        status: 'SCHEDULED'
      });
    }
  );

  it('checks current paid eligibility when rescheduling a post created before cancellation', async () => {
    const app = express();
    const router = express.Router();
    const postStore = createPostStore();
    const publishQueue = createInMemoryPublishQueue();
    const subscriptionStore = createSubscriptionStore();
    const authUser = {
      id: 'seller-canceled-schedule',
      provider: 'mock' as const,
      phoneVerified: true
    };
    const authMiddleware: express.RequestHandler = (_request, response, next) => {
      response.locals.authUser = authUser;
      next();
    };
    await subscriptionStore.activatePlan(authUser, 'PRO', {
      billingSubscriptionId: 'canceled-schedule-subscription'
    });

    app.use(express.json());
    registerPostRoutes(
      router,
      postStore,
      publishQueue,
      authMiddleware,
      createUserStore(),
      subscriptionStore,
      createInMemoryPlatformPublishStore(),
      { now: futureNow, allowSubscriptionPlanOverride: false }
    );
    app.use(router);

    const created = await request(app)
      .post('/posts')
      .send({
        caption: 'Created while paid',
        videoS3Key: ownedUploadKey(authUser.id, 'before-cancellation.mp4'),
        platforms: ['TIKTOK'],
        scheduledAt: '2026-06-10T10:00:00.000Z'
      })
      .expect(201);
    await subscriptionStore.updateStatusByBillingSubscriptionId({
      billingSubscriptionId: 'canceled-schedule-subscription',
      status: 'CANCELED'
    });

    await request(app)
      .patch(`/posts/${created.body.post.id}`)
      .send({ scheduledAt: '2026-06-12T15:30:00.000Z', subscriptionPlan: 'PRO' })
      .expect(402)
      .expect({
        status: 'error',
        code: 'PAID_PLAN_REQUIRED',
        message: 'Cloud Scheduling requires the Starter or Pro plan'
      });

    expect(await postStore.list({ userId: authUser.id })).toEqual([created.body.post]);
    expect(await publishQueue.list({ userId: authUser.id })).toEqual([
      created.body.publishJob
    ]);
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
    const app = createApp({ now: futureNow });
    await activatePaidPlan(app, 'PRO');
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
    const app = createApp({ now: futureNow });
    await activatePaidPlan(app, 'PRO');
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
    const app = createApp({ now: futureNow });
    const postId = await createScheduledPost(app);

    await request(app).delete(`/posts/${postId}`).expect(200);

    const listResponse = await request(app).get('/posts').expect(200);
    expect(listResponse.body.posts).toEqual([]);
  });

  it('removes the existing publish queue job when a scheduled post is canceled', async () => {
    const app = createApp({ now: futureNow });
    const postId = await createScheduledPost(app);

    await request(app).delete(`/posts/${postId}`).expect(200);

    const queueResponse = await request(app).get('/queue/jobs').expect(200);

    expect(queueResponse.body.jobs).toEqual([]);
  });

  it('returns 404 when rescheduling a post that does not exist', async () => {
    const app = createApp({ now: futureNow });

    await request(app)
      .patch('/posts/missing-id')
      .send({ scheduledAt: '2026-06-12T15:30:00.000Z' })
      .expect(404);
  });
});
