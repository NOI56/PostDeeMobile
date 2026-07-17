import { describe, expect, it, vi } from 'vitest';

import { createGroqTranscriptionProvider } from './transcriptionProvider.js';

describe('media-neutral transcription input', () => {
  it('passes the complete audio input to the storage fetcher', async () => {
    const fetchAudio = vi.fn(async () => ({
      data: new Uint8Array([4, 5, 6]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }));
    const provider = createGroqTranscriptionProvider({
      apiKey: 'groq-key',
      model: 'whisper-large-v3',
      fetchAudio,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({ text: 'สวัสดี', language: 'th', duration: 1 })
      })
    });
    const input = {
      mediaS3Key: 'uploads/local-dev-user/audio/clip.m4a',
      mediaKind: 'audio'
    } as const;

    await provider.transcribe(input);

    expect(fetchAudio).toHaveBeenCalledWith(input);
  });
});
