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

export type TranscriptTimingIntegrity = 'trusted' | 'untrusted';

export type TranscriptionResult = {
  text: string;
  language: string;
  durationSeconds: number;
  segments: TranscriptSegment[];
  words: TranscriptWord[];
  model: string;
  timingIntegrity: TranscriptTimingIntegrity;
  hasTimedAudioEvents: boolean;
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
  text?: unknown;
  language?: unknown;
  duration?: unknown;
  segments?: unknown;
  words?: unknown;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isFiniteNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

const normalizeTranscriptCoverage = (value: string): string =>
  value.normalize('NFC').replace(/\s+/gu, ' ').trim();

const normalizeSemanticTranscriptCoverage = (value: string): string =>
  normalizeTranscriptCoverage(value).replace(/\s+/gu, '');

const hasValidTimedBounds = (
  value: Record<string, unknown>,
  durationSeconds?: number
): value is Record<string, unknown> & { start: number; end: number } =>
  isFiniteNumber(value.start) &&
  value.start >= 0 &&
  isFiniteNumber(value.end) &&
  value.end > value.start &&
  (durationSeconds === undefined || value.end <= durationSeconds);

const readOpenAiSegments = (
  value: unknown,
  durationSeconds?: number
): { segments: TranscriptSegment[]; trusted: boolean } => {
  if (!Array.isArray(value)) return { segments: [], trusted: false };

  const segments: TranscriptSegment[] = [];
  let trusted = true;
  let previousEnd: number | undefined;
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.text !== 'string' ||
      item.text.trim().length === 0 ||
      !hasValidTimedBounds(item, durationSeconds) ||
      (previousEnd !== undefined && item.start < previousEnd)
    ) {
      trusted = false;
      continue;
    }

    const segment: TranscriptSegment = {
      text: item.text.trim(),
      start: item.start,
      end: item.end
    };
    if (isFiniteNumber(item.avg_logprob)) {
      segment.avgLogprob = item.avg_logprob;
    }
    if (isFiniteNumber(item.no_speech_prob)) {
      segment.noSpeechProbability = item.no_speech_prob;
    }
    if (isFiniteNumber(item.compression_ratio)) {
      segment.compressionRatio = item.compression_ratio;
    }
    segments.push(segment);
    previousEnd = item.end;
  }

  return { segments, trusted };
};

const readOpenAiWords = (
  value: unknown,
  durationSeconds?: number
): { words: TranscriptWord[]; trusted: boolean } => {
  if (!Array.isArray(value)) return { words: [], trusted: false };

  const words: TranscriptWord[] = [];
  let trusted = true;
  let previousEnd: number | undefined;
  for (const item of value) {
    if (
      !isRecord(item) ||
      typeof item.word !== 'string' ||
      item.word.trim().length === 0 ||
      !hasValidTimedBounds(item, durationSeconds) ||
      (previousEnd !== undefined && item.start < previousEnd)
    ) {
      trusted = false;
      continue;
    }

    words.push({ word: item.word.trim(), start: item.start, end: item.end });
    previousEnd = item.end;
  }

  return { words, trusted };
};

