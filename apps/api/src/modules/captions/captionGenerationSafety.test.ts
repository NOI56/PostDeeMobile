import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import type { AiMediaFetchOptions } from '../storage/mediaDownload.js';
import { generateLocalRealClipCaption } from './captionService.js';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';
import type { GeneratedRealClipCaption, RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';
import { CaptionGroundingAuditError, CaptionInsufficientEvidenceError } from './realClipCaptionProvider.js';

const userId = 'caption-safety-owner';
const videoS3Key = `uploads/${userId}/clip/video.mp4`;
const media = { data: new Uint8Array([1]), mimeType: 'video/mp4' };
const monthKey = new Date().toISOString().slice(0, 7);
const generated = (input: RealClipCaptionGenerateInput): GeneratedRealClipCaption => ({
  ...generateLocalRealClipCaption(input), model: 'test-ai', caption: 'พาดูเมนูที่เห็นในคลิปกัน',
  ...(input.request.platforms ? { platformCaptions: Object.fromEntries(input.request.platforms.map(platform =>
    [platform, { caption: 'พาดูเมนูที่เห็นในคลิปกัน', hashtags: [] }])) } : {})
});
const send = (app: ReturnType<typeof createApp>, body: object = {}) => request(app)
  .post('/captions/generate-from-clip').set('x-postdee-user-id', userId)
  .set('x-postdee-subscription-plan', 'PRO').send({ videoS3Key, ...body });

describe('caption generation safety', () => {
  it.each(['download', 'provider'] as const)('times out a stuck %s, refunds only its batch and admits the next request', async stage => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    await usage.record({ userId, monthKey });
    let settle!: () => void;
    const pending = new Promise<void>(resolve => { settle = resolve; });
    let signal: AbortSignal | undefined;
    const fetchClipMedia = vi.fn(async (_key: string, options?: AiMediaFetchOptions) => {
      signal = options?.signal;
      if (stage === 'download' && fetchClipMedia.mock.calls.length === 1) await pending;
      return media;
    });
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => {
      signal = input.signal;
      if (stage === 'provider' && generate.mock.calls.length === 1) await pending;
      return generated(input);
    });
    const app = createApp({ realClipCaptionUsageStore: usage, fetchClipMedia,
      realClipCaptionProvider: { generate }, maxConcurrentAiMediaRequests: 1, captionGenerationTimeoutMs: 30 });
    const timedOut = await send(app, { platforms: ['TIKTOK', 'YOUTUBE_SHORTS'], expectedCredits: 2 }).expect(504);
    expect(timedOut.body).toMatchObject({ code: 'CAPTION_GENERATION_TIMEOUT', quota: { charged: false, chargedCredits: 0 } });
    expect(signal?.aborted).toBe(true);
    expect(await usage.countForMonth({ userId, monthKey })).toBe(1);
    await send(app).expect(200);
    expect(await usage.countForMonth({ userId, monthKey })).toBe(2);
    const callsBeforeLateResult = generate.mock.calls.length;
    settle();
    await new Promise<void>(resolve => setImmediate(resolve));
    expect(generate.mock.calls.length).toBe(callsBeforeLateResult);
    expect(await usage.countForMonth({ userId, monthKey })).toBe(2);
  });

  it('cancels provider work and refunds on a disconnected client without late writes', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    let settle!: () => void;
    const pending = new Promise<void>(resolve => { settle = resolve; });
    let started!: () => void;
    const providerStarted = new Promise<void>(resolve => { started = resolve; });
    let signal: AbortSignal | undefined;
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => {
      if (generate.mock.calls.length === 1) { signal = input.signal; started(); await pending; }
      return generated(input);
    });
    const app = createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate }, maxConcurrentAiMediaRequests: 1, captionGenerationTimeoutMs: 1000 });
    const server = app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('Missing test server port');
    const client = httpRequest({ host: '127.0.0.1', port: address.port, path: '/captions/generate-from-clip', method: 'POST',
      headers: { 'content-type': 'application/json', 'x-postdee-user-id': userId, 'x-postdee-subscription-plan': 'PRO' } });
    client.on('error', () => undefined);
    client.end(JSON.stringify({ videoS3Key }));
    try {
      await providerStarted;
      client.destroy();
      await vi.waitFor(async () => {
        expect(signal?.aborted).toBe(true);
        expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
      });
      await send(app).expect(200);
      settle();
      await new Promise<void>(resolve => setImmediate(resolve));
      expect(await usage.countForMonth({ userId, monthKey })).toBe(1);
    } finally {
      settle();
      client.destroy();
      await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
  });

  it.each([
    { platform: 'YOUTUBE_SHORTS', caption: 'ดู <เมนู> นี้', hashtags: [] },
    { platform: 'YOUTUBE_SHORTS', caption: 'ก'.repeat(1600), hashtags: ['#' + 'ก'.repeat(100)] },
    { platform: 'INSTAGRAM_REELS', caption: 'ก'.repeat(2150), hashtags: ['#' + 'ก'.repeat(100)] }
  ])('refunds an unpublishable $platform result including appended hashtags', async ({ platform, caption, hashtags }) => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const app = createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate: async input => ({ ...generated(input),
        platformCaptions: { [platform]: { caption, hashtags } } }) } });
    const result = await send(app, { platforms: [platform] }).expect(200);
    expect(result.body).toMatchObject({ isFallback: true, quota: { charged: false, chargedCredits: 0 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
  });

  it('keeps a provider outage fallback factual, Thai and uncharged in shared mode', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const app = createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate: async () => { throw new Error('unavailable'); } } });
    const result = await send(app, { guidance: 'ลด 99 บาท รับรองผล' }).expect(200);
    expect(result.body).toMatchObject({ isFallback: true, fallbackReason: 'PROVIDER_UNAVAILABLE',
      caption: '[เขียนเรื่องที่เห็นจริงในคลิปของคุณที่นี่]', hooks: [], hashtags: [], seoKeywords: [],
      quota: { charged: false, chargedCredits: 0 } });
    expect(result.body.caption).not.toMatch(/99|รับรองผล|video.mp4|Stop scrolling/);
  });

  it('labels and refunds the shared local template when no AI provider is configured', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const result = await send(createApp({ realClipCaptionUsageStore: usage })).expect(200);
    expect(result.body).toMatchObject({ isFallback: true, fallbackReason: 'PROVIDER_UNAVAILABLE',
      caption: '[เขียนเรื่องที่เห็นจริงในคลิปของคุณที่นี่]', quota: { charged: false, chargedCredits: 0 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
  });

  it('returns an explicit uncharged insufficient-evidence result without inventing copy', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const result = await send(createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate: async () => { throw new CaptionInsufficientEvidenceError(); } } })).expect(200);
    expect(result.body).toMatchObject({ isFallback: true, fallbackReason: 'INSUFFICIENT_EVIDENCE',
      caption: '[เขียนเรื่องที่เห็นจริงในคลิปของคุณที่นี่]', quota: { charged: false, chargedCredits: 0 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
  });

  it('refunds a rejected grounding audit for the selected batch while keeping prior usage', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    await usage.record({ userId, monthKey });
    const result = await send(createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate: async () => { throw new CaptionGroundingAuditError(); } } }),
    { platforms: ['TIKTOK', 'YOUTUBE_SHORTS'], expectedCredits: 2 }).expect(200);
    expect(result.body).toMatchObject({ isFallback: true, fallbackReason: 'PROVIDER_UNAVAILABLE',
      quota: { charged: false, chargedCredits: 0, usedThisMonth: 1 } });
    expect(await usage.countForMonth({ userId, monthKey })).toBe(1);
  });

  it.each([false, true])('does not hold the response behind cleanup or re-debit an earlier refund (fallback=%s)', async fallback => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const release = vi.spyOn(usage, 'release');
    let finishCleanup!: () => void;
    const pending = new Promise<void>(resolve => { finishCleanup = resolve; });
    const deleteObject = vi.fn(async () => { await pending; });
    const app = createApp({ config: readServerConfig({ VIDEO_STORAGE: 'r2', CLOUDFLARE_R2_BUCKET: 'caption-test' }),
      r2Client: { createPresignedUploadUrl: async () => 'https://r2.test/upload',
        createPresignedDownloadUrl: async () => 'https://r2.test/download', deleteObject },
      realClipCaptionUsageStore: usage, fetchClipMedia: async () => media, captionGenerationTimeoutMs: 25,
      realClipCaptionProvider: { generate: async input => {
        if (fallback) throw new Error('provider unavailable');
        return generated(input);
      } } });
    try {
      const result = await send(app, { deleteAfterUse: true }).expect(504);
      expect(result.body).toMatchObject({ code: 'CAPTION_GENERATION_TIMEOUT', quota: { charged: false, chargedCredits: 0 } });
      expect(release).toHaveBeenCalledOnce();
      expect(deleteObject).toHaveBeenCalledOnce();
      expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
    } finally { finishCleanup(); }
  });

  it('waits for a late reservation and refunds its exact batch before answering timeout', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const reserve = usage.reserve;
    let completeReservation!: () => void;
    const pending = new Promise<void>(resolve => { completeReservation = resolve; });
    let started!: () => void;
    const reservationStarted = new Promise<void>(resolve => { started = resolve; });
    vi.spyOn(usage, 'reserve').mockImplementationOnce(async input => {
      started();
      await pending;
      return reserve(input);
    });
    const generate = vi.fn(async (input: RealClipCaptionGenerateInput) => generated(input));
    const app = createApp({ realClipCaptionUsageStore: usage, fetchClipMedia: async () => media,
      realClipCaptionProvider: { generate }, captionGenerationTimeoutMs: 15 });
    const result = send(app, { platforms: ['TIKTOK', 'YOUTUBE_SHORTS'], expectedCredits: 2 }).then(value => value);
    await reservationStarted;
    await new Promise<void>(resolve => setTimeout(resolve, 30));
    completeReservation();
    expect((await result).status).toBe(504);
    expect(generate).not.toHaveBeenCalled();
    expect(await usage.countForMonth({ userId, monthKey })).toBe(0);
  });
});
