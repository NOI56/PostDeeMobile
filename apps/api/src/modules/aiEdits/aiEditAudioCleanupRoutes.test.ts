import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createMockVideoStorage } from '../storage/videoStorage.js';

const ownedUploadKey = (userId: string, fileName: string) =>
  `uploads/${userId}/clip/${fileName}`;

const transcript = {
  text: 'สวัสดีค่ะ',
  language: 'th',
  durationSeconds: 60,
  segments: [{ text: 'สวัสดีค่ะ', start: 0, end: 1 }],
  words: [{ word: 'สวัสดีค่ะ', start: 0, end: 1 }],
  model: 'test-whisper'
};

describe('AI edit audio cleanup safety', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('cleans owned audio when a non-Pro plan is rejected', async () => {
    const audioS3Key = ownedUploadKey('local-dev-user', 'starter.m4a');
    const transcribe = vi.fn(async () => transcript);
    const deleteVideo = vi.fn(async () => undefined);
    const app = createApp({
      transcriptionProvider: { transcribe },
      videoStorage: { ...createMockVideoStorage(), deleteVideo }
    });

    await request(app)
      .post('/ai-edits/prepare')
      .send({ audioS3Key, durationSeconds: 60 })
      .expect(402);

    expect(transcribe).not.toHaveBeenCalled();
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
  });

  it.each([
    {
      name: 'foreign audio',
      audioS3Key: ownedUploadKey('other-seller', 'foreign.m4a'),
      status: 403,
      code: 'MEDIA_KEY_FORBIDDEN'
    },
    {
      name: 'a video key',
      audioS3Key: ownedUploadKey('local-dev-user', 'clip.mp4'),
      status: 400,
      code: 'AI_EDIT_AUDIO_KEY_INVALID'
    }
  ])('does not delete $name through the cleanup endpoint', async ({
    audioS3Key,
    status,
    code
  }) => {
    const deleteVideo = vi.fn(async () => undefined);
    const app = createApp({
      videoStorage: { ...createMockVideoStorage(), deleteVideo }
    });

    const response = await request(app)
      .post('/ai-edits/audio/cleanup')
      .send({ audioS3Key })
      .expect(status);

    expect(response.body.code).toBe(code);
    expect(deleteVideo).not.toHaveBeenCalled();
  });

  it('keeps a successful edit response when automatic cleanup fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const audioS3Key = ownedUploadKey('local-dev-user', 'cleanup-failure.m4a');
    const deleteVideo = vi.fn(async () => {
      throw new Error('storage unavailable');
    });
    const app = createApp({
      transcriptionProvider: { transcribe: vi.fn(async () => transcript) },
      videoStorage: { ...createMockVideoStorage(), deleteVideo }
    });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ audioS3Key, durationSeconds: 60 })
      .expect(200);

    expect(response.body.status).toBe('ok');
    expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
    expect(console.error).toHaveBeenCalledWith(
      'AI edit temporary audio cleanup failed:',
      'storage unavailable'
    );
  });
});