const normalizeOpenAiCompatibleTranscription = (
  value: unknown,
  model: string
): TranscriptionResult => {
  const payload = isRecord(value) ? (value as TranscriptionApiResponse) : {};
  const durationSeconds =
    isFiniteNumber(payload.duration) && payload.duration > 0
      ? payload.duration
      : 0;
  const hasTrustedDuration = durationSeconds > 0;
  const durationLimit = hasTrustedDuration ? durationSeconds : undefined;
  const segmentEvidence = readOpenAiSegments(payload.segments, durationLimit);
  const wordEvidence = readOpenAiWords(payload.words, durationLimit);
  const segmentsAbsent = payload.segments === undefined;
  const wordsAbsent = payload.words === undefined;
  const hasProvidedTimingStream =
    Array.isArray(payload.segments) || Array.isArray(payload.words);
  const rawText = typeof payload.text === 'string' ? payload.text : '';
  const textCoverage = normalizeSemanticTranscriptCoverage(rawText);
  const segmentCoverage = normalizeSemanticTranscriptCoverage(
    segmentEvidence.segments.map((segment) => segment.text).join('')
  );
  const wordCoverage = normalizeSemanticTranscriptCoverage(
    wordEvidence.words.map((word) => word.word).join('')
  );
  const hasCompleteTimingCoverage =
    textCoverage.length === 0 ||
    (segmentEvidence.segments.length > 0 && segmentCoverage === textCoverage) ||
    (wordEvidence.words.length > 0 && wordCoverage === textCoverage);
  const hasStructurallyValidStreams =
    (segmentsAbsent || segmentEvidence.trusted) &&
    (wordsAbsent || wordEvidence.trusted);

  return {
    text: rawText,
    language: normalizeTranscriptionLanguage(
      typeof payload.language === 'string' ? payload.language : undefined
    ),
    durationSeconds,
    segments: segmentEvidence.segments,
    words: wordEvidence.words,
    model,
    timingIntegrity:
      hasTrustedDuration &&
      hasProvidedTimingStream &&
      hasStructurallyValidStreams &&
      hasCompleteTimingCoverage
        ? 'trusted'
        : 'untrusted',
    hasTimedAudioEvents: false
  };
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

type ElevenLabsTimedWord = TranscriptWord & {
  displayText: string;
};

const elevenLabsPauseBoundarySeconds = 0.55;
const elevenLabsMaxSegmentSeconds = 4;
const elevenLabsMaxSegmentGraphemes = 32;
const elevenLabsEmergencyPauseBoundarySeconds = 2;
const elevenLabsEmergencyMaxSegmentSeconds = 8;
const elevenLabsEmergencyMaxSegmentGraphemes = 64;
const terminalTranscriptPunctuation = /[.!?。！？…ฯ]$/u;
const thaiGraphemeSegmenter = new Intl.Segmenter('th', {
  granularity: 'grapheme'
});
const thaiWordSegmenter = new Intl.Segmenter('th', {
  granularity: 'word'
});

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
  event.end > event.start;

const isValidElevenLabsTimedAudioEvent = (
  event: ElevenLabsTranscriptEvent
): event is ElevenLabsTranscriptEvent & {
  text: string;
  start: number;
  end: number;
  type: 'audio_event';
} =>
  event.type === 'audio_event' &&
  typeof event.text === 'string' &&
  event.text.trim().length > 0 &&
  typeof event.start === 'number' &&
  Number.isFinite(event.start) &&
  event.start >= 0 &&
  typeof event.end === 'number' &&
  Number.isFinite(event.end) &&
  event.end > event.start;

const isValidElevenLabsSpacing = (
  event: ElevenLabsTranscriptEvent
): event is ElevenLabsTranscriptEvent & { text: string; type: 'spacing' } =>
  event.type === 'spacing' && typeof event.text === 'string';

type AuditedElevenLabsEvents = {
  events: ElevenLabsTranscriptEvent[];
  timingIntegrity: TranscriptTimingIntegrity;
  hasTimedAudioEvents: boolean;
  durationSeconds: number;
};

const auditElevenLabsEvents = (value: unknown): AuditedElevenLabsEvents => {
  if (!Array.isArray(value)) {
    return {
      events: [],
      timingIntegrity: 'untrusted',
      hasTimedAudioEvents: false,
      durationSeconds: 0
    };
  }

  const events: ElevenLabsTranscriptEvent[] = [];
  let trusted = true;
  let hasTimedAudioEvents = false;
  let previousTimedEnd: number | undefined;
  let durationSeconds = 0;

  for (const item of value) {
    if (!isRecord(item)) {
      trusted = false;
      continue;
    }

    const event = item as ElevenLabsTranscriptEvent;
    if (isValidElevenLabsSpacing(event)) {
      events.push(event);
      continue;
    }

    const isWord = isValidElevenLabsTimedWord(event);
    const isAudioEvent = isValidElevenLabsTimedAudioEvent(event);
    if (!isWord && !isAudioEvent) {
      trusted = false;
      continue;
    }

    if (previousTimedEnd !== undefined && event.start < previousTimedEnd) {
      trusted = false;
      continue;
    }

    events.push(event);
    previousTimedEnd = event.end;
    durationSeconds = Math.max(durationSeconds, event.end);
    if (isAudioEvent) hasTimedAudioEvents = true;
  }

  return {
    events,
    timingIntegrity: trusted ? 'trusted' : 'untrusted',
    hasTimedAudioEvents,
    durationSeconds
  };
};

const readElevenLabsSpeechCoverage = (
  events: ElevenLabsTranscriptEvent[]
): string =>
  normalizeTranscriptCoverage(
    events
      .filter(
        (event) =>
          isValidElevenLabsTimedWord(event) ||
          isValidElevenLabsSpacing(event)
      )
      .map((event) => event.text as string)
      .join('')
  );

const readElevenLabsProviderSpeechCoverage = (
  providerText: string,
  events: ElevenLabsTranscriptEvent[]
): string => {
  let speechText = providerText.normalize('NFC');
  for (const event of events) {
    if (!isValidElevenLabsTimedAudioEvent(event)) continue;
    const label = event.text.normalize('NFC').trim();
    if (label.length > 0) speechText = speechText.replace(label, ' ');
  }
  return normalizeTranscriptCoverage(speechText);
};

const countGraphemes = (value: string): number =>
  Array.from(thaiGraphemeSegmenter.segment(value)).length;

const readElevenLabsSemanticBoundaryOffsets = (
  timedWords: ElevenLabsTimedWord[]
): Set<number> => {
  const text = timedWords
    .map((word) => word.displayText)
    .join('')
    .normalize('NFC');
  const boundaries = new Set<number>([0, text.length]);

  for (const part of thaiWordSegmenter.segment(text)) {
    boundaries.add(part.index);
    boundaries.add(part.index + part.segment.length);
  }

  return boundaries;
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
    if (!isValidElevenLabsTimedWord(event)) continue;

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
  const semanticBoundaryOffsets =
    readElevenLabsSemanticBoundaryOffsets(timedWords);
  let consumedTextLength = 0;
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
      segments.push({ text, start: current.start, end: current.end });
    }
    current = undefined;
  };

  for (const timedWord of timedWords) {
    const displayText = timedWord.displayText.normalize('NFC');
    const pauseSeconds = current
      ? timedWord.start - current.end
      : 0;
    if (
      current &&
      pauseSeconds >= elevenLabsPauseBoundarySeconds &&
      (
        semanticBoundaryOffsets.has(consumedTextLength) ||
        pauseSeconds >= elevenLabsEmergencyPauseBoundarySeconds
      )
    ) {
      flush();
    }

    if (!current) {
      current = {
        text: displayText,
        start: timedWord.start,
        end: timedWord.end
      };
    } else {
      current.text += displayText;
      current.end = timedWord.end;
    }
    consumedTextLength += displayText.length;

    const normalizedText = current.text.normalize('NFC').trim();
    const normalizedGraphemeCount = countGraphemes(normalizedText);
    const reachedForcedSegmentLimit =
      current.end - current.start >= elevenLabsMaxSegmentSeconds ||
      normalizedGraphemeCount >= elevenLabsMaxSegmentGraphemes;
    const reachedEmergencySegmentLimit =
      current.end - current.start >= elevenLabsEmergencyMaxSegmentSeconds ||
      normalizedGraphemeCount >=
        elevenLabsEmergencyMaxSegmentGraphemes;
    if (
      terminalTranscriptPunctuation.test(timedWord.word) ||
      reachedEmergencySegmentLimit ||
      (
        reachedForcedSegmentLimit &&
        semanticBoundaryOffsets.has(consumedTextLength)
      )
    ) {
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
  const auditedEvents = auditElevenLabsEvents(payload.words);
  const events = auditedEvents.events;
  const timedWords = readElevenLabsTimedWords(events);
  const fallbackText = timedWords.map((word) => word.displayText).join('');
  const providerText =
    typeof payload.text === 'string'
      ? payload.text.normalize('NFC').trim()
      : undefined;
  const text =
    providerText ?? fallbackText.normalize('NFC').trim();
  const language =
    typeof payload.language_code === 'string'
      ? payload.language_code
      : undefined;
  const hasCompleteSpeechCoverage =
    providerText === undefined ||
    readElevenLabsProviderSpeechCoverage(providerText, events) ===
      readElevenLabsSpeechCoverage(events);

  return {
    text,
    language: normalizeTranscriptionLanguage(language),
    durationSeconds: auditedEvents.durationSeconds,
    segments: buildElevenLabsSegments(timedWords),
    words: timedWords.map(({ word, start, end }) => ({ word, start, end })),
    model,
    timingIntegrity:
      auditedEvents.timingIntegrity === 'trusted' && hasCompleteSpeechCoverage
        ? 'trusted'
        : 'untrusted',
    hasTimedAudioEvents: auditedEvents.hasTimedAudioEvents
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
    model: 'mock-whisper',
    timingIntegrity: 'trusted',
    hasTimedAudioEvents: false
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
    // an ISO-639-1 hint; OpenAI-compatible services can use it to improve accuracy.
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

    return normalizeOpenAiCompatibleTranscription(await response.json(), model);
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
 * Real Thai transcription via ElevenLabs Scribe. Spacing events rebuild
 * mixed-language text; only valid word events become timed subtitle words.
 */
export const createElevenLabsTranscriptionProvider = ({
  apiKey,
  model,
  keyterms = [],
  fetchAudio,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  keyterms?: string[];
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
    form.append('tag_audio_events', 'true');
    form.append('diarize', 'false');
    form.append('no_verbatim', 'false');
    for (const keyterm of keyterms) {
      form.append('keyterms', keyterm);
    }

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
    | 'elevenLabsApiKey'
    | 'elevenLabsTranscriptionModel'
    | 'elevenLabsTranscriptionKeyterms'
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
      keyterms: config.elevenLabsTranscriptionKeyterms,
      fetchAudio
    });
  }

  return createMockTranscriptionProvider();
};
