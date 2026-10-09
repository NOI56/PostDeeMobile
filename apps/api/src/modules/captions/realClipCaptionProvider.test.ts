import { describe, expect, it, vi } from 'vitest';

import {
  createGeminiRealClipCaptionProvider,
  createRealClipCaptionProviderFromConfig
} from './realClipCaptionProvider.js';

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

  it.each(['AUDIO_ONLY', 'AUDIO_WITH_FRAMES'] as const)(
    'requests grounded hook-first captions from the supplied clip in %s mode',
    async (mode) => {
      const fetchImpl = vi.fn(async () => jsonResponse(sampleCaption));
      const provider = createGeminiRealClipCaptionProvider({
        apiKey: 'gemini-key',
        model: 'gemini-2.5-flash-lite',
        fetchImpl
      });
      const guidance = 'เน้นเมนูร้านที่เห็นในคลิป ไม่ขายสินค้า';
      await provider.generate({
        request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [], guidance },
        mode,
        audio
      });

      const body = JSON.parse(fetchImpl.mock.calls[0]?.[1]?.body as string);
      const system = body.systemInstruction.parts[0].text as string;
      const instruction = body.contents[0].parts.at(-1).text as string;
      const prompt = `${system}\n${instruction}`;
      expect(system.startsWith('ใช้ภาษาไทยเป็นค่าเริ่มต้น')).toBe(true);
      expect(system).toContain('คำพูดจริงหรือข้อความหลักที่อ่านได้ตลอดคลิปเป็นภาษาอื่น');
      expect(system).toContain('ครีเอเตอร์และผู้ขาย');
      expect(system).not.toContain('Thai affiliate marketer');
      expect(prompt).toContain('คลิปที่ส่งมา');
      expect(prompt).toContain('Hook เฉพาะเรื่องที่เห็นจริง');
      expect(prompt).toContain('ไม่ทักทาย');
      expect(prompt).toContain('ห้ามแต่งประโยชน์ สินค้า ราคา ส่วนลด');
      expect(prompt).toContain('คลิปไม่มีเสียง');
      expect(prompt).toContain('สิ่งที่เห็นและข้อความที่อ่านได้');
      expect(prompt).toContain('ตั้ง detectedSpokenLanguage เป็น "und"');
      expect(prompt).toContain('ชื่อแบรนด์ ชื่อบัญชี วันที่ ตัวเลข หรือชื่อฟิลด์ JSON');
      expect(prompt).toContain('หากข้อความหลักเป็นภาษาอื่นให้ใช้ภาษานั้น');
      expect(prompt).toContain('ปุ่ม เมนู ชื่อแพ็กเกจ และลิงก์ไม่ใช่หลักฐานว่าทำสิ่งนั้นสำเร็จ');
      expect(prompt).toContain('ถ้าคลิปไม่มีเสียงและมีเพียงการเปิดหรือสลับเมนู');
      expect(prompt).toContain('เขียนเป็นการพาชมเมนูที่เห็นจริงเท่านั้น');
      expect(prompt).toContain('ห้ามเปลี่ยนเป็นวิธีเริ่มธุรกิจ สร้างร้าน โปรโมต หรือประโยชน์ที่ยังไม่เห็น');
      expect(prompt).toContain('[ชื่อเมนูที่เห็นจริง] มีอะไรให้ดูบ้าง?');
      expect(prompt).toContain('caption, captionOptions, hooks, seoKeywords และ hashtags ทั้งชุด');
      expect(prompt).toContain('การตั้งค่า แก้ไข ซื้อสินค้า โพสต์ ตั้งเวลา หรือเชื่อมบัญชี');
      expect(prompt).toContain('ข้อสังเกตหรือคำถามธรรมชาติ');
      expect(prompt).toContain('ห้ามสั่งให้คนดูทำสิ่งที่คลิปไม่ได้แสดง');
      expect(prompt).toContain('1–2 ประโยคสั้น');
      expect(prompt).toContain('เสียงของครีเอเตอร์ที่พูดกับคนดู');
      expect(prompt).toContain('ไม่ใช่รายงานวิเคราะห์ภาพ');
      expect(prompt).toContain('captionOptions แต่ละรายการเป็นแคปชั่นพร้อมโพสต์ 1–2 ประโยคที่มี Hook ของตัวเอง');
      expect(prompt).toContain('The app shows');
      expect(prompt).toContain('อีเมลหรือรหัสบัญชีที่เห็นผ่าน ๆ');
      expect(prompt).toContain('ไม่ถอดคำพูดเป็นแคปชั่น');
      expect(prompt).toContain('ไม่ใส่รายการ SEO: หรือแฮชแท็กใน caption');
      expect(prompt).toContain('metadata ใช้ภาษาเดียวกับแคปชั่น');
      expect(prompt).toContain('ตรงกับเรื่องที่เห็นจริง');
      expect(prompt).toContain('ให้ส่ง []');
      expect(prompt).toContain(guidance);
      expect(instruction).toContain('ภาษาพูดจริง → ข้อความหลักที่อ่านได้ทั้งคลิป → คำแนะนำผู้ขาย → ภาษาไทย');
      expect(body.contents[0].parts[0].inlineData).toEqual({
        mimeType: 'video/mp4', data: 'AQID'
      });
      expect(body.generationConfig).toEqual({
        temperature: 0.4, responseMimeType: 'application/json'
      });
    }
  );

  it.each([
    { language: 'en', caption: 'Where does this menu lead?' },
    { language: 'ja', caption: 'このメニューには何がある？' }
  ])('preserves a supported $language caption without forcing or translating it into Thai', async ({ language, caption }) => {
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl: async () => jsonResponse({
        ...sampleCaption, caption, captionLanguage: language, detectedSpokenLanguage: language
      })
    });
    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });
    expect(result.caption).toBe(caption);
    expect(result.context.selectedCaptionLanguage).toBe(language);
    expect(result.context.detectedSpokenLanguage).toBe(language);
  });

  it.each([
    { name: 'missing', metadata: {} },
    { name: 'empty', metadata: { hashtags: [], seoKeywords: [] } },
    { name: 'invalid', metadata: { hashtags: [null, 1, ' '], seoKeywords: false } }
  ])('leaves $name metadata empty rather than inserting unrelated tags or keywords', async ({ metadata }) => {
    const { hashtags: _hashtags, seoKeywords: _keywords, ...withoutMetadata } = sampleCaption;
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl: async () => jsonResponse({ ...withoutMetadata, ...metadata })
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });
    expect(result.hashtags).toEqual([]);
    expect(result.seoKeywords).toEqual([]);
    expect(result.caption).toBe(sampleCaption.caption);
    expect(result.model).toBe('gemini-2.5-flash-lite');
  });

  it('normalizes and deduplicates metadata before limiting it, without rewriting the caption or hooks', async () => {
    const caption = 'เปิดเมนูร้านในคลิปนี้ แล้วดูตำแหน่งลิงก์ได้เลย';
    const hooks = ['ตำแหน่งลิงก์ร้านอยู่ตรงไหน?', 'เปิดหน้าโปรไฟล์ร้าน'];
    const provider = createGeminiRealClipCaptionProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl: async () => jsonResponse({
        ...sampleCaption,
        caption,
        hooks,
        hashtags: [' #ShopLink ', 'shoplink', '##SHOPLINK', '#ลิงก์ร้าน', '#ลิงก์ร้าน',
          'หน้าร้าน', '#หน้าร้าน', 'Café', 'Cafe\u0301', '#bad tag', '#x1', '#x2'],
        seoKeywords: [' อัปเดต\tลิงก์ร้าน ', 'อัปเดต  ลิงก์ร้าน', 'Online shop',
          'online SHOP', 'Café', 'Cafe\u0301', '  เมนู ร้าน  ', 'โปรไฟล์ร้าน', 'overflow']
      })
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });
    expect(result.hashtags).toEqual(['#ShopLink', '#ลิงก์ร้าน', '#หน้าร้าน', '#Café', '#x1']);
    expect(result.seoKeywords).toEqual(['อัปเดต ลิงก์ร้าน', 'Online shop', 'Café', 'เมนู ร้าน', 'โปรไฟล์ร้าน']);
    expect(result.caption).toBe(caption);
    expect(result.hooks).toEqual(hooks);
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
      fallbackModels: ['gemini-secondary'],
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 2
    });

    const result = await provider.generate({
      request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
      mode: 'AUDIO_ONLY',
      audio
    });

    expect(result.model).toBe('gemini-secondary');
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
      fallbackModels: ['gemini-secondary'],
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

describe('createRealClipCaptionProviderFromConfig', () => {
  it('uses only the configured Gemini model before the route fallback', async () => {
    const requestedUrls: string[] = [];
    const provider = createRealClipCaptionProviderFromConfig({
      config: {
        captionProvider: 'gemini',
        geminiApiKey: 'gemini-key',
        geminiCaptionModel: 'gemini-2.5-flash-lite'
      },
      fetchImpl: async (url) => {
        requestedUrls.push(url);
        return { ok: false, status: 400, json: async () => ({}) };
      }
    });

    expect(provider).toBeDefined();
    await expect(
      provider!.generate({
        request: { videoS3Key: 'uploads/u/clip.mp4', selectedFrameKeys: [] },
        mode: 'AUDIO_ONLY',
        audio
      })
    ).rejects.toThrow('status 400');
    expect(requestedUrls).toEqual([
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=gemini-key'
    ]);
  });
});
