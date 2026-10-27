import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { MediaDownloadError } from '../storage/mediaDownload.js';
import { createOpenAiCompatibleEditPlanProvider } from './editPlanProvider.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

const createUnavailableEditPlanProvider = () =>
  createOpenAiCompatibleEditPlanProvider({
    apiKey: 'test-key',
    model: 'test-model',
    endpointUrl: 'https://example.com/v1/chat/completions',
    failureLabel: 'Test edit plan',
    fetchImpl: async () => ({
      ok: false,
      status: 503,
      json: async () => ({})
    })
  });

describe('ai edit routes', () => {
  it('transcribes a clip for Pro users', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4') })
      .expect(200);

    expect(response.body.status).toBe('ok');
    expect(response.body.transcript.language).toBe('th');
    expect(response.body.transcript.segments.length).toBeGreaterThan(0);
  });

  it('blocks transcription for non-Pro users', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .send({ videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4') })
      .expect(402);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'PRO_REQUIRED'
    });
  });

  it('requires a videoS3Key', async () => {
    const app = createApp();

    await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({})
      .expect(400);
  });

  it('meters usage by the real clip duration, ignoring an under-reported client estimate', async () => {
    // Real clip is 150s (3 minutes); the client under-reports 30s to try to be
    // billed less. Metering must use the real transcribed duration.
    const transcribe = vi.fn(async () => ({
      text: 'hello',
      language: 'en',
      durationSeconds: 150,
      segments: [],
      words: [],
      model: 'test-whisper'
    }));
    const app = createApp({ transcriptionProvider: { transcribe } });
    const headers = { 'x-postdee-subscription-plan': 'PRO' };

    const before = await request(app)
      .get('/ai-edits/quota')
      .set(headers)
      .expect(200);
    expect(before.body.quota).toEqual({
      limitMinutes: 200,
      usedMinutes: 0,
      remainingMinutes: 200
    });

    const transcribeResponse = await request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4'),
        durationSeconds: 30
      })
      .expect(200);
    expect(transcribeResponse.body.quota.usedMinutes).toBe(3); // ceil(150/60)

    const after = await request(app)
      .get('/ai-edits/quota')
      .set(headers)
      .expect(200);
    expect(after.body.quota.usedMinutes).toBe(3);
    expect(after.body.quota.remainingMinutes).toBe(197);
  });

  it('blocks transcription when the minute quota is exceeded', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'clip.mp4'),
        durationSeconds: 99999
      })
      .expect(402);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_QUOTA_EXCEEDED'
    });
  });

  const transcriptOf = (durationSeconds: number) => ({
    text: 'clip',
    language: 'en',
    durationSeconds,
    segments: [],
    words: [],
    model: 'test-whisper'
  });

  const useMinutes = async (app: ReturnType<typeof createApp>, minutes: number) => {
    await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', `used-${minutes}.mp4`),
        durationSeconds: minutes * 60
      })
      .expect(200);
  };

  const readUsedMinutes = async (app: ReturnType<typeof createApp>) => {
    const response = await request(app)
      .get('/ai-edits/quota')
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(200);
    return response.body.quota.usedMinutes as number;
  };

  it('rejects a parallel transcription before calling the provider once reservations fill the quota', async () => {
    let releaseBlockedCall: () => void = () => undefined;
    let markBlockedCallStarted: () => void = () => undefined;
    const blockedCallStarted = new Promise<void>((resolve) => {
      markBlockedCallStarted = resolve;
    });
    const transcribe = vi.fn(async ({ mediaS3Key }: { mediaS3Key: string }) => {
      if (mediaS3Key.endsWith('used-199.mp4')) {
        return transcriptOf(199 * 60);
      }

      markBlockedCallStarted();
      await new Promise<void>((resolve) => {
        releaseBlockedCall = resolve;
      });
      return transcriptOf(60);
    });
    const app = createApp({ transcriptionProvider: { transcribe } });
    const headers = { 'x-postdee-subscription-plan': 'PRO' };
    await useMinutes(app, 199);

    const firstRequest = request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'concurrent-1.mp4'),
        durationSeconds: 60
      })
      .then((response) => response);
    await blockedCallStarted;

    const secondResponse = await request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'concurrent-2.mp4'),
        durationSeconds: 60
      })
      .expect(402);

    expect(secondResponse.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_QUOTA_EXCEEDED'
    });
    expect(transcribe).toHaveBeenCalledTimes(2);

    releaseBlockedCall();
    expect((await firstRequest).status).toBe(200);
    expect(await readUsedMinutes(app)).toBe(200);
  });

  it('refunds reserved minutes when transcription fails', async () => {
    const transcribe = vi.fn(async () => {
      throw new MediaDownloadError('too large', 413, 'AI_MEDIA_TOO_LARGE');
    });
    const app = createApp({ transcriptionProvider: { transcribe } });

    await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'broken.mp4'),
        durationSeconds: 120
      })
      .expect(413);

    expect(await readUsedMinutes(app)).toBe(0);
  });

  it('keeps the estimate charged when the real duration does not fit the remaining quota', async () => {
    const transcribe = vi.fn(async ({ mediaS3Key }: { mediaS3Key: string }) =>
      transcriptOf(mediaS3Key.endsWith('used-190.mp4') ? 190 * 60 : 30 * 60)
    );
    const app = createApp({ transcriptionProvider: { transcribe } });
    await useMinutes(app, 190);

    // The client claims 1 minute but the clip is 30 minutes long.
    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'under-reported.mp4'),
        durationSeconds: 60
      })
      .expect(402);

    expect(response.body).toMatchObject({ code: 'AI_EDIT_QUOTA_EXCEEDED' });
    expect(response.body).not.toHaveProperty('transcript');
    expect(await readUsedMinutes(app)).toBe(191);
  });

  it('allows a one-minute rounding difference at the quota limit', async () => {
    // The app measures the video (60s) and the provider the audio (61s), so an
    // honest request can round one minute over the estimate.
    const transcribe = vi.fn(async ({ mediaS3Key }: { mediaS3Key: string }) =>
      transcriptOf(mediaS3Key.endsWith('used-199.mp4') ? 199 * 60 : 61)
    );
    const app = createApp({ transcriptionProvider: { transcribe } });
    await useMinutes(app, 199);

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'rounding.mp4'),
        durationSeconds: 60
      })
      .expect(200);

    expect(response.body.transcript.durationSeconds).toBe(61);
    expect(response.body.quota).toEqual({
      limitMinutes: 200,
      usedMinutes: 200,
      remainingMinutes: 0
    });
  });

  it('refunds prepare minutes when transcription fails', async () => {
    const transcribe = vi.fn(async () => {
      throw new MediaDownloadError('too large', 413, 'AI_MEDIA_TOO_LARGE');
    });
    const app = createApp({ transcriptionProvider: { transcribe } });

    await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'broken-prepare.mp4'),
        durationSeconds: 120,
        styleId: 'flash_sale'
      })
      .expect(413);

    expect(await readUsedMinutes(app)).toBe(0);
  });

  it('rejects transcription for a clip owned by another user', async () => {
    const transcribe = vi.fn(async () => ({
      text: 'hello',
      language: 'en',
      durationSeconds: 1,
      segments: [],
      words: [],
      model: 'test-whisper'
    }));
    const app = createApp({
      transcriptionProvider: { transcribe }
    });

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-user-id', 'seller-ai-edit')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ videoS3Key: ownedUploadKey('other-seller', 'clip.mp4') })
      .expect(403);

    expect(response.body).toEqual({
      status: 'error',
      code: 'MEDIA_KEY_FORBIDDEN',
      message: 'Selected media does not belong to the authenticated user'
    });
    expect(transcribe).not.toHaveBeenCalled();
  });

  it('prepares a mobile render recipe from the AI editing UI capabilities', async () => {
    const transcribe = vi.fn(async () => ({
      text: 'ราคา 99 บาท ส่งฟรีวันนี้ กดตะกร้าได้เลย',
      language: 'th',
      durationSeconds: 65,
      segments: [
        { text: 'สวัสดีค่ะ', start: 0, end: 2 },
        { text: 'ราคา 99 บาท ส่งฟรีวันนี้', start: 4, end: 7 },
        { text: 'กดตะกร้าได้เลย', start: 10, end: 13 }
      ],
      words: [
        { word: 'ราคา', start: 4, end: 4.4 },
        { word: '99', start: 4.5, end: 4.8 },
        { word: 'บาท', start: 4.9, end: 5.2 }
      ],
      model: 'test-whisper'
    }));
    const app = createApp({ transcriptionProvider: { transcribe } });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'ui-recipe.mp4'),
        durationSeconds: 65,
        styleId: 'flash_sale',
        capabilities: {
          subtitle: true,
          silence: true,
          filler: true,
          hook: true,
          beatsync: true,
          reframe: true,
          zoom: true,
          color: true,
          sfx: true,
          audio: true,
          translate: true,
          pricetag: true,
          cta: true,
          watermark: true
        },
        settings: {
          ctaText: 'กดตะกร้าเลย',
          priceText: '99 บาท',
          watermarkText: 'Meena Shop',
          toneFilter: 'warm',
          zoomLevel: 'medium',
          music: {
            source: 'library',
            genre: 'fun',
            trackId: 'postdee-sale-01',
            beatIntensity: 'energetic',
            volume: 0.25,
            ducking: {
              enabled: true,
              musicVolumeDuringSpeech: 0.12
            }
          }
        }
      })
      .expect(200);

    expect(response.body.status).toBe('ok');
    expect(response.body.quota).toEqual({
      limitMinutes: 200,
      usedMinutes: 2,
      remainingMinutes: 198
    });
    expect(response.body.recipe).toMatchObject({
      version: 1,
      status: 'ready',
      renderMode: 'mobile-ffmpeg',
      styleId: 'flash_sale',
      transcript: {
        text: 'ราคา 99 บาท ส่งฟรีวันนี้ กดตะกร้าได้เลย',
        language: 'th',
        durationSeconds: 65
      },
      subtitles: {
        enabled: true,
        segments: [
          { text: 'สวัสดีค่ะ', start: 0, end: 2 },
          { text: 'ราคา 99 บาท ส่งฟรีวันนี้', start: 4, end: 7 },
          { text: 'กดตะกร้าได้เลย', start: 10, end: 13 }
        ]
      },
      overlays: {
        cta: { enabled: true, text: 'กดตะกร้าเลย', design: 'button' },
        priceTag: { enabled: true, text: '99 บาท' },
        watermark: { enabled: true, text: 'Meena Shop' }
      },
      renderHints: {
        toneFilter: 'warm',
        zoomLevel: 'medium'
      },
      music: {
        source: 'library',
        genre: 'fun',
        trackId: 'postdee-sale-01',
        beatIntensity: 'energetic',
        volume: 0.25,
        ducking: {
          enabled: true,
          musicVolumeDuringSpeech: 0.12
        }
      }
    });
    expect(response.body.recipe.cutRanges).toContainEqual({ start: 0, end: 4 });
    expect(response.body.recipe.cutRanges).toContainEqual({ start: 7, end: 65 });
    expect(response.body.recipe.cutRanges).toContainEqual({ start: 2, end: 4 });
    expect(response.body.recipe.capabilities.subtitle.state).toBe('applied');
    expect(response.body.recipe.capabilities.silence.state).toBe('applied');
    expect(response.body.recipe.capabilities.cta.state).toBe('planned');
    expect(response.body.recipe.capabilities.beatsync.state).toBe('planned');
    expect(response.body.recipe.capabilities.translate.state).toBe('planned');
  });

  it('passes the requested result length to the planner for highlight selection', async () => {
    const plan = vi.fn(async () => ({
      cuts: [
        { start: 0, end: 4 },
        { start: 8, end: 12 }
      ],
      summary: 'เลือกช่วงขายที่ดีที่สุดให้เหลือประมาณ 10 วิ',
      model: 'test-planner'
    }));
    const transcribe = vi.fn(async () => ({
      text: 'คลิปขายสินค้า',
      language: 'th',
      durationSeconds: 18,
      segments: [
        { text: 'เกริ่นทั่วไป', start: 0, end: 4 },
        { text: 'ช่วยประหยัดเวลา', start: 4, end: 8 },
        { text: 'รายละเอียดทั่วไป', start: 8, end: 12 },
        { text: 'ราคา 99 บาท', start: 12, end: 15 },
        { text: 'กดตะกร้าเลย', start: 15, end: 18 }
      ],
      words: [],
      model: 'test-whisper'
    }));
    const app = createApp({
      transcriptionProvider: { transcribe },
      editPlanProvider: { plan }
    });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'highlights.mp4'),
        durationSeconds: 18,
        targetDurationSeconds: 10,
        capabilities: { subtitle: true }
      })
      .expect(200);

    expect(plan).toHaveBeenCalledWith(
      expect.objectContaining({
        durationSeconds: 18,
        targetDurationSeconds: 10
      })
    );
    expect(response.body.recipe.plan).toMatchObject({
      cuts: [
        { start: 0, end: 4 },
        { start: 8, end: 12 }
      ],
      model: 'test-planner'
    });
  });

  it('sanitizes unsupported beat music settings without claiming they were applied', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'invalid-music.mp4'),
        durationSeconds: 12,
        capabilities: { beatsync: true },
        settings: {
          music: {
            source: 'spotify',
            genre: 123,
            trackId: 'private-track-that-must-not-survive',
            trackStorageKey: 'uploads/another-user/private-song.mp3',
            beatIntensity: 'hyper',
            volume: 9,
            ducking: {
              enabled: 'yes',
              musicVolumeDuringSpeech: -2
            }
          }
        }
      })
      .expect(200);

    expect(response.body.recipe.music).toEqual({
      source: 'original',
      beatIntensity: 'balanced',
      volume: 0.25,
      ducking: {
        enabled: true,
        musicVolumeDuringSpeech: 0.12
      }
    });
    expect(response.body.recipe.capabilities.beatsync.state).toBe('planned');
  });
  it('returns a cut plan for a style', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        styleId: 'flash_sale',
        durationSeconds: 10,
        segments: [
          { text: 'สวัสดีค่ะ', start: 0, end: 3 },
          { text: 'ราคา 99 บาท', start: 3, end: 6 },
          { text: 'บายค่ะ', start: 6, end: 10 }
        ]
      })
      .expect(200);

    expect(response.body.status).toBe('ok');
    expect(response.body.plan.cuts).toEqual([
      { start: 0, end: 3 },
      { start: 6, end: 10 }
    ]);
  });

  it('plans from a free-form prompt', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ prompt: 'เหลือ 5 วิ', durationSeconds: 10, segments: [] })
      .expect(200);

    expect(response.body.plan.cuts).toEqual([{ start: 5, end: 10 }]);
  });

  it('returns a clear 502 when the configured AI plan provider fails', async () => {
    const app = createApp({
      editPlanProvider: createUnavailableEditPlanProvider()
    });

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ styleId: 'flash_sale', durationSeconds: 10, segments: [] })
      .expect(502);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_PLAN_PROVIDER_FAILED'
    });
  });

  it('returns the same provider failure contract from the prepare endpoint', async () => {
    const app = createApp({
      editPlanProvider: createUnavailableEditPlanProvider()
    });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'provider-failure.mp4'),
        durationSeconds: 10,
        styleId: 'flash_sale'
      })
      .expect(502);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_PLAN_PROVIDER_FAILED'
    });

    const quotaResponse = await request(app)
      .get('/ai-edits/quota')
      .set('x-postdee-subscription-plan', 'PRO')
      .expect(200);

    expect(quotaResponse.body.quota.usedMinutes).toBe(0);
  });

  it('blocks the plan endpoint for non-Pro users', async () => {
    const app = createApp();

    await request(app)
      .post('/ai-edits/plan')
      .send({ styleId: 'flash_sale', durationSeconds: 10, segments: [] })
      .expect(402);
  });

  const createAppWithPlanSpy = () => {
    const plan = vi.fn(async () => ({ cuts: [], summary: '', model: 'spy' }));
    const transcribe = vi.fn(async () => ({
      text: 'clip', language: 'th', durationSeconds: 60, segments: [], words: [], model: 'test'
    }));
    return {
      app: createApp({ editPlanProvider: { plan }, transcriptionProvider: { transcribe } }),
      plan,
      transcribe
    };
  };

  it('rejects plan prompts longer than 500 characters before calling the planner', async () => {
    const { app, plan } = createAppWithPlanSpy();

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ prompt: 'x'.repeat(501), durationSeconds: 10, segments: [] })
      .expect(400);

    expect(response.body).toMatchObject({ code: 'AI_EDIT_PROMPT_TOO_LONG' });
    expect(plan).not.toHaveBeenCalled();
  });

  it('rejects plans with too many or too long transcript segments', async () => {
    const { app, plan } = createAppWithPlanSpy();
    const segment = (text: string, index: number) => ({ text, start: index, end: index + 1 });

    const tooMany = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        styleId: 'flash_sale',
        durationSeconds: 700,
        segments: Array.from({ length: 601 }, (_, index) => segment('hi', index))
      })
      .expect(400);
    const tooLong = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        styleId: 'flash_sale',
        durationSeconds: 10,
        segments: [segment('y'.repeat(301), 0)]
      })
      .expect(400);

    expect(tooMany.body).toMatchObject({ code: 'AI_EDIT_SEGMENTS_TOO_LARGE' });
    expect(tooLong.body).toMatchObject({ code: 'AI_EDIT_SEGMENTS_TOO_LARGE' });
    expect(plan).not.toHaveBeenCalled();
  });

  it('rejects a too-long prepare prompt before reserving minutes or transcribing', async () => {
    const { app, transcribe } = createAppWithPlanSpy();

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'long-prompt.mp4'),
        durationSeconds: 60,
        prompt: 'x'.repeat(501)
      })
      .expect(400);

    expect(response.body).toMatchObject({ code: 'AI_EDIT_PROMPT_TOO_LONG' });
    expect(transcribe).not.toHaveBeenCalled();
    expect(await readUsedMinutes(app)).toBe(0);
  });

  it('requires a style or prompt for a plan', async () => {
    const app = createApp();

    await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ durationSeconds: 10, segments: [] })
      .expect(400);
  });
});

