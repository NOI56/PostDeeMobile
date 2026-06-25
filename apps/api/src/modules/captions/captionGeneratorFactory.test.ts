import { describe, expect, it, vi } from 'vitest';

import {
  thaiAffiliateCaptionSystemPrompt,
  createCaptionGeneratorFromConfig,
  createGeminiCaptionGenerator
} from './captionGeneratorFactory.js';

const geminiOk = {
  ok: true as const,
  json: async () => ({
    candidates: [
      {
        content: {
          parts: [
            {
              text:
                'ขายดีจนต้องบอกต่อ 🔥\n#ของดีบอกต่อ #ช้อปออนไลน์ #โปรดี #รีวิวจริง #สายช้อป'
            }
          ]
        }
      }
    ]
  })
};

const baseConfig = {
  captionProvider: 'mock' as const,
  openAiApiKey: undefined,
  geminiApiKey: undefined,
  openAiCaptionModel: 'gpt-4o-mini',
  geminiCaptionModel: 'gemini-2.5-flash-lite'
};

describe('createCaptionGeneratorFromConfig', () => {
  it('uses the mock local caption generator by default', async () => {
    const generator = createCaptionGeneratorFromConfig({
      config: baseConfig
    });

    const caption = await generator.generate(['skincare']);

    expect(caption).toMatchObject({
      model: 'local-template',
      affiliateLinkPlaceholder: expect.any(String)
    });
    expect(caption.caption).toContain('skincare');
    expect(caption.hashtags).toHaveLength(5);
  });

  it('requires an OpenAI API key when OpenAI captions are configured', () => {
    expect(() =>
      createCaptionGeneratorFromConfig({
        config: {
          captionProvider: 'openai',
          openAiApiKey: undefined,
          openAiCaptionModel: 'gpt-4o-mini'
        }
      })
    ).toThrow('OPENAI_API_KEY is required when CAPTION_PROVIDER is openai');
  });

  it('uses OpenAI captions when configured', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: true,
      json: async () => ({
        choices: [
          {
            message: {
              content:
                'แคปชั่นขายดี 🔥\n#ของดีบอกต่อ #ช้อปออนไลน์ #โปรดี #รีวิวจริง #สายช้อป\n\n[ใส่ลิงก์ Affiliate ที่นี่]'
            }
          }
        ]
      })
    }));
    const generator = createCaptionGeneratorFromConfig({
      config: {
        captionProvider: 'openai',
        openAiApiKey: 'openai-key',
        openAiCaptionModel: 'gpt-4o-mini'
      },
      fetchImpl
    });

    const caption = await generator.generate(['skincare', 'sale']);

    expect(caption).toMatchObject({
      model: 'gpt-4o-mini',
      caption:
        'แคปชั่นขายดี 🔥\n#ของดีบอกต่อ #ช้อปออนไลน์ #โปรดี #รีวิวจริง #สายช้อป\n\n[ใส่ลิงก์ Affiliate ที่นี่]'
    });
    expect(caption.hashtags).toEqual([
      '#ของดีบอกต่อ',
      '#ช้อปออนไลน์',
      '#โปรดี',
      '#รีวิวจริง',
      '#สายช้อป'
    ]);
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.openai.com/v1/chat/completions',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer openai-key'
        }),
        body: expect.any(String)
      })
    );

    const body = JSON.parse(fetchImpl.mock.calls[0]?.[1]?.body as string);
    expect(body).toMatchObject({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: thaiAffiliateCaptionSystemPrompt
        },
        {
          role: 'user',
          content: 'Keywords: skincare, sale'
        }
      ]
    });
  });

  it('requires a Gemini API key when Gemini captions are configured', () => {
    expect(() =>
      createCaptionGeneratorFromConfig({
        config: {
          captionProvider: 'gemini',
          openAiApiKey: undefined,
          geminiApiKey: undefined,
          openAiCaptionModel: 'gpt-4o-mini',
          geminiCaptionModel: 'gemini-2.5-flash-lite'
        }
      })
    ).toThrow('GEMINI_API_KEY is required when CAPTION_PROVIDER is gemini');
  });

  it('uses Gemini captions when configured', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: true,
      json: async () => ({
        candidates: [
          {
            content: {
              parts: [
                {
                  text:
                    'ขายดีจนต้องบอกต่อ 🔥\n#ของดีบอกต่อ #ช้อปออนไลน์ #โปรดี #รีวิวจริง #สายช้อป\n\n[ใส่ลิงก์ Affiliate ที่นี่]'
                }
              ]
            }
          }
        ]
      })
    }));
    const generator = createCaptionGeneratorFromConfig({
      config: {
        captionProvider: 'gemini',
        openAiApiKey: undefined,
        geminiApiKey: 'gemini-key',
        openAiCaptionModel: 'gpt-4o-mini',
        geminiCaptionModel: 'gemini-2.5-flash-lite'
      },
      fetchImpl
    });

    const caption = await generator.generate(['skincare', 'sale']);

    expect(caption).toMatchObject({
      model: 'gemini-2.5-flash-lite',
      caption:
        'ขายดีจนต้องบอกต่อ 🔥\n#ของดีบอกต่อ #ช้อปออนไลน์ #โปรดี #รีวิวจริง #สายช้อป\n\n[ใส่ลิงก์ Affiliate ที่นี่]'
    });
    expect(caption.hashtags).toEqual([
      '#ของดีบอกต่อ',
      '#ช้อปออนไลน์',
      '#โปรดี',
      '#รีวิวจริง',
      '#สายช้อป'
    ]);
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=gemini-key',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'Content-Type': 'application/json'
        }),
        body: expect.any(String)
      })
    );

    const body = JSON.parse(fetchImpl.mock.calls[0]?.[1]?.body as string);
    expect(body).toMatchObject({
      systemInstruction: {
        parts: [
          {
            text: thaiAffiliateCaptionSystemPrompt
          }
        ]
      },
      contents: [
        {
          role: 'user',
          parts: [
            {
              text: 'Keywords: skincare, sale'
            }
          ]
        }
      ],
      generationConfig: {
        temperature: 0.8
      }
    });
  });

  it('retries Gemini on a transient 503 then succeeds', async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async () => {
      calls += 1;
      if (calls === 1) {
        return { ok: false, status: 503, json: async () => ({}) };
      }
      return geminiOk;
    });
    const generator = createGeminiCaptionGenerator({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    const caption = await generator.generate(['skincare']);

    expect(caption.model).toBe('gemini-2.5-flash-lite');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('does not retry Gemini on a client error', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: false,
      status: 400,
      json: async () => ({})
    }));
    const generator = createGeminiCaptionGenerator({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    await expect(generator.generate(['skincare'])).rejects.toThrow(
      'Gemini caption request failed with status 400'
    );
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('gives up after the retry budget when Gemini stays unavailable', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: false,
      status: 503,
      json: async () => ({})
    }));
    const generator = createGeminiCaptionGenerator({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    await expect(generator.generate(['skincare'])).rejects.toThrow('status 503');
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  it('falls back to a secondary Gemini model when the primary stays overloaded', async () => {
    const fetchImpl = vi.fn(async (url: string) => {
      if (url.includes('gemini-2.5-flash-lite')) {
        return { ok: false, status: 503, json: async () => ({}) };
      }
      return geminiOk;
    });
    const generator = createGeminiCaptionGenerator({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fallbackModels: ['gemini-2.0-flash'],
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 2
    });

    const caption = await generator.generate(['skincare']);

    expect(caption.model).toBe('gemini-2.0-flash');
    // primary tried twice (maxAttempts), then the fallback once.
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  it('does not try fallback models when the Gemini key is rejected', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: false,
      status: 401,
      json: async () => ({})
    }));
    const generator = createGeminiCaptionGenerator({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fallbackModels: ['gemini-2.0-flash'],
      fetchImpl,
      sleep: async () => {},
      maxAttempts: 3
    });

    await expect(generator.generate(['skincare'])).rejects.toThrow('status 401');
    // 401 is not retried and the fallback model is skipped.
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});
