import type { EditPlanCut, EditPlanResult } from './editPlanProvider.js';
import {
  isReliableTranscriptSegment,
  normalizeTranscriptionLanguage,
  type TranscriptSegment,
  type TranscriptWord,
  type TranscriptionResult
} from './transcriptionProvider.js';

export const aiEditCapabilityKeys = [
  'subtitle',
  'silence',
  'filler',
  'hook',
  'beatsync',
  'reframe',
  'zoom',
  'color',
  'sfx',
  'audio',
  'translate',
  'pricetag',
  'cta',
  'watermark'
] as const;

export type AiEditCapabilityKey = (typeof aiEditCapabilityKeys)[number];
export type AiEditCapabilityFlags = Record<AiEditCapabilityKey, boolean>;
export type AiEditCapabilityState = 'applied' | 'hinted' | 'planned' | 'skipped';

export type AiEditCapabilityStatus = {
  enabled: boolean;
  state: AiEditCapabilityState;
  message: string;
};

export type AiEditMusicSource = 'auto' | 'library' | 'device' | 'original';
export type AiEditBeatIntensity = 'smooth' | 'balanced' | 'energetic';
export type AiEditSilencePreset = 'natural' | 'balanced' | 'compact';

export type AiEditMusicSettings = {
  source: AiEditMusicSource;
  genre?: string;
  trackId?: string;
  beatIntensity: AiEditBeatIntensity;
  volume: number;
  ducking: {
    enabled: boolean;
    musicVolumeDuringSpeech: number;
  };
};

export type AiEditRecipeSettings = {
  subtitleStyle?: string;
  subtitleColor?: string;
  subtitleWordsPerLine?: number;
  subtitlePosition?: string;
  ctaText?: string;
  ctaDesign?: string;
  priceText?: string;
  watermarkText?: string;
  toneFilter?: string;
  zoomLevel?: string;
  silencePreset?: AiEditSilencePreset;
  fillerWords?: string[];
  music?: AiEditMusicSettings;
};

export type AiEditRecipe = {
  version: 1;
  status: 'ready';
  renderMode: 'mobile-ffmpeg';
  styleId?: string;
  prompt?: string;
  transcript: {
    text: string;
    language: string;
    durationSeconds: number;
    segments: TranscriptSegment[];
    words: TranscriptWord[];
    model: string;
  };
  subtitles: {
    enabled: boolean;
    segments: TranscriptSegment[];
    style: {
      mode: string;
      color: string;
      wordsPerLine: number;
      position: string;
    };
  };
  cutRanges: EditPlanCut[];
  silenceRanges: EditPlanCut[];
  fillerRanges: EditPlanCut[];
  plan: {
    cuts: EditPlanCut[];
    summary: string;
    model: string;
  };
  overlays: {
    cta: { enabled: boolean; text: string; design: string };
    priceTag: { enabled: boolean; text: string };
    watermark: { enabled: boolean; text: string };
  };
  renderHints: {
    toneFilter?: string;
    zoomLevel?: string;
  };
  music: AiEditMusicSettings;
  capabilities: Record<AiEditCapabilityKey, AiEditCapabilityStatus>;
};

const defaultCapabilities: AiEditCapabilityFlags = {
  subtitle: true,
  silence: true,
  filler: false,
  hook: false,
  beatsync: false,
  reframe: false,
  zoom: false,
  color: false,
  sfx: false,
  audio: false,
  translate: false,
  pricetag: false,
  cta: false,
  watermark: false
};

const plannedCapabilities = new Set<AiEditCapabilityKey>([
  'hook',
  'beatsync',
  'reframe',
  'zoom',
  'sfx',
  'audio',
  'translate',
  'pricetag',
  'cta',
  'watermark'
]);

const defaultFillerWords = ['เอ่อ', 'อ่า', 'แบบว่า', 'คือว่า', 'ประมาณว่า'];
const supportedFillerWords = new Set(defaultFillerWords);
const silencePresets = new Set<AiEditSilencePreset>([
  'natural',
  'balanced',
  'compact'
]);
const silenceMinGapSeconds: Record<AiEditSilencePreset, number> = {
  natural: 1,
  balanced: 0.6,
  compact: 0.4
};
const musicSources = new Set<AiEditMusicSource>(['auto', 'library', 'device', 'original']);
const beatIntensities = new Set<AiEditBeatIntensity>(['smooth', 'balanced', 'energetic']);
const defaultMusicSettings: AiEditMusicSettings = {
  source: 'original',
  beatIntensity: 'balanced',
  volume: 0.25,
  ducking: {
    enabled: true,
    musicVolumeDuringSpeech: 0.12
  }
};

const readString = (value: unknown): string | undefined => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readPositiveInteger = (value: unknown): number | undefined => {
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    return undefined;
  }

  return value;
};

