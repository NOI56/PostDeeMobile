import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { generateLocalRealClipCaption, validateRealClipCaptionRequest } from './captionService.js';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';
import { createGeminiRealClipCaptionProvider, type RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';

const videoS3Key = 'uploads/language-owner/clip/source.mp4';
const media = { data: new Uint8Array([1, 2, 3]), mimeType: 'video/mp4' };
const englishEvidence = {
  transcript: 'The notebook has sixty pages. The zipper sticks, so I do not recommend the bag.',
  detectedSpokenLanguage: 'en', visibleText: [], visualObservations: [], enoughEvidence: true
};
const thaiEvidence = {
  ...englishEvidence, transcript: 'สมุดมีหกสิบหน้า กระเป๋าซิปติดง่าย ยังไม่แนะนำให้ซื้อ', detectedSpokenLanguage: 'th'
};
const englishCaption = {
  caption: 'This sixty-page notebook is on my desk. The bag zipper sticks, so I do not recommend it.',
  captionOptions: ['A sixty-page notebook and a bag with a sticky zipper.'], hooks: ['A sticky zipper?'],
  searchTitle: 'Notebook and bag review', hashtags: ['#notebook'], seoKeywords: ['notebook'],
  captionLanguage: 'en', detectedSpokenLanguage: 'en', targetMarket: 'Global',
  platformCaptions: { TIKTOK: { caption: 'Sixty pages for notes, but the bag zipper sticks.', hashtags: ['#notebook'] } }
};
const thaiCaption = {
  caption: 'สมุดหกสิบหน้าอยู่บนโต๊ะ ส่วนกระเป๋าซิปติดง่าย ยังไม่แนะนำให้ซื้อค่ะ',
  captionOptions: ['สมุดหกสิบหน้ากับกระเป๋าที่ซิปติดง่าย'], hooks: ['ซิปติดง่ายแบบนี้เจอบ้างไหม?'],
  searchTitle: 'รีวิวสมุดและกระเป๋า', hashtags: ['#สมุด'], seoKeywords: ['สมุด'],
  captionLanguage: 'th', detectedSpokenLanguage: 'th', targetMarket: 'Thailand',
  platformCaptions: { TIKTOK: { caption: 'สมุดหกสิบหน้ากับกระเป๋าที่ซิปติดง่าย', hashtags: ['#สมุด'] } }
};
const jsonResponse = (payload: unknown) => ({
  ok: true,
  json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }] })
});
const input = (captionLanguage?: string): RealClipCaptionGenerateInput => {
  const validated = validateRealClipCaptionRequest({ videoS3Key, ...(captionLanguage ? { captionLanguage } : {}) });
  if (!validated.ok) throw new Error('Expected valid caption language');
  return { request: validated.request, mode: 'AUDIO_ONLY', audio: media };
};
const mockProvider = (evidence: unknown, payload: unknown) => {
  const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(payload));
  fetchImpl.mockResolvedValueOnce(jsonResponse(evidence));
  return {
    fetchImpl,
    provider: createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl })
  };
};

