import { describe, expect, it } from 'vitest';

import { readUploadMetadata } from './uploadService.js';

const maxSizeBytes = 200 * 1024 * 1024;

describe('readUploadMetadata', () => {
  it('accepts a bounded M4A upload only for AI edit audio', () => {
    expect(
      readUploadMetadata(
        {
          purpose: 'ai-edit-audio',
          fileName: 'clip.m4a',
          contentType: 'audio/mp4',
          sizeBytes: 1024
        },
        { maxSizeBytes }
      )
    ).toEqual({
      ok: true,
      metadata: {
        fileName: 'clip.m4a',
        contentType: 'audio/mp4',
        sizeBytes: 1024,
        width: undefined,
        height: undefined
      }
    });
  });

  it.each([
    {
      name: 'has no AI edit purpose',
      body: { fileName: 'clip.m4a', contentType: 'audio/mp4', sizeBytes: 1024 }
    },
    {
      name: 'uses a non-M4A extension',
      body: {
        purpose: 'ai-edit-audio',
        fileName: 'clip.mp3',
        contentType: 'audio/mp4',
        sizeBytes: 1024
      }
    },
    {
      name: 'uses a non-MP4 audio MIME type',
      body: {
        purpose: 'ai-edit-audio',
        fileName: 'clip.m4a',
        contentType: 'audio/mpeg',
        sizeBytes: 1024
      }
    },
    {
      name: 'includes video dimensions',
      body: {
        purpose: 'ai-edit-audio',
        fileName: 'clip.m4a',
        contentType: 'audio/mp4',
        sizeBytes: 1024,
        width: 1080,
        height: 1920
      }
    },
    {
      name: 'is larger than 25 MiB',
      body: {
        purpose: 'ai-edit-audio',
        fileName: 'clip.m4a',
        contentType: 'audio/mp4',
        sizeBytes: 25 * 1024 * 1024 + 1
      }
    }
  ])('rejects audio that $name', ({ body }) => {
    expect(readUploadMetadata(body, { maxSizeBytes })).toMatchObject({ ok: false });
  });

  it.each([
    { fileName: 'clip.mp4', contentType: 'video/mp4' },
    { fileName: 'frame.jpg', contentType: 'image/jpeg' }
  ])('keeps accepting existing $contentType uploads', ({ fileName, contentType }) => {
    expect(
      readUploadMetadata(
        {
          fileName,
          contentType,
          sizeBytes: 1024
        },
        { maxSizeBytes }
      )
    ).toMatchObject({ ok: true });
  });
});
