import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import type { Platform } from '../posts/postStore.js';
import { generateLocalRealClipCaption, validateRealClipCaptionRequest } from './captionService.js';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';
import { MediaDownloadError } from '../storage/mediaDownload.js';
import { createGeminiRealClipCaptionProvider, type RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';

const platforms: Platform[] = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
const videoS3Key = 'uploads/platform-caption-owner/clip/source.mp4';
const media = { data: new Uint8Array([1, 2, 3]), mimeType: 'video/mp4' };
const cleanupOptions = (deleteObject: (input: { bucket: string; key: string }) => Promise<void>) => ({
  config: readServerConfig({ VIDEO_STORAGE: 'r2', CLOUDFLARE_R2_BUCKET: 'caption-test-bucket' }),
  r2Client: { createPresignedUploadUrl: async () => 'https://r2.local/upload',
    createPresignedDownloadUrl: async () => 'https://r2.local/download', deleteObject }
});
const platformCaptions = {
  TIKTOK: { caption: 'เมนูนี้มีอะไรให้ดูบ้าง? ลองเปิดตามคลิปกัน', hashtags: ['#เมนูร้าน'] },
  YOUTUBE_SHORTS: { caption: 'พาดูข้อมูลในหน้าเมนูร้านแบบสั้น ๆ', hashtags: ['#เมนูร้าน', '#Shorts'] },
  INSTAGRAM_REELS: { caption: 'เก็บบรรยากาศหน้าเมนูร้านมาฝาก ✨', hashtags: ['#เมนูร้าน'] },
  FACEBOOK_REELS: { caption: 'วันนี้พาดูข้อมูลที่อยู่ในหน้าเมนูร้าน มีตรงไหนที่อยากรู้เพิ่มบ้าง?', hashtags: [] }
};
const providerPayload = {
  caption: 'หน้าเมนูนี้มีอะไรให้ดูบ้าง?', captionOptions: [], hooks: [], hashtags: [], seoKeywords: [],
  searchTitle: 'เมนูร้าน', detectedSpokenLanguage: 'und', captionLanguage: 'th', targetMarket: 'th'
};
const makeProvider = (payload: unknown) => {
  const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => ({
    ok: true,
    json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }] })
  }));
  return { fetchImpl, provider: createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl }) };
};
const input = (): RealClipCaptionGenerateInput => ({
  request: { videoS3Key, selectedFrameKeys: [], deleteAfterUse: false, platforms }, mode: 'AUDIO_ONLY', audio: media
});

