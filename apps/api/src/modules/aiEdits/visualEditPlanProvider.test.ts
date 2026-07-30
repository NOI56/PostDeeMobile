import { describe, expect, it, vi } from 'vitest';

import { createGeminiVisualEditPlanProvider } from './visualEditPlanProvider.js';

const response = (
  payload: unknown,
  options: {
    ok?: boolean;
    status?: number;
    headers?: Record<string, string>;
  } = {}
) => ({
  ok: options.ok ?? true,
  status: options.status,
  headers: {
    get: (name: string) =>
      Object.entries(options.headers ?? {}).find(
        ([key]) => key.toLowerCase() === name.toLowerCase()
      )?.[1] ?? null
  },
  json: async () => payload
});

describe('visual edit plan provider', () => {
  it('uploads the whole proxy, waits for Gemini, and plans with transcript',
      async () => {
    const uploadedBytes: number[] = [];
    const deletedFiles: string[] = [];
    const filesClient = {
      upload: vi.fn(async ({
        file,
        config
      }: {
        file: string | Blob;
        config?: { displayName?: string; mimeType?: string };
      }) => {
        expect(file).toBeInstanceOf(Blob);
        expect(config).toEqual({
          displayName: 'postdee-visual-proxy',
          mimeType: 'video/mp4'
        });
        uploadedBytes.push(
          ...new Uint8Array(await (file as Blob).arrayBuffer())
        );
        return {
          name: 'files/postdee-visual',
          uri: 'https://files.local/postdee-visual',
          mimeType: 'video/mp4',
          state: 'PROCESSING'
        };
      }),
      get: vi.fn(async () => ({
        name: 'files/postdee-visual',
        uri: 'https://files.local/postdee-visual',
        mimeType: 'video/mp4',
        state: 'ACTIVE'
      })),
      delete: vi.fn(async ({ name }: { name: string }) => {
        deletedFiles.push(name);
        return {};
      })
    };
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes(':generateContent')) {
        const body = JSON.parse(String(init.body)) as {
          generationConfig?: Record<string, unknown>;
          contents?: unknown[];
        };

        expect(url).toContain(
          '/models/gemini-3.5-flash-lite:generateContent'
        );
        expect(body.generationConfig).toEqual({
          responseMimeType: 'application/json'
        });
        expect(body.generationConfig).not.toHaveProperty('temperature');
        expect(String(init.body)).toContain('ราคา 99 บาท');
        expect(String(init.body)).toContain('fileUri');
        return response({
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: JSON.stringify({
                      cuts: [
                        { start: 0, end: 10 },
                        { start: 55, end: 100 }
                      ],
                      summary: 'เลือกภาพสินค้าและช่วงเสนอราคา'
                    })
                  }
                ]
              }
            }
          ]
        });
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-3.5-flash-lite',
      filesClient,
      fetchImpl,
      sleep: async () => undefined
    });

    const result = await provider.plan({
      durationSeconds: 100,
      targetDurationSeconds: 45,
      segments: [
        { text: 'ราคา 99 บาท กดตะกร้าได้เลย', start: 45, end: 55 }
      ],
      video: {
        data: new Uint8Array([1, 2, 3]),
        mimeType: 'video/mp4'
      }
    });

    expect(uploadedBytes).toEqual([1, 2, 3]);
    expect(result).toEqual({
      cuts: [
        { start: 0, end: 10 },
        { start: 55, end: 100 }
      ],
      summary: 'เลือกภาพสินค้าและช่วงเสนอราคา',
      model: 'gemini-3.5-flash-lite-visual'
    });
    expect(filesClient.upload).toHaveBeenCalledOnce();
    expect(filesClient.get).toHaveBeenCalledWith({
      name: 'files/postdee-visual'
    });
    expect(deletedFiles).toEqual(['files/postdee-visual']);
  });

  it.each([
    {
      label: 'an identical second JSON object',
      duplicatePlan: true
    },
    {
      label: 'trailing explanatory text',
      duplicatePlan: false
    }
  ])('uses one complete JSON plan when Gemini adds $label', async ({
    duplicatePlan
  }) => {
    const filesClient = {
      upload: vi.fn(async () => ({
        name: 'files/postdee-extra-content',
        uri: 'https://files.local/postdee-extra-content',
        mimeType: 'video/mp4',
        state: 'ACTIVE' as const
      })),
      get: vi.fn(),
      delete: vi.fn(async () => ({}))
    };
    const firstPlan = {
      cuts: [
        { start: 0, end: 10 },
        { start: 55, end: 100 }
      ],
      summary: 'ใช้แผน JSON ก้อนแรก'
    };
    const suffix = duplicatePlan
      ? `\n${JSON.stringify(firstPlan)}`
      : '\nI selected the strongest complete story window.';
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes(':generateContent')) {
        return response({
          candidates: [
            {
              content: {
                parts: [{ text: `${JSON.stringify(firstPlan)}${suffix}` }]
              }
            }
          ]
        });
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
      filesClient,
      fetchImpl,
      sleep: async () => undefined
    });

    const result = await provider.plan({
      durationSeconds: 100,
      targetDurationSeconds: 45,
      segments: [
        { text: 'ราคา 99 บาท กดตะกร้าได้เลย', start: 45, end: 55 }
      ],
      video: {
        data: new Uint8Array([1, 2, 3]),
        mimeType: 'video/mp4'
      }
    });

    expect(result).toEqual({
      cuts: [
        { start: 0, end: 10 },
        { start: 55, end: 100 }
      ],
      summary: 'ใช้แผน JSON ก้อนแรก',
      model: 'gemini-test-visual'
    });
    expect(filesClient.delete).toHaveBeenCalledWith({
      name: 'files/postdee-extra-content'
    });
  });

  it.each([
    {
      label: 'malformed first JSON when valid JSON follows it',
      content:
        '{"cuts":[}]\n' +
        '{"cuts":[{"start":0,"end":10}],"summary":"must not recover"}',
      expectedMessage: undefined
    },
    {
      label: 'an invalid first plan shape when valid JSON follows it',
      content:
        '{}\n' +
        '{"cuts":[{"start":0,"end":10}],"summary":"must not replace primary"}',
      expectedMessage: 'invalid plan shape'
    },
    {
      label: 'two conflicting JSON plans',
      content:
        '{"cuts":[{"start":0,"end":10}],"summary":"first"}\n' +
        '{"cuts":[{"start":10,"end":20}],"summary":"second"}',
      expectedMessage: 'conflicting plans'
    },
    {
      label: 'a conflicting plan after prose and a Markdown fence',
      content:
        '{"cuts":[{"start":0,"end":10}],"summary":"first"}\n' +
        'I reconsidered the visual sequence.\n```json\n' +
        '{"cuts":[{"start":10,"end":20}],"summary":"second"}\n```',
      expectedMessage: 'conflicting plans'
    }
  ])('rejects $label', async ({ content, expectedMessage }) => {
    const filesClient = {
      upload: vi.fn(async () => ({
        name: 'files/postdee-malformed-first',
        uri: 'https://files.local/postdee-malformed-first',
        mimeType: 'video/mp4',
        state: 'ACTIVE' as const
      })),
      get: vi.fn(),
      delete: vi.fn(async () => ({}))
    };
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes(':generateContent')) {
        return response({
          candidates: [
            {
              content: {
                parts: [{ text: content }]
              }
            }
          ]
        });
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
      filesClient,
      fetchImpl,
      sleep: async () => undefined
    });

    await expect(
      provider.plan({
        durationSeconds: 30,
        targetDurationSeconds: 20,
        segments: [],
        video: {
          data: new Uint8Array([1]),
          mimeType: 'video/mp4'
        }
      })
    ).rejects.toThrow(expectedMessage);
    expect(filesClient.delete).toHaveBeenCalledWith({
      name: 'files/postdee-malformed-first'
    });
  });

  it('rejects an unusable Gemini response so callers can fall back to audio',
      async () => {
    const filesClient = {
      upload: vi.fn(async () => ({
        name: 'files/postdee-empty',
        uri: 'https://files.local/postdee-empty',
        mimeType: 'video/mp4',
        state: 'ACTIVE'
      })),
      get: vi.fn(),
      delete: vi.fn(async () => ({}))
    };
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes(':generateContent')) {
        return response({ candidates: [] });
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
      filesClient,
      fetchImpl,
      sleep: async () => undefined
    });

    await expect(
      provider.plan({
        durationSeconds: 30,
        targetDurationSeconds: 15,
        segments: [],
        video: {
          data: new Uint8Array([1]),
          mimeType: 'video/mp4'
        }
      })
    ).rejects.toThrow('Visual edit plan provider returned no content');
    expect(filesClient.delete).toHaveBeenCalledWith({
      name: 'files/postdee-empty'
    });
  });

  it('keeps Gemini cut boundaries outside transcript cues', async () => {
    const filesClient = {
      upload: vi.fn(async () => ({
        name: 'files/postdee-boundary',
        uri: 'https://files.local/postdee-boundary',
        mimeType: 'video/mp4',
        state: 'ACTIVE'
      })),
      get: vi.fn(),
      delete: vi.fn(async () => ({}))
    };
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes(':generateContent')) {
        return response({
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: JSON.stringify({
                      cuts: [
                        { start: 0, end: 112.762 },
                        { start: 142.762, end: 150.649 }
                      ],
                      summary: 'live regression'
                    })
                  }
                ]
              }
            }
          ]
        });
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
      filesClient,
      fetchImpl,
      sleep: async () => undefined
    });

    const result = await provider.plan({
      durationSeconds: 150.649,
      targetDurationSeconds: 30,
      segments: [
        { text: 'opening cue', start: 112.081, end: 112.912 },
        { text: 'closing cue', start: 142.2, end: 143.1 }
      ],
      video: {
        data: new Uint8Array([1]),
        mimeType: 'video/mp4'
      }
    });

    expect(result.cuts).toEqual([
      { start: 0, end: 113.1 },
      { start: 143.1, end: 150.649 }
    ]);
  });
});
