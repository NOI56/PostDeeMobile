import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import { createOwnerMutationLock } from './modules/account/ownerMutationLock.js';
import { createInMemorySocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';
import { createMockVideoStorage } from './modules/storage/videoStorage.js';

describe('PostDee API scaffold', () => {
  const app = createApp();

  it('returns the health payload', async () => {
    const response = await request(app).get('/health').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      service: 'postdee-api'
    });
  });

  it('does not expose the removed legacy clip review endpoint', async () => {
    await request(app)
      .post('/clip-reviews')
      .set('x-postdee-user-id', 'seller-legacy-review')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: 'uploads/legacy-demo.mp4',
        mode: 'VIDEO'
      })
      .expect(404);
  });

  it('guards the mutating HEAD fallback for billing subscription reads after owner deletion', async () => {
    const ownerMutationLock = createOwnerMutationLock();
    ownerMutationLock.markDeleted('seller-head-deleted');
    const guardedApp = createApp({ ownerMutationLock });

    await request(guardedApp)
      .head('/billing/subscription')
      .set('x-postdee-user-id', 'seller-head-deleted')
      .expect(409);
  });

  it('creates the app with ElevenLabs transcription, Gemini planning, and R2 configured', () => {
    const configuredApp = createApp({
      config: readServerConfig({
        TRANSCRIPTION_PROVIDER: 'elevenlabs',
        ELEVENLABS_API_KEY: 'elevenlabs-key',
        EDIT_PLAN_PROVIDER: 'gemini',
        GEMINI_API_KEY: 'gemini-key',
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
      }),
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
        deleteObject: async () => undefined
      }
    });

    expect(configuredApp).toBeDefined();
  });

  it('wires the empty-backlog guard only into real PostPeer scheduler startup', async () => {
    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.upsert({
      userId: 'staging-guard-test-user',
      platform: 'YOUTUBE_SHORTS',
      postPeerAccountId: 'postpeer-staging-youtube'
    });
    const guardedApp = createApp({
      config: readServerConfig({
        SOCIAL_PUBLISHER: 'postpeer',
        SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG: 'true',
        POSTPEER_API_KEY: 'test-postpeer-key'
      }),
      socialConnectionStore
    });

    await request(guardedApp)
      .post('/posts')
      .set('x-postdee-user-id', 'staging-guard-test-user')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        caption: 'future staging guard test',
        videoS3Key: 'uploads/staging-guard-test-user/upload-1/video.mp4',
        platforms: ['YOUTUBE_SHORTS'],
        scheduledAt: new Date(Date.now() + 60 * 60 * 1000).toISOString()
      })
      .expect(201);

    await expect(guardedApp.locals.publishScheduler.start()).rejects.toThrow(
      'Social publishing activation blocked: 1 queued or publishing posts exist'
    );
  });
});

describe('Owner deletion guards on mutating reads', () => {
  it.each([
    '/billing/subscription/',
    '/Billing/Subscription',
    '/social-connections/',
    '/Social-Connections'
  ])('keeps the deletion guard on Express-compatible mutating reads at %s', async (path) => {
    const ownerId = 'seller-deleted-route-variant';
    const ownerMutationLock = createOwnerMutationLock();
    const ensure = vi.fn();
    const app = createApp({
      ownerMutationLock,
      prisma: { user: { upsert: ensure } } as never
    });
    ownerMutationLock.markDeleted(ownerId);
    await request(app).get(path).set('x-postdee-user-id', ownerId).expect(409);
    await request(app).head(path).set('x-postdee-user-id', ownerId).expect(409);
    expect(ensure).not.toHaveBeenCalled();
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });

  it.each(['/uploads/upload-1', '/Uploads/upload-1/'])('blocks upload status reconciliation after deletion at %s', async (path) => {
    const ownerId = 'seller-deleted-upload-status';
    const ownerMutationLock = createOwnerMutationLock();
    const get = vi.fn(async () => ({ sessionStatus: 'COMPLETED', upload: {} }));
    const app = createApp({
      ownerMutationLock,
      managedUploadService: { get, assertOwnerActive: async () => undefined } as never
    });
    ownerMutationLock.markDeleted(ownerId);
    await request(app).get(path).set('x-postdee-user-id', ownerId).expect(409);
    await request(app).head(path).set('x-postdee-user-id', ownerId).expect(409);
    expect(get).not.toHaveBeenCalled();
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });

  it('holds the owner barrier until an in-flight upload status reconciliation completes', async () => {
    const ownerId = 'seller-upload-status-drain';
    const ownerMutationLock = createOwnerMutationLock();
    let finishReconciliation!: () => void;
    let markStarted!: () => void;
    const started = new Promise<void>((resolve) => { markStarted = resolve; });
    const get = async () => {
      markStarted();
      await new Promise<void>((resolve) => { finishReconciliation = resolve; });
      return { sessionStatus: 'COMPLETED', upload: {} };
    };
    const app = createApp({
      ownerMutationLock,
      managedUploadService: { get, assertOwnerActive: async () => undefined } as never
    });
    const pending = request(app).get('/uploads/upload-1')
      .set('x-postdee-user-id', ownerId).then((response) => response);
    await started;
    let deletionEntered = false;
    const deletion = ownerMutationLock.acquire(ownerId).then((release) => {
      deletionEntered = true;
      release();
    });
    try {
      await Promise.resolve();
      expect(deletionEntered).toBe(false);
    } finally {
      finishReconciliation();
    }
    expect((await pending).status).toBe(200);
    await deletion;
    expect(deletionEntered).toBe(true);
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });
});

