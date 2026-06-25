import { describe, expect, it, vi } from 'vitest';

import { createGeminiRealClipCaptionProvider } from './realClipCaptionProvider.js';

const jsonResponse = (payload: unknown) => ({
  ok: true as const,
  json: async () => ({
    candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }]
  })
});

const sampleCaption = {
  caption: 'หยุดเลื่อนก่อน! สินค้านี้ดีจริง 🔥',
  captionOptions: ['ตัวเลือก 1', 'ตัวเลือก 2', 'ตัวเลือก 3'],
  hooks: ['hook1', 'hook2', 'hook3'],
  hashtags: ['#ของดี', '#รีวิว', '#ช้อป', '#โปร', '#ขายดี'],
  seoKeywords: ['ครีม', 'กันแดด', 'ส่งฟรี', 'รีวิว', 'โปร'],
  searchTitle: 'รีวิวสินค้าตัวนี้',
  detectedSpokenLanguage: 'th',
  captionLanguage: 'Thai',
  targetMarket: 'Thailand'
};

const audio = { data: new Uint8Array([1, 2, 3]), mimeType: 'video/mp4' };

describe('createGeminiRealClipCaptionProvider', () => {
  it('listens to the clip and maps a structured caption (Starter audio-only)', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse(sampleCaption));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {}
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });

    expect(result.model).toBe('gemini-2.5-flash-lite');
    expect(result.caption).toBe('หยุดเลื่อนก่อน! สินค้านี้ดีจริง 🔥');
    expect(result.hashtags).toHaveLength(5);
    expect(result.context.detectedSpokenLanguage).toBe('th');
    expect(result.source.mode).toBe('AUDIO_ONLY');
    expect(result.source.selectedFrameCount).toBe(0);

    // Audio part + instruction text part only (no frames in audio-only mode).
    const body = JSON.parse(fetchImpl.mock.calls[0]?.[1]?.body as string);
    const parts = body.contents[0].parts;
    expect(parts.filter((p: { inlineData?: unknown }) => p.inlineData)).toHaveLength(1);
  });

  it('sends selected frames for Pro audio-with-frames mode', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse(sampleCaption));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {}
    });

    const result = await provider.generate({
      request: {
        videoS3Key: 'uploads/u/clip.mp4',
        selectedFrameKeys: ['f1.jpg', 'f2.jpg']
      },
      mode: 'AUDIO_WITH_FRAMES',
      audio,
      frames: [
        { data: new Uint8Array([9]), mimeType: 'image/jpeg' },
        { data: new Uint8Array([8]), mimeType: 'image/jpeg' }
      ]
    });

    expect(result.source.mode).toBe('AUDIO_WITH_FRAMES');
    expect(result.source.selectedFrameCount).toBe(2);

    const body = JSON.parse(fetchImpl.mock.calls[0]?.[1]?.body as string);
    const inlineParts = body.contents[0].parts.filter(
      (p: { inlineData?: unknown }) => p.inlineData
    );
    // audio + 2 frames.
    expect(inlineParts).toHaveLength(3);
  });

  it('retries a transient 503 then succeeds', async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async () => {
      calls += 1;
      if (calls === 1) {
        return { ok: false, status: 503, json: async () => ({}) };
      }
      return jsonResponse(sampleCaption);
    });
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });

    expect(result.caption).toBeTruthy();
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('falls back to a secondary model when the primary stays overloaded', async () => {
    const fetchImpl = vi.fn(async (url: string) => {
      if (url.includes('gemini-2.5-flash-lite')) {
        return { ok: false, status: 503, json: async () => ({}) };
      }
      return jsonResponse(sampleCaption);
    });
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fallbackModels: ['gemini-2.0-flash'],
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 2
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });

    expect(result.model).toBe('gemini-2.0-flash');
  });

  it('throws on invalid JSON so the route can fall back to template', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: true as const,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: 'not json at all' }] } }]
      })
    }));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {}
    });

    await expect(
      provider.generate({
        request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
        mode: 'AUDIO_ONLY',
        audio
      })
    ).rejects.toThrow('invalid JSON');
  });

  it('does not try fallback models when the key is rejected', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: false,
      status: 401,
      json: async () => ({})
    }));
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fallbackModels: ['gemini-2.0-flash'],
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    await expect(
      provider.generate({
        request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
        mode: 'AUDIO_ONLY',
        audio
      })
    ).rejects.toThrow('status 401');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});
