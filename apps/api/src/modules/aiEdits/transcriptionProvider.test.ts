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
        keyterms: ['PostDee', 'ปักตะกร้า']
      }
    ]);
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
    expect(result.segments).toEqual([
      {
        text: 'วันนี้ลด Weekend Market',
        start: 0.1,
        end: 1.6
      },
      { text: 'ค่ะ', start: 2.3, end: 2.6 }
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
