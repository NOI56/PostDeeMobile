import request from 'supertest';
import express from 'express';
import { describe, expect, it, vi } from 'vitest';

import { createAccountAwareAuthMiddleware, createApp } from './app.js';
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

  it('creates the app with Groq transcription and R2 video storage configured', () => {
    const appWithGroq = createApp({
      config: readServerConfig({
        TRANSCRIPTION_PROVIDER: 'groq',
        GROQ_API_KEY: 'groq-key',
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
      }),
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
        deleteObject: async () => undefined
      }
    });

    expect(appWithGroq).toBeDefined();
  });

  it('ensures the authenticated user before Prisma-backed mutations', async () => {
    const appWithRelationalMutation = express();
    const ensure = vi.fn(async (authUser: { id: string }) => ({
      id: authUser.id,
      firebaseUid: `mock:${authUser.id}`,
      email: `${authUser.id}@postdee.local`,
      createdAt: '2026-08-13T00:00:00.000Z',
      updatedAt: '2026-08-13T00:00:00.000Z'
    }));
    const authMiddleware: express.RequestHandler = (_request, response, next) => {
      response.locals.authUser = {
        id: 'seller-relational-mutation',
        provider: 'mock'
      };
      next();
    };

    appWithRelationalMutation.post(
      '/relational-mutation',
      createAccountAwareAuthMiddleware({
        authMiddleware,
        userStore: {
          ensure,
          exists: vi.fn(async () => true)
        }
      }),
      (_request, response) => response.json({ status: 'ok' })
    );

    await request(appWithRelationalMutation)
      .post('/relational-mutation')
      .expect(200, { status: 'ok' });
    expect(ensure).toHaveBeenCalledWith({
      id: 'seller-relational-mutation',
      provider: 'mock'
    });
  });
});