const normalizeFillerWord = (value: string): string =>
  value
    .normalize('NFC')
    .trim()
    .replace(/^[\p{P}\p{S}\s]+|[\p{P}\p{S}\s]+$/gu, '');

const canonicalizeFillerWord = (value: string): string => {
  const normalized = normalizeFillerWord(value);
  return normalized === 'เออ' ? 'เอ่อ' : normalized;
};

const readFillerWords = (value: unknown): string[] | undefined => {
  if (value === undefined) {
    return undefined;
  }

  if (!Array.isArray(value)) {
    return [];
  }

  return [
    ...new Set(
      value.flatMap((item) => {
        if (typeof item !== 'string') {
          return [];
        }

        const normalized = normalizeFillerWord(item);
        return supportedFillerWords.has(normalized) ? [normalized] : [];
      })
    )
  ];
};

const readRatio = (value: unknown, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1
    ? value
    : fallback;

const readAiEditMusicSettings = (value: unknown): AiEditMusicSettings => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return { ...defaultMusicSettings, ducking: { ...defaultMusicSettings.ducking } };
  }

  const record = value as Record<string, unknown>;
  const rawSource = readString(record.source);
  const source = rawSource && musicSources.has(rawSource as AiEditMusicSource)
    ? rawSource as AiEditMusicSource
    : defaultMusicSettings.source;
  const rawIntensity = readString(record.beatIntensity);
  const beatIntensity = rawIntensity && beatIntensities.has(rawIntensity as AiEditBeatIntensity)
    ? rawIntensity as AiEditBeatIntensity
    : defaultMusicSettings.beatIntensity;
  const rawDucking = typeof record.ducking === 'object' &&
    record.ducking !== null &&
    !Array.isArray(record.ducking)
    ? record.ducking as Record<string, unknown>
    : {};

  return {
    source,
    genre: source === 'auto' || source === 'library'
      ? readString(record.genre)
      : undefined,
    trackId: source === 'library' ? readString(record.trackId) : undefined,
    beatIntensity,
    volume: readRatio(record.volume, defaultMusicSettings.volume),
    ducking: {
      enabled: typeof rawDucking.enabled === 'boolean'
        ? rawDucking.enabled
        : defaultMusicSettings.ducking.enabled,
      musicVolumeDuringSpeech: readRatio(
        rawDucking.musicVolumeDuringSpeech ?? rawDucking.speechVolume,
        defaultMusicSettings.ducking.musicVolumeDuringSpeech
      )
    }
  };
};

export const readAiEditCapabilities = (value: unknown): AiEditCapabilityFlags => {
  const flags: AiEditCapabilityFlags = { ...defaultCapabilities };

  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return flags;
  }

  const record = value as Record<string, unknown>;

  for (const key of aiEditCapabilityKeys) {
    if (typeof record[key] === 'boolean') {
      flags[key] = record[key];
    }
  }

  return flags;
};

export const readAiEditRecipeSettings = (value: unknown): AiEditRecipeSettings => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return {};
  }

  const record = value as Record<string, unknown>;
  const rawSilencePreset = readString(record.silencePreset);
  const silencePreset = rawSilencePreset &&
    silencePresets.has(rawSilencePreset as AiEditSilencePreset)
    ? rawSilencePreset as AiEditSilencePreset
    : undefined;

  return {
    subtitleStyle: readString(record.subtitleStyle),
    subtitleColor: readString(record.subtitleColor),
    subtitleWordsPerLine: readPositiveInteger(record.subtitleWordsPerLine),
    subtitlePosition: readString(record.subtitlePosition),
    ctaText: readString(record.ctaText),
    ctaDesign: readString(record.ctaDesign),
    priceText: readString(record.priceText),
    watermarkText: readString(record.watermarkText),
    toneFilter: readString(record.toneFilter),
    zoomLevel: readString(record.zoomLevel),
    silencePreset,
    fillerWords: readFillerWords(record.fillerWords),
    music: readAiEditMusicSettings(record.music)
  };
};

type TimedRange = { start: number; end: number };
const wordTimingCoverageToleranceSeconds = 1;
const minimumWordTextCoverageRatio = 0.8;
const minimumFragmentedTokenCount = 4;
const fragmentedFillerBoundarySeconds = 0.08;
const minimumEstimatedSubtitleDurationSeconds = 0.7;

const normalizeTranscriptTextForCoverage = (value: string): string =>
  value
    .normalize('NFC')
    .toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');

const readThaiWordBoundaryOffsets = (value: string): Set<number> => {
  const boundaries = new Set<number>();
  let offset = 0;

  const segments = new Intl.Segmenter('th', { granularity: 'word' }).segment(value);
  for (const segment of segments) {
    const normalizedSegment = normalizeTranscriptTextForCoverage(segment.segment);
    const segmentLength = Array.from(normalizedSegment).length;
    if (segment.isWordLike && segmentLength > 0) {
      boundaries.add(offset);
      boundaries.add(offset + segmentLength);
    }
    offset += segmentLength;
  }

  return boundaries;
};

