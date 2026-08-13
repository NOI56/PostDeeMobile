import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import { createOwnerMutationLock } from './modules/account/ownerMutationLock.js';
import { createInMemorySocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';

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
