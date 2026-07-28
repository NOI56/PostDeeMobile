import { describe, expect, it, vi } from 'vitest';

import { createElevenLabsTranscriptionProvider } from './transcriptionProvider.js';

describe('media-neutral transcription input', () => {
  it('passes the complete audio input to the storage fetcher', async () => {
    const fetchAudio = vi.fn(async () => ({
      data: new Uint8Array([4, 5, 6]),
      filename: 'clip.m4a',
      contentType: 'audio/mp4'
    }));
    const provider = createElevenLabsTranscriptionProvider({
      apiKey: 'elevenlabs-key',
      model: 'scribe_v2',
      fetchAudio,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          text: 'สวัสดี',
          language_code: 'tha',
          words: [{ text: 'สวัสดี', type: 'word', start: 0, end: 1 }]
        })
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
