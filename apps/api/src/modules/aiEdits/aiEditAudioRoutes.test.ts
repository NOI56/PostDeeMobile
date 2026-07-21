import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createMockVideoStorage } from '../storage/videoStorage.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

const transcript = {
  text: 'สวัสดีค่ะ',
  language: 'th',
  durationSeconds: 60,
  segments: [{ text: 'สวัสดีค่ะ', start: 0, end: 1 }],
  words: [{ word: 'สวัสดีค่ะ', start: 0, end: 1 }],
  model: 'test-whisper'
};

const createStorageWithDeleteSpy = () => {
  const deleteVideo = vi.fn(async () => undefined);
  return {
    deleteVideo,
    videoStorage: { ...createMockVideoStorage(), deleteVideo }
  };
};

describe('AI edit audio routes', () => {
  it('prepares from owned temporary audio and deletes it after success', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'clip.m4a');
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        audioS3Key,
        durationSeconds: 60,
        capabilities: { silence: true }
      })
      .expect(200);

    expect(transcribe).toHaveBeenCalledWith({ mediaS3Key: audioS3Key, mediaKind: 'audio' });
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
  });

  it('transcribes from owned temporary audio and deletes it after success', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'clip.m4a');
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ audioS3Key, durationSeconds: 60 })
      .expect(200);

    expect(transcribe).toHaveBeenCalledWith({ mediaS3Key: audioS3Key, mediaKind: 'audio' });
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
  });

  it('rejects requests that contain both audio and legacy video keys', async () => {
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        audioS3Key: ownedUploadKey('local-dev-user', 'clip.m4a'),
        videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4')
      })
      .expect(400);

    expect(response.body.code).toBe('AI_EDIT_MEDIA_AMBIGUOUS');
    expect(transcribe).not.toHaveBeenCalled();
    expect(deleteVideo).not.toHaveBeenCalled();
  });

  it('returns a clear error when neither media key is provided', async () => {
    const response = await request(createApp())
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({})
      .expect(400);

    expect(response.body.code).toBe('AI_EDIT_MEDIA_REQUIRED');
  });

  it.each([
    {
      name: 'belongs to another user',
      audioS3Key: ownedUploadKey('other-seller', 'clip.m4a'),
      expectedStatus: 403,
      expectedCode: 'MEDIA_KEY_FORBIDDEN'
    },
    {
      name: 'does not identify an M4A object',
      audioS3Key: ownedUploadKey('local-dev-user', 'clip.mp4'),
      expectedStatus: 400,
      expectedCode: 'AI_EDIT_AUDIO_KEY_INVALID'
    }
  ])('does not process or delete audio that $name', async ({
    audioS3Key,
    expectedStatus,
    expectedCode
  }) => {
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ audioS3Key })
      .expect(expectedStatus);

    expect(response.body.code).toBe(expectedCode);
    expect(transcribe).not.toHaveBeenCalled();
    expect(deleteVideo).not.toHaveBeenCalled();
  });

  it('deletes owned temporary audio when the preliminary quota check rejects it', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'quota.m4a');
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ audioS3Key, durationSeconds: 99999 })
      .expect(402);

    expect(transcribe).not.toHaveBeenCalled();
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
  });

  it('deletes owned temporary audio when the provider fails', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'provider-failure.m4a');
    const transcribe = vi.fn(async () => {
      throw new Error('provider unavailable');
    });
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ audioS3Key, durationSeconds: 60 })
      .expect(502);

    expect(response.body.code).toBe('AI_TRANSCRIPTION_PROVIDER_FAILED');
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
  });

  it('keeps legacy video compatible and never deletes it automatically', async () => {
    const videoS3Key = ownedUploadKey('local-dev-user', 'legacy.mp4');
    const transcribe = vi.fn(async () => transcript);
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ transcriptionProvider: { transcribe }, videoStorage });

    await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key, durationSeconds: 60 })
      .expect(200);

    expect(transcribe).toHaveBeenCalledWith({
      mediaS3Key: videoS3Key,
      mediaKind: 'legacy-video'
    });
    expect(deleteVideo).not.toHaveBeenCalled();
  });

  it('allows duplicate authenticated cleanup requests', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'orphan.m4a');
    const { deleteVideo, videoStorage } = createStorageWithDeleteSpy();
    const app = createApp({ videoStorage });

    await request(app)
      .post('/ai-edits/audio/cleanup')
      .send({ audioS3Key })
      .expect(200, { status: 'ok' });
    await request(app)
      .post('/ai-edits/audio/cleanup')
      .send({ audioS3Key })
      .expect(200, { status: 'ok' });

    expect(deleteVideo).toHaveBeenCalledTimes(2);
    expect(deleteVideo).toHaveBeenNthCalledWith(1, audioS3Key);
    expect(deleteVideo).toHaveBeenNthCalledWith(2, audioS3Key);
  });
});
