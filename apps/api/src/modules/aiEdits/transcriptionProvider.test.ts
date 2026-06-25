import { describe, expect, it } from 'vitest';

import { readServerConfig } from '../../config/env.js';
import {
  createGroqTranscriptionProvider,
  createTranscriptionProviderFromConfig,
  createWhisperTranscriptionProvider
} from './transcriptionProvider.js';

describe('transcription provider', () => {
  it('returns a mock Thai transcript by default', async () => {
    const config = readServerConfig({});
    const provider = createTranscriptionProviderFromConfig({ config });

    const result = await provider.transcribe({ videoS3Key: 'uploads/clip.mp4' });

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

  it('calls Whisper with the fetched audio and parses word timing', async () => {
    const calls: { url: string }[] = [];
    const provider = createWhisperTranscriptionProvider({
      apiKey: 'oa-key',
      model: 'whisper-1',
      fetchAudio: async (key) => ({
        data: new Uint8Array([1, 2, 3]),
        filename: `${key}.mp4`,
        contentType: 'video/mp4'
      }),
      fetchImpl: async (url) => {
        calls.push({ url });
        return {
          ok: true,
          status: 200,
          json: async () => ({
            text: 'สวัสดีค่ะ',
            language: 'th',
            duration: 3.2,
            segments: [{ text: ' สวัสดีค่ะ ', start: 0, end: 3.2 }],
            words: [{ word: 'สวัสดีค่ะ', start: 0.1, end: 1.2 }]
          })
        };
      }
    });

    const result = await provider.transcribe({ videoS3Key: 'uploads/clip' });

    expect(calls[0].url).toBe('https://api.openai.com/v1/audio/transcriptions');
    expect(result.text).toBe('สวัสดีค่ะ');
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

    await expect(provider.transcribe({ videoS3Key: 'k' })).rejects.toThrow(
      /Whisper transcription failed with status 500/
    );
  });

  it('calls Groq with the fetched audio and top transcription model', async () => {
    const calls: { url: string; auth?: string }[] = [];
    const provider = createGroqTranscriptionProvider({
      apiKey: 'groq-key',
      model: 'whisper-large-v3',
      fetchAudio: async (key) => ({
        data: new Uint8Array([4, 5, 6]),
        filename: `${key}.mp4`,
        contentType: 'video/mp4'
      }),
      fetchImpl: async (url, init) => {
        calls.push({
          url,
          auth: (init.headers as Record<string, string>).Authorization
        });
        return {
          ok: true,
          status: 200,
          json: async () => ({
            text: 'สวัสดีค่ะ',
            language: 'th',
            duration: 2.5,
            segments: [{ text: ' สวัสดีค่ะ ', start: 0, end: 2.5 }],
            words: [{ word: 'สวัสดีค่ะ', start: 0.2, end: 1.8 }]
          })
        };
      }
    });

    const result = await provider.transcribe({ videoS3Key: 'uploads/groq-clip' });

    expect(calls[0]).toEqual({
      url: 'https://api.groq.com/openai/v1/audio/transcriptions',
      auth: 'Bearer groq-key'
    });
    expect(result).toMatchObject({
      text: 'สวัสดีค่ะ',
      language: 'th',
      durationSeconds: 2.5,
      model: 'whisper-large-v3'
    });
    expect(result.segments[0]).toEqual({ text: 'สวัสดีค่ะ', start: 0, end: 2.5 });
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

    await expect(provider.transcribe({ videoS3Key: 'k' })).rejects.toThrow(
      /Groq transcription failed with status 429/
    );
  });
});
