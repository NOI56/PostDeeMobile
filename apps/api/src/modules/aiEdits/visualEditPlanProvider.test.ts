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

    expect(uploadedBytes).toEqual([1, 2, 3]);
    expect(result).toEqual({
      cuts: [
        { start: 0, end: 10 },
        { start: 55, end: 100 }
      ],
      summary: 'เลือกภาพสินค้าและช่วงเสนอราคา',
      model: 'gemini-test-visual'
    });
    expect(filesClient.upload).toHaveBeenCalledOnce();
    expect(filesClient.get).toHaveBeenCalledWith({
      name: 'files/postdee-visual'
    });
    expect(deletedFiles).toEqual(['files/postdee-visual']);
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
});
