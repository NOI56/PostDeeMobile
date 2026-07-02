import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

describe('caption routes', () => {
  const app = createApp();

  it('generates a Thai affiliate caption from one or two keywords', async () => {
    const response = await request(app)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ keywords: ['กันแดด', 'ผิวใส'] })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'local-template',
      affiliateLinkPlaceholder: '[ใส่ลิงก์ Affiliate ที่นี่]'
    });
    expect(response.body.caption).toContain('กันแดด');
    expect(response.body.caption).toContain('ผิวใส');
    expect(response.body.caption).toContain('[ใส่ลิงก์ Affiliate ที่นี่]');
    expect(response.body.hashtags).toHaveLength(5);
  });

  it('falls back to a local caption when the AI generator fails', async () => {
    const generate = vi.fn(async () => {
      throw new Error('Gemini caption request failed with status 503');
    });
    const appWithFailingGenerator = createApp({
      captionGenerator: { generate }
    });

    const response = await request(appWithFailingGenerator)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ keywords: ['กันแดด', 'ผิวใส'] })
      .expect(200);

    expect(generate).toHaveBeenCalledWith(['กันแดด', 'ผิวใส']);
    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'local-template',
      affiliateLinkPlaceholder: '[ใส่ลิงก์ Affiliate ที่นี่]'
    });
    expect(response.body.caption).toContain('กันแดด');
    expect(response.body.caption).toContain('ผิวใส');
    expect(response.body.hashtags).toHaveLength(5);
  });

  it('requires a paid plan to generate captions', async () => {
    const response = await request(app)
      .post('/captions/generate')
      .send({ keywords: ['skincare'] })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PRO_REQUIRED',
      message: 'AI Caption Assistant requires a paid plan'
    });
  });

  it('allows Starter users to generate captions', async () => {
    const response = await request(app)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ keywords: ['skincare'] })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'local-template'
    });
  });

  it('meters keyword captions against the monthly AI caption quota', async () => {
    const userId = 'seller-keyword-caption-quota';
    const generate = vi.fn(async () => ({
      model: 'local-template' as const,
      caption: 'Generated caption',
      hashtags: ['#one'],
      affiliateLinkPlaceholder: '[link]'
    }));
    const usageStore = {
      countForMonth: vi.fn(async () => 0),
      record: vi.fn(async () => ({
        userId,
        monthKey: '2026-06',
        createdAt: '2026-06-25T00:00:00.000Z'
      })),
      reserve: vi.fn(async () => ({
        ok: true as const,
        usedThisMonth: 1,
        record: {
          userId,
          monthKey: '2026-06',
          createdAt: '2026-06-25T00:00:00.000Z'
        }
      }))
    };
    const appWithQuota = createApp({
      captionGenerator: { generate },
      realClipCaptionUsageStore: usageStore
    });

    const response = await request(appWithQuota)
      .post('/captions/generate')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ keywords: ['skincare'] })
      .expect(200);

    expect(generate).toHaveBeenCalledWith(['skincare']);
    expect(usageStore.reserve).toHaveBeenCalledWith({
      userId,
      monthKey: expect.any(String),
      limit: 50
    });
    expect(response.body.quota).toEqual({
      limit: 50,
      usedThisMonth: 1,
      remainingThisMonth: 49
    });
  });

  it('rejects keyword captions when the monthly AI caption quota is exhausted', async () => {
    const userId = 'seller-keyword-caption-over-quota';
    const generate = vi.fn(async () => ({
      model: 'local-template' as const,
      caption: 'Generated caption',
      hashtags: ['#one'],
      affiliateLinkPlaceholder: '[link]'
    }));
    const usageStore = {
      countForMonth: vi.fn(async () => 50),
      record: vi.fn(async () => ({
        userId,
        monthKey: '2026-06',
        createdAt: '2026-06-25T00:00:00.000Z'
      })),
      reserve: vi.fn(async () => ({
        ok: false as const,
        usedThisMonth: 50
      }))
    };
    const appWithQuota = createApp({
      captionGenerator: { generate },
      realClipCaptionUsageStore: usageStore
    });

    const response = await request(appWithQuota)
      .post('/captions/generate')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ keywords: ['skincare'] })
      .expect(429);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_CAPTION_QUOTA_REACHED',
      quota: {
        limit: 50,
        usedThisMonth: 50,
        remainingThisMonth: 0
      }
    });
    expect(generate).not.toHaveBeenCalled();
    expect(usageStore.record).not.toHaveBeenCalled();
  });

  it('rejects requests without one or two keywords', async () => {
    const response = await request(app)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ keywords: [] })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'keywords must contain 1 or 2 non-empty values'
    });
  });

  it('rejects keyword captions with a keyword longer than 80 characters', async () => {
    const generate = vi.fn(async () => ({
      model: 'local-template' as const,
      caption: 'Generated caption',
      hashtags: ['#one'],
      affiliateLinkPlaceholder: '[link]'
    }));
    const appWithGenerator = createApp({ captionGenerator: { generate } });

    const response = await request(appWithGenerator)
      .post('/captions/generate')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ keywords: ['x'.repeat(81)] })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'keywords must be 80 characters or fewer'
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it('generates a real-clip caption for Starter from audio only', async () => {
    const userId = 'seller-starter-real-clip';
    const videoS3Key = ownedUploadKey(userId, 'starter-real-clip.mp4');

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        videoS3Key,
        guidance: 'promote a skincare launch'
      })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'local-real-clip-template',
      source: {
        videoS3Key,
        mode: 'AUDIO_ONLY',
        selectedFrameCount: 0
      },
      quota: {
        limit: 50,
        usedThisMonth: 1,
        remainingThisMonth: 49
      }
    });
    expect(response.body.caption).toContain('starter-real-clip.mp4');
    expect(response.body.captionOptions).toHaveLength(3);
    expect(response.body.hooks).toHaveLength(3);
    expect(response.body.seoKeywords).toHaveLength(5);
    expect(response.body.hashtags).toHaveLength(5);
    expect(response.body.searchTitle).toContain('starter-real-clip.mp4');
  });

  it('generates a real-clip caption for Pro with selected visual frames', async () => {
    const userId = 'seller-pro-real-clip';
    const videoS3Key = ownedUploadKey(userId, 'pro-real-clip.mp4');

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key,
        selectedFrameKeys: [
          ownedUploadKey(userId, 'pro-1.jpg', 'frame-1'),
          ownedUploadKey(userId, 'pro-2.jpg', 'frame-2')
        ]
      })
      .expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'local-real-clip-template',
      source: {
        videoS3Key,
        mode: 'AUDIO_WITH_FRAMES',
        selectedFrameCount: 2
      },
      quota: {
        limit: 120,
        usedThisMonth: 1,
        remainingThisMonth: 119
      }
    });
  });

  const fakeRealClipCaption = (input: {
    request: { videoS3Key: string };
    mode: string;
    frames?: unknown[];
  }) => ({
    model: 'gemini-2.5-flash-lite',
    caption: 'AI ฟังคลิปแล้วเขียนแคปชั่นให้',
    captionOptions: ['ก', 'ข', 'ค'],
    hooks: ['h1', 'h2', 'h3'],
    hashtags: ['#a', '#b', '#c', '#d', '#e'],
    seoKeywords: ['k1', 'k2', 'k3', 'k4', 'k5'],
    searchTitle: 'หัวข้อค้นหา',
    affiliateLinkPlaceholder: '[ใส่ลิงก์ Affiliate ที่นี่]',
    context: {
      selectedCaptionLanguage: 'Thai',
      selectedTargetMarket: 'Thailand',
      selectedTone: 'auto',
      detectedSpokenLanguage: 'th',
      suggestedCaptionLanguage: 'Thai',
      suggestedTargetMarket: 'Thailand'
    },
    source: {
      videoS3Key: input.request.videoS3Key,
      mode: input.mode,
      selectedFrameCount: input.frames?.length ?? 0
    }
  });

  it('uses the Gemini real-clip provider to listen and write the caption', async () => {
    const userId = 'seller-gemini';
    const videoS3Key = ownedUploadKey(userId, 'gemini-clip.mp4');
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const fetchClipMedia = vi.fn(async () => ({
      data: new Uint8Array([1, 2, 3]),
      mimeType: 'video/mp4'
    }));
    const appWithProvider = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    const response = await request(appWithProvider)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key })
      .expect(200);

    expect(generate).toHaveBeenCalledTimes(1);
    expect(fetchClipMedia).toHaveBeenCalledWith(videoS3Key);
    expect(response.body).toMatchObject({
      status: 'ok',
      model: 'gemini-2.5-flash-lite',
      caption: 'AI ฟังคลิปแล้วเขียนแคปชั่นให้',
      quota: { limit: 50, usedThisMonth: 1, remainingThisMonth: 49 }
    });
  });

  it('rejects real-clip captions for a clip owned by another user', async () => {
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const fetchClipMedia = vi.fn(async () => ({
      data: new Uint8Array([1, 2, 3]),
      mimeType: 'video/mp4'
    }));
    const appWithProvider = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    const response = await request(appWithProvider)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'seller-gemini')
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: ownedUploadKey('other-seller', 'gemini-clip.mp4') })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      code: 'MEDIA_KEY_FORBIDDEN',
      message: 'Selected media does not belong to the authenticated user'
    });
    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(generate).not.toHaveBeenCalled();
  });

  it('sends selected frames to the provider for Pro audio-with-frames', async () => {
    const userId = 'seller-pro-frames';
    const videoS3Key = ownedUploadKey(userId, 'pro.mp4');
    const frameKeys = [
      ownedUploadKey(userId, 'a.jpg', 'frame-a'),
      ownedUploadKey(userId, 'b.jpg', 'frame-b')
    ];
    let receivedFrameCount = 0;
    const generate = vi.fn(async (input) => {
      receivedFrameCount = input.frames?.length ?? 0;
      return fakeRealClipCaption(input);
    });
    const fetchClipMedia = vi.fn(async (key: string) => ({
      data: new Uint8Array([1]),
      mimeType: key.endsWith('.jpg') ? 'image/jpeg' : 'video/mp4'
    }));
    const appPro = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    await request(appPro)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key,
        selectedFrameKeys: frameKeys
      })
      .expect(200);

    // audio + 2 frames fetched and forwarded.
    expect(fetchClipMedia).toHaveBeenCalledTimes(3);
    expect(receivedFrameCount).toBe(2);
  });

  it('cleans up AI caption clip and frames when requested', async () => {
    const userId = 'seller-ai-cleanup';
    const videoS3Key = ownedUploadKey(userId, 'cleanup.mp4');
    const frameKeys = [
      ownedUploadKey(userId, 'one.jpg', 'frame-one'),
      ownedUploadKey(userId, 'two.jpg', 'frame-two')
    ];
    const deleteObject = vi.fn(async () => undefined);
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const fetchClipMedia = vi.fn(async (key: string) => ({
      data: new Uint8Array([1]),
      mimeType: key.endsWith('.jpg') ? 'image/jpeg' : 'video/mp4'
    }));
    const appWithR2 = createApp({
      config: readServerConfig({
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
      }),
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
        deleteObject
      },
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    await request(appWithR2)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key,
        selectedFrameKeys: frameKeys,
        deleteAfterUse: true
      })
      .expect(200);

    expect(deleteObject).toHaveBeenCalledTimes(3);
    expect(deleteObject).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: videoS3Key
    });
    expect(deleteObject).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: frameKeys[0]
    });
    expect(deleteObject).toHaveBeenCalledWith({
      bucket: 'postdee-r2-temp',
      key: frameKeys[1]
    });
  });

  it('does not clean up clip media unless the request opts in', async () => {
    const userId = 'seller-no-cleanup';
    const deleteObject = vi.fn(async () => undefined);
    const appWithR2 = createApp({
      config: readServerConfig({
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
      }),
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
        deleteObject
      },
      realClipCaptionProvider: { generate: vi.fn(async (input) => fakeRealClipCaption(input)) },
      fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' })
    });

    await request(appWithR2)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: ownedUploadKey(userId, 'keep.mp4') })
      .expect(200);

    expect(deleteObject).not.toHaveBeenCalled();
  });

  it('still returns the caption if AI caption cleanup fails', async () => {
    const userId = 'seller-cleanup-failure';
    const deleteObject = vi.fn(async () => {
      throw new Error('R2 delete failed');
    });
    const appWithR2 = createApp({
      config: readServerConfig({
        VIDEO_STORAGE: 'r2',
        CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
      }),
      r2Client: {
        createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
        createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
        deleteObject
      },
      realClipCaptionProvider: { generate: vi.fn(async (input) => fakeRealClipCaption(input)) },
      fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' })
    });

    const response = await request(appWithR2)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        videoS3Key: ownedUploadKey(userId, 'cleanup-fails.mp4'),
        deleteAfterUse: true
      })
      .expect(200);

    expect(response.body.status).toBe('ok');
    expect(deleteObject).toHaveBeenCalledTimes(1);
  });

  it('rejects when quota is exhausted after the initial availability check', async () => {
    const userId = 'seller-quota-race';
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const usageStore = {
      countForMonth: vi.fn(async () => 49),
      record: vi.fn(async () => ({
        userId,
        monthKey: '2026-06',
        createdAt: '2026-06-25T00:00:00.000Z'
      })),
      reserve: vi.fn(async () => ({
        ok: false as const,
        usedThisMonth: 50
      }))
    };
    const appWithQuotaRace = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' }),
      realClipCaptionUsageStore: usageStore
    });

    const response = await request(appWithQuotaRace)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: ownedUploadKey(userId, 'race.mp4') })
      .expect(429);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_CAPTION_QUOTA_REACHED',
      quota: {
        limit: 50,
        usedThisMonth: 50,
        remainingThisMonth: 0
      }
    });
    expect(usageStore.reserve).toHaveBeenCalledWith({
      userId,
      monthKey: expect.any(String),
      limit: 50
    });
    expect(generate).not.toHaveBeenCalled();
    expect(usageStore.record).not.toHaveBeenCalled();
  });

  it('limits Pro selected frames to three media objects', async () => {
    const userId = 'seller-pro-frame-limit';
    let receivedFrameCount = 0;
    const generate = vi.fn(async (input) => {
      receivedFrameCount = input.frames?.length ?? 0;
      return fakeRealClipCaption(input);
    });
    const fetchClipMedia = vi.fn(async (key: string) => ({
      data: new Uint8Array([1]),
      mimeType: key.endsWith('.jpg') ? 'image/jpeg' : 'video/mp4'
    }));
    const appPro = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    await request(appPro)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey(userId, 'pro.mp4'),
        selectedFrameKeys: [
          ownedUploadKey(userId, 'a.jpg', 'frame-a'),
          ownedUploadKey(userId, 'b.jpg', 'frame-b'),
          ownedUploadKey(userId, 'c.jpg', 'frame-c'),
          ownedUploadKey(userId, 'd.jpg', 'frame-d')
        ]
      })
      .expect(200);

    expect(fetchClipMedia).toHaveBeenCalledTimes(4); // audio + first 3 frames
    expect(receivedFrameCount).toBe(3);
  });

  it('rejects Pro frame keys owned by another user before fetching media', async () => {
    const userId = 'seller-pro-frames';
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const fetchClipMedia = vi.fn(async () => ({
      data: new Uint8Array([1]),
      mimeType: 'video/mp4'
    }));
    const appPro = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia
    });

    await request(appPro)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey(userId, 'pro.mp4'),
        selectedFrameKeys: [ownedUploadKey('other-seller', 'a.jpg', 'frame-a')]
      })
      .expect(403);

    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(generate).not.toHaveBeenCalled();
  });

  it('returns 413 when the selected clip is too large for AI media processing', async () => {
    const userId = 'seller-huge-media';
    const generate = vi.fn(async (input) => fakeRealClipCaption(input));
    const arrayBuffer = vi.fn(async () => new ArrayBuffer(0));
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: new Headers({
        'content-length': String(201 * 1024 * 1024),
        'content-type': 'video/mp4'
      }),
      arrayBuffer
    }));
    vi.stubGlobal('fetch', fetchMock);

    try {
      const appWithR2 = createApp({
        config: readServerConfig({
          VIDEO_STORAGE: 'r2',
          CLOUDFLARE_R2_BUCKET: 'postdee-r2-temp'
        }),
        r2Client: {
          createPresignedUploadUrl: async () => 'https://r2.local/upload-url',
          createPresignedDownloadUrl: async () => 'https://r2.local/download-url',
          deleteObject: async () => undefined
        },
        realClipCaptionProvider: { generate }
      });

      const response = await request(appWithR2)
        .post('/captions/generate-from-clip')
        .set('x-postdee-user-id', userId)
        .set('x-postdee-subscription-plan', 'STARTER')
        .send({ videoS3Key: ownedUploadKey(userId, 'huge.mp4') })
        .expect(413);

      expect(response.body).toEqual({
        status: 'error',
        code: 'AI_MEDIA_TOO_LARGE',
        message: 'Selected media is too large for AI processing'
      });
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(arrayBuffer).not.toHaveBeenCalled();
      expect(generate).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('falls back to the local template when the Gemini provider fails', async () => {
    const userId = 'seller-gemini-fail';
    const generate = vi.fn(async () => {
      throw new Error('gemini unavailable');
    });
    const appWithFailingProvider = createApp({
      realClipCaptionProvider: { generate },
      fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' })
    });

    const response = await request(appWithFailingProvider)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: ownedUploadKey(userId, 'fail.mp4') })
      .expect(200);

    expect(generate).toHaveBeenCalledTimes(1);
    expect(response.body.model).toBe('local-real-clip-template');
  });

  it('uses automatic clip context when no caption language or market is selected', async () => {
    const userId = 'seller-global-real-clip';

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        videoS3Key: ownedUploadKey(userId, 'global-real-clip.mp4'),
        guidance: 'write the caption in Japanese for Japan'
      })
      .expect(200);

    expect(response.body.context).toEqual({
      selectedCaptionLanguage: 'Thai',
      selectedTargetMarket: 'Thailand',
      selectedTone: 'auto',
      detectedSpokenLanguage: 'th',
      suggestedCaptionLanguage: 'Thai',
      suggestedTargetMarket: 'Thailand'
    });
    expect(response.body.caption).toContain('Detected spoken language: Thai');
    expect(response.body.caption).toContain('write the caption in Japanese for Japan');
  });

  it('uses transcript language to suggest caption language and market automatically', async () => {
    const userId = 'seller-japanese-real-clip';
    const videoS3Key = ownedUploadKey(userId, 'japanese-real-clip.mp4');
    const transcribe = vi.fn(async () => ({
      text: 'この商品は朝の準備を楽にします',
      language: 'ja',
      durationSeconds: 9,
      segments: [{ text: 'この商品は朝の準備を楽にします', start: 0, end: 9 }],
      words: [],
      model: 'test-whisper'
    }));
    const appWithTranscript = createApp({
      transcriptionProvider: { transcribe }
    });

    const response = await request(appWithTranscript)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({
        videoS3Key
      })
      .expect(200);

    expect(transcribe).toHaveBeenCalledWith({
      videoS3Key
    });
    expect(response.body.context).toEqual({
      selectedCaptionLanguage: 'Japanese',
      selectedTargetMarket: 'Japan',
      selectedTone: 'auto',
      detectedSpokenLanguage: 'ja',
      suggestedCaptionLanguage: 'Japanese',
      suggestedTargetMarket: 'Japan'
    });
    expect(response.body.caption).toContain('Japanese');
    expect(response.body.caption).toContain('Japan');
    expect(response.body.caption).toContain('この商品は朝の準備を楽にします');
  });

  it('requires a paid plan for real-clip captions', async () => {
    const userId = 'seller-basic-real-clip';

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .send({ videoS3Key: ownedUploadKey(userId, 'basic-real-clip.mp4') })
      .expect(402);

    expect(response.body).toEqual({
      status: 'error',
      code: 'PAID_PLAN_REQUIRED',
      message: 'AI caption from a real clip requires Starter or Pro'
    });
  });

  it('rejects real-clip caption requests without a video key', async () => {
    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', 'seller-invalid-real-clip')
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ guidance: 'missing clip' })
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'videoS3Key is required'
    });
  });

  it('blocks Starter real-clip captions after 50 generations in the month', async () => {
    const userId = 'seller-starter-real-clip-quota';

    for (let index = 0; index < 50; index += 1) {
      await request(app)
        .post('/captions/generate-from-clip')
        .set('x-postdee-user-id', userId)
        .set('x-postdee-subscription-plan', 'STARTER')
        .send({
          videoS3Key: ownedUploadKey(
            userId,
            `starter-quota-${index + 1}.mp4`,
            `clip-${index + 1}`
          )
        })
        .expect(200);
    }

    const response = await request(app)
      .post('/captions/generate-from-clip')
      .set('x-postdee-user-id', userId)
      .set('x-postdee-subscription-plan', 'STARTER')
      .send({ videoS3Key: ownedUploadKey(userId, 'starter-quota-over-limit.mp4') })
      .expect(429);

    expect(response.body).toEqual({
      status: 'error',
      code: 'AI_CAPTION_QUOTA_REACHED',
      message: 'Starter is limited to 50 real-clip AI caption generations per month',
      quota: {
        limit: 50,
        usedThisMonth: 50,
        remainingThisMonth: 0
      }
    });
  });
});