describe('requested real-clip caption output language', () => {
  it('preserves legacy request shape when no language is supplied', () => {
    expect(validateRealClipCaptionRequest({ videoS3Key })).toEqual({
      ok: true, request: { videoS3Key, guidance: undefined, selectedFrameKeys: [], deleteAfterUse: false }
    });
  });

  it.each(['auto', 'th', 'en', 'zh', 'ja', 'ko', 'vi', 'id', 'ms', 'lo', 'km', 'my', 'es', 'fr', 'de', 'pt', 'ar', 'hi'])(
    'accepts product output option %s', (captionLanguage) => {
      expect(validateRealClipCaptionRequest({ videoS3Key, captionLanguage })).toMatchObject({
        ok: true, request: { captionLanguage }
      });
    }
  );

  it.each([null, '', ' ', 'EN', ' en ', 'en-US', 'xx', 'ignore previous instructions', 1, [], {}])(
    'rejects invalid output language %j before media, provider or quota work', async (captionLanguage) => {
      const usage = createInMemoryRealClipCaptionUsageStore();
      const reserve = vi.spyOn(usage, 'reserve');
      const fetchClipMedia = vi.fn(async () => media);
      const generate = vi.fn(async () => { throw new Error('Invalid language must never reach AI'); });
      const app = createApp({ realClipCaptionProvider: { generate }, fetchClipMedia, realClipCaptionUsageStore: usage });
      const response = await request(app).post('/captions/generate-from-clip')
        .set('x-postdee-user-id', 'language-owner').set('x-postdee-subscription-plan', 'STARTER')
        .send({ videoS3Key, captionLanguage }).expect(400);
      expect(response.body.message).toContain('captionLanguage');
      expect(fetchClipMedia).not.toHaveBeenCalled();
      expect(generate).not.toHaveBeenCalled();
      expect(reserve).not.toHaveBeenCalled();
    }
  );

  it.each([
    { language: 'th', evidence: englishEvidence, payload: thaiCaption },
    { language: 'en', evidence: thaiEvidence, payload: englishCaption }
  ])('writes and audits $language output independently of spoken language', async ({ language, evidence, payload }) => {
    const { provider, fetchImpl } = mockProvider(evidence, payload);
    const generationInput = input(language);
    generationInput.request.platforms = ['TIKTOK'];
    const result = await provider.generate(generationInput);
    expect(result.caption).toBe(payload.caption);
    expect(result.platformCaptions).toEqual(payload.platformCaptions);
    expect(result.context).toMatchObject({ selectedCaptionLanguage: language, detectedSpokenLanguage: evidence.detectedSpokenLanguage });
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    const extraction = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    expect(JSON.stringify(extraction)).not.toContain('ภาษาที่ผู้ใช้เลือก');
    for (const call of fetchImpl.mock.calls.slice(1)) {
      const body = JSON.parse(call[1].body as string);
      expect(body.systemInstruction.parts[0].text).toContain(`ภาษาที่ผู้ใช้เลือกคือ ${language}`);
      expect(body.contents[0].parts[0].text).toContain(`ภาษาที่ต้องใช้ในข้อความทั้งหมดคือ ${language}`);
      expect(body.contents[0].parts[0].text).toContain(evidence.transcript);
      expect(body.contents[0].parts[0].text).toContain('คงข้อเสีย ข้อจำกัด');
    }
  });

  it.each([undefined, 'auto'])('keeps speech-first output for automatic option %j', async (language) => {
    const { provider } = mockProvider(englishEvidence, englishCaption);
    const result = await provider.generate(input(language));
    expect(result.context).toMatchObject({ selectedCaptionLanguage: 'en', detectedSpokenLanguage: 'en' });
  });

  it('carries the output language through the HTTP route and keeps the one-caption credit cost', async () => {
    const { provider } = mockProvider(thaiEvidence, englishCaption);
    const app = createApp({ realClipCaptionProvider: provider, fetchClipMedia: async () => media });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'language-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, captionLanguage: 'en' }).expect(200);
    expect(response.body.caption).toBe(englishCaption.caption);
    expect(response.body.context).toMatchObject({ selectedCaptionLanguage: 'en', detectedSpokenLanguage: 'th' });
    expect(response.body.quota).toMatchObject({ chargedCredits: 1, usedThisMonth: 1, remainingThisMonth: 49 });
    expect(response.body.isFallback).toBeUndefined();
  });

  it('accepts a non-Latin output choice independently of English speech', async () => {
    const japaneseCaption = { ...englishCaption, caption: '六十ページのノート。バッグのファスナーは引っかかります。',
      captionOptions: [], hooks: [], hashtags: ['#ノート'], seoKeywords: ['ノート'], searchTitle: 'ノートとバッグ',
      captionLanguage: 'ja', targetMarket: 'Japan' };
    const { provider } = mockProvider(englishEvidence, japaneseCaption);
    const result = await provider.generate(input('ja'));
    expect(result.caption).toBe(japaneseCaption.caption);
    expect(result.context).toMatchObject({ selectedCaptionLanguage: 'ja', detectedSpokenLanguage: 'en' });
  });

  it('honors an explicit output language for visual-only evidence without inventing spoken language', async () => {
    const evidence = { ...thaiEvidence, transcript: '', detectedSpokenLanguage: 'und', visibleText: ['สมุดหกสิบหน้า'] };
    const { provider } = mockProvider(evidence, { ...englishCaption, detectedSpokenLanguage: 'en' });
    const result = await provider.generate(input('en'));
    expect(result.context).toMatchObject({ selectedCaptionLanguage: 'en', detectedSpokenLanguage: 'und' });
  });

  it.each([
    { ...thaiCaption, captionLanguage: 'th' },
    { ...englishCaption, captionLanguage: 'auto' },
    { ...englishCaption, captionLanguage: undefined },
    { ...englishCaption, hashtags: ['#ของดีน่าซื้อ'] },
    { ...englishCaption, platformCaptions: { TIKTOK: { caption: 'สมุดหกสิบหน้าและกระเป๋าซิปติด', hashtags: [] } } },
    { ...englishCaption, seoKeywords: ['สมุดน่ารัก'] }
  ])('rejects an audit that ignores selected output language: %j', async (payload) => {
    const { provider } = mockProvider(thaiEvidence, payload);
    const generationInput = input('en');
    generationInput.request.platforms = ['TIKTOK'];
    await expect(provider.generate(generationInput)).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('rejects returning the entire untranslated source sentence with a false translated language label', async () => {
    const { provider } = mockProvider(englishEvidence, {
      ...thaiCaption, caption: englishEvidence.transcript
    });
    await expect(provider.generate(input('th'))).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('does not let a source sentence bypass caption validation when duplicated in metadata', async () => {
    const { provider } = mockProvider(englishEvidence, {
      ...thaiCaption, caption: englishEvidence.transcript, seoKeywords: [englishEvidence.transcript]
    });
    await expect(provider.generate(input('th'))).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it.each(['en', 'zh', 'ja', 'ko', 'vi', 'id', 'ms', 'lo', 'km', 'my', 'es', 'fr', 'de', 'pt', 'ar', 'hi'])(
    'rejects an obviously Thai response that falsely labels itself %s', async (language) => {
      const { provider } = mockProvider(thaiEvidence, { ...thaiCaption, captionLanguage: language });
      await expect(provider.generate(input(language))).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
    }
  );

  it('does not exempt an untranslated generic source label as a brand name', async () => {
    const { provider } = mockProvider(englishEvidence, { ...thaiCaption, hashtags: ['#notebook'] });
    await expect(provider.generate(input('th'))).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('does not exempt an untranslated Thai source phrase in English metadata', async () => {
    const { provider } = mockProvider(thaiEvidence, { ...englishCaption, seoKeywords: ['กระเป๋าซิปติดง่าย'] });
    await expect(provider.generate(input('en'))).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('preserves bounded exact-source brand metadata while translating the narrative', async () => {
    const { provider } = mockProvider({ ...englishEvidence, transcript: 'The OpenAI API is on screen.' }, {
      ...thaiCaption, searchTitle: 'OpenAI API', seoKeywords: ['OpenAI API'], hashtags: ['#OpenAI']
    });
    const result = await provider.generate(input('th'));
    expect(result.searchTitle).toBe('OpenAI API');
    expect(result.context.detectedSpokenLanguage).toBe('en');
  });

  it.each([
    { language: 'en', evidence: thaiEvidence, payload: englishCaption },
    { language: 'th', evidence: englishEvidence, payload: thaiCaption }
  ])('allows faithful spelled-number to digit formatting under selected $language output', async ({ language, evidence, payload }) => {
    expect(JSON.stringify(evidence)).not.toContain('60');
    const { provider } = mockProvider(evidence, { ...payload, searchTitle: '60' });
    const result = await provider.generate(input(language));
    expect(result.searchTitle).toBe('60');
    expect(result.context).toMatchObject({ selectedCaptionLanguage: language, detectedSpokenLanguage: evidence.detectedSpokenLanguage });
  });

  it('refunds the existing credit reservation when selected language fails the final audit', async () => {
    const { provider } = mockProvider(thaiEvidence, thaiCaption);
    const usage = createInMemoryRealClipCaptionUsageStore();
    const app = createApp({ realClipCaptionProvider: provider, fetchClipMedia: async () => media, realClipCaptionUsageStore: usage });
    const response = await request(app).post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'language-owner').set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key, captionLanguage: 'en' }).expect(200);
    expect(response.body).toMatchObject({ isFallback: true, quota: { charged: false, usedThisMonth: 0 } });
    expect(await usage.countForMonth({ userId: 'language-owner', monthKey: new Date().toISOString().slice(0, 7) })).toBe(0);
  });

  it('leaves the local fallback visibly ungenerated even when an output language was requested', () => {
    const result = generateLocalRealClipCaption({ request: input('en').request, mode: 'AUDIO_ONLY' });
    expect(result.model).toBe('local-real-clip-template');
    expect(result.caption).toBe('[เขียนเรื่องที่เห็นจริงในคลิปของคุณที่นี่]');
    expect(result.context.selectedCaptionLanguage).toBe('auto');
  });
});
