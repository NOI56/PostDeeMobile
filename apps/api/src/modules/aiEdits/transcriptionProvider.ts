import type { ServerConfig } from '../../config/env.js';

export type TranscriptWord = { word: string; start: number; end: number };
export type TranscriptSegment = {
  text: string;
  start: number;
  end: number;
  avgLogprob?: number;
  noSpeechProbability?: number;
  compressionRatio?: number;
};

const leakedTranscriptionPromptSignals = [
  'ชื่อแอปให้เขียนเป็นภาษาไทยว่า',
  'คำศัพท์เฉพาะ'
];
const unexpectedThaiTranscriptScript =
  /[\p{Script=Cyrillic}\p{Script=Han}\p{Script=Hangul}\p{Script=Arabic}\p{Script=Devanagari}\p{Script=Hiragana}\p{Script=Katakana}\uFFFD]/u;

/** Keeps uncertain speech and provider prompt leakage out of user-facing text. */
export const isReliableTranscriptSegment = (
  segment: TranscriptSegment
): boolean => {
  const text = segment.text.normalize('NFC').trim().toLowerCase();
  if (text.length === 0) return false;
  if (leakedTranscriptionPromptSignals.some((signal) => text.includes(signal))) {
    return false;
  }
  if (unexpectedThaiTranscriptScript.test(text)) {
    return false;
  }
  if (segment.avgLogprob !== undefined && segment.avgLogprob < -1) {
    return false;
  }
  if (
    segment.noSpeechProbability !== undefined &&
    segment.noSpeechProbability > 0.6
  ) {
    return false;
  }
  if (segment.compressionRatio !== undefined && segment.compressionRatio > 2.4) {
    return false;
  }
  return true;
};

export type TranscriptionResult = {
  text: string;
  language: string;
  durationSeconds: number;
  segments: TranscriptSegment[];
  words: TranscriptWord[];
  model: string;
};

export type TranscriptionMediaKind = 'audio' | 'legacy-video';

export type TranscriptionInput = {
  mediaS3Key: string;
  mediaKind: TranscriptionMediaKind;
};

export type TranscriptionProvider = {
  transcribe: (input: TranscriptionInput) => Promise<TranscriptionResult>;
};

export type AudioSource = {
  data: Uint8Array;
  filename: string;
  contentType: string;
};

/** Normalizes provider language labels without changing unknown languages. */
export const normalizeTranscriptionLanguage = (value?: string): string => {
  const language = value?.trim();
  if (!language) {
    return 'th';
  }

  const normalized = language.toLowerCase();
  if (
    normalized === 'th' ||
    normalized === 'tha' ||
    normalized === 'thai' ||
    normalized.startsWith('th-') ||
    normalized.startsWith('th_')
  ) {
    return 'th';
  }

  return language;
};

/** Downloads the audio or legacy clip bytes for transcription (e.g. from R2). */
export type FetchAudio = (input: TranscriptionInput) => Promise<AudioSource>;

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
  segments?: Array<{
    text?: string;
    start?: number;
    end?: number;
    avg_logprob?: number;
    no_speech_prob?: number;
    compression_ratio?: number;
  }>;
  words?: Array<{ word?: string; start?: number; end?: number }>;
};

type ElevenLabsTranscriptEvent = {
  text?: unknown;
  start?: unknown;
  end?: unknown;
  type?: unknown;
};

type ElevenLabsTranscriptionResponse = {
  text?: unknown;
  language_code?: unknown;
  words?: unknown;
};

type ElevenLabsTimedWord = {
  word: string;
  displayText: string;
  start: number;
  end: number;
};

const elevenLabsPauseBoundarySeconds = 0.55;
const elevenLabsMaxSegmentSeconds = 4;
const elevenLabsMaxSegmentGraphemes = 32;
const terminalTranscriptPunctuation = /[.!?。！？…ฯ]$/u;
const thaiGraphemeSegmenter = new Intl.Segmenter('th', {
  granularity: 'grapheme'
});

const isElevenLabsEvent = (
  value: unknown
): value is ElevenLabsTranscriptEvent =>
  typeof value === 'object' && value !== null;

const isValidElevenLabsTimedWord = (
  event: ElevenLabsTranscriptEvent
): event is ElevenLabsTranscriptEvent & {
  text: string;
  start: number;
  end: number;
  type: 'word';
} =>
  event.type === 'word' &&
  typeof event.text === 'string' &&
  event.text.trim().length > 0 &&
  typeof event.start === 'number' &&
  Number.isFinite(event.start) &&
  event.start >= 0 &&
  typeof event.end === 'number' &&
  Number.isFinite(event.end) &&
  event.end >= event.start;

const countGraphemes = (value: string): number =>
  Array.from(thaiGraphemeSegmenter.segment(value)).length;