const hasFinitePositiveDuration = (value?: number): value is number =>
  value !== undefined && Number.isFinite(value) && value > 0;

const readSafeTimedRange = (
  range: TimedRange,
  durationSeconds?: number
): TimedRange | undefined => {
  if (
    !Number.isFinite(range.start) ||
    !Number.isFinite(range.end) ||
    range.start < 0 ||
    range.end <= range.start
  ) {
    return undefined;
  }

  if (hasFinitePositiveDuration(durationSeconds)) {
    if (range.start >= durationSeconds) {
      return undefined;
    }

    const end = Math.min(range.end, durationSeconds);
    return end > range.start ? { start: range.start, end } : undefined;
  }

  return { start: range.start, end: range.end };
};

const hasFragmentedThaiWordTimings = (
  words: TranscriptWord[],
  language: string,
  referenceText: string
): boolean => {
  if (
    normalizeTranscriptionLanguage(language) !== 'th' ||
    words.length < minimumFragmentedTokenCount
  ) {
    return false;
  }

  const normalizedReference = normalizeTranscriptTextForCoverage(referenceText);
  const normalizedWords = normalizeTranscriptTextForCoverage(
    words.map((word) => word.word).join('')
  );
  const hasReferenceEvidence =
    normalizedReference.length === 0 || normalizedReference.includes(normalizedWords);
  const thaiTokenRatio = words.filter((word) =>
    /\p{Script=Thai}/u.test(word.word)
  ).length / words.length;
  const hasStandaloneCombiningMark = words.some((word) =>
    /^\p{M}+$/u.test(word.word.trim().normalize('NFD'))
  );
  const referenceWordTokens = Array.from(
    new Intl.Segmenter('th', { granularity: 'word' }).segment(referenceText)
  )
    .filter((segment) => segment.isWordLike)
    .map((segment) => normalizeTranscriptTextForCoverage(segment.segment))
    .filter(Boolean);
  const providerWordTokens = words
    .map((word) => normalizeTranscriptTextForCoverage(word.word))
    .filter(Boolean);
  const tokenBoundariesDiffer =
    referenceWordTokens.length > 0 &&
    (
      referenceWordTokens.length !== providerWordTokens.length ||
      referenceWordTokens.some(
        (word, index) => word !== providerWordTokens[index]
      )
    );
  const tightPairCount = words.slice(1).filter((word, index) => {
    const previous = words[index]!;
    const gap = word.start - previous.end;
    return gap >= -Number.EPSILON && gap <= fragmentedFillerBoundarySeconds;
  }).length;
  const tightPairRatio = words.length <= 1
    ? 0
    : tightPairCount / (words.length - 1);

  return (
    hasReferenceEvidence &&
    thaiTokenRatio >= 0.5 &&
    (hasStandaloneCombiningMark || tokenBoundariesDiffer) &&
    tightPairRatio >= 0.5
  );
};

const readSafeTranscriptWords = (
  words: TranscriptWord[],
  durationSeconds?: number
): TranscriptWord[] =>
  words
    .flatMap((word) => {
      const text = word.word.trim();
      const range = readSafeTimedRange(word, durationSeconds);
      const hasTranscriptText =
        normalizeTranscriptTextForCoverage(text).length > 0;
      return hasTranscriptText && range
        ? [{ word: text, start: range.start, end: range.end }]
        : [];
    })
    .sort((a, b) => a.start - b.start || a.end - b.end);

const readValidTranscriptSegments = (
  segments: TranscriptSegment[],
  durationSeconds?: number
): TranscriptSegment[] =>
  segments
    .flatMap((segment) => {
      const text = segment.text.trim();
      const range = readSafeTimedRange(segment, durationSeconds);
      return text.length > 0 && range
        ? [{
            text,
            start: range.start,
            end: range.end,
            ...(segment.avgLogprob !== undefined
              ? { avgLogprob: segment.avgLogprob }
              : {}),
            ...(segment.noSpeechProbability !== undefined
              ? { noSpeechProbability: segment.noSpeechProbability }
              : {}),
            ...(segment.compressionRatio !== undefined
              ? { compressionRatio: segment.compressionRatio }
              : {})
          }]
        : [];
    })
    .sort((a, b) => a.start - b.start || a.end - b.end);

