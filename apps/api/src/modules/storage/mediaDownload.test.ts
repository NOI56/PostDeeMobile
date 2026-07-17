import { describe, expect, it } from 'vitest';

import {
  MediaDownloadError,
  aiEditAudioDownloadMaxBytes,
  readAiMediaResponseBytes
} from './mediaDownload.js';

const makeResponse = ({
  contentLength,
  actualBytes
}: {
  contentLength?: number;
  actualBytes: number;
}) => ({
  headers: new Headers(
    contentLength === undefined ? {} : { 'content-length': String(contentLength) }
  ),
  arrayBuffer: async () => new Uint8Array(actualBytes).buffer
});

describe('AI media download limits', () => {
  it('defines the AI edit audio ceiling as 25 MiB', () => {
    expect(aiEditAudioDownloadMaxBytes).toBe(25 * 1024 * 1024);
  });
  it('rejects declared AI edit audio larger than 25 MiB before reading the body', async () => {
    const response = makeResponse({
      contentLength: 25 * 1024 * 1024 + 1,
      actualBytes: 1
    });

    await expect(
      readAiMediaResponseBytes(response, 25 * 1024 * 1024)
    ).rejects.toMatchObject<Partial<MediaDownloadError>>({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE'
    });
  });

  it('rejects AI edit audio whose actual body exceeds 25 MiB', async () => {
    const response = makeResponse({ actualBytes: 25 * 1024 * 1024 + 1 });

    await expect(
      readAiMediaResponseBytes(response, 25 * 1024 * 1024)
    ).rejects.toMatchObject<Partial<MediaDownloadError>>({
      statusCode: 413,
      code: 'AI_MEDIA_TOO_LARGE'
    });
  });
});
