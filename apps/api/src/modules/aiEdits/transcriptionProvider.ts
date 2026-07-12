import type { ServerConfig } from '../../config/env.js';

export type TranscriptWord = { word: string; start: number; end: number };
export type TranscriptSegment = { text: string; start: number; end: number };

export type TranscriptionResult = {
  text: string;
  language: string;
  durationSeconds: number;
  segments: TranscriptSegment[];
  words: TranscriptWord[];
  model: string;
};

export type TranscriptionInput = { videoS3Key: string };

export type TranscriptionProvider = {
  transcribe: (input: TranscriptionInput) => Promise<TranscriptionResult>;
};

export type AudioSource = {
  data: Uint8Array;
  filename: string;
  contentType: string;
};

/** Downloads the clip audio/video bytes for a stored key (e.g. from R2). */
export type FetchAudio = (videoS3Key: string) => Promise<AudioSource>;

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

type TranscriptionApiResponse = {
  text?: string;
  language?: string;
  duration?: number;
  segments?: Array<{ text?: string; start?: number; end?: number }>;
  words?: Array<{ word?: string; start?: number; end?: number }>;
};

export const createMockTranscriptionProvider = (): TranscriptionProvider => ({
  transcribe: async () => ({
    text: 'สวัสดีค่ะ วันนี้มีของดีมาแนะนำ สินค้าตัวนี้ขายดีมากบอกเลย กดลิงก์ในไบโอสั่งได้เลยนะคะ',
    language: 'th',
    durationSeconds: 18,
    segments: [
      { text: 'สวัสดีค่ะ วันนี้มีของดีมาแนะนำ', start: 0, end: 6 },
      { text: 'สินค้าตัวนี้ขายดีมากบอกเลย', start: 6, end: 12 },
      { text: 'กดลิงก์ในไบโอสั่งได้เลยนะคะ', start: 12, end: 18 }
    ],
    words: [],
    model: 'mock-whisper'
  })
});

const createOpenAiCompatibleTranscriptionProvider = ({
  apiKey,
  model,
  fetchAudio,
  fetchImpl = fetch as unknown as FetchImpl,
  endpointUrl,
  failureLabel
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
  endpointUrl: string;
  failureLabel: string;
}): TranscriptionProvider => ({
  transcribe: async ({ videoS3Key }) => {
    const audio = await fetchAudio(videoS3Key);
    const form = new FormData();
    form.append(
      'file',
      new Blob([audio.data], { type: audio.contentType }),
      audio.filename
    );
    form.append('model', model);
    form.append('response_format', 'verbose_json');
    form.append('timestamp_granularities[]', 'word');
    form.append('timestamp_granularities[]', 'segment');

    const response = await fetchImpl(endpointUrl, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form as unknown as RequestInit['body']
    });

    if (!response.ok) {
      throw new Error(
        `${failureLabel} failed with status ${response.status ?? 'unknown'}`
      );
    }

    const payload = (await response.json()) as TranscriptionApiResponse;

    return {
      text: payload.text ?? '',
      language: payload.language ?? 'th',
      durationSeconds: payload.duration ?? 0,
      segments: (payload.segments ?? []).map((segment) => ({
        text: (segment.text ?? '').trim(),
        start: segment.start ?? 0,
        end: segment.end ?? 0
      })),
      words: (payload.words ?? []).map((word) => ({
        word: word.word ?? '',
        start: word.start ?? 0,
        end: word.end ?? 0
      })),
      model
    };
  }
});

/**
 * Real Thai transcription via OpenAI Whisper. Used when
 * TRANSCRIPTION_PROVIDER=openai and OPENAI_API_KEY is set. `fetchAudio` must
 * return the clip's audio/video bytes (e.g. downloaded from Cloudflare R2);
 * Whisper needs the media, not the storage key.
 */
export const createWhisperTranscriptionProvider = ({
  apiKey,
  model,
  fetchAudio,
  fetchImpl
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
}): TranscriptionProvider =>
  createOpenAiCompatibleTranscriptionProvider({
    apiKey,
    model,
    fetchAudio,
    fetchImpl,
    endpointUrl: 'https://api.openai.com/v1/audio/transcriptions',
    failureLabel: 'Whisper transcription'
  });

/**
 * Real Thai transcription via Groq's OpenAI-compatible speech-to-text API.
 * `whisper-large-v3` is the default top-quality Groq model.
 */
export const createGroqTranscriptionProvider = ({
  apiKey,
  model,
  fetchAudio,
  fetchImpl
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
}): TranscriptionProvider =>
  createOpenAiCompatibleTranscriptionProvider({
    apiKey,
    model,
    fetchAudio,
    fetchImpl,
    endpointUrl: 'https://api.groq.com/openai/v1/audio/transcriptions',
    failureLabel: 'Groq transcription'
  });

export const createTranscriptionProviderFromConfig = ({
  config,
  fetchAudio
}: {
  config: Pick<
    ServerConfig,
    | 'transcriptionProvider'
    | 'openAiApiKey'
    | 'whisperModel'
    | 'groqApiKey'
    | 'groqTranscriptionModel'
  >;
  fetchAudio?: FetchAudio;
}): TranscriptionProvider => {
  if (config.transcriptionProvider === 'openai') {
    if (!config.openAiApiKey) {
      throw new Error('OPENAI_API_KEY is required when TRANSCRIPTION_PROVIDER is openai');
    }

    if (!fetchAudio) {
      throw new Error('A fetchAudio implementation is required for Whisper transcription');
    }

    return createWhisperTranscriptionProvider({
      apiKey: config.openAiApiKey,
      model: config.whisperModel,
      fetchAudio
    });
  }

  if (config.transcriptionProvider === 'groq') {
    if (!config.groqApiKey) {
      throw new Error('GROQ_API_KEY is required when TRANSCRIPTION_PROVIDER is groq');
    }

    if (!fetchAudio) {
      throw new Error('A fetchAudio implementation is required for Groq transcription');
    }

    return createGroqTranscriptionProvider({
      apiKey: config.groqApiKey,
      model: config.groqTranscriptionModel,
      fetchAudio
    });
  }

  return createMockTranscriptionProvider();
};
