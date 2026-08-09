import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createMockVideoStorage } from '../storage/videoStorage.js';

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

  it('merges trusted audio chunks and preserves timed audio event evidence', async () => {
    const transcripts = [
      {
        text: 'first',
        language: 'en',
        durationSeconds: 10,
        segments: [{ text: 'first', start: 1, end: 9 }],
        words: [{ word: 'first', start: 1, end: 2 }],
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: true,
        model: 'test-scribe'
      },
      {
        text: 'second',
        language: 'en',
        durationSeconds: 5,
        segments: [{ text: 'second', start: 0, end: 5 }],
        words: [{ word: 'second', start: 0, end: 1 }],
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: false,
        model: 'test-scribe'
      }
    ];
    let callIndex = 0;
    const transcribe = vi.fn(async () => transcripts[callIndex++]!);
    const app = createApp({ transcriptionProvider: { transcribe } });

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        audioChunks: [
          {
            audioS3Key: ownedUploadKey('local-dev-user', 'part-1.m4a'),
            startSeconds: 0
          },
          {
            audioS3Key: ownedUploadKey('local-dev-user', 'part-2.m4a'),
            startSeconds: 10
          }
        ],
        durationSeconds: 15
      })
      .expect(200);

    expect(response.body.transcript).toMatchObject({
      durationSeconds: 15,
      timingIntegrity: 'trusted',
      hasTimedAudioEvents: true,
      segments: [
        { text: 'first', start: 1, end: 9 },
        { text: 'second', start: 10, end: 15 }
      ]
    });
  });

  it.each([
    ['clips', { text: 'clipped', start: 8, end: 12 }, 1],
    ['drops', { text: 'dropped', start: 11, end: 12 }, 0]
  ])(
    'marks merged timing untrusted when a chunk boundary %s a timed range',
    async (_description, firstSegment, expectedFirstChunkSegments) => {
      const transcripts = [
        {
          text: firstSegment.text,
          language: 'en',
          durationSeconds: 12,
          segments: [firstSegment],
          words: [],
          timingIntegrity: 'trusted' as const,
          hasTimedAudioEvents: false,
          model: 'test-scribe'
        },
        {
          text: 'second',
          language: 'en',
          durationSeconds: 5,
          segments: [{ text: 'second', start: 0, end: 5 }],
          words: [],
          timingIntegrity: 'trusted' as const,
          hasTimedAudioEvents: false,
          model: 'test-scribe'
        }
      ];
      let callIndex = 0;
      const transcribe = vi.fn(async () => transcripts[callIndex++]!);
      const app = createApp({ transcriptionProvider: { transcribe } });

      const response = await request(app)
        .post('/ai-edits/transcribe')
        .set('x-postdee-subscription-plan', 'PRO')
        .send({
          audioChunks: [
            {
              audioS3Key: ownedUploadKey('local-dev-user', 'part-1.m4a'),
              startSeconds: 0
            },
            {
              audioS3Key: ownedUploadKey('local-dev-user', 'part-2.m4a'),
              startSeconds: 10
            }
          ],
          durationSeconds: 15
        })
        .expect(200);

      expect(response.body.transcript.timingIntegrity).toBe('untrusted');
      expect(
        response.body.transcript.segments.filter(
          (segment: { text: string }) => segment.text === firstSegment.text
        )
      ).toHaveLength(expectedFirstChunkSegments);
    }
  );

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
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
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

  it('meters the longer media timeline when transcription ends just before a minute boundary', async () => {
    const transcribe = vi.fn(async () => ({
      text: 'provider stopped before the media ended',
      language: 'en',
      durationSeconds: 119.9,
      segments: [
        {
          text: 'provider stopped before the media ended',
          start: 0,
          end: 119.9
        }
      ],
      words: [],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'test-whisper'
    }));
    const app = createApp({ transcriptionProvider: { transcribe } });

    const response = await request(app)
      .post('/ai-edits/transcribe')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'early-ending.mp4'),
        durationSeconds: 120.001
      })
      .expect(200);

    expect(response.body.transcript.durationSeconds).toBe(119.9);
    expect(response.body.quota.usedMinutes).toBe(3);
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
          timingIntegrity: 'trusted' as const,
          hasTimedAudioEvents: false,
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
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: false,
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
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
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

  it.each(['/ai-edits/transcribe', '/ai-edits/prepare'])(
    'returns a safe JSON error when transcription fails on %s',
    async (endpoint) => {
      const transcribe = vi.fn(async () => {
        throw new Error('Transcription failed: secret provider detail');
      });
      const app = createApp({ transcriptionProvider: { transcribe } });

      const response = await request(app)
        .post(endpoint)
        .set('x-postdee-subscription-plan', 'PRO')
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'provider-failure.mp4'),
          durationSeconds: 30
        })
        .expect('Content-Type', /json/)
        .expect(502);

      expect(response.body).toEqual({
        status: 'error',
        code: 'AI_TRANSCRIPTION_PROVIDER_FAILED',
        message: 'AI transcription is temporarily unavailable'
      });
      expect(JSON.stringify(response.body)).not.toContain('secret provider detail');

      const quotaResponse = await request(app)
        .get('/ai-edits/quota')
        .set('x-postdee-subscription-plan', 'PRO')
        .expect(200);
      expect(quotaResponse.body.quota.usedMinutes).toBe(0);
    }
  );

  it.each([
    ['style', { styleId: 'flash_sale' }],
    ['prompt', { prompt: 'keep the strongest claim' }],
    [
      'target duration',
      { targetDurationSeconds: 10, capabilities: { subtitle: true } }
    ]
  ])(
    'rejects %s planning before planner and quota reservation when timing is untrusted',
    async (_description, planningRequest) => {
      const transcribe = vi.fn(async () => ({
        text: 'usable display text',
        language: 'en',
        durationSeconds: 20,
        segments: [{ text: 'usable display text', start: 0, end: 20 }],
        words: [],
        timingIntegrity: 'untrusted' as const,
        hasTimedAudioEvents: false,
        model: 'test-scribe'
      }));
      const plan = vi.fn(async () => ({
        cuts: [],
        summary: 'must not run',
        model: 'test-planner'
      }));
      const app = createApp({
        transcriptionProvider: { transcribe },
        editPlanProvider: { plan }
      });
      const headers = { 'x-postdee-subscription-plan': 'PRO' };

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set(headers)
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'untrusted.mp4'),
          durationSeconds: 20,
          ...planningRequest
        })
        .expect(422);

      expect(response.body).toMatchObject({
        status: 'error',
        code: 'AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE',
        message: 'Transcript timing evidence is unavailable'
      });
      expect(plan).not.toHaveBeenCalled();

      const quota = await request(app)
        .get('/ai-edits/quota')
        .set(headers)
        .expect(200);
      expect(quota.body.quota.usedMinutes).toBe(0);
    }
  );

  it.each([
    [
      'overshoots the media duration',
      [{ text: 'bad end', start: 0, end: 999 }]
    ],
    [
      'moves backwards in provider order',
      [
        { text: 'later', start: 10, end: 15 },
        { text: 'earlier', start: 0, end: 5 }
      ]
    ]
  ])(
    'rejects trusted provider timing that %s before planning',
    async (_description, segments) => {
      const transcribe = vi.fn(async () => ({
        text: 'provider accidentally marked malformed timing trusted',
        language: 'en',
        durationSeconds: 20,
        segments,
        words: [],
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: false,
        model: 'test-scribe'
      }));
      const plan = vi.fn(async () => ({
        cuts: [],
        summary: 'must not run',
        model: 'test-planner'
      }));
      const app = createApp({
        transcriptionProvider: { transcribe },
        editPlanProvider: { plan }
      });

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set('x-postdee-subscription-plan', 'PRO')
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'malformed.mp4'),
          durationSeconds: 20,
          styleId: 'flash_sale'
        })
        .expect(422);

      expect(response.body.code).toBe('AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE');
      expect(plan).not.toHaveBeenCalled();
    }
  );

  it('returns a safe non-executable recipe for subtitle and silence on untrusted timing',
      async () => {
    const transcribe = vi.fn(async () => ({
      text: 'first second',
      language: 'en',
      durationSeconds: 10,
      segments: [
        { text: 'first', start: 1, end: 2 },
        { text: 'second', start: 4, end: 5 }
      ],
      words: [],
      timingIntegrity: 'untrusted' as const,
      hasTimedAudioEvents: false,
      model: 'test-scribe'
    }));
    const app = createApp({ transcriptionProvider: { transcribe } });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'safe-recipe.mp4'),
        durationSeconds: 10,
        capabilities: { subtitle: true, silence: true }
      })
      .expect(200);

    expect(response.body.recipe).toMatchObject({
      subtitles: { segments: [] },
      cutRanges: [],
      silenceRanges: [],
      capabilities: {
        subtitle: { state: 'hinted' },
        silence: { state: 'hinted' }
      }
    });
  });

  it.each([
    ['zero words', { subtitleWordsPerLine: 0 }],
    ['too many words', { subtitleWordsPerLine: 6 }],
    ['fractional words', { subtitleWordsPerLine: 2.5 }],
    ['null words', { subtitleWordsPerLine: null }],
    ['invalid text colour', { subtitleColor: 'white' }],
    ['invalid outline colour', { subtitleOutlineColor: '#GGGGGG' }],
    ['missing Y coordinate', { subtitleNormalizedX: 0.5 }],
    [
      'out of range coordinate',
      { subtitleNormalizedX: 0.5, subtitleNormalizedY: 1.1 }
    ]
  ])(
    'rejects invalid subtitle settings (%s) before transcription and metering',
    async (_description, settings) => {
      const transcribe = vi.fn(async () => ({
        text: 'must not run',
        language: 'en',
        durationSeconds: 10,
        segments: [{ text: 'must not run', start: 0, end: 10 }],
        words: [],
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: false,
        model: 'test-scribe'
      }));
      const app = createApp({ transcriptionProvider: { transcribe } });
      const headers = { 'x-postdee-subscription-plan': 'PRO' };

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set(headers)
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'invalid-settings.mp4'),
          durationSeconds: 10,
          capabilities: { subtitle: true },
          settings
        })
        .expect(400);

      expect(response.body).toMatchObject({
        status: 'error',
        code: 'INVALID_AI_EDIT_SETTINGS'
      });
      expect(transcribe).not.toHaveBeenCalled();

      const quota = await request(app)
        .get('/ai-edits/quota')
        .set(headers)
        .expect(200);
      expect(quota.body.quota.usedMinutes).toBe(0);
    }
  );

  it.each([
    ['explicit empty capabilities', {}],
    ['color-only capabilities', { color: true }]
  ])(
    'rejects %s before transcription, planning, and metering',
    async (_description, capabilities) => {
      const transcribe = vi.fn(async () => ({
        text: 'must not run',
        language: 'en',
        durationSeconds: 60,
        segments: [{ text: 'must not run', start: 0, end: 1 }],
        words: [{ word: 'must', start: 0, end: 0.4 }],
        timingIntegrity: 'trusted' as const,
        hasTimedAudioEvents: false,
        model: 'test-scribe'
      }));
      const plan = vi.fn(async () => ({
        cuts: [],
        summary: 'must not run',
        model: 'test-planner'
      }));
      const app = createApp({
        transcriptionProvider: { transcribe },
        editPlanProvider: { plan }
      });
      const headers = { 'x-postdee-subscription-plan': 'PRO' };

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set(headers)
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'local-only.mp4'),
          durationSeconds: 60,
          capabilities
        })
        .expect(400);

      expect(response.body).toEqual({
        status: 'error',
        code: 'AI_EDIT_NO_ANALYSIS_REQUESTED',
        message: 'เลือกงาน AI ที่ต้องการก่อนเริ่มวิเคราะห์'
      });
      expect(transcribe).not.toHaveBeenCalled();
      expect(plan).not.toHaveBeenCalled();

      const quota = await request(app)
        .get('/ai-edits/quota')
        .set(headers)
        .expect(200);
      expect(quota.body.quota.usedMinutes).toBe(0);
    }
  );

  it('keeps metering a legacy preparation that omits capabilities and planning',
      async () => {
    const transcribe = vi.fn(async () => ({
      text: 'legacy request',
      language: 'en',
      durationSeconds: 60,
      segments: [{ text: 'legacy request', start: 0, end: 1 }],
      words: [
        { word: 'legacy', start: 0, end: 0.4 },
        { word: 'request', start: 0.5, end: 1 }
      ],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'test-scribe'
    }));
    const app = createApp({ transcriptionProvider: { transcribe } });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'legacy.mp4'),
        durationSeconds: 60
      })
      .expect(200);

    expect(transcribe).toHaveBeenCalledTimes(1);
    expect(response.body.recipe.analysisOutcomes).toEqual({
      plan: 'not-requested',
      subtitle: 'not-requested',
      silence: 'not-requested',
      speechReduction: 'not-requested'
    });
    expect(response.body.quota.usedMinutes).toBe(1);
  });

  it('meters prepare only when at least one requested analysis succeeds',
      async () => {
    const unavailableRepeatTranscript = {
      text: 'ชุมชน ชุมชน',
      language: 'th',
      durationSeconds: 60,
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1 }],
      words: [
        { word: 'ชุม', start: 0, end: 0.1 },
        { word: 'ชล', start: 0.2, end: 0.4 },
        { word: 'ชุมชน', start: 0.5, end: 1 }
      ],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'test-elevenlabs'
    };
    const cases = [
      {
        name: 'repeat-only ready',
        transcript: {
          ...unavailableRepeatTranscript,
          words: [
            { word: 'ชุมชน', start: 0, end: 0.4 },
            { word: 'ชุมชน', start: 0.5, end: 1 }
          ]
        },
        capabilities: { filler: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { speechReduction: 'succeeded' },
        expectedMinutes: 1
      },
      {
        name: 'repeat analysis ready with no repeated group',
        transcript: {
          ...unavailableRepeatTranscript,
          text: 'สินค้า',
          segments: [{ text: 'สินค้า', start: 0, end: 1 }],
          words: [{ word: 'สินค้า', start: 0, end: 1 }]
        },
        capabilities: { filler: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { speechReduction: 'succeeded' },
        expectedMinutes: 1
      },
      {
        name: 'legacy fixed filler range success',
        transcript: {
          ...unavailableRepeatTranscript,
          text: 'เอ่อ',
          segments: [{ text: 'เอ่อ', start: 0, end: 1 }],
          words: [{ word: 'เอ่อ', start: 0, end: 1 }]
        },
        capabilities: { filler: true },
        settings: {},
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { speechReduction: 'succeeded' },
        expectedMinutes: 1
      },
      {
        name: 'repeat-only unavailable',
        transcript: unavailableRepeatTranscript,
        capabilities: { filler: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { speechReduction: 'unavailable' },
        expectedMinutes: 0
      },
      {
        name: 'repeat unavailable plus subtitle success',
        transcript: unavailableRepeatTranscript,
        capabilities: { filler: true, subtitle: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: {
          speechReduction: 'unavailable',
          subtitle: 'succeeded'
        },
        expectedMinutes: 1
      },
      {
        name: 'repeat unavailable plus subtitle unavailable',
        transcript: {
          ...unavailableRepeatTranscript,
          text: '',
          segments: [],
          words: []
        },
        capabilities: { filler: true, subtitle: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: {
          speechReduction: 'unavailable',
          subtitle: 'unavailable'
        },
        expectedMinutes: 0
      },
      {
        name: 'repeat unavailable plus target plan success',
        transcript: unavailableRepeatTranscript,
        capabilities: { filler: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: 30,
        planResult: {
          cuts: [{ start: 30, end: 60 }],
          summary: 'kept the first half',
          model: 'test-planner'
        },
        expectedOutcomes: {
          speechReduction: 'unavailable',
          plan: 'succeeded'
        },
        expectedMinutes: 1
      },
      {
        name: 'repeat unavailable plus unusable target plan',
        transcript: unavailableRepeatTranscript,
        capabilities: { filler: true },
        settings: { speechReductionMode: 'auto' },
        targetDurationSeconds: 30,
        planResult: null,
        expectedOutcomes: {
          speechReduction: 'unavailable',
          plan: 'unavailable'
        },
        expectedMinutes: 0
      },
      {
        name: 'safe silence analysis with no candidate',
        transcript: {
          text: 'สินค้า',
          language: 'th',
          durationSeconds: 60,
          segments: [{ text: 'สินค้า', start: 0, end: 1 }],
          words: [{ word: 'สินค้า', start: 0, end: 1 }],
          timingIntegrity: 'trusted' as const,
          hasTimedAudioEvents: false,
          model: 'test-elevenlabs'
        },
        capabilities: { silence: true },
        settings: {},
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { silence: 'succeeded' },
        expectedMinutes: 1
      },
      {
        name: 'unsafe silence analysis',
        transcript: {
          text: 'สินค้า',
          language: 'th',
          durationSeconds: 60,
          segments: [{ text: 'สินค้า', start: 0, end: 1 }],
          words: [{ word: 'สินค้า', start: 0, end: 1 }],
          timingIntegrity: 'untrusted' as const,
          hasTimedAudioEvents: false,
          model: 'test-elevenlabs'
        },
        capabilities: { silence: true },
        settings: {},
        targetDurationSeconds: undefined,
        planResult: undefined,
        expectedOutcomes: { silence: 'unavailable' },
        expectedMinutes: 0
      }
    ];

    for (const testCase of cases) {
      const transcribe = vi.fn(async () => testCase.transcript);
      const plan = vi.fn(async () =>
        testCase.planResult === null
          ? undefined as never
          : testCase.planResult as never
      );
      const app = createApp({
        transcriptionProvider: { transcribe },
        editPlanProvider: { plan }
      });
      const headers = { 'x-postdee-subscription-plan': 'PRO' };
      const body = {
        videoS3Key: ownedUploadKey('local-dev-user', `${testCase.name}.mp4`),
        durationSeconds: 60,
        capabilities: testCase.capabilities,
        settings: testCase.settings,
        ...(testCase.targetDurationSeconds === undefined
          ? {}
          : { targetDurationSeconds: testCase.targetDurationSeconds })
      };

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set(headers)
        .send(body)
        .expect(200);

      expect(response.body.recipe.analysisOutcomes, testCase.name)
        .toMatchObject(testCase.expectedOutcomes);
      if (testCase.name === 'repeat analysis ready with no repeated group') {
        expect(response.body.recipe.speechReduction).toMatchObject({
          status: 'ready',
          groups: []
        });
      }
      if (testCase.name === 'legacy fixed filler range success') {
        expect(response.body.recipe.speechReduction).toBeUndefined();
        expect(response.body.recipe.fillerRanges).toEqual([
          { start: 0, end: 1 }
        ]);
      }
      expect(response.body.quota.usedMinutes, testCase.name)
        .toBe(testCase.expectedMinutes);
      const quota = await request(app)
        .get('/ai-edits/quota')
        .set(headers)
        .expect(200);
      expect(quota.body.quota.usedMinutes, testCase.name)
        .toBe(testCase.expectedMinutes);
    }
  });

  it.each([
    {
      name: 'provider timing marked untrusted',
      timingIntegrity: 'untrusted' as const,
      hasTimedAudioEvents: false,
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1 }],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.4 },
        { word: 'ชุมชน', start: 0.5, end: 1 }
      ]
    },
    {
      name: 'timed audio event between words',
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: true,
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1 }],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.4 },
        { word: 'ชุมชน', start: 0.5, end: 1 }
      ]
    },
    {
      name: 'unreliable speech between repeated words',
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      segments: [
        { text: 'ชุมชน', start: 0, end: 0.3 },
        {
          text: 'เอ่อ',
          start: 0.3,
          end: 0.6,
          noSpeechProbability: 0.9
        },
        { text: 'ชุมชน', start: 0.6, end: 1 }
      ],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.3 },
        { word: 'เอ่อ', start: 0.3, end: 0.6 },
        { word: 'ชุมชน', start: 0.6, end: 1 }
      ]
    }
  ])(
    'does not meter repeat-only analysis across $name',
    async ({ timingIntegrity, hasTimedAudioEvents, segments, words }) => {
      const transcribe = vi.fn(async () => ({
        text: segments.map((segment) => segment.text).join(' '),
        language: 'th',
        durationSeconds: 60,
        segments,
        words,
        timingIntegrity,
        hasTimedAudioEvents,
        model: 'test-elevenlabs'
      }));
      const app = createApp({ transcriptionProvider: { transcribe } });
      const headers = { 'x-postdee-subscription-plan': 'PRO' };

      const response = await request(app)
        .post('/ai-edits/prepare')
        .set(headers)
        .send({
          videoS3Key: ownedUploadKey('local-dev-user', 'repeat-barrier.mp4'),
          durationSeconds: 60,
          capabilities: { filler: true },
          settings: { speechReductionMode: 'auto' }
        })
        .expect(200);

      expect(response.body.recipe.analysisOutcomes.speechReduction)
        .toBe('unavailable');
      expect(response.body.recipe.speechReduction).toMatchObject({
        status: 'unavailable',
        defaultCutRanges: []
      });
      expect(response.body.recipe.cutRanges).toEqual([]);
      expect(response.body.quota.usedMinutes).toBe(0);
    }
  );

  it('meters prepare usage only after the edit recipe succeeds', async () => {
    const transcribe = vi.fn(async () => ({
      text: 'retry after planner failure',
      language: 'en',
      durationSeconds: 60,
      segments: [
        { text: 'retry after planner failure', start: 0, end: 60 }
      ],
      words: [],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'test-whisper'
    }));
    const plan = vi
      .fn()
      .mockRejectedValueOnce(new Error('planner unavailable'))
      .mockResolvedValueOnce({
        cuts: [{ start: 30, end: 60 }],
        summary: 'keep the first half',
        model: 'test-planner'
      });
    const app = createApp({
      transcriptionProvider: { transcribe },
      editPlanProvider: { plan }
    });
    const headers = { 'x-postdee-subscription-plan': 'PRO' };
    const body = {
      videoS3Key: ownedUploadKey('local-dev-user', 'planner-retry.mp4'),
      durationSeconds: 60,
      targetDurationSeconds: 30
    };

    await request(app)
      .post('/ai-edits/prepare')
      .set(headers)
      .send(body)
      .expect(500);

    const afterFailure = await request(app)
      .get('/ai-edits/quota')
      .set(headers)
      .expect(200);
    expect(afterFailure.body.quota.usedMinutes).toBe(0);

    const retry = await request(app)
      .post('/ai-edits/prepare')
      .set(headers)
      .send(body)
      .expect(200);
    expect(retry.body.quota.usedMinutes).toBe(1);

    const afterSuccess = await request(app)
      .get('/ai-edits/quota')
      .set(headers)
      .expect(200);
    expect(afterSuccess.body.quota.usedMinutes).toBe(1);
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
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
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
          subtitleColor: '#00e5a8',
          subtitleOutlineColor: '#112233',
          subtitlePosition: 'top',
          subtitleNormalizedX: 0.25,
          subtitleNormalizedY: 0.6,
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
        style: {
          color: '#00E5A8',
          outlineColor: '#112233',
          normalizedX: 0.25,
          normalizedY: 0.6,
          position: 'middle'
        },
        segments: [
          { text: 'สวัสดีค่ะ', start: 0, end: 2 },
          { text: 'ราคา 99', start: 4, end: 5.125 },
          { text: 'บาทส่ง', start: 5.125, end: 6.0625 },
          { text: 'ฟรีวัน', start: 6.0625, end: 6.8125 },
          { text: 'นี้', start: 6.8125, end: 7 },
          { text: 'กดตะกร้า', start: 10, end: 11.75 },
          { text: 'ได้เลย', start: 11.75, end: 13 }
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
    expect(response.body.recipe.silenceRanges).toEqual([
      { start: 2, end: 4 },
      { start: 7, end: 10 }
    ]);
    expect(response.body.recipe.cutRanges).not.toContainEqual({ start: 2, end: 4 });
    expect(response.body.recipe.cutRanges).not.toContainEqual({ start: 7, end: 10 });
    expect(response.body.recipe.capabilities.subtitle.state).toBe('applied');
    expect(response.body.recipe.capabilities.silence.state).toBe('hinted');
    expect(response.body.recipe.capabilities.cta.state).toBe('planned');
    expect(response.body.recipe.capabilities.beatsync.state).toBe('planned');
    expect(response.body.recipe.capabilities.translate.state).toBe('planned');
    expect(Object.keys(response.body.recipe.subtitles.variants)).toEqual([
      '1',
      '3',
      '5'
    ]);
    expect(transcribe).toHaveBeenCalledTimes(1);
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
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
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

  it('plans on fine word-derived boundaries even when automatic captions are off',
      async () => {
    const rawText =
      'สนามฟุตบอลเหมือนทุกวันนี้มันก็เริ่มเรื่องใหม่ที่น่าสนใจมาก';
    const plan = vi.fn(async ({
      segments,
      durationSeconds,
      targetDurationSeconds
    }: {
      segments: Array<{ text: string; start: number; end: number }>;
      durationSeconds: number;
      targetDurationSeconds?: number;
    }) => {
      const completeThought = segments.find(
        (segment) => segment.text === 'ทุกวันนี้'
      );
      expect(completeThought?.start).toBe(11.136);

      const keptStart = completeThought?.start ?? 10;
      const keptEnd = keptStart + (targetDurationSeconds ?? 30);
      return {
        cuts: [
          { start: 0, end: keptStart },
          { start: keptEnd, end: durationSeconds }
        ],
        summary: 'เริ่มจากประโยคที่สมบูรณ์',
        model: 'test-fine-planner'
      };
    });
    const transcribe = vi.fn(async () => ({
      text: rawText,
      language: 'th',
      durationSeconds: 45,
      segments: [{ text: rawText, start: 10, end: 15 }],
      words: [
        { word: 'สนาม', start: 10, end: 10.35 },
        { word: 'ฟุตบอล', start: 10.35, end: 10.8 },
        { word: 'เหมือน', start: 10.8, end: 11.136 },
        { word: 'ทุก', start: 11.136, end: 11.35 },
        { word: 'วัน', start: 11.35, end: 11.55 },
        { word: 'นี้', start: 11.55, end: 11.75 },
        { word: 'มัน', start: 11.75, end: 11.95 },
        { word: 'ก็', start: 11.95, end: 12.1 },
        { word: 'เริ่ม', start: 12.1, end: 12.55 },
        { word: 'เรื่อง', start: 12.55, end: 13 },
        { word: 'ใหม่', start: 13, end: 13.35 },
        { word: 'ที่', start: 13.35, end: 13.55 },
        { word: 'น่า', start: 13.55, end: 13.85 },
        { word: 'สนใจ', start: 13.85, end: 14.3 },
        { word: 'มาก', start: 14.3, end: 15 }
      ],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'scribe_v2'
    }));
    const app = createApp({
      transcriptionProvider: { transcribe },
      editPlanProvider: { plan }
    });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'fine-boundary.mp4'),
        durationSeconds: 45,
        targetDurationSeconds: 30,
        capabilities: { subtitle: false, silence: false },
        settings: { subtitleWordsPerLine: 3 }
      })
      .expect(200);

    expect(plan).toHaveBeenCalledWith(
      expect.objectContaining({
        segments: expect.arrayContaining([
          expect.objectContaining({
            text: 'สนามฟุตบอลเหมือน',
            end: 11.136
          }),
          expect.objectContaining({
            text: 'ทุกวันนี้',
            start: 11.136
          })
        ])
      })
    );
    expect(response.body.recipe.subtitles).toMatchObject({
      enabled: false,
      segments: []
    });
    expect(response.body.recipe.plan.cuts[0]).toEqual({
      start: 0,
      end: 11.136
    });
    expect(response.body.recipe.cutRanges[0]).toEqual({
      start: 0,
      end: 11.136
    });
  });

  it('preserves coarse question and answer segments for style planning', async () => {
    const styleSegments = [
      { text: 'ใช้ยังไง?', start: 0, end: 2 },
      { text: 'เปิดฝาแล้วใช้งานได้เลย', start: 2, end: 8 }
    ];
    const plan = vi.fn(async ({
      segments
    }: {
      segments: Array<{ text: string; start: number; end: number }>;
    }) => {
      expect(segments).toEqual(styleSegments);
      return {
        cuts: [{ start: 8, end: 10 }],
        summary: 'เก็บคำถามและคำตอบครบ',
        model: 'test-style-planner'
      };
    });
    const app = createApp({
      transcriptionProvider: {
        transcribe: async () => ({
          text: 'ใช้ยังไง? เปิดฝาแล้วใช้งานได้เลย',
          language: 'th',
          durationSeconds: 10,
          segments: styleSegments,
          words: [],
          timingIntegrity: 'trusted' as const,
          hasTimedAudioEvents: false,
          model: 'scribe_v2'
        })
      },
      editPlanProvider: { plan }
    });

    await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'qa-style.mp4'),
        durationSeconds: 10,
        styleId: 'qa'
      })
      .expect(200);

    expect(plan).toHaveBeenCalledOnce();
  });

  it('preserves client segment groups for a style-only replan', async () => {
    const styleSegments = [
      { text: 'ใช้ยังไง?', start: 0, end: 2 },
      { text: 'เปิดฝาแล้วใช้งานได้เลย', start: 2, end: 8 }
    ];
    const plan = vi.fn(async ({
      segments
    }: {
      segments: Array<{ text: string; start: number; end: number }>;
    }) => {
      expect(segments).toEqual(styleSegments);
      return {
        cuts: [{ start: 8, end: 10 }],
        summary: 'เก็บคำถามและคำตอบครบ',
        model: 'test-style-planner'
      };
    });
    const app = createApp({ editPlanProvider: { plan } });

    await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 10,
        styleId: 'qa',
        segments: styleSegments
      })
      .expect(200);

    expect(plan).toHaveBeenCalledOnce();
  });

  it.each([
    ['is not an array', 'not-an-array'],
    [
      'contains an item that would previously be silently dropped',
      [
        { text: 'valid', start: 0, end: 2 },
        null
      ]
    ],
    [
      'overshoots the media duration',
      [{ text: 'overshoot', start: 0, end: 11 }]
    ],
    [
      'overlaps in raw client order',
      [
        { text: 'first', start: 0, end: 6 },
        { text: 'second', start: 5, end: 8 }
      ]
    ],
    [
      'moves backwards in raw client order',
      [
        { text: 'later', start: 5, end: 8 },
        { text: 'earlier', start: 0, end: 4 }
      ]
    ]
  ])('rejects a plan before the planner when segments %s', async (_description, segments) => {
    const plan = vi.fn(async () => ({
      cuts: [],
      summary: 'must not run',
      model: 'test-planner'
    }));
    const app = createApp({ editPlanProvider: { plan } });

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 10,
        styleId: 'flash_sale',
        segments
      })
      .expect(422);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE'
    });
    expect(plan).not.toHaveBeenCalled();
  });

  it('cleans an owned visual proxy when invalid segment timing returns 422', async () => {
    const plan = vi.fn(async () => ({
      cuts: [],
      summary: 'must not run',
      model: 'test-planner'
    }));
    const fetchClipMedia = vi.fn(async () => ({
      data: new Uint8Array([1]),
      mimeType: 'video/mp4'
    }));
    const deleteVideo = vi.fn(async () => undefined);
    const proxyKey = ownedUploadKey(
      'local-dev-user',
      'invalid-timing-proxy.mp4',
      'invalid-timing-proxy'
    );
    const app = createApp({
      editPlanProvider: { plan },
      fetchClipMedia,
      videoStorage: { ...createMockVideoStorage(), deleteVideo }
    });

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 10,
        targetDurationSeconds: 5,
        segments: [{ text: 'overshoot', start: 0, end: 11 }],
        visualProxyS3Key: proxyKey
      })
      .expect(422);

    expect(response.body.code).toBe('AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE');
    expect(plan).not.toHaveBeenCalled();
    expect(fetchClipMedia).not.toHaveBeenCalled();
    expect(deleteVideo).toHaveBeenCalledOnce();
    expect(deleteVideo).toHaveBeenCalledWith(proxyKey);
  });

  it('uses the full media timeline when ElevenLabs ends before the video', async () => {
    const plan = vi.fn(async () => ({
      cuts: [],
      summary: 'keep the selected thirty seconds',
      model: 'test-planner'
    }));
    const transcribe = vi.fn(async () => ({
      text: 'คำสุดท้ายก่อนช่วงภาพท้ายคลิป',
      language: 'th',
      durationSeconds: 148.709,
      segments: [
        {
          text: 'คำสุดท้ายก่อนช่วงภาพท้ายคลิป',
          start: 147.5,
          end: 148.709
        }
      ],
      words: [
        {
          word: 'คลิป',
          start: 148.2,
          end: 148.709
        }
      ],
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: false,
      model: 'scribe_v2'
    }));
    const app = createApp({
      transcriptionProvider: { transcribe },
      editPlanProvider: { plan }
    });

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'full-timeline.mp4'),
        durationSeconds: 150.635,
        targetDurationSeconds: 30,
        capabilities: { subtitle: true }
      })
      .expect(200);

    expect(plan).toHaveBeenCalledWith(
      expect.objectContaining({
        durationSeconds: 150.635,
        targetDurationSeconds: 30
      })
    );
    expect(response.body.recipe.transcript.durationSeconds).toBe(150.635);
    expect(response.body.recipe.transcript.words.at(-1)).toMatchObject({
      word: 'คลิป',
      end: 148.709
    });
    expect(response.body.quota.usedMinutes).toBe(3);
  });

  it('sanitizes unsupported beat music settings without claiming they were applied', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/prepare')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        videoS3Key: ownedUploadKey('local-dev-user', 'invalid-music.mp4'),
        durationSeconds: 12,
        capabilities: { beatsync: true, silence: true },
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

  it('uses an owned whole-clip proxy for visual highlight planning and cleans it',
      async () => {
    const info = vi.spyOn(console, 'info').mockImplementation(() => undefined);
    const visualPlan = vi.fn(async () => ({
      cuts: [
        { start: 0, end: 5 },
        { start: 15, end: 20 }
      ],
      summary: 'เลือกช่วงที่เห็นสินค้าและการสาธิตชัด',
      model: 'gemini-test-visual'
    }));
    const fetchClipMedia = vi.fn(async () => ({
      data: new Uint8Array([1, 2, 3]),
      mimeType: 'video/mp4'
    }));
    const deleteVideo = vi.fn(async () => undefined);
    const proxyKey = ownedUploadKey(
      'local-dev-user',
      'visual-proxy.mp4',
      'visual-proxy'
    );
    const app = createApp({
      visualEditPlanProvider: { plan: visualPlan },
      fetchClipMedia,
      videoStorage: { ...createMockVideoStorage(), deleteVideo }
    });

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 20,
        targetDurationSeconds: 10,
        segments: [
          { text: 'ใช้แล้วง่ายมาก', start: 5, end: 10 },
          { text: 'ราคา 99 บาท', start: 10, end: 15 }
        ],
        visualProxyS3Key: proxyKey
      })
      .expect(200);

    expect(visualPlan).toHaveBeenCalledWith(
      expect.objectContaining({
        durationSeconds: 20,
        targetDurationSeconds: 10,
        video: expect.objectContaining({ mimeType: 'video/mp4' })
      })
    );
    expect(visualPlan.mock.calls[0]?.[0].segments.length).toBeGreaterThan(2);
    expect(fetchClipMedia).toHaveBeenCalledOnce();
    expect(fetchClipMedia).toHaveBeenCalledWith(proxyKey);
    expect(deleteVideo).toHaveBeenCalledWith(proxyKey);
    expect(response.body.plan.model).toBe('gemini-test-visual');
    expect(info).toHaveBeenCalledWith(
      'AI visual edit planning succeeded',
      expect.objectContaining({
        model: 'gemini-test-visual',
        cutCount: 2
      })
    );
    info.mockRestore();
  });

  it('falls back to the audio planner when visual planning fails', async () => {
    const audioPlan = vi.fn(async () => ({
      cuts: [{ start: 10, end: 20 }],
      summary: 'ใช้แผนจากเสียง',
      model: 'audio-fallback'
    }));
    const visualPlan = vi.fn(async () => {
      throw new Error('Gemini unavailable');
    });
    const proxyKey = ownedUploadKey(
      'local-dev-user',
      'visual-proxy.mp4',
      'proxy-fallback'
    );
    const app = createApp({
      editPlanProvider: { plan: audioPlan },
      visualEditPlanProvider: { plan: visualPlan },
      fetchClipMedia: async () => ({
        data: new Uint8Array([1]),
        mimeType: 'video/mp4'
      })
    });

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 20,
        targetDurationSeconds: 10,
        segments: [
          {
            text: 'สนามฟุตบอลเหมือนทุกวันนี้มันก็เริ่มเรื่องใหม่',
            start: 0,
            end: 20
          }
        ],
        visualProxyS3Key: proxyKey
      })
      .expect(200);

    expect(visualPlan.mock.calls[0]?.[0].segments.length).toBeGreaterThan(1);
    expect(audioPlan).toHaveBeenCalledOnce();
    expect(audioPlan.mock.calls[0]?.[0].segments.length).toBeGreaterThan(1);
    expect(response.body.plan.model).toBe('audio-fallback');
  });

  it('rejects a visual proxy owned by another seller', async () => {
    const app = createApp();

    const response = await request(app)
      .post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({
        durationSeconds: 20,
        targetDurationSeconds: 10,
        segments: [],
        visualProxyS3Key: ownedUploadKey(
          'another-seller',
          'visual-proxy.mp4',
          'foreign-proxy'
        )
      })
      .expect(403);

    expect(response.body.code).toBe('MEDIA_KEY_FORBIDDEN');
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