const readValidTranscriptWords = (
  words: TranscriptWord[],
  segments: TranscriptSegment[],
  transcriptText: string,
  durationSeconds?: number
): TranscriptWord[] | undefined => {
  const sortedWords = readSafeTranscriptWords(words, durationSeconds);
  const meaningfulWordCount = words.filter(
    (word) => normalizeTranscriptTextForCoverage(word.word).length > 0
  ).length;
  if (
    sortedWords.length === 0 ||
    sortedWords.length !== meaningfulWordCount
  ) {
    return undefined;
  }

  if (
    sortedWords.some(
      (word, index) => index > 0 && word.start < sortedWords[index - 1]!.end
    )
  ) {
    return undefined;
  }

  if (segments.length > 0) {
    const firstWord = sortedWords[0]!;
    const lastWord = sortedWords.at(-1)!;
    const firstSegment = segments[0]!;
    const lastSegment = segments.at(-1)!;
    const coversTranscriptTime =
      firstWord.start + Number.EPSILON >= firstSegment.start &&
      lastWord.end <= lastSegment.end + Number.EPSILON &&
      Math.abs(firstWord.start - firstSegment.start) <=
        wordTimingCoverageToleranceSeconds &&
      Math.abs(lastWord.end - lastSegment.end) <=
        wordTimingCoverageToleranceSeconds;
    const transcriptReferenceText = normalizeTranscriptTextForCoverage(transcriptText);
    const segmentText = transcriptReferenceText || normalizeTranscriptTextForCoverage(
      segments.map((segment) => segment.text).join('')
    );
    const wordText = normalizeTranscriptTextForCoverage(
      sortedWords.map((word) => word.word).join('')
    );
    const textCoverageRatio = segmentText.length === 0
      ? 1
      : wordText.length / segmentText.length;
    const coversTranscriptText =
      segmentText.length === 0 ||
      (
        textCoverageRatio >= minimumWordTextCoverageRatio &&
        segmentText.includes(wordText)
      );

    if (!coversTranscriptTime || !coversTranscriptText) {
      return undefined;
    }
  } else {
    const transcriptReferenceText = normalizeTranscriptTextForCoverage(transcriptText);
    const wordText = normalizeTranscriptTextForCoverage(
      sortedWords.map((word) => word.word).join('')
    );
    const textCoverageRatio = transcriptReferenceText.length === 0
      ? 1
      : wordText.length / transcriptReferenceText.length;

    if (
      transcriptReferenceText.length > 0 &&
      (
        textCoverageRatio < minimumWordTextCoverageRatio ||
        !transcriptReferenceText.includes(wordText)
      )
    ) {
      return undefined;
    }
  }

  return sortedWords;
};

const isNumericSubtitleToken = (value: string): boolean => {
  const digits = value.replace(/[.,]/gu, '');
  return digits.length > 0 && /^\p{Number}+$/u.test(digits);
};

const readGraphemeCount = (value: string): number =>
  Array.from(
    new Intl.Segmenter('th', { granularity: 'grapheme' }).segment(value)
  ).length;

/**
 * Groq can return Thai "word" timestamps as individual characters. Rebuild
 * readable word boundaries from each reliable segment and estimate the timing
 * proportionally inside that segment. This keeps Thai words intact while still
 * preserving the provider's trustworthy segment-level timeline.
 */
const rebuildThaiWordsFromSegment = (
  segment: TranscriptSegment
): TranscriptWord[] => {
  const tokens: string[] = [];
  const segmented = new Intl.Segmenter('th', { granularity: 'word' })
    .segment(segment.text.normalize('NFC').trim());

  for (const part of segmented) {
    const value = part.segment.normalize('NFC');
    if (part.isWordLike) {
      tokens.push(value);
      continue;
    }

    const punctuation = value.trim();
    if (!punctuation) {
      continue;
    }
    if (tokens.length === 0) {
      tokens.push(punctuation);
    } else {
      tokens[tokens.length - 1] = `${tokens.at(-1)!}${punctuation}`;
    }
  }

  if (tokens.length === 0) {
    return [];
  }

  const weights = tokens.map((token) => Math.max(1, readGraphemeCount(token)));
  const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
  const span = segment.end - segment.start;
  let elapsedWeight = 0;

  return tokens.map((word, index) => {
    const start = segment.start + span * elapsedWeight / totalWeight;
    elapsedWeight += weights[index]!;
    const end = index === tokens.length - 1
      ? segment.end
      : segment.start + span * elapsedWeight / totalWeight;
    return { word, start, end };
  });
};