const rebuildFragmentedElevenLabsThaiWords = (
  timedWords: ElevenLabsTimedWord[],
  language?: string,
  referenceText?: string
): ElevenLabsTimedWord[] => {
  if (
    normalizeTranscriptionLanguage(language) !== 'th' ||
    timedWords.length < 4
  ) {
    return timedWords;
  }

  const timelineText = timedWords
    .map((word) => word.displayText)
    .join('')
    .normalize('NFC');
  const compact = (value: string) =>
    value.normalize('NFC').replace(/\s+/gu, '');
  const compactTimelineWords = compact(
    timedWords.map((word) => word.word).join('')
  );
  const normalizedReference = referenceText?.normalize('NFC').trim();
  const referenceMatchesTimeline =
    normalizedReference &&
    compact(normalizedReference) === compactTimelineWords;
  const canonicalText =
    referenceMatchesTimeline
      ? normalizedReference
      : timelineText;
  const canonicalSpacingDiffers =
    referenceMatchesTimeline &&
    normalizedReference !== timelineText.trim();
  const parts = Array.from(
    new Intl.Segmenter('th', { granularity: 'word' }).segment(canonicalText)
  );
  const semanticWordCount = parts.filter((part) => part.isWordLike).length;

  // Scribe normally returns Thai timing events as grapheme-sized fragments.
  // Leave providers that already return semantic words untouched.
  if (
    semanticWordCount === 0 ||
    (
      !canonicalSpacingDiffers &&
      timedWords.length <= semanticWordCount * 1.5
    )
  ) {
    return timedWords;
  }

  let offset = 0;
  const indexedWords = timedWords.flatMap((timedWord) => {
    const word = compact(timedWord.word);
    if (!word) {
      return [];
    }
    const indexedWord = {
      timedWord,
      wordStart: offset,
      wordEnd: offset + word.length
    };
    offset += word.length;
    return [indexedWord];
  });
  const readPartRange = (start: number, end: number) => {
    const overlapping = indexedWords.filter(
      (entry) => entry.wordStart < end && entry.wordEnd > start
    );
    const first = overlapping[0]?.timedWord;
    const last = overlapping.at(-1)?.timedWord;
    return first && last
      ? { start: first.start, end: last.end }
      : undefined;
  };

  const rebuilt: ElevenLabsTimedWord[] = [];
  let pendingSpacing = '';
  let compactOffset = 0;

  for (const part of parts) {
    const value = part.segment.normalize('NFC');
    const compactValue = compact(value);
    const partStart = compactOffset;
    const partEnd = partStart + compactValue.length;
    compactOffset = partEnd;

    if (!part.isWordLike) {
      if (/^\s+$/u.test(value)) {
        pendingSpacing += value;
        continue;
      }

      const previous = rebuilt.at(-1);
      const range = compactValue
        ? readPartRange(partStart, partEnd)
        : undefined;
      if (previous) {
        previous.word += value;
        previous.displayText += value;
        if (range) {
          previous.end = Math.max(previous.end, range.end);
        }
      } else {
        pendingSpacing += value;
      }
      continue;
    }

    const word = value.trim();
    const range = compactValue
      ? readPartRange(partStart, partEnd)
      : undefined;
    if (!word || !range) {
      continue;
    }

    rebuilt.push({
      word,
      displayText: `${pendingSpacing}${word}`,
      start: range.start,
      end: range.end
    });
    pendingSpacing = '';
  }

  return rebuilt.length > 0 ? rebuilt : timedWords;
};

const readElevenLabsTimedWords = (
  events: ElevenLabsTranscriptEvent[]
): ElevenLabsTimedWord[] => {
  const timedWords: ElevenLabsTimedWord[] = [];
  let pendingSpacing = '';

  for (const event of events) {
    if (event.type === 'spacing' && typeof event.text === 'string') {
      pendingSpacing += event.text;
      continue;
    }

    if (!isValidElevenLabsTimedWord(event)) {
      continue;
    }

    const word = event.text.normalize('NFC').trim();
    timedWords.push({
      word,
      displayText: `${pendingSpacing}${word}`,
      start: event.start,
      end: event.end
    });
    pendingSpacing = '';
  }

  return timedWords;
};

const buildElevenLabsSegments = (
  timedWords: ElevenLabsTimedWord[]
): TranscriptSegment[] => {
  const segments: TranscriptSegment[] = [];
  let current:
    | {
        text: string;
        start: number;
        end: number;
      }
    | undefined;

  const flush = () => {
    if (!current) return;
    const text = current.text.normalize('NFC').trim();
    if (text) {
      segments.push({
        text,
        start: current.start,
        end: current.end
      });
    }
    current = undefined;
  };

  for (const timedWord of timedWords) {
    if (
      current &&
      timedWord.start - current.end >= elevenLabsPauseBoundarySeconds
    ) {
      flush();
    }

    if (!current) {
      current = {
        text: timedWord.displayText,
        start: timedWord.start,
        end: timedWord.end
      };
    } else {
      current.text += timedWord.displayText;
      current.end = timedWord.end;
    }

    const normalizedText = current.text.normalize('NFC').trim();
    const reachedBoundary =
      terminalTranscriptPunctuation.test(timedWord.word) ||
      current.end - current.start >= elevenLabsMaxSegmentSeconds ||
      countGraphemes(normalizedText) >= elevenLabsMaxSegmentGraphemes;

    if (reachedBoundary) {
      flush();
    }
  }

  flush();
  return segments;
};

