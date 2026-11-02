import { describe, expect, it, vi } from 'vitest';

import { createGeminiRealClipCaptionProvider, type RealClipCaptionGenerateInput } from './realClipCaptionProvider.js';

const evidence = {
  transcript: 'กระเป๋าใบนี้ซิปติดง่าย ยังไม่แนะนำให้ซื้อ',
  detectedSpokenLanguage: 'th',
  visibleText: [],
  visualObservations: [],
  enoughEvidence: true
};
const caption = {
  caption: 'ซิปติดง่ายแบบนี้ ยังไม่แนะนำให้ซื้อค่ะ', captionOptions: [], hooks: [],
  hashtags: [], seoKeywords: [], searchTitle: 'รีวิวซิปกระเป๋า',
  detectedSpokenLanguage: 'th', captionLanguage: 'th', targetMarket: 'Thailand'
};
const jsonResponse = (payload: unknown) => ({
  ok: true,
  json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }] })
});
const input = (): RealClipCaptionGenerateInput => ({
  request: {
    videoS3Key: 'uploads/evidence-owner/clip/audio.m4a', mediaKind: 'audio',
    selectedFrameKeys: [], deleteAfterUse: false
  },
  mode: 'AUDIO_ONLY', audio: { data: new Uint8Array([1, 2, 3]), mimeType: 'audio/mp4' }
});

