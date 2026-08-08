import { describe, expect, it } from 'vitest';

import { readServerConfig } from '../../config/env.js';
import {
  createElevenLabsTranscriptionProvider,
  createTranscriptionProviderFromConfig,
  createWhisperTranscriptionProvider
} from './transcriptionProvider.js';

const legacyVideoInput = (mediaS3Key: string) => ({
  mediaS3Key,
  mediaKind: 'legacy-video' as const
});

const transcribeElevenLabsPayload = async (payload: unknown) => {
  const provider = createElevenLabsTranscriptionProvider({
    apiKey: 'elevenlabs-key',
    model: 'scribe_v2',
    fetchAudio: async () => ({
      data: new Uint8Array([1]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }),
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      json: async () => payload
    })
  });

  return provider.transcribe(legacyVideoInput('uploads/provider-audit'));
};

const transcribeWhisperPayload = async (payload: unknown) => {
  const provider = createWhisperTranscriptionProvider({
    apiKey: 'oa-key',
    model: 'whisper-1',
    fetchAudio: async () => ({
      data: new Uint8Array([1]),
      filename: 'clip.mp4',
      contentType: 'video/mp4'
    }),
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      json: async () => payload
    })
  });

  return provider.transcribe(legacyVideoInput('uploads/provider-audit'));
};

