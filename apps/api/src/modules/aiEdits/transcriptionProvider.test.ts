import { describe, expect, it } from 'vitest';

import { readServerConfig } from '../../config/env.js';
import {
  createElevenLabsTranscriptionProvider,
  createGroqTranscriptionProvider,
  createTranscriptionProviderFromConfig,
  createWhisperTranscriptionProvider
} from './transcriptionProvider.js';

const legacyVideoInput = (mediaS3Key: string) => ({
  mediaS3Key,
  mediaKind: 'legacy-video' as const
});

const transcribeElevenLabsFixture = async (
  words: Array<Record<string, unknown>>,
  text = words.map((entry) => entry.text ?? '').join('')
) => {
  const provider = createElevenLabsTranscriptionProvider({
    apiKey: 'elevenlabs-key',
    model: 'scribe_v2',
    fetchAudio: async () => ({
      data: new Uint8Array([1, 2, 3]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }),
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        language_code: 'tha',
        text,
        words
      })
    })
  });

  return provider.transcribe(legacyVideoInput('uploads/elevenlabs-clip'));
};

describe('transcription provider', () => {
  it('returns a mock Thai transcript by default', async () => {
    const config = readServerConfig({});
    const provider = createTranscriptionProviderFromConfig({ config });

    const result = await provider.transcribe(legacyVideoInput('uploads/clip.mp4'));

    expect(result.language).toBe('th');
    expect(result.segments.length).toBeGreaterThan(0);
    expect(result.model).toBe('mock-whisper');
  });

  it('requires an OpenAI key when TRANSCRIPTION_PROVIDER is openai', () => {
    const config = readServerConfig({ TRANSCRIPTION_PROVIDER: 'openai' });

    expect(() => createTranscriptionProviderFromConfig({ config })).toThrow(
      /OPENAI_API_KEY is required/
    );
  });

  it('requires a Groq key when TRANSCRIPTION_PROVIDER is groq', () => {
    const config = readServerConfig({ TRANSCRIPTION_PROVIDER: 'groq' });

    expect(() =>
      createTranscriptionProviderFromConfig({
        config,
        fetchAudio: async () => ({
          data: new Uint8Array([1]),
          filename: 'clip.mp4',
          contentType: 'video/mp4'
        })
      })
    ).toThrow(/GROQ_API_KEY is required/);
  });

  it('requires an ElevenLabs key when TRANSCRIPTION_PROVIDER is elevenlabs', () => {
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

  it('requires fetched media when TRANSCRIPTION_PROVIDER is elevenlabs', () => {
    const config = readServerConfig({
      TRANSCRIPTION_PROVIDER: 'elevenlabs',
      ELEVENLABS_API_KEY: 'elevenlabs-key'
    });

    expect(() => createTranscriptionProviderFromConfig({ config })).toThrow(
      /fetchAudio implementation is required for ElevenLabs transcription/
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

  it('calls Groq with the fetched audio and top transcription model', async () => {
    const calls: {
      url: string;
      auth?: string;
      language?: string;
      prompt?: string;
      responseFormat?: string;
      timestampGranularities: string[];
    }[] = [];
    const provider = createGroqTranscriptionProvider({
      apiKey: 'groq-key',
      model: 'whisper-large-v3',
      fetchAudio: async (input) => ({
        data: new Uint8Array([4, 5, 6]),
        filename: `${input.mediaS3Key}.mp4`,
        contentType: 'video/mp4'
      }),
      fetchImpl: async (url, init) => {
        const form = init.body as FormData;
        calls.push({
          url,
          auth: (init.headers as Record<string, string>).Authorization,
          language: form.get('language')?.toString(),
          prompt: form.get('prompt')?.toString(),
          responseFormat: form.get('response_format')?.toString(),
          timestampGranularities: form
            .getAll('timestamp_granularities[]')
            .map((value) => value.toString())
        });
        return {
          ok: true,
          status: 200,
          json: async () => ({
            text: 'สวัสดีค่ะ',
            language: 'Thai',
            duration: 2.5,
            segments: [
              {
                text: ' สวัสดีค่ะ ',
                start: 0,
                end: 2.5,
                avg_logprob: -0.2,
                no_speech_prob: 0.01,
                compression_ratio: 1.1
              }
            ],
            words: [{ word: 'สวัสดีค่ะ', start: 0.2, end: 1.8 }]
          })
        };
      }
    });

    const result = await provider.transcribe(legacyVideoInput('uploads/groq-clip'));

    expect(calls[0]).toEqual({
      url: 'https://api.groq.com/openai/v1/audio/transcriptions',
      auth: 'Bearer groq-key',
      language: 'th',
      prompt: undefined,
      responseFormat: 'verbose_json',
      timestampGranularities: ['word', 'segment']
    });
    expect(result).toMatchObject({
      text: 'สวัสดีค่ะ',
      language: 'th',
      durationSeconds: 2.5,
      model: 'whisper-large-v3'
    });
    expect(result.segments[0]).toEqual({
      text: 'สวัสดีค่ะ',
      start: 0,
      end: 2.5,
      avgLogprob: -0.2,
      noSpeechProbability: 0.01,
      compressionRatio: 1.1
    });
    expect(result.words[0]).toEqual({ word: 'สวัสดีค่ะ', start: 0.2, end: 1.8 });
  });

  it('throws when Groq responds with an error', async () => {
    const provider = createGroqTranscriptionProvider({
      apiKey: 'groq-key',
      model: 'whisper-large-v3',
      fetchAudio: async () => ({
        data: new Uint8Array([1]),
        filename: 'clip.mp4',
        contentType: 'video/mp4'
      }),
      fetchImpl: async () => ({ ok: false, status: 429, json: async () => ({}) })
    });

    await expect(provider.transcribe(legacyVideoInput('k'))).rejects.toThrow(
      /Groq transcription failed with status 429/
    );
  });

  it('calls ElevenLabs Scribe v2 and normalizes timed words', async () => {
    const calls: Array<{
      url: string;
      apiKey?: string;
      modelId?: string;
      languageCode?: string;
      timestampGranularity?: string;
      tagAudioEvents?: string;
      diarize?: string;
      noVerbatim?: string;
    }> = [];
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
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
          timestampGranularity: form.get('timestamps_granularity')?.toString(),
          tagAudioEvents: form.get('tag_audio_events')?.toString(),
          diarize: form.get('diarize')?.toString(),
          noVerbatim: form.get('no_verbatim')?.toString()
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
              { type: 'spacing', text: ' ' },
              { type: 'audio_event', text: '(music)', start: 1.6, end: 1.9 },
              { type: 'word', text: 'ค่ะ', start: 2.3, end: 2.6 }
            ]
          })
        };
      }
    });

    const result = await provider.transcribe(
      legacyVideoInput('uploads/elevenlabs-clip')
    );

    expect(calls[0]).toEqual({
      url: 'https://api.elevenlabs.io/v1/speech-to-text',
      apiKey: 'elevenlabs-key',
      modelId: 'scribe_v2',
      languageCode: 'th',
      timestampGranularity: 'word',
      tagAudioEvents: 'false',
      diarize: 'false',
      noVerbatim: 'false'
    });
    expect(result).toMatchObject({
      text: 'วันนี้ลด Weekend Market ค่ะ',
      language: 'th',
      durationSeconds: 2.6,
      model: 'scribe_v2'
    });
    expect(result.words).toEqual([
      { word: 'วันนี้ลด', start: 0.1, end: 0.7 },
      { word: 'Weekend', start: 0.8, end: 1.2 },
      { word: 'Market', start: 1.25, end: 1.6 },
      { word: 'ค่ะ', start: 2.3, end: 2.6 }
    ]);
    expect(result.segments.map((segment) => segment.text)).toEqual([
      'วันนี้ลด Weekend Market',
      'ค่ะ'
    ]);
  });

  it.each([
    [
      'punctuation',
      [
        { type: 'word', text: 'จริงไหม?', start: 0, end: 0.8 },
        { type: 'word', text: 'จริงค่ะ', start: 0.9, end: 1.6 }
      ],
      ['จริงไหม?', 'จริงค่ะ']
    ],
    [
      'pause',
      [
        { type: 'word', text: 'ช่วงแรก', start: 0, end: 0.8 },
        { type: 'word', text: 'ช่วงใหม่', start: 1.36, end: 2 }
      ],
      ['ช่วงแรก', 'ช่วงใหม่']
    ],
    [
      'duration',
      [
        { type: 'word', text: 'หนึ่ง', start: 0, end: 1.5 },
        { type: 'word', text: 'สอง', start: 1.6, end: 3 },
        { type: 'word', text: 'สาม', start: 3.1, end: 4.1 },
        { type: 'word', text: 'สี่', start: 4.2, end: 4.8 }
      ],
      ['หนึ่งสองสาม', 'สี่']
    ]
  ])(
    'splits ElevenLabs segments at the %s boundary',
    async (_, words, texts) => {
      const result = await transcribeElevenLabsFixture(words);
      expect(result.segments.map((segment) => segment.text)).toEqual(texts);
    }
  );

  it('splits ElevenLabs segments at 32 Thai graphemes', async () => {
    const longWord = 'ก'.repeat(32);
    const result = await transcribeElevenLabsFixture([
      { type: 'word', text: longWord, start: 0, end: 1 },
      { type: 'word', text: 'ต่อ', start: 1.1, end: 1.5 }
    ]);

    expect(result.segments.map((segment) => segment.text)).toEqual([
      longWord,
      'ต่อ'
    ]);
  });

  it('drops malformed and non-word ElevenLabs events', async () => {
    const result = await transcribeElevenLabsFixture([
      { type: 'word', text: 'ถูก', start: 0.1, end: 0.4 },
      { type: 'word', text: 'ไม่มีเวลา' },
      { type: 'word', text: 'ติดลบ', start: -1, end: 0.2 },
      { type: 'word', text: 'กลับด้าน', start: 1, end: 0.5 },
      { type: 'word', text: 'ไม่ใช่เลข', start: '1', end: 2 },
      { type: 'audio_event', text: '(music)', start: 0.4, end: 1 }
    ]);

    expect(result.words).toEqual([{ word: 'ถูก', start: 0.1, end: 0.4 }]);
    expect(result.segments).toEqual([
      { text: 'ถูก', start: 0.1, end: 0.4 }
    ]);
  });

  it('returns an empty transcript for an empty ElevenLabs success response', async () => {
    const result = await transcribeElevenLabsFixture([], '');

    expect(result).toMatchObject({
      text: '',
      durationSeconds: 0,
      segments: [],
      words: []
    });
  });

  it('throws when ElevenLabs responds with an error', async () => {
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
        json: async () => ({})
      })
    });

    await expect(
      provider.transcribe(legacyVideoInput('uploads/clip'))
    ).rejects.toThrow(/ElevenLabs transcription failed with status 429/);
  });
});
