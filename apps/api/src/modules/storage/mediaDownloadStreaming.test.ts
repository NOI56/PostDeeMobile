import { describe, expect, it, vi } from 'vitest';

import { MediaDownloadError, readAiMediaResponseBytes } from './mediaDownload.js';

const createChunkedResponse = (chunkCount: number, chunkBytes: number, headers: Record<string, string> = {}) => {
  let pulled = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (pulled >= chunkCount) {
        controller.close();
        return;
      }
      pulled += 1;
      controller.enqueue(new Uint8Array(chunkBytes));
    }
  });
  return { response: new Response(body, { headers }), pulledChunks: () => pulled };
};

// A missing or understated Content-Length must not let a response be buffered
// in full before the size check runs.
describe('readAiMediaResponseBytes streaming limit', () => {
  it('cancels an oversized declared body without reading it', async () => {
    const cancel = vi.fn();
    const pull = vi.fn();
    const response = new Response(new ReadableStream<Uint8Array>({ cancel, pull }), {
      headers: { 'content-length': '5000' }
    });
    const getReader = vi.spyOn(response.body!, 'getReader');

    await expect(readAiMediaResponseBytes(response, 4096)).rejects.toMatchObject({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE',
      declaredSizeBytes: 5000
    });
    expect(cancel).toHaveBeenCalledOnce();
    expect(getReader).not.toHaveBeenCalled();
  });

  it('keeps the size error when cancelling an oversized body fails', async () => {
    const response = new Response(new ReadableStream<Uint8Array>({
      cancel: () => Promise.reject(new Error('connection already closed'))
    }), { headers: { 'content-length': '5000' } });

    await expect(readAiMediaResponseBytes(response, 4096)).rejects.toMatchObject({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE'
    });
  });

  it('stops reading a body without Content-Length as soon as it passes the limit', async () => {
    const { response, pulledChunks } = createChunkedResponse(1000, 1024);

    await expect(readAiMediaResponseBytes(response, 4 * 1024)).rejects.toMatchObject({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE'
    });
    expect(pulledChunks()).toBeLessThan(10);
  });

  it('rejects a body larger than its understated Content-Length limit check', async () => {
    const { response } = createChunkedResponse(8, 1024, { 'content-length': '1024' });

    await expect(readAiMediaResponseBytes(response, 4 * 1024)).rejects.toBeInstanceOf(MediaDownloadError);
  });

  it('returns the exact bytes of a body within the limit', async () => {
    const { response } = createChunkedResponse(3, 1024);

    const bytes = await readAiMediaResponseBytes(response, 4 * 1024);

    expect(bytes.byteLength).toBe(3 * 1024);
  });
});
