import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { aiCaptionFrameMaxBytes } from '../storage/mediaDownload.js';
import type { GeneratedRealClipCaption, RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

const fakeCaption = (input: RealClipCaptionGenerateInput): GeneratedRealClipCaption => ({
  model: 'gemini-test',
  caption: 'AI caption',
  captionOptions: ['a', 'b', 'c'],
  hooks: ['h1', 'h2', 'h3'],
  hashtags: ['#a', '#b', '#c', '#d', '#e'],
  seoKeywords: ['k1', 'k2', 'k3', 'k4', 'k5'],
  searchTitle: 'search title',
  affiliateLinkPlaceholder: '[affiliate link]',
  context: {
    selectedCaptionLanguage: 'Thai',
    selectedTargetMarket: 'Thailand',
    selectedTone: 'auto',
    detectedSpokenLanguage: 'th',
    suggestedCaptionLanguage: 'Thai',
    suggestedTargetMarket: 'Thailand'
  },
  source: { videoS3Key: input.request.videoS3Key, mode: input.mode, selectedFrameCount: input.frames?.length ?? 0 }
});

const sendProClipCaption = (app: ReturnType<typeof createApp>, userId: string, body: Record<string, unknown>) =>
  request(app)
    .post('/captions/generate-from-clip')
    .set('x-postdee-user-id', userId)
    .set('x-postdee-subscription-plan', 'PRO')
    .send(body);

// Real-clip captions buffer media in the single shared API process. Frame
// inputs are small JPEG stills from the app, so anything else must be refused
// before the server downloads it.
describe('real-clip caption media limits', () => {
  it('rejects a non-image frame key before downloading any media', async () => {
    const userId = 'seller-frame-type';
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => fakeCaption(input));
    const fetchClipMedia = vi.fn(async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' }));
    const app = createApp({ realClipCaptionProvider: { generate }, fetchClipMedia });

    const response = await sendProClipCaption(app, userId, {
      videoS3Key: ownedUploadKey(userId, 'clip.mp4'),
      selectedFrameKeys: [ownedUploadKey(userId, 'huge.mp4', 'frame-video')]
    }).expect(400);

    expect(response.body).toMatchObject({ status: 'error', code: 'AI_CAPTION_FRAME_INVALID' });
    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(generate).not.toHaveBeenCalled();
  });

  it('downloads each distinct frame once with the frame size limit', async () => {
    const userId = 'seller-frame-dedupe';
    const videoS3Key = ownedUploadKey(userId, 'clip.mp4');
    const frameKey = ownedUploadKey(userId, 'frame_1.jpg', 'frame-one');
    let receivedFrameCount = 0;
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => {
      receivedFrameCount = input.frames?.length ?? 0;
      return fakeCaption(input);
    });
    const fetchClipMedia = vi.fn(async (key: string) => ({
      data: new Uint8Array([1]),
      mimeType: key.endsWith('.jpg') ? 'image/jpeg' : 'video/mp4'
    }));
    const app = createApp({ realClipCaptionProvider: { generate }, fetchClipMedia });

    await sendProClipCaption(app, userId, {
      videoS3Key,
      selectedFrameKeys: [frameKey, frameKey, frameKey]
    }).expect(200);

    expect(fetchClipMedia).toHaveBeenCalledTimes(2);
    expect(fetchClipMedia).toHaveBeenNthCalledWith(1, videoS3Key);
    expect(fetchClipMedia).toHaveBeenNthCalledWith(2, frameKey, { kind: 'frame', maxBytes: aiCaptionFrameMaxBytes });
    expect(receivedFrameCount).toBe(1);
  });

  it('answers 503 instead of buffering more clips than the shared media budget allows', async () => {
    const userId = 'seller-media-busy';
    let releaseFirst!: () => void;
    const gate = new Promise<void>((release) => { releaseFirst = release; });
    let markStarted!: () => void;
    const firstDownloadStarted = new Promise<void>((started) => { markStarted = started; });
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => fakeCaption(input));
    const fetchClipMedia = vi.fn(async () => {
      markStarted();
      await gate;
      return { data: new Uint8Array([1]), mimeType: 'video/mp4' };
    });
    const app = createApp({ realClipCaptionProvider: { generate }, fetchClipMedia, maxConcurrentAiMediaRequests: 1 });

    const first = sendProClipCaption(app, userId, { videoS3Key: ownedUploadKey(userId, 'first.mp4') }).then((response) => response);
    await firstDownloadStarted;
    const second = await sendProClipCaption(app, userId, { videoS3Key: ownedUploadKey(userId, 'second.mp4', 'second') });

    expect(second.status).toBe(503);
    expect(second.headers['retry-after']).toBe('1');
    expect(second.body).toMatchObject({ status: 'error', code: 'AI_MEDIA_BUSY' });

    releaseFirst();
    expect((await first).status).toBe(200);
    expect(fetchClipMedia).toHaveBeenCalledTimes(1);
  });
});