describe('real-clip evidence before caption writing', () => {
  it('audits a draft against the same evidence and returns repaired facts and tags', async () => {
    const notebookEvidence = { ...evidence, transcript: 'สมุด60หน้า ราคา49บาท มีสีน้ำเงินและสีชมพู' };
    const draft = { ...caption, caption: 'สมุดกับปากกาดี ๆ กำลังจัดโปรโมชั่น', hashtags: ['#โปรโมชั่น'],
      platformCaptions: { FACEBOOK_REELS: { caption: 'ใครกำลังหาปากกาดี ๆ กับสมุดโน้ต', hashtags: ['#โปรโมชั่น'] } } };
    const corrected = { ...caption, caption: 'สมุด60หน้า ราคา49บาท เลือกสีน้ำเงินหรือสีชมพูได้ค่ะ', hashtags: ['#สมุด'],
      platformCaptions: { FACEBOOK_REELS: { caption: 'สมุด60หน้า ราคา49บาท มีสีน้ำเงินกับสีชมพูค่ะ', hashtags: ['#สมุด'] } } };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(corrected));
    fetchImpl.mockResolvedValueOnce(jsonResponse(notebookEvidence)).mockResolvedValueOnce(jsonResponse(draft));
    const request = input();
    request.request.platforms = ['FACEBOOK_REELS'];
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    const result = await provider.generate(request);

    expect(fetchImpl).toHaveBeenCalledTimes(3);
    expect(result.caption).toBe(corrected.caption);
    expect(result.platformCaptions).toEqual(corrected.platformCaptions);
    expect(JSON.stringify(result)).not.toMatch(/ปากกา|โปรโมชั่น/);
    const audit = JSON.parse(fetchImpl.mock.calls[2][1].body as string);
    expect(audit.contents[0].parts).toHaveLength(1);
    expect(audit.contents[0].parts[0]).not.toHaveProperty('inlineData');
    expect(audit.contents[0].parts[0].text).toContain(notebookEvidence.transcript);
    expect(audit.contents[0].parts[0].text).toContain(draft.platformCaptions.FACEBOOK_REELS.caption);
    expect(audit.contents[0].parts[0].text).toContain('ลบสินค้าหรือสิ่งของ');
    expect(audit.contents[0].parts[0].text).toContain('แฮชแท็ก');
    expect(audit.generationConfig.temperature).toBe(0);
  });

  it.each([{ verified: true }, { ...caption, caption: '' }, null])('rejects an audit without usable corrected captions: %j', async (invalidAudit) => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(invalidAudit));
    fetchImpl.mockResolvedValueOnce(jsonResponse(evidence)).mockResolvedValueOnce(jsonResponse(caption));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate(input())).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  it('locks writing and audit to the spoken language and removes emoji when the selected style forbids them', async () => {
    const englishEvidence = { ...evidence, transcript: 'This notebook has sixty pages and costs forty nine baht.', detectedSpokenLanguage: 'en' };
    const englishCaption = { ...caption, caption: 'Sixty pages for your notes 📓', captionOptions: ['A notebook for your ideas ✨'],
      hooks: ['Ready for a fresh page? 💡'], searchTitle: 'Notebook', captionLanguage: 'en', detectedSpokenLanguage: 'en',
      platformCaptions: { TIKTOK: { caption: 'A sixty-page notebook 📓', hashtags: [] } } };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(englishCaption));
    fetchImpl.mockResolvedValueOnce(jsonResponse(englishEvidence));
    const request = input();
    request.request.platforms = ['TIKTOK'];
    request.request.writingStyle = { tone: 'friendly', length: 'short', emoji: 'none', examples: [] };
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    const result = await provider.generate(request);

    expect(result.context.selectedCaptionLanguage).toBe('en');
    expect(result.caption).toBe('Sixty pages for your notes');
    expect(result.captionOptions).toEqual(['A notebook for your ideas']);
    expect(result.hooks).toEqual(['Ready for a fresh page?']);
    expect(result.platformCaptions?.TIKTOK?.caption).toBe('A sixty-page notebook');
    for (const call of fetchImpl.mock.calls.slice(1)) {
      const body = JSON.parse(call[1].body as string);
      expect(body.contents[0].parts[0].text).toContain('ภาษาที่ต้องใช้ในข้อความทั้งหมดคือ en');
      expect(body.contents[0].parts[0].text).toContain('ไม่ใส่อีโมจิ');
    }
  });

  it('rejects audited Thai captions for English speech instead of reporting them as a successful English result', async () => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse({ ...caption, captionLanguage: 'en' }));
    fetchImpl.mockResolvedValueOnce(jsonResponse({ ...evidence, transcript: 'This notebook has sixty pages.', detectedSpokenLanguage: 'en' }));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate(input())).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('rejects wrong-language appended hashtags even when the main English caption is valid', async () => {
    const englishCaption = { ...caption, caption: 'A notebook for your notes', captionOptions: [], hooks: [],
      searchTitle: 'Notebook', captionLanguage: 'en', hashtags: ['#สมุดน่ารัก'] };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(englishCaption));
    fetchImpl.mockResolvedValueOnce(jsonResponse({ ...evidence, transcript: 'This notebook has sixty pages.', detectedSpokenLanguage: 'en' }));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate(input())).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('allows exact source brand names despite hashtag casing or equivalent Unicode composition', async () => {
    const brandedCaption = { ...caption, caption: 'พาดู iPhone15 กับ Café กันค่ะ',
      hashtags: ['#iphone15', '#CAFÉ'], seoKeywords: ['iphone15', 'café'] };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(brandedCaption));
    fetchImpl.mockResolvedValueOnce(jsonResponse({ ...evidence, transcript: 'รีวิว iPhone15 และ Cafe\u0301' }));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    const result = await provider.generate(input());

    expect(result.caption).toBe(brandedCaption.caption);
    expect(result.hashtags).toEqual(['#iphone15', '#CAFÉ']);
    expect(result.seoKeywords).toEqual(['iphone15', 'café']);
  });

  it('does not treat unrelated Latin metadata as a proper name when allowing source brand names', async () => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse({ ...caption, hashtags: ['#bestdeal'] }));
    fetchImpl.mockResolvedValueOnce(jsonResponse({ ...evidence, transcript: 'รีวิว iPhone15 และ Cafe\u0301' }));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate(input())).rejects.toMatchObject({ code: 'AI_CAPTION_GROUNDING_FAILED' });
  });

  it('preserves Thai combining marks and product quantities while removing emoji sequences', async () => {
    const thaiCaption = { ...caption, caption: 'สมุด60หน้า ราคา49บาท สีน้ำเงิน 1️⃣เล่ม 👩🏽‍💻🇹🇭' };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(thaiCaption));
    fetchImpl.mockResolvedValueOnce(jsonResponse({ ...evidence, transcript: 'สมุด60หน้า ราคา49บาท สีน้ำเงิน หนึ่งเล่ม' }));
    const request = input();
    request.request.writingStyle = { tone: 'friendly', length: 'short', emoji: 'none', examples: [] };
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    expect((await provider.generate(request)).caption).toBe('สมุด60หน้า ราคา49บาท สีน้ำเงิน 1เล่ม');
  });

  it('extracts from actual media before writing text-only captions, preserving negative speech as evidence', async () => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(caption));
    fetchImpl.mockResolvedValueOnce(jsonResponse(evidence)).mockResolvedValueOnce(jsonResponse(caption));
    const request = input();
    request.request.guidance = 'เขียนให้น่าซื้อ';
    request.request.writingStyle = { tone: 'soft_sell', length: 'short', emoji: 'none', examples: ['สินค้าดีมาก ลด90%'] };
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    const result = await provider.generate(request);

    expect(result.caption).toBe(caption.caption);
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    const extraction = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    const writing = JSON.parse(fetchImpl.mock.calls[1][1].body as string);
    expect(extraction.contents[0].parts[0].inlineData.mimeType).toBe('audio/mp4');
    expect(JSON.stringify(extraction)).not.toContain(request.request.guidance);
    expect(JSON.stringify(extraction)).not.toContain('สินค้าดีมาก ลด90%');
    expect(JSON.stringify(extraction)).toContain('ไม่มีภาพ');
    expect(JSON.stringify(extraction)).not.toContain('[ชื่อเมนูที่เห็นจริง]');
    expect(writing.contents[0].parts).toHaveLength(1);
    expect(writing.contents[0].parts[0]).not.toHaveProperty('inlineData');
    expect(writing.contents[0].parts[0].text).toContain(evidence.transcript);
    expect(writing.contents[0].parts[0].text).toContain('ห้ามกลับคำปฏิเสธเป็นคำชม');
    expect(writing.contents[0].parts[0].text).toContain('เขียนให้น่าซื้อ');
    expect(extraction.generationConfig.temperature).toBe(0);
    expect(writing.generationConfig.temperature).toBe(0.4);
  });

  it.each([
    { ...evidence, transcript: '', detectedSpokenLanguage: 'und', enoughEvidence: false },
    { ...evidence, transcript: '', detectedSpokenLanguage: 'und', enoughEvidence: true },
    { ...evidence, transcript: '', visualObservations: ['หน้าจอเปิดเมนูร้านค้า'], visibleText: ['ร้านค้า'], enoughEvidence: true }
  ])('rejects no usable audio evidence without inventing a scene or trying another model: %j', async (emptyEvidence) => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(emptyEvidence));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'test-key', model: 'test-model', fallbackModels: ['secondary-model'], fetchImpl
    });

    await expect(provider.generate(input())).rejects.toMatchObject({ code: 'AI_CAPTION_INSUFFICIENT_EVIDENCE' });
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('allows visible product evidence from a silent video without inventing spoken language', async () => {
    const videoEvidence = { ...evidence, transcript: '', detectedSpokenLanguage: 'und',
      visibleText: ['สมุด60หน้า 49บาท'], visualObservations: ['สมุดสีน้ำเงินและสีชมพู'] };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(caption));
    fetchImpl.mockResolvedValueOnce(jsonResponse(videoEvidence));
    const request = input();
    request.audio.mimeType = 'video/mp4';
    delete request.request.mediaKind;
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    const result = await provider.generate(request);

    expect(result.context.detectedSpokenLanguage).toBe('und');
    const writing = JSON.parse(fetchImpl.mock.calls[1][1].body as string);
    expect(writing.contents[0].parts[0].text).toContain('สมุด60หน้า 49บาท');
  });

  it('accepts actual Pro frames as visual evidence with an audio primary part', async () => {
    const frameEvidence = { ...evidence, transcript: '', detectedSpokenLanguage: 'und',
      visualObservations: ['กระเป๋าสีดำ'] };
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(caption));
    fetchImpl.mockResolvedValueOnce(jsonResponse(frameEvidence));
    const request = input();
    request.mode = 'AUDIO_WITH_FRAMES';
    request.frames = [{ data: new Uint8Array([4]), mimeType: 'image/jpeg' }];
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    expect((await provider.generate(request)).context.detectedSpokenLanguage).toBe('und');
    const extraction = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    expect(extraction.contents[0].parts.filter((part: { inlineData?: unknown }) => part.inlineData)).toHaveLength(2);
  });

  it('does not treat unused Starter frames as evidence', async () => {
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse({ ...evidence, transcript: '',
      visualObservations: ['กระเป๋าสีดำ'] }));
    const request = input();
    request.frames = [{ data: new Uint8Array([4]), mimeType: 'image/jpeg' }];
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate(request)).rejects.toMatchObject({ code: 'AI_CAPTION_INSUFFICIENT_EVIDENCE' });
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('ends the overall provider operation when fetch does not settle', async () => {
    const fetchImpl = vi.fn((_url: string, _init: RequestInit) => new Promise<never>(() => {}));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'test-key', model: 'test-model', fetchImpl, requestTimeoutMs: 20
    });

    await expect(provider.generate(input())).rejects.toThrow('timed out');
    expect(fetchImpl).toHaveBeenCalledOnce();
    expect(fetchImpl.mock.calls[0][1].signal?.aborted).toBe(true);
  });

  it('propagates the caller cancellation without retrying or starting caption writing', async () => {
    const controller = new AbortController();
    const fetchImpl = vi.fn((_url: string, _init: RequestInit) => new Promise<never>(() => {}));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });
    const request = { ...input(), signal: controller.signal };
    const pending = provider.generate(request);
    controller.abort(new Error('caller cancelled caption'));

    await expect(pending).rejects.toThrow('caller cancelled caption');
    expect(fetchImpl).toHaveBeenCalledOnce();
    expect(fetchImpl.mock.calls[0][1].signal?.aborted).toBe(true);
  });

  it('uses the same deadline during caption writing after evidence has completed', async () => {
    const fetchImpl = vi.fn((_url: string, _init: RequestInit): Promise<ReturnType<typeof jsonResponse>> => new Promise(() => {}));
    fetchImpl.mockResolvedValueOnce(jsonResponse(evidence));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'test-key', model: 'test-model', fetchImpl, requestTimeoutMs: 20
    });

    await expect(provider.generate(input())).rejects.toThrow('timed out');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(fetchImpl.mock.calls[0][1].signal).toBe(fetchImpl.mock.calls[1][1].signal);
    expect(fetchImpl.mock.calls[1][1].signal?.aborted).toBe(true);
  });

  it('stops retry backoff immediately when the caller cancels', async () => {
    const controller = new AbortController();
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => ({ ok: false, status: 503, json: async () => ({}) }));
    const sleep = vi.fn(async () => {
      controller.abort(new Error('cancelled during retry'));
      await new Promise<never>(() => {});
    });
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl, sleep });

    await expect(provider.generate({ ...input(), signal: controller.signal })).rejects.toThrow('cancelled during retry');
    expect(sleep).toHaveBeenCalledOnce();
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('does not send media for an already cancelled operation', async () => {
    const controller = new AbortController();
    controller.abort(new Error('cancelled before request'));
    const fetchImpl = vi.fn(async (_url: string, _init: RequestInit) => jsonResponse(evidence));
    const provider = createGeminiRealClipCaptionProvider({ apiKey: 'test-key', model: 'test-model', fetchImpl });

    await expect(provider.generate({ ...input(), signal: controller.signal })).rejects.toThrow('cancelled before request');
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