describe('transcription provider', () => {
  it('returns a mock Thai transcript by default', async () => {
    const config = readServerConfig({});
    const provider = createTranscriptionProviderFromConfig({ config });

    const result = await provider.transcribe(legacyVideoInput('uploads/clip.mp4'));

    expect(result.language).toBe('th');
    expect(result.segments.length).toBeGreaterThan(0);
    expect(result.model).toBe('mock-whisper');
    expect(result.timingIntegrity).toBe('trusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it('requires an OpenAI key when TRANSCRIPTION_PROVIDER is openai', () => {
    const config = readServerConfig({ TRANSCRIPTION_PROVIDER: 'openai' });

    expect(() => createTranscriptionProviderFromConfig({ config })).toThrow(
      /OPENAI_API_KEY is required/
    );
  });

  it('requires an ElevenLabs key when selected', () => {
    const config = readServerConfig({
      TRANSCRIPTION_PROVIDER: 'elevenlabs'
    });

    expect(() =>
      createTranscriptionProviderFromConfig({
        config,
        fetchAudio: async () => ({
          data: new Uint8Array([1]),
          filename: 'clip.m4a',
          contentType: 'audio/mp4'
        })
      })
    ).toThrow(/ELEVENLABS_API_KEY is required/);
  });

  it('requires an audio fetcher when ElevenLabs is selected', () => {
    const config = readServerConfig({
      TRANSCRIPTION_PROVIDER: 'elevenlabs',
      ELEVENLABS_API_KEY: 'elevenlabs-key'
    });

    expect(() => createTranscriptionProviderFromConfig({ config })).toThrow(
      /fetchAudio implementation is required for ElevenLabs/
    );
  });

  it('calls Whisper with the fetched audio and parses word timing', async () => {
    const calls: { url: string; prompt?: string }[] = [];
    const provider = createWhisperTranscriptionProvider({
      apiKey: 'oa-key',
      model: 'whisper-1',
      fetchAudio: async (input) => ({
        data: new Uint8Array([1, 2, 3]),
        filename: `${input.mediaS3Key}.mp4`,
        contentType: 'video/mp4'
      }),
      fetchImpl: async (url, init) => {
        const form = init.body as FormData;
        calls.push({
          url,
          prompt: form.get('prompt')?.toString()
        });
        return {
          ok: true,
          status: 200,
          json: async () => ({
            text: 'สวัสดีค่ะ',
            language: 'Thai',
            duration: 3.2,
            segments: [{ text: ' สวัสดีค่ะ ', start: 0, end: 3.2 }],
            words: [{ word: 'สวัสดีค่ะ', start: 0.1, end: 1.2 }]
          })
        };
      }
    });

    const result = await provider.transcribe(legacyVideoInput('uploads/clip'));

    expect(calls[0].url).toBe('https://api.openai.com/v1/audio/transcriptions');
    expect(calls[0].prompt).toBeUndefined();
    expect(result.text).toBe('สวัสดีค่ะ');
    expect(result.language).toBe('th');
    expect(result.durationSeconds).toBe(3.2);
    expect(result.segments[0]).toEqual({ text: 'สวัสดีค่ะ', start: 0, end: 3.2 });
    expect(result.words[0]).toEqual({ word: 'สวัสดีค่ะ', start: 0.1, end: 1.2 });
    expect(result.timingIntegrity).toBe('trusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it('does not manufacture zero timing for malformed Whisper evidence', async () => {
    const result = await transcribeWhisperPayload({
      text: 'hello',
      language: 'th',
      duration: 3,
      segments: [{ text: 'hello', end: 1 }],
      words: [{ word: 'hello', end: 1 }]
    });

    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.hasTimedAudioEvents).toBe(false);
    expect(result.segments).toEqual([]);
    expect(result.words).toEqual([]);
  });

  it.each([
    {
      name: 'non-array segments',
      payload: { text: '', duration: 3, segments: 'invalid', words: [] }
    },
    {
      name: 'non-array words',
      payload: { text: '', duration: 3, segments: [], words: 'invalid' }
    },
    {
      name: 'overlapping segments',
      payload: {
        text: 'one two',
        duration: 3,
        segments: [
          { text: 'one', start: 0, end: 2 },
          { text: 'two', start: 1, end: 3 }
        ],
        words: []
      }
    },
    {
      name: 'backwards words',
      payload: {
        text: 'one two',
        duration: 3,
        segments: [],
        words: [
          { word: 'one', start: 2, end: 3 },
          { word: 'two', start: 0, end: 1 }
        ]
      }
    }
  ])('marks Whisper timing untrusted for $name', async ({ payload }) => {
    const result = await transcribeWhisperPayload(payload);

    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it.each([
    {
      name: 'segment-only timing',
      payload: {
        text: 'hello world',
        duration: 3,
        segments: [{ text: 'hello world', start: 0, end: 2 }]
      }
    },
    {
      name: 'word-only timing',
      payload: {
        text: 'hello world',
        duration: 3,
        words: [
          { word: 'hello', start: 0, end: 1 },
          { word: 'world', start: 1, end: 2 }
        ]
      }
    }
  ])('trusts complete OpenAI $name evidence', async ({ payload }) => {
    const result = await transcribeWhisperPayload(payload);

    expect(result.timingIntegrity).toBe('trusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it('distrusts nonempty OpenAI text when both timing streams are empty', async () => {
    const result = await transcribeWhisperPayload({
      text: 'hello world',
      duration: 3,
      segments: [],
      words: []
    });

    expect(result.timingIntegrity).toBe('untrusted');
  });

  it('distrusts OpenAI timing when both streams omit middle speech', async () => {
    const result = await transcribeWhisperPayload({
      text: 'one missing two',
      duration: 4,
      segments: [
        { text: 'one', start: 0, end: 1 },
        { text: 'two', start: 3, end: 4 }
      ],
      words: [
        { word: 'one', start: 0, end: 1 },
        { word: 'two', start: 3, end: 4 }
      ]
    });

    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.segments).toHaveLength(2);
    expect(result.words).toHaveLength(2);
  });

  it('trusts OpenAI timing when one complete stream covers a partial stream', async () => {
    const result = await transcribeWhisperPayload({
      text: 'one middle two',
      duration: 4,
      segments: [{ text: 'one middle two', start: 0, end: 4 }],
      words: [
        { word: 'one', start: 0, end: 1 },
        { word: 'two', start: 3, end: 4 }
      ]
    });

    expect(result.timingIntegrity).toBe('trusted');
  });

  it('throws when Whisper responds with an error', async () => {
    const provider = createWhisperTranscriptionProvider({
      apiKey: 'oa-key',
      model: 'whisper-1',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.mp4',
        contentType: 'video/mp4'
      }),
      fetchImpl: async () => ({ ok: false, status: 500, json: async () => ({}) })
    });

    await expect(provider.transcribe(legacyVideoInput('k'))).rejects.toThrow(
      /Whisper transcription failed with status 500/
    );
  });

  it('calls ElevenLabs Scribe with keyterms and normalizes timed words', async () => {
    const calls: Array<{
      url: string;
      apiKey?: string;
      modelId?: string;
      languageCode?: string;
      tagAudioEvents?: string;
      keyterms: string[];
    }> = [];
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      keyterms: ['PostDee', 'ปักตะกร้า'],
      fetchAudio: async () => ({
        data: new Uint8Array([1, 2, 3]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      }),
      fetchImpl: async (url, init) => {
        const form = init.body as FormData;
        calls.push({
          url,
          apiKey: (init.headers as Record<string, string>)['xi-api-key'],
          modelId: form.get('model_id')?.toString(),
          languageCode: form.get('language_code')?.toString(),
          tagAudioEvents: form.get('tag_audio_events')?.toString(),
          keyterms: form.getAll('keyterms').map((value) => value.toString())
        });
        return {
          ok: true,
          status: 200,
          json: async () => ({
            language_code: 'tha',
            text: 'วันนี้ลด Weekend Market ค่ะ',
            words: [
              { type: 'word', text: 'วันนี้ลด', start: 0.1, end: 0.7 },
              { type: 'spacing', text: ' ' },
              { type: 'word', text: 'Weekend', start: 0.8, end: 1.2 },
              { type: 'spacing', text: ' ' },
              { type: 'word', text: 'Market', start: 1.25, end: 1.6 },
              { type: 'audio_event', text: '(music)', start: 1.6, end: 1.9 },
              { type: 'spacing', text: ' ' },
              { type: 'word', text: 'ค่ะ', start: 2.3, end: 2.6 }
            ]
          })
        };
      }
    });

    const result = await provider.transcribe(
      legacyVideoInput('uploads/elevenlabs-clip')
    );

    expect(calls).toEqual([
      {
        url: 'https://api.elevenlabs.io/v1/speech-to-text',
        apiKey: 'elevenlabs-key',
        modelId: 'scribe_v2',
        languageCode: 'th',
        tagAudioEvents: 'true',
        keyterms: ['PostDee', 'ปักตะกร้า']
      }
    ]);
    expect(result).toMatchObject({
      text: 'วันนี้ลด Weekend Market ค่ะ',
      language: 'th',
      durationSeconds: 2.6,
      model: 'scribe_v2',
      timingIntegrity: 'trusted',
      hasTimedAudioEvents: true
    });
    expect(result.words).toEqual([
      { word: 'วันนี้ลด', start: 0.1, end: 0.7 },
      { word: 'Weekend', start: 0.8, end: 1.2 },
      { word: 'Market', start: 1.25, end: 1.6 },
      { word: 'ค่ะ', start: 2.3, end: 2.6 }
    ]);
    expect(result.segments).toEqual([
      {
        text: 'วันนี้ลด Weekend Market',
        start: 0.1,
        end: 1.6
      },
      { text: 'ค่ะ', start: 2.3, end: 2.6 }
    ]);
  });

  it('keeps valid ElevenLabs display words but distrusts a malformed middle word', async () => {
    const result = await transcribeElevenLabsPayload({
      language_code: 'tha',
      text: 'ชุมชน เอ่อ ชุมชน',
      words: [
        { type: 'word', text: 'ชุมชน', start: 0, end: 1 },
        { type: 'spacing', text: ' ' },
        { type: 'word', text: 'เอ่อ', start: 1.1 },
        { type: 'spacing', text: ' ' },
        { type: 'word', text: 'ชุมชน', start: 2, end: 3 }
      ]
    });

    expect(result.text).toBe('ชุมชน เอ่อ ชุมชน');
    expect(result.words).toEqual([
      { word: 'ชุมชน', start: 0, end: 1 },
      { word: 'ชุมชน', start: 2, end: 3 }
    ]);
    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it.each([
    { name: 'missing words array', words: undefined },
    { name: 'non-array words', words: 'invalid' },
    { name: 'non-object item', words: [null] },
    { name: 'unknown item type', words: [{ type: 'speaker', text: 'A' }] }
  ])('marks ElevenLabs timing untrusted for $name', async ({ words }) => {
    const result = await transcribeElevenLabsPayload({ text: '', words });

    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it.each([
    {
      name: 'empty word text',
      words: [{ type: 'word', text: ' ', start: 0, end: 1 }]
    },
    {
      name: 'non-finite start',
      words: [{ type: 'word', text: 'x', start: Number.NaN, end: 1 }]
    },
    {
      name: 'non-finite end',
      words: [{ type: 'word', text: 'x', start: 0, end: Number.POSITIVE_INFINITY }]
    },
    {
      name: 'negative start',
      words: [{ type: 'word', text: 'x', start: -1, end: 1 }]
    },
    {
      name: 'zero duration',
      words: [{ type: 'word', text: 'x', start: 1, end: 1 }]
    },
    {
      name: 'negative duration',
      words: [{ type: 'word', text: 'x', start: 2, end: 1 }]
    },
    {
      name: 'backwards order',
      words: [
        { type: 'word', text: 'x', start: 2, end: 3 },
        { type: 'word', text: 'y', start: 0, end: 1 }
      ]
    },
    {
      name: 'overlap',
      words: [
        { type: 'word', text: 'x', start: 0, end: 2 },
        { type: 'word', text: 'y', start: 1, end: 3 }
      ]
    },
    {
      name: 'malformed audio event',
      words: [{ type: 'audio_event', text: '(music)', start: 0 }]
    },
    {
      name: 'malformed spacing',
      words: [{ type: 'spacing', text: 42 }]
    },
    {
      name: 'overlapping audio event',
      words: [
        { type: 'word', text: 'x', start: 0, end: 2 },
        { type: 'audio_event', text: '(music)', start: 1, end: 3 }
      ]
    }
  ])('marks invalid ElevenLabs timing untrusted for $name', async ({ words }) => {
    const result = await transcribeElevenLabsPayload({ text: '', words });

    expect(result.timingIntegrity).toBe('untrusted');
  });

  it('accepts valid ElevenLabs spacing without treating it as an audio event', async () => {
    const result = await transcribeElevenLabsPayload({
      text: '  hello   world  ',
      words: [
        { type: 'word', text: 'hello', start: 0, end: 1 },
        { type: 'spacing', text: ' ' },
        { type: 'word', text: 'world', start: 1, end: 2 }
      ]
    });

    expect(result.timingIntegrity).toBe('trusted');
    expect(result.hasTimedAudioEvents).toBe(false);
  });

  it('uses valid timed audio events as a repeat-safety barrier', async () => {
    const result = await transcribeElevenLabsPayload({
      text: 'hello (laughter) world',
      words: [
        { type: 'word', text: 'hello', start: 0, end: 1 },
        { type: 'audio_event', text: '(laughter)', start: 1, end: 1.5 },
        { type: 'spacing', text: ' ' },
        { type: 'word', text: 'world', start: 1.5, end: 2 }
      ]
    });

    expect(result.timingIntegrity).toBe('trusted');
    expect(result.hasTimedAudioEvents).toBe(true);
  });

  it('distrusts ElevenLabs timing when semantic word coverage is incomplete', async () => {
    const result = await transcribeElevenLabsPayload({
      text: 'ชุมชน เอ่อ ชุมชน',
      words: [
        { type: 'word', text: 'ชุมชน', start: 0, end: 1 },
        { type: 'spacing', text: ' ' },
        { type: 'word', text: 'ชุมชน', start: 2, end: 3 }
      ]
    });

    expect(result.timingIntegrity).toBe('untrusted');
    expect(result.words).toHaveLength(2);
  });

  it('does not split an ElevenLabs Thai word at a forced segment boundary', async () => {
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      }),
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          language_code: 'tha',
          text: 'ต่างๆก็จะมีอาหารที่ต้องการ',
          words: [
            {
              type: 'word',
              text: 'ต่างๆก็จะมีอาห',
              start: 0,
              end: 4.1
            },
            {
              type: 'word',
              text: 'ารที่ต้องการ',
              start: 4.1,
              end: 5.2
            }
          ]
        })
      })
    });

    const result = await provider.transcribe(
      legacyVideoInput('uploads/thai-mid-word-boundary')
    );

    expect(result.segments).toEqual([
      {
        text: 'ต่างๆก็จะมีอาหารที่ต้องการ',
        start: 0,
        end: 5.2
      }
    ]);
  });

  it('uses an emergency cap for one unknown token split into many events', async () => {
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      }),
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          language_code: 'tha',
          text: 'x'.repeat(100),
          words: Array.from({ length: 100 }, (_, index) => ({
            type: 'word',
            text: 'x',
            start: index * 0.1,
            end: (index + 1) * 0.1
          }))
        })
      })
    });

    const result = await provider.transcribe(
      legacyVideoInput('uploads/unknown-long-token')
    );

    expect(result.segments.length).toBeGreaterThan(1);
    expect(
      result.segments.every(
        (segment) =>
          segment.end - segment.start <= 8 + Number.EPSILON &&
          segment.text.length <= 64
      )
    ).toBe(true);
    expect(result.segments.map((segment) => segment.text).join('')).toBe(
      'x'.repeat(100)
    );
  });

  it('does not bridge an unusually long pause inside an unknown token', async () => {
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      }),
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          language_code: 'tha',
          text: 'ชีวิต',
          words: [
            { type: 'word', text: 'ชีวิ', start: 0, end: 1 },
            { type: 'word', text: 'ต', start: 3.1, end: 3.5 }
          ]
        })
      })
    });

    const result = await provider.transcribe(
      legacyVideoInput('uploads/unknown-token-long-pause')
    );

    expect(result.segments).toEqual([
      { text: 'ชีวิ', start: 0, end: 1 },
      { text: 'ต', start: 3.1, end: 3.5 }
    ]);
  });

  it('reports ElevenLabs provider failures without exposing the response body', async () => {
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.m4a',
        contentType: 'audio/mp4'
      }),
      fetchImpl: async () => ({
        ok: false,
        status: 429,
        json: async () => ({ detail: 'provider-secret-detail' })
      })
    });

    await expect(
      provider.transcribe(legacyVideoInput('uploads/rate-limited'))
    ).rejects.toThrow('ElevenLabs transcription failed with status 429');
  });
});
