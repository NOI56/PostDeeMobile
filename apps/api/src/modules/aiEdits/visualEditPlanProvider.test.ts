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
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes('/upload/v1beta/files')) {
        expect(JSON.parse(String(init.body))).toEqual({
          file: { display_name: 'postdee-visual-proxy' }
        });
        return response(
          {},
          { headers: { 'x-goog-upload-url': 'https://upload.local/session' } }
        );
      }
      if (url === 'https://upload.local/session') {
        uploadedBytes.push(...new Uint8Array(init.body as ArrayBuffer));
        return response({
          file: {
            name: 'files/postdee-visual',
            uri: 'https://files.local/postdee-visual',
            mimeType: 'video/mp4',
            state: 'PROCESSING'
          }
        });
      }
      if (url.includes('/v1beta/files/postdee-visual') && init.method === 'GET') {
        return response({
          name: 'files/postdee-visual',
          uri: 'https://files.local/postdee-visual',
          mimeType: 'video/mp4',
          state: 'ACTIVE'
        });
      }
      if (url.includes(':generateContent')) {
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
      if (url.includes('/v1beta/files/postdee-visual') && init.method === 'DELETE') {
        return response({});
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
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
      model: 'gemini-test-visual'
    });
    expect(
      fetchImpl.mock.calls.some(
        ([url, init]) =>
          String(url).includes('/v1beta/files/postdee-visual') &&
          init?.method === 'DELETE'
      ),
      true
    );
  });

  it('rejects an unusable Gemini response so callers can fall back to audio',
      async () => {
    const fetchImpl = vi.fn(async (url: string, init: RequestInit = {}) => {
      if (url.includes('/upload/v1beta/files')) {
        return response(
          {},
          { headers: { 'x-goog-upload-url': 'https://upload.local/session' } }
        );
      }
      if (url === 'https://upload.local/session') {
        return response({
          file: {
            name: 'files/postdee-empty',
            uri: 'https://files.local/postdee-empty',
            mimeType: 'video/mp4',
            state: 'ACTIVE'
          }
        });
      }
      if (url.includes(':generateContent')) {
        return response({ candidates: [] });
      }
      if (url.includes('/v1beta/files/postdee-empty') && init.method === 'DELETE') {
        return response({});
      }
      throw new Error(`Unexpected request: ${init.method ?? 'GET'} ${url}`);
    });
    const provider = createGeminiVisualEditPlanProvider({
      apiKey: 'test-key',
      model: 'gemini-test',
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
  });
});