const buildSubtitleSegments = ({
  words,
  language,
  wordsPerLine,
  minimumDurationSeconds = 0
}: {
  words: TranscriptWord[];
  language: string;
  wordsPerLine: number;
  minimumDurationSeconds?: number;
}): TranscriptSegment[] => {
  const isThai = normalizeTranscriptionLanguage(language) === 'th';
  const segments: TranscriptSegment[] = [];
  const groups: TranscriptWord[][] = [];
  let current: TranscriptWord[] = [];

  for (const word of words) {
    current.push(word);
    if (current.length < wordsPerLine) {
      continue;
    }
    const duration = current.at(-1)!.end - current[0]!.start;
    if (minimumDurationSeconds <= 0 || duration >= minimumDurationSeconds) {
      groups.push(current);
      current = [];
    }
  }
  if (current.length > 0) {
    groups.push(current);
  }
  if (minimumDurationSeconds > 0 && groups.length > 1) {
    const last = groups.at(-1)!;
    const lastDuration = last.at(-1)!.end - last[0]!.start;
    if (lastDuration < minimumDurationSeconds) {
      groups[groups.length - 2]!.push(...last);
      groups.pop();
    }
  }

  for (const lineWords of groups) {
    const first = lineWords[0];
    const last = lineWords.at(-1);

    if (!first || !last) {
      continue;
    }

    const lineText = lineWords
      .map((word) => word.word.trim())
      .reduce((text, word, wordIndex, tokens) => {
        if (wordIndex === 0) {
          return word;
        }

        const previousWord = tokens[wordIndex - 1]!;
        const previousIsNumber = isNumericSubtitleToken(previousWord);
        const wordIsNumber = isNumericSubtitleToken(word);
        const needsSpace = !isThai ||
          /\p{Script=Latin}/u.test(previousWord) ||
          /\p{Script=Latin}/u.test(word) ||
          previousIsNumber !== wordIsNumber;
        return `${text}${needsSpace ? ' ' : ''}${word}`;
      }, '');

    segments.push({
      text: lineText,
      start: Math.min(...lineWords.map((word) => word.start)),
      end: Math.max(...lineWords.map((word) => word.end))
    });
  }

  return segments;
};

const buildEstimatedThaiSubtitleSegments = (
  segments: TranscriptSegment[],
  wordsPerLine: number
): TranscriptSegment[] =>
  segments.flatMap((segment) =>
    buildSubtitleSegments({
      words: rebuildThaiWordsFromSegment(segment),
      language: 'th',
      wordsPerLine,
      minimumDurationSeconds: minimumEstimatedSubtitleDurationSeconds
    })
  );

const joinSubtitleText = (left: string, right: string): string => {
  const first = left.trim();
  const second = right.trim();
  if (!first) return second;
  if (!second) return first;
  if (/^[\p{Pe}\p{Pf}.,!?;:\u0E2F\u0E46]/u.test(second)) {
    return `${first}${second}`;
  }
  const thaiBoundary = /\p{Script=Thai}$/u.test(first) &&
    /^\p{Script=Thai}/u.test(second);
  return `${first}${thaiBoundary ? '' : ' '}${second}`;
};

const mergeShortSubtitleSegments = (
  segments: TranscriptSegment[],
  minimumDurationSeconds = minimumEstimatedSubtitleDurationSeconds,
  maximumGapSeconds = 0.5
): TranscriptSegment[] => {
  const merged: TranscriptSegment[] = [];

  for (const segment of segments) {
    const previous = merged.at(-1);
    const previousDuration = previous ? previous.end - previous.start : 0;
    const gap = previous ? segment.start - previous.end : Number.POSITIVE_INFINITY;
    if (
      previous &&
      previousDuration < minimumDurationSeconds &&
      gap >= -Number.EPSILON &&
      gap <= maximumGapSeconds
    ) {
      merged[merged.length - 1] = {
        text: joinSubtitleText(previous.text, segment.text),
        start: previous.start,
        end: Math.max(previous.end, segment.end)
      };
    } else {
      merged.push(segment);
    }
  }

  const last = merged.at(-1);
  const previous = merged.at(-2);
  if (last && previous && last.end - last.start < minimumDurationSeconds) {
    const gap = last.start - previous.end;
    if (gap >= -Number.EPSILON && gap <= maximumGapSeconds) {
      merged.splice(merged.length - 2, 2, {
        text: joinSubtitleText(previous.text, last.text),
        start: previous.start,
        end: Math.max(previous.end, last.end)
      });
    }
  }

  return merged;
};

const findSilenceRanges = (
  ranges: TimedRange[],
  minGapSeconds = 0.6,
  durationSeconds?: number,
  edgeRanges = ranges
): EditPlanCut[] => {
  const sorted = ranges
    .flatMap((range) => {
      const safeRange = readSafeTimedRange(range, durationSeconds);
      return safeRange ? [safeRange] : [];
    })
    .sort((a, b) => a.start - b.start || a.end - b.end);
  const safeEdgeRanges = edgeRanges
    .flatMap((range) => {
      const safeRange = readSafeTimedRange(range, durationSeconds);
      return safeRange ? [safeRange] : [];
    })
    .sort((a, b) => a.start - b.start || a.end - b.end);

  if (sorted.length === 0 || safeEdgeRanges.length === 0) {
    return [];
  }

  const silenceRanges: EditPlanCut[] = [];
  const first = sorted[0]!;
  const firstEdge = safeEdgeRanges[0]!;
  const lastEdgeEnd = Math.max(...safeEdgeRanges.map((range) => range.end));
  let activeEnd = Math.max(0, first.end);

  if (firstEdge.start + Number.EPSILON >= minGapSeconds) {
    silenceRanges.push({ start: 0, end: firstEdge.start });
  }

  for (let index = 1; index < sorted.length; index += 1) {
    const next = sorted[index]!;
    const start = activeEnd;
    const end = Math.max(start, next.start);

    if (end - start + Number.EPSILON >= minGapSeconds) {
      silenceRanges.push({ start, end });
    }

    activeEnd = Math.max(activeEnd, next.end);
  }

  if (
    hasFinitePositiveDuration(durationSeconds) &&
    durationSeconds - lastEdgeEnd + Number.EPSILON >= minGapSeconds
  ) {
    silenceRanges.push({ start: lastEdgeEnd, end: durationSeconds });
  }

  return silenceRanges;
};

