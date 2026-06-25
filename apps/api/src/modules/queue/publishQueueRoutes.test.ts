import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

describe('publish queue routes', () => {
  it('requires authentication before listing queue jobs in Firebase mode', async () => {
    const app = createApp({
      config: readServerConfig({
        AUTH_PROVIDER: 'firebase',
        FIREBASE_PROJECT_ID: 'postdee-test'
      }),
      firebaseVerifier: {
        verifyIdToken: async () => ({ id: 'seller-firebase', provider: 'firebase' })
      }
    });

    await request(app).get('/queue/jobs').expect(401);
  });

  it('lists publish jobs created when posts are queued', async () => {
    const app = createApp();

    const createPostResponse = await request(app)
      .post('/posts')
      .set('x-postdee-phone-verified', 'true')
      .send({
        caption: 'Ready to publish',
        videoS3Key: 'uploads/demo-video.mp4',
        platforms: ['INSTAGRAM_REELS']
      })
      .expect(201);

    const response = await request(app).get('/queue/jobs').expect(200);

    expect(response.body).toEqual({
      status: 'ok',
      jobs: [createPostResponse.body.publishJob]
    });
  });
});
