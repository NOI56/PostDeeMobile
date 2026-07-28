import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';

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
});
