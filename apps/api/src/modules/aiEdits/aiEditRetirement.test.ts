import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

const createProviders = () => ({
  transcriptionProvider: { transcribe: vi.fn(async () => { throw new Error('transcription must not run'); }) },
  editPlanProvider: { plan: vi.fn(async () => { throw new Error('edit planning must not run'); }) },
  soundEffectPlanProvider: { plan: vi.fn(async () => { throw new Error('sound planning must not run'); }) },
  visualEditPlanProvider: { plan: vi.fn(async () => { throw new Error('visual planning must not run'); }) }
});

// AI video editing was removed from the mobile product. Its API must not keep
// spending paid transcription/planning provider work for direct callers.
describe('retired AI editing routes', () => {
  const userId = 'seller-retired-ai-edit';
  const retiredRequests: Array<{ method: 'get' | 'post'; path: string; body?: Record<string, unknown> }> = [
    { method: 'post', path: '/ai-edits/transcribe', body: { videoS3Key: ownedUploadKey(userId, 'clip.mp4'), durationSeconds: 30 } },
    { method: 'post', path: '/ai-edits/prepare', body: { videoS3Key: ownedUploadKey(userId, 'clip.mp4'), durationSeconds: 30 } },
    { method: 'post', path: '/ai-edits/plan', body: { segments: [{ text: 'hello', start: 0, end: 1 }], durationSeconds: 30 } },
    { method: 'post', path: '/ai-edits/audio/cleanup', body: { audioS3Key: ownedUploadKey(userId, 'audio.m4a') } },
    { method: 'post', path: '/ai-edits/visual-proxy/cleanup', body: { visualProxyS3Key: ownedUploadKey(userId, 'proxy.mp4') } },
    { method: 'get', path: '/ai-edits/quota' }
  ];

  it.each(retiredRequests)('answers $method $path with 410 without calling AI providers by default', async ({ method, path, body }) => {
    const providers = createProviders();
    const app = createApp({ config: readServerConfig({}), ...providers });

    const call = request(app)[method](path)
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO');
    const response = await (body ? call.send(body) : call).expect(410);

    expect(response.body).toEqual({
      status: 'error',
      code: 'AI_EDITING_RETIRED',
      message: 'AI video editing is no longer available.'
    });
    expect(providers.transcriptionProvider.transcribe).not.toHaveBeenCalled();
    expect(providers.editPlanProvider.plan).not.toHaveBeenCalled();
    expect(providers.soundEffectPlanProvider.plan).not.toHaveBeenCalled();
    expect(providers.visualEditPlanProvider.plan).not.toHaveBeenCalled();
  });

  it('keeps real-clip AI captions working while AI editing is retired', async () => {
    const videoS3Key = ownedUploadKey(userId, 'caption.mp4');
    const generate = vi.fn(async () => ({
      caption: 'แคปชันจากคลิปจริง',
      hashtags: ['#PostDee'],
      model: 'gemini-test',
      source: { videoS3Key, mode: 'AUDIO_ONLY' as const, selectedFrameCount: 0 }
    }));
    const fetchClipMedia = vi.fn(async () => ({ data: new Uint8Array([1, 2, 3]), mimeType: 'video/mp4' }));
    const app = createApp({
      config: readServerConfig({}),
      realClipCaptionProvider: { generate } as never,
      fetchClipMedia
    });

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key })
      .expect(200);

    expect(response.body).toMatchObject({ status: 'ok', caption: 'แคปชันจากคลิปจริง' });
    expect(generate).toHaveBeenCalledTimes(1);
  });

  it('can be re-enabled explicitly for a controlled rollback', async () => {
    const app = createApp({ config: readServerConfig({ AI_EDITING_ENABLED: 'true' }) });

    const response = await request(app)
      .get('/ai-edits/quota')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(200);

    expect(response.body).toMatchObject({ status: 'ok' });
  });
});
