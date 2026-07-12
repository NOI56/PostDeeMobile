import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';

const ownedUploadKey = (userId: string, fileName: string, uploadId = 'clip') =>
  `uploads/${userId}/${uploadId}/${fileName}`;

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

  it('does not let concurrent transcriptions exceed the monthly minute quota', async () => {
    let transcribeCalls = 0;
    let concurrentCalls = 0;
    let resolveBothConcurrentCalls: () => void = () => undefined;
    let releaseConcurrentTranscriptions: () => void = () => undefined;
    const bothConcurrentCallsStarted = new Promise<void>((resolve) => {
      resolveBothConcurrentCalls = resolve;
    });
    const concurrentTranscriptionsCanFinish = new Promise<void>((resolve) => {
      releaseConcurrentTranscriptions = resolve;
    });
    const transcribe = vi.fn(async () => {
      transcribeCalls += 1;

      if (transcribeCalls === 1) {
        return {
          text: 'already used 199 minutes',
          language: 'en',
          durationSeconds: 199 * 60,
          segments: [],
          words: [],
          model: 'test-whisper'
        };
      }

      concurrentCalls += 1;

      if (concurrentCalls === 2) {
        resolveBothConcurrentCalls();
      }

      await concurrentTranscriptionsCanFinish;

      return {
        text: 'one more minute',
        language: 'en',
        durationSeconds: 60,
        segments: [],
        words: [],
        model: 'test-whisper'
      };
    });
    const app = createApp({ transcriptionProvider: { transcribe } });
    const headers = { 'x-postdee-subscription-plan': 'PRO' };

    await request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'already-used.mp4'),
        durationSeconds: 199 * 60
      })
      .expect(200);

    const firstRequest = request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'concurrent-1.mp4'),
        durationSeconds: 60
      })
      .then((response) => response);
    const secondRequest = request(app)
      .post('/ai-edits/transcribe')
      .set(headers)
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'concurrent-2.mp4'),
        durationSeconds: 60
      })
      .then((response) => response);

    await bothConcurrentCallsStarted;
    releaseConcurrentTranscriptions();

    const responses = await Promise.all([firstRequest, secondRequest]);
    const statuses = responses.map((response) => response.status).sort();
    expect(statuses).toEqual([200, 402]);
    expect(responses.find((response) => response.status === 402)?.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_QUOTA_EXCEEDED'
    });

    const quotaResponse = await request(app)
      .get('/ai-edits/quota')
      .set(headers)
      .expect(200);
    expect(quotaResponse.body.quota).toEqual({
      limitMinutes: 200,
      usedMinutes: 200,
      remainingMinutes: 0
    });
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
    expect(response.body.recipe.capabilities.cta.state).toBe('hinted');
    expect(response.body.recipe.capabilities.beatsync.state).toBe('planned');
    expect(response.body.recipe.capabilities.translate.state).toBe('planned');
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

  it('blocks the plan endpoint for non-Pro users', async () => {
    const app = createApp();

    await request(app)
      .post('/ai-edits/plan')
      .send({ styleId: 'flash_sale', durationSeconds: 10, segments: [] })
      .expect(402);
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