const normalizeElevenLabsTranscription = (
  value: unknown,
  model: string
): TranscriptionResult => {
  const payload =
    typeof value === 'object' && value !== null
      ? (value as ElevenLabsTranscriptionResponse)
      : {};
  const events = Array.isArray(payload.words)
    ? payload.words.filter(isElevenLabsEvent)
    : [];
  const language =
    typeof payload.language_code === 'string'
      ? payload.language_code
      : undefined;
  const rawTimedWords = readElevenLabsTimedWords(events);
  const rawFallbackText = rawTimedWords
    .map((word) => word.displayText)
    .join('');
  const text =
    typeof payload.text === 'string'
      ? payload.text.normalize('NFC').trim()
      : rawFallbackText.normalize('NFC').trim();
  const timedWords = rebuildFragmentedElevenLabsThaiWords(
    rawTimedWords,
    language,
    text
  );

  return {
    text,
    language: normalizeTranscriptionLanguage(language),
    durationSeconds: timedWords.reduce(
      (duration, word) => Math.max(duration, word.end),
      0
    ),
    segments: buildElevenLabsSegments(timedWords),
    words: timedWords.map(({ word, start, end }) => ({ word, start, end })),
    model
  };
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
  failureLabel,
  prompt
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
  endpointUrl: string;
  failureLabel: string;
  prompt?: string;
}): TranscriptionProvider => ({
  transcribe: async (input) => {
    const audio = await fetchAudio(input);
    const form = new FormData();
    form.append(
      'file',
      new Blob([audio.data], { type: audio.contentType }),
      audio.filename
    );
    form.append('model', model);
    // PostDee transcription is Thai-first. The compatible speech APIs accept
    // an ISO-639-1 hint; Groq documents improved accuracy and latency from it.
    form.append('language', 'th');
    if (prompt?.trim()) {
      form.append('prompt', prompt.trim());
    }
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
      language: normalizeTranscriptionLanguage(payload.language),
      durationSeconds: payload.duration ?? 0,
      segments: (payload.segments ?? []).map((segment) => ({
        text: (segment.text ?? '').trim(),
        start: segment.start ?? 0,
        end: segment.end ?? 0,
        ...(typeof segment.avg_logprob === 'number'
          ? { avgLogprob: segment.avg_logprob }
          : {}),
        ...(typeof segment.no_speech_prob === 'number'
          ? { noSpeechProbability: segment.no_speech_prob }
          : {}),
        ...(typeof segment.compression_ratio === 'number'
          ? { compressionRatio: segment.compression_ratio }
          : {})
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

/**
 * Real Thai transcription via ElevenLabs Scribe v2. Spacing events rebuild
 * readable mixed-language text, while only valid word events become timed
 * subtitle words.
 */
export const createElevenLabsTranscriptionProvider = ({
  apiKey,
  model,
  fetchAudio,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  fetchAudio: FetchAudio;
  fetchImpl?: FetchImpl;
}): TranscriptionProvider => ({
  transcribe: async (input) => {
    const audio = await fetchAudio(input);
    const form = new FormData();
    form.append(
      'file',
      new Blob([audio.data], { type: audio.contentType }),
      audio.filename
    );
    form.append('model_id', model);
    form.append('language_code', 'th');
    form.append('timestamps_granularity', 'word');
    form.append('tag_audio_events', 'false');
    form.append('diarize', 'false');
    form.append('no_verbatim', 'false');

    const response = await fetchImpl(
      'https://api.elevenlabs.io/v1/speech-to-text',
      {
        method: 'POST',
        headers: { 'xi-api-key': apiKey },
        body: form as unknown as RequestInit['body']
      }
    );

    if (!response.ok) {
      throw new Error(
        `ElevenLabs transcription failed with status ${
          response.status ?? 'unknown'
        }`
      );
    }

    return normalizeElevenLabsTranscription(await response.json(), model);
  }
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
    | 'elevenLabsApiKey'
    | 'elevenLabsTranscriptionModel'
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

  if (config.transcriptionProvider === 'elevenlabs') {
    if (!config.elevenLabsApiKey) {
      throw new Error(
        'ELEVENLABS_API_KEY is required when TRANSCRIPTION_PROVIDER is elevenlabs'
      );
    }

    if (!fetchAudio) {
      throw new Error(
        'A fetchAudio implementation is required for ElevenLabs transcription'
      );
    }

    return createElevenLabsTranscriptionProvider({
      apiKey: config.elevenLabsApiKey,
      model: config.elevenLabsTranscriptionModel,
      fetchAudio
    });
  }

  return createMockTranscriptionProvider();
};