describe('Operational readiness wiring', () => {
  it('reports scheduler readiness separately from basic process health', async () => {
    const app = createApp();
    const scheduler = app.locals.publishScheduler;
    await request(app).get('/ready').expect(503);
    await request(app).get('/health').expect(200);
    await scheduler.start();
    try {
      const response = await request(app).get('/ready').expect(200);
      expect(response.headers['cache-control']).toBe('no-store');
      expect(response.body).toEqual({
        status: 'ok',
        service: 'postdee-api',
        checks: { database: 'ok', queue: 'ok' }
      });
      app.locals.shuttingDown = true;
      await request(app).get('/ready').expect(503);
      await request(app).get('/health').expect(200);
    } finally {
      scheduler.stop();
      await app.locals.closeResources();
    }
  });

  it('checks the relational database without writes and hides failures until it recovers', async () => {
    const query = vi.fn().mockRejectedValue(new Error('private database connection details'));
    const disconnect = vi.fn().mockResolvedValue(undefined);
    const app = createApp({ prisma: { $queryRawUnsafe: query, $disconnect: disconnect } as never });
    const scheduler = app.locals.publishScheduler;
    await scheduler.start();
    try {
      const failed = await request(app).get('/ready').expect(503);
      expect(failed.body.checks).toEqual({ database: 'unavailable', queue: 'ok' });
      expect(JSON.stringify(failed.body)).not.toContain('private database');
      expect(query).toHaveBeenCalledWith('SELECT 1');
      query.mockResolvedValue([{ '?column?': 1 }]);
      await request(app).get('/ready').expect(200);
      app.locals.shuttingDown = true;
      const queryCount = query.mock.calls.length;
      await request(app).get('/ready').expect(503);
      expect(query).toHaveBeenCalledTimes(queryCount);
    } finally {
      scheduler.stop();
      await scheduler.drain();
      await app.locals.closeResources();
    }
    expect(disconnect).toHaveBeenCalledOnce();
  });
});

describe('Home media preview application wiring', () => {
  it('signs storage media only for the authenticated opt-in post list', async () => {
    const ownerId = 'seller-app-preview';
    const videoS3Key = `uploads/${ownerId}/clip/video.mp4`;
    const downloadUrl = 'https://private-media.test/video.mp4?signature=test&expires=60';
    const createDownloadAccess = vi.fn(async (key: string) => ({
      videoS3Key: key,
      storageProvider: 'r2' as const,
      accessType: 'signed-url' as const,
      downloadUrl
    }));
    const app = createApp({
      videoStorage: { ...createMockVideoStorage(), createDownloadAccess }
    });
    await request(app).post('/posts')
      .set('x-postdee-user-id', ownerId)
      .set('x-postdee-phone-verified', 'true')
      .send({ caption: 'App media wiring', videoS3Key, platforms: ['TIKTOK'] })
      .expect(201);
    const legacy = await request(app).get('/posts')
      .set('x-postdee-user-id', ownerId).expect(200);
    expect(legacy.body.posts[0]).not.toHaveProperty('videoUrl');
    expect(createDownloadAccess).not.toHaveBeenCalled();
    const privateList = await request(app).get('/posts?includeMedia=true&limit=3')
      .set('x-postdee-user-id', ownerId).expect(200);
    expect(privateList.headers['cache-control']).toBe('private, no-store');
    expect(privateList.body.posts[0].videoUrl).toBe(downloadUrl);
    expect(createDownloadAccess).toHaveBeenCalledExactlyOnceWith(videoS3Key);
    const otherOwner = await request(app).get('/posts?includeMedia=true&limit=3')
      .set('x-postdee-user-id', 'seller-other-preview').expect(200);
    expect(otherOwner.body.posts).toEqual([]);
    expect(createDownloadAccess).toHaveBeenCalledOnce();
  });
});