describe('platform-specific real-clip captions', () => {
  it('keeps legacy request and provider results unchanged when platforms is omitted', async () => {
    const validated = validateRealClipCaptionRequest({ videoS3Key });
    expect(validated).toEqual({ ok: true, request: { videoS3Key, guidance: undefined, selectedFrameKeys: [], deleteAfterUse: false } });
    const { provider } = makeProvider({ ...providerPayload, platformCaptions });
    const legacyInput = input();
    delete legacyInput.request.platforms;
    expect(await provider.generate(legacyInput)).not.toHaveProperty('platformCaptions');
  });

  it.each([null, [], 'TIKTOK', ['tiktok'], ['SHOPEE_VIDEO'], ['TIKTOK', 'TIKTOK'], ['TIKTOK', null], [1], [' TIKTOK ']].map((invalid) => ({ invalid })))(
    'rejects invalid platforms $invalid before downloading media or reserving quota', async ({ invalid }) => {
      const usage = createInMemoryRealClipCaptionUsageStore();
      const reserve = vi.spyOn(usage, 'reserve');
      const fetchClipMedia = vi.fn(async () => media);
      const { provider, fetchImpl } = makeProvider(providerPayload);
      const app = createApp({ realClipCaptionProvider: provider, fetchClipMedia, realClipCaptionUsageStore: usage });
      const response = await request(app).post('/captions/generate-from-clip')
        .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
        .send({ videoS3Key, platforms: invalid }).expect(400);
      expect(response.body.message).toContain('platforms');
      expect(fetchClipMedia).not.toHaveBeenCalled();
      expect(fetchImpl).not.toHaveBeenCalled();
      expect(reserve).not.toHaveBeenCalled();
    }
  );

  it('requests four adapted captions with the same clip evidence and writing style in one provider call', async () => {
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const generationInput = input();
    generationInput.request.writingStyle = { tone: 'friendly', length: 'short', emoji: 'light', examples: ['ลองดูตรงนี้กันนะ'] };
    const result = await provider.generate(generationInput);
    expect(result.platformCaptions).toEqual(platformCaptions);
    expect(new Set(Object.values(result.platformCaptions!).map((entry) => entry!.caption)).size).toBe(4);
    expect(fetchImpl).toHaveBeenCalledOnce();
    const body = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    const instruction = body.contents[0].parts.at(-1).text as string;
    for (const platform of platforms) expect(instruction).toContain(platform);
    expect(instruction).toContain('platformCaptions');
    expect(instruction).toContain('Facebook Reels บนเพจ Facebook');
    expect(instruction).not.toContain('Facebook Page Video');
    expect(instruction).not.toContain('ไม่เรียกว่า Facebook Reels');
    expect(instruction).toContain('คุยเป็นกันเอง');
    expect(instruction).toContain('ลองดูตรงนี้กันนะ');
    expect(body.systemInstruction.parts[0].text).toContain('ห้ามแต่งประโยชน์ สินค้า ราคา ส่วนลด');
    expect(body.generationConfig.responseMimeType).toBe('application/json');
  });

  it('returns only the selected channel variants without inventing missing channels', async () => {
    const { provider } = makeProvider({ ...providerPayload, platformCaptions });
    const generationInput = input();
    generationInput.request.platforms = ['YOUTUBE_SHORTS'];
    expect((await provider.generate(generationInput)).platformCaptions).toEqual({ YOUTUBE_SHORTS: platformCaptions.YOUTUBE_SHORTS });
  });

  it.each([
    undefined, null, [], {},
    { ...platformCaptions, TIKTOK: { caption: ' ', hashtags: [] } },
    { ...platformCaptions, TIKTOK: { caption: 'ข้อความ', hashtags: 'tag' } },
    { ...platformCaptions, TIKTOK: { caption: 'ข้อความ', hashtags: [null] } },
    { ...platformCaptions, YOUTUBE_SHORTS: { caption: 5, hashtags: [] } }
  ].map((variants) => ({ variants })))('rejects incomplete or malformed provider variants $variants so the route can label the fallback', async ({ variants }) => {
    const { provider } = makeProvider({ ...providerPayload, platformCaptions: variants });
    await expect(provider.generate(input())).rejects.toThrow('platform captions');
  });

  it('reserves one generation and cleans the owned media once for all four variants', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const reserve = vi.spyOn(usage, 'reserve');
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const generate = vi.spyOn(provider, 'generate');
    const deleteObject = vi.fn(async () => {});
    const app = createApp({ ...cleanupOptions(deleteObject), realClipCaptionProvider: provider, fetchClipMedia: async () => media,
      realClipCaptionUsageStore: usage });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms, deleteAfterUse: true }).expect(200);
    expect(response.body.platformCaptions).toEqual(platformCaptions);
    expect(response.body.quota).toMatchObject({ limit: 50, usedThisMonth: 1, remainingThisMonth: 49 });
    expect(response.body.isFallback).toBeUndefined();
    expect(reserve).toHaveBeenCalledOnce();
    expect(generate).toHaveBeenCalledOnce();
    expect(fetchImpl).toHaveBeenCalledOnce();
    expect(deleteObject).toHaveBeenCalledExactlyOnceWith({ bucket: 'caption-test-bucket', key: videoS3Key });
  });

  it.each([
    { selected: ['YOUTUBE_SHORTS'] as Platform[] },
    { selected: ['TIKTOK', 'INSTAGRAM_REELS'] as Platform[] }
  ])('returns only selected $selected captions and charges one generation for the request', async ({ selected }) => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const reserve = vi.spyOn(usage, 'reserve');
    const release = vi.spyOn(usage, 'release');
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const generate = vi.spyOn(provider, 'generate');
    const app = createApp({ realClipCaptionProvider: provider, fetchClipMedia: async () => media, realClipCaptionUsageStore: usage });

    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms: selected }).expect(200);

    expect(response.body.platformCaptions).toEqual(Object.fromEntries(selected.map(platform => [platform, platformCaptions[platform]])));
    expect(Object.keys(response.body.platformCaptions)).toEqual(selected);
    expect(response.body.quota).toMatchObject({ limit: 50, usedThisMonth: 1, remainingThisMonth: 49 });
    expect(response.body.isFallback).toBeUndefined();
    expect(reserve).toHaveBeenCalledOnce();
    expect(release).not.toHaveBeenCalled();
    expect(generate).toHaveBeenCalledExactlyOnceWith(expect.objectContaining({
      request: expect.objectContaining({ platforms: selected })
    }));
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it.each([
    { selected: ['YOUTUBE_SHORTS'] as Platform[] },
    { selected: ['TIKTOK', 'INSTAGRAM_REELS'] as Platform[] }
  ])('refunds selected $selected fallback once without returning unrequested captions or removing prior usage', async ({ selected }) => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const monthKey = new Date().toISOString().slice(0, 7);
    await usage.record({ userId: 'platform-caption-owner', monthKey });
    const reserve = vi.spyOn(usage, 'reserve');
    const release = vi.spyOn(usage, 'release');
    const { provider, fetchImpl } = makeProvider({
      ...providerPayload, platformCaptions: { FACEBOOK_REELS: platformCaptions.FACEBOOK_REELS }
    });
    const generate = vi.spyOn(provider, 'generate');
    const app = createApp({ realClipCaptionProvider: provider, fetchClipMedia: async () => media, realClipCaptionUsageStore: usage });

    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms: selected }).expect(200);

    expect(response.body).toMatchObject({
      isFallback: true, model: 'local-real-clip-template',
      quota: { charged: false, usedThisMonth: 1, remainingThisMonth: 49 }
    });
    expect(Object.keys(response.body.platformCaptions)).toEqual(selected);
    for (const entry of Object.values(response.body.platformCaptions) as Array<{ caption: string; hashtags: string[] }>) {
      expect(entry.caption).toBeTruthy();
      expect(entry.hashtags).toEqual([]);
    }
    expect(reserve).toHaveBeenCalledOnce();
    const reservation = await reserve.mock.results[0].value;
    expect(reservation.ok).toBe(true);
    if (reservation.ok) expect(release).toHaveBeenCalledExactlyOnceWith(reservation.record);
    expect(await usage.countForMonth({ userId: 'platform-caption-owner', monthKey })).toBe(1);
    expect(generate).toHaveBeenCalledOnce();
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('returns complete transparent uncharged fallback variants when the provider omits a channel', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const { provider } = makeProvider({ ...providerPayload, platformCaptions: { TIKTOK: platformCaptions.TIKTOK } });
    const deleteObject = vi.fn(async () => {});
    const app = createApp({ ...cleanupOptions(deleteObject), realClipCaptionProvider: provider, fetchClipMedia: async () => media,
      realClipCaptionUsageStore: usage });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key, platforms, deleteAfterUse: true }).expect(200);
    expect(response.body).toMatchObject({ isFallback: true, model: 'local-real-clip-template', quota: { charged: false, usedThisMonth: 0 } });
    expect(Object.keys(response.body.platformCaptions)).toEqual(platforms);
    expect(deleteObject).toHaveBeenCalledExactlyOnceWith({ bucket: 'caption-test-bucket', key: videoS3Key });
    for (const entry of Object.values(response.body.platformCaptions) as Array<{ caption: string; hashtags: string[] }>) {
      expect(entry.caption).toBeTruthy();
      expect(entry.hashtags).toEqual([]);
    }
  });

  it('also labels selected platform templates as fallback when no AI provider is configured', async () => {
    const app = createApp();
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms }).expect(200);
    expect(response.body).toMatchObject({ isFallback: true, model: 'local-real-clip-template', quota: { charged: false, usedThisMonth: 0 } });
    expect(Object.keys(response.body.platformCaptions)).toEqual(platforms);
  });

  it('does not accept partial results from another provider adapter as successful AI', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const generate = vi.fn(async (generationInput: RealClipCaptionGenerateInput) => ({
      ...generateLocalRealClipCaption({ request: generationInput.request, mode: generationInput.mode }),
      model: 'another-ai-provider', platformCaptions: { TIKTOK: platformCaptions.TIKTOK }
    }));
    const app = createApp({ realClipCaptionProvider: { generate }, fetchClipMedia: async () => media, realClipCaptionUsageStore: usage });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms }).expect(200);
    expect(generate).toHaveBeenCalledOnce();
    expect(response.body).toMatchObject({ isFallback: true, model: 'local-real-clip-template', quota: { charged: false, usedThisMonth: 0 } });
    expect(Object.keys(response.body.platformCaptions)).toEqual(platforms);
  });

  it('cleans selected owned frames and clip without charging when media download fails', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const reserve = vi.spyOn(usage, 'reserve');
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const frameKey = 'uploads/platform-caption-owner/frame/frame.jpg';
    const deleteObject = vi.fn(async () => {});
    const fetchClipMedia = vi.fn(async (key: string) => {
      if (key === frameKey) throw new MediaDownloadError('Media expired', 410, 'AI_MEDIA_EXPIRED');
      return media;
    });
    const app = createApp({ ...cleanupOptions(deleteObject), realClipCaptionProvider: provider, fetchClipMedia, realClipCaptionUsageStore: usage });
    await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key, platforms, selectedFrameKeys: [frameKey], deleteAfterUse: true }).expect(410);
    expect(reserve).not.toHaveBeenCalled();
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(deleteObject).toHaveBeenCalledTimes(2);
    expect(deleteObject).toHaveBeenCalledWith({ bucket: 'caption-test-bucket', key: frameKey });
    expect(deleteObject).toHaveBeenCalledWith({ bucket: 'caption-test-bucket', key: videoS3Key });
  });

  it('enforces the same monthly cap and cleans owned media without making a provider request', async () => {
    const usage = createInMemoryRealClipCaptionUsageStore();
    const monthKey = new Date().toISOString().slice(0, 7);
    for (let count = 0; count < 50; count += 1) await usage.record({ userId: 'platform-caption-owner', monthKey });
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const fetchClipMedia = vi.fn(async () => media);
    const deleteObject = vi.fn(async () => {});
    const app = createApp({ ...cleanupOptions(deleteObject), realClipCaptionProvider: provider, fetchClipMedia, realClipCaptionUsageStore: usage });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, platforms, deleteAfterUse: true }).expect(429);
    expect(response.body.quota).toMatchObject({ limit: 50, usedThisMonth: 50, remainingThisMonth: 0 });
    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(deleteObject).toHaveBeenCalledExactlyOnceWith({ bucket: 'caption-test-bucket', key: videoS3Key });
  });

  it('keeps the paid-plan and owner-media guards for multi-platform generation', async () => {
    const { provider, fetchImpl } = makeProvider({ ...providerPayload, platformCaptions });
    const fetchClipMedia = vi.fn(async () => media);
    const deleteObject = vi.fn(async () => {});
    const app = createApp({ ...cleanupOptions(deleteObject), realClipCaptionProvider: provider, fetchClipMedia });
    await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'platform-caption-owner').set('x-postdee-subscription-plan', 'BASIC')
      .send({ videoS3Key, platforms, deleteAfterUse: true }).expect(402);
    await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'different-owner').set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key, platforms, deleteAfterUse: true }).expect(403);
    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it('does not invent product claims or transplant seller guidance into selected template captions', () => {
    const fallback = generateLocalRealClipCaption({ request: { ...input().request, guidance: 'ลดเหลือ 49 บาท รับรองผล' }, mode: 'AUDIO_ONLY' });
    expect(fallback.caption).not.toMatch(/49|รับรองผล|source\.mp4/);
    for (const entry of Object.values(fallback.platformCaptions!)) {
      expect(entry!.caption).not.toMatch(/49|รับรองผล|source\.mp4/);
      expect(entry!.hashtags).toEqual([]);
    }
  });
});