const findFillerRanges = (
  words: TranscriptWord[],
  fillerWords: readonly string[],
  matchFragmentedTokens = false,
  referenceText = ''
): EditPlanCut[] => {
  const selectedWords = new Set(fillerWords.map(canonicalizeFillerWord));
  const selectedWordList = [...selectedWords];
  const sortedWords = [...words].sort(
    (a, b) => a.start - b.start || a.end - b.end
  );
  const exactRanges = sortedWords
    .filter((word) => selectedWords.has(canonicalizeFillerWord(word.word)))
    .map((word) => ({ start: word.start, end: word.end }))
    .filter((range) => range.end > range.start);

  if (!matchFragmentedTokens || selectedWords.size === 0) {
    return exactRanges;
  }

  const fragments = sortedWords.flatMap((word) => {
    const text = normalizeFillerWord(word.word);
    return text.length > 0 ? [{ ...word, text }] : [];
  });
  const fragmentOffsets = [0];
  for (const fragment of fragments) {
    fragmentOffsets.push(
      fragmentOffsets.at(-1)! + Array.from(fragment.text).length
    );
  }
  const referenceWordBoundaries = readThaiWordBoundaryOffsets(referenceText);
  const transcriptStart = referenceText.normalize('NFC').trimStart();
  const fragmentedRanges: EditPlanCut[] = [];

  for (let startIndex = 0; startIndex < fragments.length; startIndex += 1) {
    let text = '';

    for (let endIndex = startIndex; endIndex < fragments.length; endIndex += 1) {
      const fragment = fragments[endIndex]!;
      const previousFragment = fragments[endIndex - 1];
      if (
        endIndex > startIndex &&
        previousFragment &&
        fragment.start - previousFragment.end > fragmentedFillerBoundarySeconds
      ) {
        break;
      }

      text += fragment.text;
      const canonicalText = canonicalizeFillerWord(text);
      const isSelected = selectedWords.has(canonicalText);

      if (isSelected && endIndex > startIndex) {
        const first = fragments[startIndex]!;
        const last = fragments[endIndex]!;
        const previous = fragments[startIndex - 1];
        const next = fragments[endIndex + 1];
        const hasTimingBoundaries =
          (previous === undefined ||
            first.start - previous.end >= fragmentedFillerBoundarySeconds) &&
          (next === undefined ||
            next.start - last.end >= fragmentedFillerBoundarySeconds);
        const candidate = text.normalize('NFC');
        const textAfterCandidate = transcriptStart.startsWith(candidate)
          ? transcriptStart.slice(candidate.length)
          : '';
        const hasTranscriptStartBoundary =
          startIndex === 0 &&
          transcriptStart.startsWith(candidate) &&
          (
            textAfterCandidate.length === 0 ||
            /^[\s\p{P}\p{S}]/u.test(textAfterCandidate)
          );
        const candidateStartOffset = fragmentOffsets[startIndex]!;
        const candidateEndOffset = fragmentOffsets[endIndex + 1]!;
        const hasReferenceWordBoundaries =
          referenceWordBoundaries.has(candidateStartOffset) &&
          referenceWordBoundaries.has(candidateEndOffset);

        if (
          hasTimingBoundaries ||
          hasTranscriptStartBoundary ||
          hasReferenceWordBoundaries
        ) {
          fragmentedRanges.push({ start: first.start, end: last.end });
        }
      }

      const canStillMatch = selectedWordList.some((selectedWord) =>
        selectedWord.startsWith(canonicalText)
      );
      if (!canStillMatch) {
        break;
      }
    }
  }

  return sortRanges(
    [...exactRanges, ...fragmentedRanges].filter(
      (range, index, ranges) =>
        ranges.findIndex(
          (candidate) => candidate.start === range.start && candidate.end === range.end
        ) === index
    )
  );
};

const inferPriceText = (transcriptText: string): string => {
  const match = transcriptText.match(/(?:ราคา\s*)?(\d[\d,]*(?:\.\d+)?)\s*(บาท|฿)/u);
  if (!match) {
    return '';
  }

  const unit = match[2] === '฿' ? '฿' : 'บาท';
  return `${match[1]} ${unit}`;
};

