import { describe, expect, it, vi } from 'vitest';

import { createFetchMediaFromVideoStorage } from '../../app.js';
import { aiCaptionFrameMaxBytes } from './mediaDownload.js';
import type { VideoStorage } from './videoStorage.js';

const signedStorage = (): VideoStorage => ({
  createUpload: vi.fn(),
  createDownloadAccess: async (videoS3Key) => ({
    videoS3Key,
    storageProvider: 'r2',
    accessType: 'signed-url',
    downloadUrl: `https://storage.test/${videoS3Key}`,
    downloadMethod: 'GET'
  }),
  deleteVideo: vi.fn(),
  deleteAllVideosForOwner: vi.fn()
});

const frameOptions = { kind: 'frame', maxBytes: aiCaptionFrameMaxBytes } as const;

// A key ending in .jpg only proves the name; the stored object itself must be a
// small image before it is buffered for Gemini.
describe('createFetchMediaFromVideoStorage frame limits', () => {
  it('refuses a frame whose stored object is not an image', async () => {
    const fetchImpl = vi.fn(async () => new Response(new Uint8Array(16), { headers: { 'content-type': 'video/mp4' } }));
    const fetchMedia = createFetchMediaFromVideoStorage(signedStorage(), fetchImpl);

    await expect(fetchMedia('uploads/u/frame/frame_1.jpg', frameOptions)).rejects.toMatchObject({
      statusCode: 415,
      code: 'AI_CAPTION_FRAME_INVALID'
    });
  });

  it('refuses a frame larger than the frame limit', async () => {
    const fetchImpl = vi.fn(
      async () => new Response(new Uint8Array(aiCaptionFrameMaxBytes + 1), { headers: { 'content-type': 'image/jpeg' } })
    );
    const fetchMedia = createFetchMediaFromVideoStorage(signedStorage(), fetchImpl);

    await expect(fetchMedia('uploads/u/frame/frame_1.jpg', frameOptions)).rejects.toMatchObject({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE'
    });
  });

  it('returns an image frame within the limit with its mime type', async () => {
    const fetchImpl = vi.fn(async () => new Response(new Uint8Array([1, 2, 3]), { headers: { 'content-type': 'image/jpeg' } }));
    const fetchMedia = createFetchMediaFromVideoStorage(signedStorage(), fetchImpl);

    const media = await fetchMedia('uploads/u/frame/frame_1.jpg', frameOptions);

    expect(media.mimeType).toBe('image/jpeg');
    expect([...media.data]).toEqual([1, 2, 3]);
  });

  it('keeps clip downloads on the clip limit without an image check', async () => {
    const fetchImpl = vi.fn(
      async () => new Response(new Uint8Array(aiCaptionFrameMaxBytes + 1), { headers: { 'content-type': 'video/mp4' } })
    );
    const fetchMedia = createFetchMediaFromVideoStorage(signedStorage(), fetchImpl);

    const media = await fetchMedia('uploads/u/clip/clip.mp4');

    expect(media.mimeType).toBe('video/mp4');
    expect(media.data.byteLength).toBe(aiCaptionFrameMaxBytes + 1);
  });
});
