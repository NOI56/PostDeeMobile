import { describe, expect, it } from 'vitest';

import { readUploadMetadata } from './uploadService.js';

const maxSizeBytes = 200 * 1024 * 1024;

describe('readUploadMetadata', () => {
  const aiCaptionVideo = {
    purpose: 'ai-caption-video',
    fileName: 'caption-clip.mp4',
    contentType: 'video/mp4',
    sizeBytes: 1024
  };

  it.each([
    { ratio: '9:20', width: 1080, height: 2400 },
    { ratio: 'landscape', width: 1920, height: 1080 },
    { ratio: 'square', width: 1080, height: 1080 },
    { ratio: '9:16', width: 1080, height: 1920 }
  ])('preserves actual $ratio dimensions for an AI caption video', ({ width, height }) => {
    expect(
      readUploadMetadata({ ...aiCaptionVideo, width, height }, { maxSizeBytes })
    ).toEqual({
      ok: true,
      metadata: {
        fileName: aiCaptionVideo.fileName,
        contentType: aiCaptionVideo.contentType,
        sizeBytes: aiCaptionVideo.sizeBytes,
        width,
        height
      }
    });
  });

  it('accepts an AI caption video when both dimensions are unavailable', () => {
    expect(readUploadMetadata(aiCaptionVideo, { maxSizeBytes })).toEqual({
      ok: true,
      metadata: {
        fileName: aiCaptionVideo.fileName,
        contentType: aiCaptionVideo.contentType,
        sizeBytes: aiCaptionVideo.sizeBytes,
        width: undefined,
        height: undefined
      }
    });
  });

  it('accepts an AI caption video at the configured size limit', () => {
    expect(
      readUploadMetadata({ ...aiCaptionVideo, sizeBytes: maxSizeBytes }, { maxSizeBytes })
    ).toMatchObject({ ok: true, metadata: { sizeBytes: maxSizeBytes } });
  });

  it.each([
    { name: 'missing MP4 extension', fields: { fileName: 'caption-clip' } },
    { name: 'non-MP4 extension', fields: { fileName: 'caption-clip.mov' } },
    { name: 'non-MP4 video MIME type', fields: { contentType: 'video/quicktime' } },
    { name: 'image MIME type', fields: { contentType: 'image/jpeg' } },
    { name: 'audio MIME type', fields: { contentType: 'audio/mp4' } },
    { name: 'zero size', fields: { sizeBytes: 0 } },
    { name: 'negative size', fields: { sizeBytes: -1 } },
    { name: 'non-finite size', fields: { sizeBytes: Number.POSITIVE_INFINITY } },
    { name: 'oversized file', fields: { sizeBytes: maxSizeBytes + 1 } },
    { name: 'width alone', fields: { width: 1080 } },
    { name: 'height alone', fields: { height: 2400 } },
    { name: 'zero dimension', fields: { width: 0, height: 2400 } },
    { name: 'negative dimension', fields: { width: 1080, height: -2400 } },
    { name: 'fractional dimension', fields: { width: 1080.5, height: 2400 } },
    { name: 'non-finite dimension', fields: { width: 1080, height: Number.POSITIVE_INFINITY } },
    { name: 'NaN dimension', fields: { width: Number.NaN, height: 2400 } },
    { name: 'string dimension', fields: { width: '1080', height: 2400 } },
    { name: 'null dimensions', fields: { width: null, height: null } }
  ])('rejects an AI caption video with $name', ({ fields }) => {
    expect(
      readUploadMetadata({ ...aiCaptionVideo, ...fields }, { maxSizeBytes })
    ).toMatchObject({ ok: false, code: 'UPLOAD_AI_CAPTION_VIDEO_INVALID' });
  });

  it('keeps rejecting 9:20 dimensions for a generic post video upload', () => {
    expect(
      readUploadMetadata(
        {
          fileName: aiCaptionVideo.fileName,
          contentType: aiCaptionVideo.contentType,
          sizeBytes: aiCaptionVideo.sizeBytes,
          width: 1080,
          height: 2400
        },
        { maxSizeBytes }
      )
    ).toEqual({ ok: false, message: 'Use a vertical 9:16 video, such as 1080x1920.' });
  });

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

  it('accepts a bounded whole-clip MP4 visual proxy', () => {
    expect(
      readUploadMetadata(
        {
          purpose: 'ai-edit-visual-proxy',
          fileName: 'whole-clip-proxy.mp4',
          contentType: 'video/mp4',
          sizeBytes: 1024
        },
        { maxSizeBytes }
      )
    ).toEqual({
      ok: true,
      metadata: {
        fileName: 'whole-clip-proxy.mp4',
        contentType: 'video/mp4',
        sizeBytes: 1024,
        width: undefined,
        height: undefined
      }
    });
  });

  it.each([
    {
      name: 'uses a non-MP4 extension',
      body: {
        purpose: 'ai-edit-visual-proxy',
        fileName: 'proxy.mov',
        contentType: 'video/mp4',
        sizeBytes: 1024
      }
    },
    {
      name: 'uses a non-MP4 MIME type',
      body: {
        purpose: 'ai-edit-visual-proxy',
        fileName: 'proxy.mp4',
        contentType: 'video/quicktime',
        sizeBytes: 1024
      }
    },
    {
      name: 'includes client dimensions',
      body: {
        purpose: 'ai-edit-visual-proxy',
        fileName: 'proxy.mp4',
        contentType: 'video/mp4',
        sizeBytes: 1024,
        width: 360,
        height: 640
      }
    },
    {
      name: 'is larger than 50 MiB',
      body: {
        purpose: 'ai-edit-visual-proxy',
        fileName: 'proxy.mp4',
        contentType: 'video/mp4',
        sizeBytes: 50 * 1024 * 1024 + 1
      }
    }
  ])('rejects a visual proxy that $name', ({ body }) => {
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