const buildCapabilityStatus = ({
  key,
  enabled,
  state,
  message
}: {
  key: AiEditCapabilityKey;
  enabled: boolean;
  state?: AiEditCapabilityState;
  message?: string;
}): AiEditCapabilityStatus => {
  if (!enabled) {
    return { enabled, state: 'skipped', message: 'ไม่ได้เลือกใน UI' };
  }

  if (plannedCapabilities.has(key)) {
    return {
      enabled,
      state: 'planned',
      message: 'รับค่าไว้ใน recipe แล้ว แต่ต้องใช้การวิเคราะห์เสียง/ภาพขั้นต่อไปก่อนทำจริง'
    };
  }

  return {
    enabled,
    state: state ?? 'hinted',
    message: message ?? 'ส่งเป็นคำแนะนำให้ mobile renderer ใช้ตอน export'
  };
};

const sortRanges = (ranges: EditPlanCut[]) =>
  [...ranges].sort((a, b) => a.start - b.start || a.end - b.end);

export const buildAiEditRecipe = ({
  transcript,
  capabilities,
  settings,
  styleId,
  prompt,
  plan
}: {
  transcript: TranscriptionResult;
  capabilities: AiEditCapabilityFlags;
  settings: AiEditRecipeSettings;
  styleId?: string;
  prompt?: string;
  plan?: EditPlanResult;
}): AiEditRecipe => {
  const subtitleWordsPerLine = settings.subtitleWordsPerLine ?? 2;
  const transcriptLanguage = normalizeTranscriptionLanguage(transcript.language);
  const validTranscriptSegments = readValidTranscriptSegments(
    transcript.segments,
    transcript.durationSeconds
  );
  const reliableTranscriptSegments = validTranscriptSegments.filter(
    isReliableTranscriptSegment
  );
  const unreliableTranscriptSegments = validTranscriptSegments.filter(
    (segment) => !isReliableTranscriptSegment(segment)
  );
  const transcriptSegmentsAreComplete =
    validTranscriptSegments.length === transcript.segments.length;
  const safeTranscriptWords = readSafeTranscriptWords(
    transcript.words,
    transcript.durationSeconds
  );
  const validTranscriptWords = readValidTranscriptWords(
    transcript.words,
    validTranscriptSegments,
    transcript.text,
    transcript.durationSeconds
  );
  const wordOverlapsUnreliableSegment = (word: TranscriptWord): boolean =>
    unreliableTranscriptSegments.some(
      (segment) => word.start < segment.end && word.end > segment.start
    );
  const reliableSafeTranscriptWords = safeTranscriptWords.filter(
    (word) => !wordOverlapsUnreliableSegment(word)
  );
  const reliableValidTranscriptWords = validTranscriptWords?.filter(
    (word) => !wordOverlapsUnreliableSegment(word)
  );
  const transcriptReferenceText = reliableTranscriptSegments
    .map((segment) => segment.text)
    .join('') || transcript.text.trim();
  const normalizedTranscriptText = normalizeTranscriptTextForCoverage(
    transcript.text
  );
  const normalizedWordText = validTranscriptWords
    ? normalizeTranscriptTextForCoverage(
        validTranscriptWords.map((word) => word.word).join('')
      )
    : '';
  const wordsFullyCoverTranscript =
    normalizedTranscriptText.length > 0 &&
    normalizedWordText === normalizedTranscriptText;
  const hasReliableSilenceTimeline =
    transcriptSegmentsAreComplete &&
    (
      validTranscriptSegments.length > 0 ||
      (
        transcript.segments.length === 0 &&
        validTranscriptWords !== undefined &&
        wordsFullyCoverTranscript
      )
    );
  const fragmentedThaiWordTimings = reliableValidTranscriptWords
    ? hasFragmentedThaiWordTimings(
        reliableValidTranscriptWords,
        transcriptLanguage,
        transcriptReferenceText
      )
    : false;
  const estimatedThaiSubtitleSegments =
    fragmentedThaiWordTimings && reliableTranscriptSegments.length > 0
      ? buildEstimatedThaiSubtitleSegments(
          reliableTranscriptSegments,
          subtitleWordsPerLine
        )
      : undefined;
  const subtitleWords = reliableValidTranscriptWords && !fragmentedThaiWordTimings
    ? reliableValidTranscriptWords
    : reliableTranscriptSegments.length === 0 &&
        validTranscriptSegments.length === 0 &&
        reliableSafeTranscriptWords.length > 0
      ? reliableSafeTranscriptWords
      : undefined;
  const preparedSubtitleSegments = capabilities.subtitle
    ? estimatedThaiSubtitleSegments ??
      (subtitleWords
        ? buildSubtitleSegments({
            words: subtitleWords,
            language: transcriptLanguage,
            wordsPerLine: subtitleWordsPerLine
          })
        : reliableTranscriptSegments)
    : [];
  const subtitleSegments = mergeShortSubtitleSegments(preparedSubtitleSegments);
  const silencePreset = settings.silencePreset ?? 'balanced';
  const silenceRanges = capabilities.silence && hasReliableSilenceTimeline
    ? findSilenceRanges(
        validTranscriptWords ?? validTranscriptSegments,
        silenceMinGapSeconds[silencePreset],
        transcript.durationSeconds,
        validTranscriptSegments.length > 0
          ? validTranscriptSegments
          : validTranscriptWords ?? []
      )
    : [];
  const fillerRanges = capabilities.filler
    ? findFillerRanges(
        reliableSafeTranscriptWords,
        settings.fillerWords ?? defaultFillerWords,
        fragmentedThaiWordTimings,
        transcriptReferenceText
      )
    : [];
  const planCuts = plan?.cuts ?? [];
  const priceText = settings.priceText ?? inferPriceText(transcript.text);
  const ctaText = settings.ctaText ?? 'กดตะกร้าเลย';
  const watermarkText = settings.watermarkText ?? 'PostDee';

  return {
    version: 1,
    status: 'ready',
    renderMode: 'mobile-ffmpeg',
    styleId,
    prompt,
    transcript: {
      text: transcript.text,
      language: transcriptLanguage,
      durationSeconds: transcript.durationSeconds,
      segments: transcript.segments,
      words: transcript.words,
      model: transcript.model
    },
    subtitles: {
      enabled: capabilities.subtitle,
      segments: subtitleSegments,
      style: {
        mode: settings.subtitleStyle ?? 'bold',
        color: settings.subtitleColor ?? '#FFFFFF',
        wordsPerLine: subtitleWordsPerLine,
        position: settings.subtitlePosition ?? 'bottom'
      }
    },
    cutRanges: sortRanges([...planCuts, ...silenceRanges, ...fillerRanges]),
    silenceRanges,
    fillerRanges,
    plan: {
      cuts: planCuts,
      summary: plan?.summary ?? '',
      model: plan?.model ?? 'none'
    },
    overlays: {
      cta: {
        enabled: capabilities.cta,
        text: capabilities.cta ? ctaText : '',
        design: settings.ctaDesign ?? 'button'
      },
      priceTag: {
        enabled: capabilities.pricetag,
        text: capabilities.pricetag ? priceText : ''
      },
      watermark: {
        enabled: capabilities.watermark,
        text: capabilities.watermark ? watermarkText : ''
      }
    },
    renderHints: {
      toneFilter: capabilities.color ? settings.toneFilter ?? 'auto-bright' : undefined,
      zoomLevel: capabilities.zoom ? settings.zoomLevel ?? 'subtle' : undefined
    },
    music: settings.music ?? {
      ...defaultMusicSettings,
      ducking: { ...defaultMusicSettings.ducking }
    },
    capabilities: {
      subtitle: buildCapabilityStatus({
        key: 'subtitle',
        enabled: capabilities.subtitle,
        state: 'applied',
        message: 'ถอดเสียงเป็นซับพร้อมเวลาให้ mobile renderer แล้ว'
      }),
      silence: buildCapabilityStatus({
        key: 'silence',
        enabled: capabilities.silence,
        state: silenceRanges.length > 0 ? 'applied' : 'hinted',
        message: silenceRanges.length > 0
          ? 'หาช่วงเงียบจากช่องว่างของ transcript แล้ว'
          : 'รับค่าไว้แล้ว แต่ยังไม่พบช่วงเงียบจาก transcript รอบนี้'
      }),
      filler: buildCapabilityStatus({
        key: 'filler',
        enabled: capabilities.filler,
        state: fillerRanges.length > 0 ? 'applied' : 'hinted',
        message: fillerRanges.length > 0
          ? 'พบคำฟุ่มเฟือยจาก word timing แล้ว'
          : 'รับค่าไว้แล้ว แต่ยังไม่พบคำฟุ่มเฟือยจาก transcript รอบนี้'
      }),
      hook: buildCapabilityStatus({ key: 'hook', enabled: capabilities.hook }),
      beatsync: buildCapabilityStatus({ key: 'beatsync', enabled: capabilities.beatsync }),
      reframe: buildCapabilityStatus({ key: 'reframe', enabled: capabilities.reframe }),
      zoom: buildCapabilityStatus({ key: 'zoom', enabled: capabilities.zoom }),
      color: buildCapabilityStatus({ key: 'color', enabled: capabilities.color }),
      sfx: buildCapabilityStatus({ key: 'sfx', enabled: capabilities.sfx }),
      audio: buildCapabilityStatus({ key: 'audio', enabled: capabilities.audio }),
      translate: buildCapabilityStatus({ key: 'translate', enabled: capabilities.translate }),
      pricetag: buildCapabilityStatus({ key: 'pricetag', enabled: capabilities.pricetag }),
      cta: buildCapabilityStatus({ key: 'cta', enabled: capabilities.cta }),
      watermark: buildCapabilityStatus({ key: 'watermark', enabled: capabilities.watermark })
    }
  };
};
