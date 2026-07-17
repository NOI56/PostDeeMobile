import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';

describe('AI edit audio upload route', () => {
  it('creates an owner-scoped M4A upload for the explicit AI edit purpose', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .set('x-postdee-user-id', 'seller-audio')
      .send({
        purpose: 'ai-edit-audio',
        fileName: 'analysis.m4a',
        contentType: 'audio/mp4',
        sizeBytes: 4096
      })
      .expect(201);

    expect(response.body.upload).toMatchObject({
      fileName: 'analysis.m4a',
      contentType: 'audio/mp4',
      sizeBytes: 4096
    });
    expect(response.body.upload.videoS3Key).toMatch(
      /^uploads\/seller-audio\/.+\/analysis\.m4a$/
    );
  });

  it('returns a stable code when an AI edit audio upload is invalid', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/uploads')
      .set('x-postdee-user-id', 'seller-audio')
      .send({
        purpose: 'ai-edit-audio',
        fileName: 'analysis.mp3',
        contentType: 'audio/mpeg',
        sizeBytes: 4096
      })
      .expect(400);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'UPLOAD_AI_EDIT_AUDIO_INVALID'
    });
  });
});
