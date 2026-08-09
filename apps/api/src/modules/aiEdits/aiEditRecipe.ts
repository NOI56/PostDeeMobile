import { createHash } from 'node:crypto';

import type {
  EditPlanCut,
  EditPlanResult,
  EditPlanSegment
} from './editPlanProvider.js';
import type { AiEditAnalysisOutcomes } from './aiEditUsagePolicy.js';
import type {
  AiSoundEffectPlacement,
  SoundEffectPlanResult
} from './soundEffectPlanProvider.js';
import {
  isReliableTranscriptSegment,
  normalizeTranscriptionLanguage,
  type TranscriptSegment,
  type TranscriptWord,
  type TranscriptionResult
} from './transcriptionProvider.js';
import {
  readThaiSubtitleWordBoundaryOffsets,
  readThaiSubtitleWordParts,
  repairThaiSubtitleSegmentBoundaries
} from './thaiSubtitleSegmentBoundaries.js';
import { reconstructThaiTimedWords } from './thaiTimedTokenReconstructor.js';

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
export type AiEditSpeechReductionMode = 'auto';

export type AiEditSpeechReductionOccurrenceKind =
  | 'adjacent-word'
  | 'adjacent-phrase'
  | 'frequent-only';

export type AiEditSpeechReductionOccurrence = {
  id: string;
  groupId: string;
  text: string;
  normalizedText: string;
  start: number;
  end: number;
  occurrenceIndex: number;
  occurrenceCount: number;
  kind: AiEditSpeechReductionOccurrenceKind;
  recommendation: 'cut' | 'keep';
  canAutoRemove: boolean;
  selectedByDefault: boolean;
  contextBefore: string;
  contextAfter: string;
};

export type AiEditSpeechReductionGroup = {
  id: string;
  text: string;
  normalizedText: string;
  totalOccurrences: number;
  occurrenceIds: string[];
};

export type AiEditSpeechReductionCut = EditPlanCut & {
  occurrenceId: string;
};

export type AiEditSpeechReduction = {
  version: 1;
  status: 'ready' | 'unavailable';
  unavailableReason?:
    | 'unsupported-language'
    | 'unsafe-word-timing'
    | 'fragmented-word-timing';
  groups: AiEditSpeechReductionGroup[];
  occurrences: AiEditSpeechReductionOccurrence[];
  defaultCutRanges: AiEditSpeechReductionCut[];
};

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
  subtitleOutlineColor?: string;
  subtitleWordsPerLine?: number;
  subtitlePosition?: string;
  subtitleNormalizedX?: number;
  subtitleNormalizedY?: number;
  ctaText?: string;
  ctaDesign?: string;
  priceText?: string;
  watermarkText?: string;
  toneFilter?: string;
  zoomLevel?: string;
  silencePreset?: AiEditSilencePreset;
  fillerWords?: string[];
  speechReductionMode?: AiEditSpeechReductionMode;
  music?: AiEditMusicSettings;
};

export type AiEditSubtitleSegment = TranscriptSegment & {
  words: TranscriptWord[];
};

export type AiEditSubtitleVariantKey = '1' | '3' | '5';
export type AiEditSubtitleVariants = Record<
  AiEditSubtitleVariantKey,
  AiEditSubtitleSegment[]
>;

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
    boundarySegments: TranscriptSegment[];
    words: TranscriptWord[];
    model: string;
  };
  subtitles: {
    enabled: boolean;
    segments: AiEditSubtitleSegment[];
    variants?: AiEditSubtitleVariants;
    style: {
      mode: string;
      color: string;
      outlineColor: string;
      wordsPerLine: number;
      position: string;
      normalizedX?: number;
      normalizedY?: number;
    };
  };
  cutRanges: EditPlanCut[];
  silenceRanges: EditPlanCut[];
  fillerRanges: EditPlanCut[];
  speechReduction?: AiEditSpeechReduction;
  analysisOutcomes: AiEditAnalysisOutcomes;
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
  /** AI-selected bundled effects at absolute source-video timestamps. */
  soundEffects: AiSoundEffectPlacement[];
  capabilities: Record<AiEditCapabilityKey, AiEditCapabilityStatus>;
};

const defaultCapabilities: AiEditCapabilityFlags = Object.fromEntries(
  aiEditCapabilityKeys.map((key) => [key, false])
) as AiEditCapabilityFlags;

const plannedCapabilities = new Set<AiEditCapabilityKey>([
  'hook',
  'beatsync',
  'reframe',
  'zoom',
  'audio',
  'translate',
  'pricetag',
  'cta',
  'watermark'
]);

const defaultFillerWords = [
  'เอ่อ',
  'อ่า',
  'แบบว่า',
  'คือว่า',
  'ประมาณว่า'
];
const supportedFillerWords = new Set([...defaultFillerWords, 'อาฮะ']);
const fillerWordAliases = new Map([
  ['เออ', 'เอ่อ'],
  ['อะฮะ', 'อาฮะ']
]);
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
const speechReductionModes = new Set<AiEditSpeechReductionMode>(['auto']);
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
const maximumSubtitleWordsPerCue = 5;
const subtitleVariantWordLimits = [1, 3, 5] as const;
const subtitleHexColorPattern = /^#[0-9A-F]{6}$/i;

const readString = (value: unknown): string | undefined => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readSubtitleWordsPerLine = (value: unknown): number | undefined => {
  if (value === undefined) {
    return undefined;
  }
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 1 ||
    value > maximumSubtitleWordsPerCue
  ) {
    throw new RangeError(
      `subtitleWordsPerLine must be an integer between 1 and ${maximumSubtitleWordsPerCue}`
    );
  }

  return value;
};

const readSubtitleHexColor = (
  value: unknown,
  fieldName: 'subtitleColor' | 'subtitleOutlineColor'
): string | undefined => {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'string' || !subtitleHexColorPattern.test(value)) {
    throw new RangeError(`${fieldName} must use #RRGGBB format`);
  }

  return value.toUpperCase();
};

const readSubtitleNormalizedCoordinates = ({
  subtitleNormalizedX,
  subtitleNormalizedY
}: {
  subtitleNormalizedX: unknown;
  subtitleNormalizedY: unknown;
}): Pick<AiEditRecipeSettings, 'subtitleNormalizedX' | 'subtitleNormalizedY'> => {
  const hasX = subtitleNormalizedX !== undefined;
  const hasY = subtitleNormalizedY !== undefined;

  if (!hasX && !hasY) {
    return {};
  }
  if (
    !hasX ||
    !hasY ||
    typeof subtitleNormalizedX !== 'number' ||
    typeof subtitleNormalizedY !== 'number' ||
    !Number.isFinite(subtitleNormalizedX) ||
    !Number.isFinite(subtitleNormalizedY) ||
    subtitleNormalizedX < 0 ||
    subtitleNormalizedX > 1 ||
    subtitleNormalizedY < 0 ||
    subtitleNormalizedY > 1
  ) {
    throw new RangeError(
      'subtitleNormalizedX and subtitleNormalizedY must be supplied together as finite numbers between 0 and 1'
    );
  }

  return { subtitleNormalizedX, subtitleNormalizedY };
};

const readLegacySubtitlePosition = (normalizedY: number): string => {
  if (normalizedY < 0.34) {
    return 'top';
  }
  if (normalizedY < 0.67) {
    return 'middle';
  }

  return 'bottom';
};

const normalizeFillerWord = (value: string): string =>
  value
    .normalize('NFC')
    .trim()
    .replace(/^[\p{P}\p{S}\s]+|[\p{P}\p{S}\s]+$/gu, '');

const canonicalizeFillerWord = (value: string): string => {
  const normalized = normalizeFillerWord(value);
  return fillerWordAliases.get(normalized) ?? normalized;
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
  const rawSpeechReductionMode = readString(record.speechReductionMode);
  const speechReductionMode = rawSpeechReductionMode &&
    speechReductionModes.has(rawSpeechReductionMode as AiEditSpeechReductionMode)
    ? rawSpeechReductionMode as AiEditSpeechReductionMode
    : undefined;
  const normalizedCoordinates = readSubtitleNormalizedCoordinates({
    subtitleNormalizedX: record.subtitleNormalizedX,
    subtitleNormalizedY: record.subtitleNormalizedY
  });

  return {
    subtitleStyle: readString(record.subtitleStyle),
    subtitleColor: readSubtitleHexColor(record.subtitleColor, 'subtitleColor'),
    subtitleOutlineColor: readSubtitleHexColor(
      record.subtitleOutlineColor,
      'subtitleOutlineColor'
    ),
    subtitleWordsPerLine: readSubtitleWordsPerLine(record.subtitleWordsPerLine),
    subtitlePosition: readString(record.subtitlePosition),
    ...normalizedCoordinates,
    ctaText: readString(record.ctaText),
    ctaDesign: readString(record.ctaDesign),
    priceText: readString(record.priceText),
    watermarkText: readString(record.watermarkText),
    toneFilter: readString(record.toneFilter),
    zoomLevel: readString(record.zoomLevel),
    silencePreset,
    fillerWords: readFillerWords(record.fillerWords),
    speechReductionMode,
    music: readAiEditMusicSettings(record.music)
  };
};

type TimedRange = { start: number; end: number };
const wordTimingCoverageToleranceSeconds = 1;
const minimumWordTextCoverageRatio = 0.8;
const minimumFragmentedTokenCount = 4;
const fragmentedFillerBoundarySeconds = 0.08;
const minimumEstimatedSubtitleDurationSeconds = 0.7;
const maximumEstimatedThaiWordsPerCue = 2;
const maximumThaiSemanticWordsPerCue = maximumSubtitleWordsPerCue;
const maximumThaiGraphemesPerCue = 20;
const subtitleWordTimingToleranceSeconds = 1e-6;
const maximumAdjacentRepeatGapSeconds = 0.35;
const maximumRepeatedPhraseWords = 3;
const minimumFrequentOccurrenceCount = 3;
const speechReductionContextWordCount = 2;
const neverAutoRemoveSpeechReductionWords = new Set([
  'ไม่',
  'ราคา',
  'บาท',
  'เปอร์เซ็นต์',
  'ส่วนลด',
  'โปรโมชั่น'
]);
const frequentOnlyProtectedSpeechReductionWords = new Set([
  ...neverAutoRemoveSpeechReductionWords,
  'ก็',
  'จะ',
  'ที่',
  'และ',
  'หรือ',
  'แต่',
  'แล้ว',
  'เรา',
  'เขา',
  'มัน',
  'คือ',
  'ว่า',
  'ของ',
  'ใน',
  'ไป',
  'มา',
  'ให้',
  'ได้',
  'มี',
  'เป็น',
  'ครับ',
  'ค่ะ',
  'คะ',
  'นะ'
]);

const normalizeTranscriptTextForCoverage = (value: string): string =>
  value
    .normalize('NFC')
    .toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');

const normalizeSubtitleTextForReconstruction = (value: string): string =>
  value.replace(/[\p{P}\p{S}\s]+/gu, '');

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

export const readStrictTranscriptEvidence = <T extends TimedRange>(
  ranges: readonly T[],
  durationSeconds: number
): T[] | undefined => {
  if (!hasFinitePositiveDuration(durationSeconds)) {
    return undefined;
  }

  const strict: T[] = [];
  let previousEnd: number | undefined;
  for (const range of ranges) {
    if (
      !Number.isFinite(range.start) ||
      !Number.isFinite(range.end) ||
      range.start < 0 ||
      range.end <= range.start ||
      range.end > durationSeconds ||
      (previousEnd !== undefined && range.start < previousEnd)
    ) {
      return undefined;
    }
    strict.push({ ...range });
    previousEnd = range.end;
  }

  return strict;
};

const hasFragmentedThaiWordTimings = (
  words: TranscriptWord[],
  language: string,
  referenceText: string
): boolean => {
  if (
    normalizeTranscriptionLanguage(language) !== 'th' ||
    words.length < 2
  ) {
    return false;
  }

  const normalizedReference = normalizeTranscriptTextForCoverage(referenceText);
  const normalizedProviderWords = words.map((word) =>
    normalizeTranscriptTextForCoverage(word.word)
  );
  const normalizedWords = normalizedProviderWords.join('');
  const hasReferenceEvidence =
    normalizedReference.length === 0 || normalizedReference.includes(normalizedWords);
  const thaiTokenRatio = words.filter((word) =>
    /\p{Script=Thai}/u.test(word.word)
  ).length / words.length;
  const hasStandaloneCombiningMark = words.some((word) =>
    /^\p{M}+$/u.test(word.word.trim().normalize('NFD'))
  );
  const referenceWordTokens = readThaiSubtitleWordParts(referenceText)
    .filter((segment) => segment.isWordLike)
    .map((segment) => normalizeTranscriptTextForCoverage(segment.segment))
    .filter(Boolean);
  const providerWordTokens = words
    .map((word) => normalizeTranscriptTextForCoverage(word.word))
    .filter(Boolean);
  const providerTextStartIndex = normalizedReference.indexOf(normalizedWords);
  const providerTextStartOffset = providerTextStartIndex < 0
    ? -1
    : Array.from(normalizedReference.slice(0, providerTextStartIndex)).length;
  const referenceWordBoundaries =
    readThaiSubtitleWordBoundaryOffsets(referenceText);
  let providerBoundaryOffset = providerTextStartOffset;
  const hasTightBoundaryInsideThaiWord =
    providerTextStartOffset >= 0 &&
    normalizedProviderWords.slice(0, -1).some((word, index) => {
      providerBoundaryOffset += Array.from(word).length;
      const current = words[index]!;
      const next = words[index + 1]!;
      const gap = next.start - current.end;
      const currentText = current.word.trim().normalize('NFC');
      const nextText = next.word.trim().normalize('NFC');
      return (
        gap >= -Number.EPSILON &&
        gap <= fragmentedFillerBoundarySeconds &&
        /[\u0E00-\u0E7F]$/u.test(currentText) &&
        /^[\u0E00-\u0E7F]/u.test(nextText) &&
        !referenceWordBoundaries.has(providerBoundaryOffset)
      );
    });

  if (
    hasReferenceEvidence &&
    thaiTokenRatio >= 0.5 &&
    hasTightBoundaryInsideThaiWord
  ) {
    return true;
  }

  if (words.length < minimumFragmentedTokenCount) {
    return false;
  }

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

export const attachValidatedSubtitleWords = (
  segments: TranscriptSegment[],
  words: TranscriptWord[]
): AiEditSubtitleSegment[] =>
  segments.map((segment) => {
    const cueWords = words.filter(
      (word) => word.start < segment.end && word.end > segment.start
    );
    if (cueWords.length === 0) {
      return { ...segment, words: [] };
    }

    const hasWordOutsideCue = cueWords.some(
      (word) =>
        word.start < segment.start - subtitleWordTimingToleranceSeconds ||
        word.end > segment.end + subtitleWordTimingToleranceSeconds
    );
    const hasOverlappingWords = cueWords.some(
      (word, index) =>
        index > 0 &&
        word.start <
          cueWords[index - 1]!.end - subtitleWordTimingToleranceSeconds
    );
    const cueText = normalizeSubtitleTextForReconstruction(segment.text);
    const reconstructedText = normalizeSubtitleTextForReconstruction(
      cueWords.map((word) => word.word).join('')
    );

    if (
      hasWordOutsideCue ||
      hasOverlappingWords ||
      cueText.length === 0 ||
      reconstructedText !== cueText
    ) {
      return { ...segment, words: [] };
    }

    return { ...segment, words: cueWords };
  });

const isNumericSubtitleToken = (value: string): boolean => {
  const digits = value.replace(/[.,]/gu, '');
  return digits.length > 0 && /^\p{Number}+$/u.test(digits);
};

const readGraphemeCount = (value: string): number =>
  Array.from(
    new Intl.Segmenter('th', { granularity: 'grapheme' }).segment(value)
  ).length;

const readThaiSemanticWordCount = (value: string): number =>
  readThaiSubtitleWordParts(value).filter(
    (segment) =>
      segment.isWordLike && /\p{Letter}/u.test(segment.segment)
  ).length;

const readSubtitleSemanticWordCount = (
  value: string,
  language: string
): number => {
  const normalizedLanguage = normalizeTranscriptionLanguage(language);
  if (normalizedLanguage === 'th') {
    return readThaiSubtitleWordParts(value).filter(
      (segment) => segment.isWordLike
    ).length;
  }

  return Array.from(
    new Intl.Segmenter(normalizedLanguage || 'en', { granularity: 'word' })
      .segment(value.normalize('NFC'))
  ).filter((segment) => segment.isWordLike).length;
};

const isWithinThaiSubtitleCueLimits = (value: string): boolean =>
  readThaiSemanticWordCount(value) <= maximumThaiSemanticWordsPerCue &&
  readGraphemeCount(value) <= maximumThaiGraphemesPerCue;

const buildSubtitleLineText = (
  words: TranscriptWord[],
  isThai: boolean
): string =>
  words
    .map((word) => word.word.trim())
    .filter(Boolean)
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

/**
 * Some providers can return Thai "word" timestamps as individual characters. Rebuild
 * readable word boundaries from each reliable segment and estimate the timing
 * proportionally inside that segment. This keeps Thai words intact while still
 * preserving the provider's trustworthy segment-level timeline.
 */
const rebuildThaiWordsFromSegment = (
  segment: TranscriptSegment
): TranscriptWord[] => {
  const tokens: string[] = [];
  const segmented = readThaiSubtitleWordParts(segment.text.trim());

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

const rebuildNonThaiWordsFromSegment = (
  segment: TranscriptSegment,
  language: string
): TranscriptWord[] => {
  const normalizedLanguage = normalizeTranscriptionLanguage(language);
  const tokens: string[] = [];
  const parts = Array.from(
    new Intl.Segmenter(normalizedLanguage || 'en', { granularity: 'word' })
      .segment(segment.text.trim().normalize('NFC'))
  );

  for (const part of parts) {
    if (part.isWordLike) {
      tokens.push(part.segment);
      continue;
    }

    const punctuation = part.segment.trim();
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
  const subtitleWords = isThai
    ? words.flatMap((word) => {
        const semanticWords = rebuildThaiWordsFromSegment({
          text: word.word,
          start: word.start,
          end: word.end
        });
        return semanticWords.length > 0 ? semanticWords : [word];
      })
    : words.flatMap((word) => {
        const semanticWords = rebuildNonThaiWordsFromSegment(
          {
            text: word.word,
            start: word.start,
            end: word.end
          },
          language
        );
        return semanticWords.length > 0 ? semanticWords : [word];
      });
  let current: TranscriptWord[] = [];

  for (const word of subtitleWords) {
    const candidate = [...current, word];
    if (
      isThai &&
      current.length > 0 &&
      !isWithinThaiSubtitleCueLimits(buildSubtitleLineText(candidate, true))
    ) {
      groups.push(current);
      current = [];
    }

    current.push(word);
    const currentText = buildSubtitleLineText(current, isThai);
    // A brand, URL, or other single provider token can be wider than 20
    // graphemes. Splitting it would corrupt the word, so flush it intact as its
    // own cue. The strict candidate/merge checks keep every other token out of
    // that cue.
    const isIndivisibleOverlongThaiToken =
      isThai &&
      current.length === 1 &&
      !isWithinThaiSubtitleCueLimits(currentText);
    if (current.length < wordsPerLine && !isIndivisibleOverlongThaiToken) {
      continue;
    }
    groups.push(current);
    current = [];
  }
  if (current.length > 0) {
    groups.push(current);
  }
  if (minimumDurationSeconds > 0 && groups.length > 1) {
    const last = groups.at(-1)!;
    const lastDuration = last.at(-1)!.end - last[0]!.start;
    if (lastDuration < minimumDurationSeconds) {
      const previous = groups[groups.length - 2]!;
      const candidate = [...previous, ...last];
      if (
        candidate.length <= wordsPerLine &&
        (!isThai || isWithinThaiSubtitleCueLimits(buildSubtitleLineText(candidate, true)))
      ) {
        previous.push(...last);
        groups.pop();
      }
    }
  }

  for (const lineWords of groups) {
    const first = lineWords[0];
    const last = lineWords.at(-1);

    if (!first || !last) {
      continue;
    }

    const lineText = buildSubtitleLineText(lineWords, isThai);

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
      wordsPerLine: Math.min(wordsPerLine, maximumEstimatedThaiWordsPerCue),
      minimumDurationSeconds: minimumEstimatedSubtitleDurationSeconds
    })
  );

const buildReadableFallbackSubtitleSegments = (
  segments: TranscriptSegment[],
  language: string,
  wordsPerLine: number
): TranscriptSegment[] => {
  const isThai = normalizeTranscriptionLanguage(language) === 'th';

  return segments.flatMap((segment) => {
    const rebuilt = isThai
      ? buildEstimatedThaiSubtitleSegments([segment], wordsPerLine)
      : buildSubtitleSegments({
          words: rebuildNonThaiWordsFromSegment(segment, language),
          language,
          wordsPerLine,
          minimumDurationSeconds: minimumEstimatedSubtitleDurationSeconds
        });
    return rebuilt.length > 1 ? rebuilt : [segment];
  });
};

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
  language: string,
  maximumWordsPerCue: number,
  minimumDurationSeconds = minimumEstimatedSubtitleDurationSeconds,
  maximumGapSeconds = 0.5
): TranscriptSegment[] => {
  const merged: TranscriptSegment[] = [];
  const isThai = normalizeTranscriptionLanguage(language) === 'th';

  for (const segment of segments) {
    const previous = merged.at(-1);
    const previousDuration = previous ? previous.end - previous.start : 0;
    const gap = previous ? segment.start - previous.end : Number.POSITIVE_INFINITY;
    const joinedText = previous
      ? joinSubtitleText(previous.text, segment.text)
      : segment.text;
    if (
      previous &&
      previousDuration < minimumDurationSeconds &&
      gap >= -Number.EPSILON &&
      gap <= maximumGapSeconds &&
      readSubtitleSemanticWordCount(joinedText, language) <= maximumWordsPerCue &&
      (!isThai || isWithinThaiSubtitleCueLimits(joinedText))
    ) {
      merged[merged.length - 1] = {
        text: joinedText,
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
    const joinedText = joinSubtitleText(previous.text, last.text);
    if (
      gap >= -Number.EPSILON &&
      gap <= maximumGapSeconds &&
      readSubtitleSemanticWordCount(joinedText, language) <= maximumWordsPerCue &&
      (!isThai || isWithinThaiSubtitleCueLimits(joinedText))
    ) {
      merged.splice(merged.length - 2, 2, {
        text: joinedText,
        start: previous.start,
        end: Math.max(previous.end, last.end)
      });
    }
  }

  return merged;
};

const findInternalSilenceCandidates = (
  ranges: TimedRange[],
  minGapSeconds = 0.6,
  durationSeconds?: number
): EditPlanCut[] => {
  if (!hasFinitePositiveDuration(durationSeconds)) {
    return [];
  }
  const strict = readStrictTranscriptEvidence(ranges, durationSeconds);
  if (!strict || strict.length < 2) return [];
  const sorted = [...strict].sort(
    (left, right) => left.start - right.start || left.end - right.end
  );

  const candidates: EditPlanCut[] = [];
  let activeEnd = sorted[0]!.end;
  for (let index = 1; index < sorted.length; index += 1) {
    const next = sorted[index]!;
    if (next.start - activeEnd + Number.EPSILON >= minGapSeconds) {
      candidates.push({ start: activeEnd, end: next.start });
    }
    activeEnd = Math.max(activeEnd, next.end);
  }
  return candidates;
};

const findFillerRanges = (
  words: TranscriptWord[],
  fillerWords: readonly string[],
  matchFragmentedTokens = false,
  referenceText = ''
): EditPlanCut[] => {
  const selectedWords = new Set(fillerWords.map(canonicalizeFillerWord));
  const selectedWordVariants = [
    ...selectedWords,
    ...[...fillerWordAliases]
      .filter(([, canonical]) => selectedWords.has(canonical))
      .map(([alias]) => alias)
  ];
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
  const referenceWordBoundaries =
    readThaiSubtitleWordBoundaryOffsets(referenceText);
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

      const canStillMatch = selectedWordVariants.some((selectedWord) =>
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

type SpeechReductionToken = {
  text: string;
  normalizedText: string;
  start: number;
  end: number;
  sourceIndex: number;
  endsSentence: boolean;
};

const buildSpeechReductionId = (
  prefix: 'srg' | 'sro',
  parts: Array<string | number>
): string => {
  const digest = createHash('sha256')
    .update(parts.join('|'))
    .digest('hex')
    .slice(0, 16);
  return `${prefix}_${digest}`;
};

const buildUnavailableSpeechReduction = (
  unavailableReason: NonNullable<AiEditSpeechReduction['unavailableReason']>
): AiEditSpeechReduction => ({
  version: 1,
  status: 'unavailable',
  unavailableReason,
  groups: [],
  occurrences: [],
  defaultCutRanges: []
});

const readSpeechReductionTokens = (
  words: TranscriptWord[]
): SpeechReductionToken[] | undefined => {
  const tokens: SpeechReductionToken[] = [];

  for (const [sourceIndex, word] of words.entries()) {
    const normalizedProviderText = word.word.trim().normalize('NFC');
    const semanticParts = readThaiSubtitleWordParts(normalizedProviderText)
      .filter(
        (part) =>
          part.isWordLike &&
          normalizeTranscriptTextForCoverage(part.segment).length > 0
      );

    // A provider timestamp spanning multiple semantic words cannot identify a
    // safe cut boundary. Keep the whole transcript instead of estimating one.
    if (semanticParts.length !== 1) {
      return undefined;
    }

    const text = semanticParts[0]!.segment.trim().normalize('NFC');
    const normalizedText = normalizeTranscriptTextForCoverage(text);
    if (normalizedText.length === 0) {
      return undefined;
    }

    tokens.push({
      text,
      normalizedText,
      start: word.start,
      end: word.end,
      sourceIndex,
      endsSentence: /[.!?ฯ]+(?:["'”’\)\]]*)\s*$/u.test(normalizedProviderText)
    });
  }

  return tokens;
};

const canSuggestAdjacentSpeechReductionForToken = (
  token: SpeechReductionToken
): boolean =>
  /^\p{Script=Thai}+$/u.test(token.normalizedText) &&
  !token.normalizedText.includes('ๆ') &&
  !/[\p{Number}฿$€£¥]/u.test(token.text) &&
  !neverAutoRemoveSpeechReductionWords.has(token.normalizedText);

const canReportFrequentSpeechReductionToken = (
  token: SpeechReductionToken
): boolean =>
  canSuggestAdjacentSpeechReductionForToken(token) &&
  readGraphemeCount(token.normalizedText) >= 3 &&
  !frequentOnlyProtectedSpeechReductionWords.has(token.normalizedText);

const hasSafeAdjacentSpeechBoundary = (
  left: SpeechReductionToken,
  right: SpeechReductionToken
): boolean => {
  const gap = right.start - left.end;
  return (
    !left.endsSentence &&
    gap >= -Number.EPSILON &&
    gap <= maximumAdjacentRepeatGapSeconds
  );
};

const readSpeechReductionContext = (
  tokens: SpeechReductionToken[],
  startIndex: number,
  endIndex: number
): { contextBefore: string; contextAfter: string } => ({
  contextBefore: tokens
    .slice(
      Math.max(0, startIndex - speechReductionContextWordCount),
      startIndex
    )
    .map((token) => token.text)
    .join(''),
  contextAfter: tokens
    .slice(endIndex, endIndex + speechReductionContextWordCount)
    .map((token) => token.text)
    .join('')
});

const buildReadySpeechReduction = (
  tokens: SpeechReductionToken[]
): AiEditSpeechReduction => {
  const groups: AiEditSpeechReductionGroup[] = [];
  const occurrences: AiEditSpeechReductionOccurrence[] = [];
  const defaultCutRanges: AiEditSpeechReductionCut[] = [];
  const consumedTokenIndexes = new Set<number>();

  for (let startIndex = 0; startIndex < tokens.length; startIndex += 1) {
    if (consumedTokenIndexes.has(startIndex)) {
      continue;
    }

    let foundAdjacentRepeat = false;
    for (
      let phraseWordCount = maximumRepeatedPhraseWords;
      phraseWordCount >= 1;
      phraseWordCount -= 1
    ) {
      if (startIndex + phraseWordCount * 2 > tokens.length) {
        continue;
      }

      const baseTokens = tokens.slice(
        startIndex,
        startIndex + phraseWordCount
      );
      if (!baseTokens.every(canSuggestAdjacentSpeechReductionForToken)) {
        continue;
      }
      if (
        phraseWordCount > 1 &&
        baseTokens.every(
          (token) => token.normalizedText === baseTokens[0]!.normalizedText
        )
      ) {
        continue;
      }
      if (
        baseTokens.some(
          (token, index) =>
            index > 0 &&
            !hasSafeAdjacentSpeechBoundary(baseTokens[index - 1]!, token)
        )
      ) {
        continue;
      }

      const matchesPhraseAt = (candidateStartIndex: number): boolean => {
        const candidateEndIndex = candidateStartIndex + phraseWordCount;
        if (candidateEndIndex > tokens.length) {
          return false;
        }

        const candidateTokens = tokens.slice(
          candidateStartIndex,
          candidateEndIndex
        );
        if (
          candidateTokens.some(
            (token, index) =>
              consumedTokenIndexes.has(candidateStartIndex + index) ||
              !canSuggestAdjacentSpeechReductionForToken(token) ||
              token.normalizedText !== baseTokens[index]!.normalizedText
          )
        ) {
          return false;
        }

        const boundaryStartIndex = Math.max(startIndex + 1, candidateStartIndex);
        for (
          let tokenIndex = boundaryStartIndex;
          tokenIndex < candidateEndIndex;
          tokenIndex += 1
        ) {
          if (
            !hasSafeAdjacentSpeechBoundary(
              tokens[tokenIndex - 1]!,
              tokens[tokenIndex]!
            )
          ) {
            return false;
          }
        }

        return true;
      };

      if (!matchesPhraseAt(startIndex + phraseWordCount)) {
        continue;
      }

      let occurrenceCount = 2;
      while (
        matchesPhraseAt(startIndex + occurrenceCount * phraseWordCount)
      ) {
        occurrenceCount += 1;
      }

      const normalizedText = baseTokens
        .map((token) => token.normalizedText)
        .join('');
      const text = baseTokens.map((token) => token.text).join('');
      const runEndIndex = startIndex + occurrenceCount * phraseWordCount;
      const groupId = buildSpeechReductionId('srg', [
        'adjacent',
        normalizedText,
        Math.round(tokens[startIndex]!.start * 1000),
        Math.round(tokens[runEndIndex - 1]!.end * 1000)
      ]);
      const occurrenceIds: string[] = [];

      for (
        let occurrenceOffset = 0;
        occurrenceOffset < occurrenceCount;
        occurrenceOffset += 1
      ) {
        const occurrenceStartIndex =
          startIndex + occurrenceOffset * phraseWordCount;
        const occurrenceEndIndex = occurrenceStartIndex + phraseWordCount;
        const first = tokens[occurrenceStartIndex]!;
        const last = tokens[occurrenceEndIndex - 1]!;
        const isAnchorOccurrence = occurrenceOffset === occurrenceCount - 1;
        const occurrenceId = buildSpeechReductionId('sro', [
          groupId,
          occurrenceOffset + 1,
          Math.round(first.start * 1000),
          Math.round(last.end * 1000)
        ]);
        const context = readSpeechReductionContext(
          tokens,
          occurrenceStartIndex,
          occurrenceEndIndex
        );

        occurrenceIds.push(occurrenceId);
        occurrences.push({
          id: occurrenceId,
          groupId,
          text,
          normalizedText,
          start: first.start,
          end: last.end,
          occurrenceIndex: occurrenceOffset + 1,
          occurrenceCount,
          kind: phraseWordCount === 1
            ? 'adjacent-word'
            : 'adjacent-phrase',
          recommendation: isAnchorOccurrence ? 'keep' : 'cut',
          canAutoRemove: !isAnchorOccurrence,
          selectedByDefault: !isAnchorOccurrence,
          ...context
        });

        if (!isAnchorOccurrence) {
          defaultCutRanges.push({
            occurrenceId,
            start: first.start,
            end: last.end
          });
        }
      }

      groups.push({
        id: groupId,
        text,
        normalizedText,
        totalOccurrences: occurrenceCount,
        occurrenceIds
      });
      for (
        let tokenIndex = startIndex;
        tokenIndex < runEndIndex;
        tokenIndex += 1
      ) {
        consumedTokenIndexes.add(tokenIndex);
      }
      startIndex = runEndIndex - 1;
      foundAdjacentRepeat = true;
      break;
    }

    if (foundAdjacentRepeat) {
      continue;
    }
  }

  const frequentTokens = new Map<string, SpeechReductionToken[]>();
  for (const [tokenIndex, token] of tokens.entries()) {
    if (
      consumedTokenIndexes.has(tokenIndex) ||
      !canReportFrequentSpeechReductionToken(token)
    ) {
      continue;
    }

    const matches = frequentTokens.get(token.normalizedText) ?? [];
    matches.push(token);
    frequentTokens.set(token.normalizedText, matches);
  }

  const frequentEntries = [...frequentTokens.entries()]
    .filter(([, matches]) => matches.length >= minimumFrequentOccurrenceCount)
    .sort(
      ([leftText, leftMatches], [rightText, rightMatches]) =>
        leftMatches[0]!.start - rightMatches[0]!.start ||
        leftText.localeCompare(rightText, 'th')
    );
  for (const [normalizedText, matches] of frequentEntries) {
    const groupId = buildSpeechReductionId('srg', [
      'frequent',
      normalizedText
    ]);
    const occurrenceIds: string[] = [];

    for (const [occurrenceOffset, token] of matches.entries()) {
      const occurrenceId = buildSpeechReductionId('sro', [
        groupId,
        occurrenceOffset + 1,
        Math.round(token.start * 1000),
        Math.round(token.end * 1000)
      ]);
      const context = readSpeechReductionContext(
        tokens,
        token.sourceIndex,
        token.sourceIndex + 1
      );
      occurrenceIds.push(occurrenceId);
      occurrences.push({
        id: occurrenceId,
        groupId,
        text: token.text,
        normalizedText,
        start: token.start,
        end: token.end,
        occurrenceIndex: occurrenceOffset + 1,
        occurrenceCount: matches.length,
        kind: 'frequent-only',
        recommendation: 'keep',
        canAutoRemove: false,
        selectedByDefault: false,
        ...context
      });
    }

    groups.push({
      id: groupId,
      text: matches[0]!.text,
      normalizedText,
      totalOccurrences: matches.length,
      occurrenceIds
    });
  }

  occurrences.sort(
    (left, right) =>
      left.start - right.start ||
      left.end - right.end ||
      left.id.localeCompare(right.id)
  );
  defaultCutRanges.sort(
    (left, right) =>
      left.start - right.start ||
      left.end - right.end ||
      left.occurrenceId.localeCompare(right.occurrenceId)
  );
  const occurrenceStartById = new Map(
    occurrences.map((occurrence) => [occurrence.id, occurrence.start])
  );
  groups.sort(
    (left, right) =>
      (occurrenceStartById.get(left.occurrenceIds[0]!) ?? 0) -
        (occurrenceStartById.get(right.occurrenceIds[0]!) ?? 0) ||
      left.id.localeCompare(right.id)
  );

  return {
    version: 1,
    status: 'ready',
    groups,
    occurrences,
    defaultCutRanges
  };
};

const buildSpeechReduction = ({
  language,
  words,
  unsafeReason,
  referenceText
}: {
  language: string;
  words: TranscriptWord[] | undefined;
  unsafeReason: 'unsafe-word-timing' | 'fragmented-word-timing';
  referenceText: string;
}): AiEditSpeechReduction => {
  if (normalizeTranscriptionLanguage(language) !== 'th') {
    return buildUnavailableSpeechReduction('unsupported-language');
  }
  if (!words || words.length === 0) {
    return buildUnavailableSpeechReduction(unsafeReason);
  }

  const normalizedReferenceText =
    normalizeTranscriptTextForCoverage(referenceText);
  const normalizedWordText = normalizeTranscriptTextForCoverage(
    words.map((word) => word.word).join('')
  );
  const tokens = readSpeechReductionTokens(words);
  if (
    !tokens ||
    normalizedReferenceText.length === 0 ||
    normalizedWordText !== normalizedReferenceText
  ) {
    return buildUnavailableSpeechReduction(unsafeReason);
  }

  return buildReadySpeechReduction(tokens);
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
  plan,
  soundEffectPlan,
  hasExplicitPlanRequest
}: {
  transcript: TranscriptionResult;
  capabilities: AiEditCapabilityFlags;
  settings: AiEditRecipeSettings;
  styleId?: string;
  prompt?: string;
  plan?: EditPlanResult;
  soundEffectPlan?: SoundEffectPlanResult;
  hasExplicitPlanRequest: boolean;
}): AiEditRecipe => {
  const subtitleWordsPerLine =
    readSubtitleWordsPerLine(settings.subtitleWordsPerLine) ?? 2;
  const subtitleColor =
    readSubtitleHexColor(settings.subtitleColor, 'subtitleColor') ?? '#FFFFFF';
  const subtitleOutlineColor = readSubtitleHexColor(
    settings.subtitleOutlineColor,
    'subtitleOutlineColor'
  ) ?? '#000000';
  const normalizedCoordinates = readSubtitleNormalizedCoordinates({
    subtitleNormalizedX: settings.subtitleNormalizedX,
    subtitleNormalizedY: settings.subtitleNormalizedY
  });
  const subtitlePosition = normalizedCoordinates.subtitleNormalizedY === undefined
    ? settings.subtitlePosition ?? 'bottom'
    : readLegacySubtitlePosition(normalizedCoordinates.subtitleNormalizedY);
  const transcriptLanguage = normalizeTranscriptionLanguage(transcript.language);
  const timingEvidenceTrusted = transcript.timingIntegrity === 'trusted';
  const strictTranscriptSegments = timingEvidenceTrusted
    ? readStrictTranscriptEvidence(
        transcript.segments,
        transcript.durationSeconds
      )
    : undefined;
  const strictTranscriptWords = timingEvidenceTrusted
    ? readStrictTranscriptEvidence(transcript.words, transcript.durationSeconds)
    : undefined;
  const hasStrictTranscriptTimeline =
    strictTranscriptSegments !== undefined && strictTranscriptWords !== undefined;
  const validTranscriptSegments = hasStrictTranscriptTimeline
    ? readValidTranscriptSegments(
        strictTranscriptSegments,
        transcript.durationSeconds
      )
    : [];
  const strictReliableTranscriptSegments = strictTranscriptSegments?.filter(
    isReliableTranscriptSegment
  ) ?? [];
  const transcriptBoundarySegments = repairThaiSubtitleSegmentBoundaries(
    strictReliableTranscriptSegments,
    transcriptLanguage,
    transcript.text
  );
  const reliableTranscriptSegments = hasStrictTranscriptTimeline
    ? strictReliableTranscriptSegments
    : [];
  const unreliableTranscriptSegments = validTranscriptSegments.filter(
    (segment) => !isReliableTranscriptSegment(segment)
  );
  const transcriptSegmentsAreComplete =
    validTranscriptSegments.length === transcript.segments.length;
  const safeTranscriptWords = hasStrictTranscriptTimeline
    ? readSafeTranscriptWords(
        strictTranscriptWords,
        transcript.durationSeconds
      )
    : [];
  const validTranscriptWords = hasStrictTranscriptTimeline
    ? readValidTranscriptWords(
        strictTranscriptWords,
        validTranscriptSegments,
        transcript.text,
        transcript.durationSeconds
      )
    : undefined;
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
  const subtitleTranscriptSegments = repairThaiSubtitleSegmentBoundaries(
    reliableTranscriptSegments,
    transcriptLanguage,
    transcript.text
  );
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
    hasStrictTranscriptTimeline &&
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
  const orderedSpeechFragments = strictTranscriptWords ?? [];
  const hasCompleteRepeatTimeline =
    timingEvidenceTrusted &&
    !transcript.hasTimedAudioEvents &&
    strictTranscriptSegments !== undefined &&
    strictTranscriptWords !== undefined &&
    strictTranscriptSegments.length > 0 &&
    strictReliableTranscriptSegments.length === strictTranscriptSegments.length;
  const requiresExactThaiWordVerification =
    hasCompleteRepeatTimeline &&
    transcriptLanguage === 'th' &&
    strictReliableTranscriptSegments.length > 0 &&
    orderedSpeechFragments.length > 0;
  const reconstructedSpeechWords = requiresExactThaiWordVerification
    ? reconstructThaiTimedWords({
        segments: strictReliableTranscriptSegments,
        fragments: orderedSpeechFragments,
        durationSeconds: transcript.durationSeconds
      })
    : undefined;
  const speechReductionWords = !hasCompleteRepeatTimeline
    ? undefined
    : transcriptLanguage === 'th'
      ? reconstructedSpeechWords
      : strictTranscriptWords;
  const speechReductionUnsafeReason =
    transcriptLanguage === 'th' && hasCompleteRepeatTimeline
      ? 'fragmented-word-timing'
      : 'unsafe-word-timing';
  const subtitleWords = reliableValidTranscriptWords && !fragmentedThaiWordTimings
    ? reliableValidTranscriptWords
    : reliableTranscriptSegments.length === 0 &&
        validTranscriptSegments.length === 0 &&
        reliableSafeTranscriptWords.length > 0
      ? reliableSafeTranscriptWords
      : undefined;
  const subtitleSegmentsByWordLimit = new Map<
    number,
    {
      segments: TranscriptSegment[];
      segmentsWithValidatedWords: AiEditSubtitleSegment[];
    }
  >();
  const buildSubtitleSegmentsForWordLimit = (wordsPerLine: number) => {
    const cached = subtitleSegmentsByWordLimit.get(wordsPerLine);
    if (cached) {
      return cached;
    }

    const estimatedThaiSubtitleSegments =
      fragmentedThaiWordTimings && subtitleTranscriptSegments.length > 0
        ? buildEstimatedThaiSubtitleSegments(
            subtitleTranscriptSegments,
            wordsPerLine
          )
        : undefined;
    const fallbackSubtitleSegments = buildReadableFallbackSubtitleSegments(
      subtitleTranscriptSegments,
      transcriptLanguage,
      wordsPerLine
    );
    const preparedSubtitleSegments = capabilities.subtitle
      ? estimatedThaiSubtitleSegments ??
        (subtitleWords
          ? buildSubtitleSegments({
              words: subtitleWords,
              language: transcriptLanguage,
              wordsPerLine
            })
          : fallbackSubtitleSegments)
      : [];
    const segments = mergeShortSubtitleSegments(
      preparedSubtitleSegments,
      transcriptLanguage,
      wordsPerLine
    );
    const segmentsWithValidatedWords =
      capabilities.subtitle &&
      reliableValidTranscriptWords &&
      !fragmentedThaiWordTimings
        ? attachValidatedSubtitleWords(segments, reliableValidTranscriptWords)
        : segments.map((segment) => ({ ...segment, words: [] }));
    const result = { segments, segmentsWithValidatedWords };
    subtitleSegmentsByWordLimit.set(wordsPerLine, result);
    return result;
  };
  const {
    segments: subtitleSegments,
    segmentsWithValidatedWords: subtitleSegmentsWithValidatedWords
  } = buildSubtitleSegmentsForWordLimit(subtitleWordsPerLine);
  const subtitleVariants = capabilities.subtitle
    ? Object.fromEntries(
        subtitleVariantWordLimits.map((wordsPerLine) => [
          String(wordsPerLine),
          buildSubtitleSegmentsForWordLimit(wordsPerLine)
            .segmentsWithValidatedWords
        ])
      ) as AiEditSubtitleVariants
    : undefined;
  const silencePreset = settings.silencePreset ?? 'balanced';
  const silenceRanges = capabilities.silence && hasReliableSilenceTimeline
    ? findInternalSilenceCandidates(
        validTranscriptWords ?? validTranscriptSegments,
        silenceMinGapSeconds[silencePreset],
        transcript.durationSeconds
      )
    : [];
  const speechReduction =
    capabilities.filler && settings.speechReductionMode === 'auto'
      ? buildSpeechReduction({
          language: transcriptLanguage,
          words: speechReductionWords,
          unsafeReason: speechReductionUnsafeReason,
          referenceText: transcriptReferenceText
        })
      : undefined;
  const fillerRanges = capabilities.filler
    ? speechReduction
      ? speechReduction.defaultCutRanges.map(({ start, end }) => ({
          start,
          end
        }))
      : findFillerRanges(
          reliableSafeTranscriptWords,
          settings.fillerWords ?? defaultFillerWords,
          fragmentedThaiWordTimings,
          transcriptReferenceText
        )
    : [];
  const planCuts = hasStrictTranscriptTimeline ? plan?.cuts ?? [] : [];
  const analysisOutcomes: AiEditAnalysisOutcomes = {
    plan: !hasExplicitPlanRequest
      ? 'not-requested'
      : plan
        ? 'succeeded'
        : 'unavailable',
    subtitle: !capabilities.subtitle
      ? 'not-requested'
      : timingEvidenceTrusted && subtitleSegmentsWithValidatedWords.length > 0
        ? 'succeeded'
        : 'unavailable',
    silence: !capabilities.silence
      ? 'not-requested'
      : hasReliableSilenceTimeline
        ? 'succeeded'
        : 'unavailable',
    speechReduction: !capabilities.filler
      ? 'not-requested'
      : speechReduction?.status === 'ready'
        ? 'succeeded'
        : !speechReduction && fillerRanges.length > 0
          ? 'succeeded'
          : 'unavailable',
    sfx: !capabilities.sfx
      ? 'not-requested'
      : soundEffectPlan
        ? 'succeeded'
        : 'unavailable'
  };
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
      boundarySegments: transcriptBoundarySegments,
      words: transcript.words,
      model: transcript.model
    },
    subtitles: {
      enabled: capabilities.subtitle,
      segments: subtitleSegmentsWithValidatedWords,
      ...(subtitleVariants ? { variants: subtitleVariants } : {}),
      style: {
        mode: settings.subtitleStyle ?? 'bold',
        color: subtitleColor,
        outlineColor: subtitleOutlineColor,
        wordsPerLine: subtitleWordsPerLine,
        ...(normalizedCoordinates.subtitleNormalizedX === undefined
          ? {}
          : {
              normalizedX: normalizedCoordinates.subtitleNormalizedX,
              normalizedY: normalizedCoordinates.subtitleNormalizedY
            }),
        position: subtitlePosition
      }
    },
    cutRanges: sortRanges([...planCuts, ...fillerRanges]),
    silenceRanges,
    fillerRanges,
    ...(speechReduction ? { speechReduction } : {}),
    analysisOutcomes,
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
    soundEffects: capabilities.sfx
      ? soundEffectPlan?.soundEffects ?? []
      : [],
    capabilities: {
      subtitle: buildCapabilityStatus({
        key: 'subtitle',
        enabled: capabilities.subtitle,
        state: hasStrictTranscriptTimeline && subtitleSegments.length > 0
          ? 'applied'
          : 'hinted',
        message: !hasStrictTranscriptTimeline
          ? 'ยืนยันเวลาเสียงไม่ได้ จึงยังไม่สร้างซับสำหรับเรนเดอร์'
          : subtitleSegments.length > 0
            ? 'ถอดเสียงเป็นซับพร้อมเวลาให้ mobile renderer แล้ว'
            : 'ยังไม่พบคำพูดที่มีเวลาปลอดภัยสำหรับสร้างซับ'
      }),
      silence: buildCapabilityStatus({
        key: 'silence',
        enabled: capabilities.silence,
        state: 'hinted',
        message: !hasReliableSilenceTimeline
          ? 'ยืนยันเวลาเสียงไม่ได้ จึงยังไม่ส่งช่วงเงียบให้ตรวจต่อ'
          : silenceRanges.length > 0
            ? 'พบตำแหน่งที่อาจเงียบ รอมือถือยืนยันจาก waveform ก่อนตัด'
            : 'ตรวจ transcript แล้ว แต่ยังไม่พบช่วงเงียบภายในคลิป'
      }),
      filler: buildCapabilityStatus({
        key: 'filler',
        enabled: capabilities.filler,
        state: speechReduction
          ? speechReduction.groups.length > 0
            ? 'applied'
            : 'hinted'
          : fillerRanges.length > 0
            ? 'applied'
            : 'hinted',
        message: speechReduction
          ? speechReduction.status === 'unavailable'
            ? 'ยังตรวจคำพูดซ้ำไม่ได้ เพราะเวลารายคำรอบนี้ไม่ปลอดภัยต่อการตัด'
            : speechReduction.groups.length > 0
              ? 'ตรวจคำพูดซ้ำแล้ว พร้อมรายการให้เลือกตัดหรือเก็บทีละจุด'
              : 'ตรวจคำพูดซ้ำแล้ว แต่ไม่พบจุดที่ควรเสนอให้ตัด'
          : fillerRanges.length > 0
            ? 'พบคำฟุ่มเฟือยจาก word timing แล้ว'
            : 'รับค่าไว้แล้ว แต่ยังไม่พบคำฟุ่มเฟือยจาก transcript รอบนี้'
      }),
      hook: buildCapabilityStatus({ key: 'hook', enabled: capabilities.hook }),
      beatsync: buildCapabilityStatus({ key: 'beatsync', enabled: capabilities.beatsync }),
      reframe: buildCapabilityStatus({ key: 'reframe', enabled: capabilities.reframe }),
      zoom: buildCapabilityStatus({ key: 'zoom', enabled: capabilities.zoom }),
      color: buildCapabilityStatus({ key: 'color', enabled: capabilities.color }),
      sfx: buildCapabilityStatus({
        key: 'sfx',
        enabled: capabilities.sfx,
        state: soundEffectPlan ? 'applied' : 'hinted',
        message: !soundEffectPlan
          ? 'ยังเลือกเอฟเฟกต์เสียงไม่ได้ เพราะผลวิเคราะห์หรือเวลาอ้างอิงไม่พร้อม'
          : soundEffectPlan.soundEffects.length > 0
            ? `AI เลือกเอฟเฟกต์เสียงจากคลัง PostDee ${soundEffectPlan.soundEffects.length} จุดแล้ว`
            : 'AI วิเคราะห์แล้ว และเลือกไม่ใส่เอฟเฟกต์เสียงเพิ่มในคลิปนี้'
      }),
      audio: buildCapabilityStatus({ key: 'audio', enabled: capabilities.audio }),
      translate: buildCapabilityStatus({ key: 'translate', enabled: capabilities.translate }),
      pricetag: buildCapabilityStatus({ key: 'pricetag', enabled: capabilities.pricetag }),
      cta: buildCapabilityStatus({ key: 'cta', enabled: capabilities.cta }),
      watermark: buildCapabilityStatus({ key: 'watermark', enabled: capabilities.watermark })
    }
  };
};

/**
 * Builds the fine transcript timeline used only for AI cut planning.
 *
 * Planning must use the same word-aware boundaries as subtitles even when the
 * user turns automatic captions off. The returned shape remains the existing
 * EditPlanSegment contract; subtitle-only word metadata is intentionally not
 * exposed to callers.
 */
export const buildAiEditPlanningSegments = ({
  transcript,
  settings = {}
}: {
  transcript: TranscriptionResult;
  settings?: AiEditRecipeSettings;
}): EditPlanSegment[] => {
  const planningRecipe = buildAiEditRecipe({
    transcript,
    capabilities: {
      ...defaultCapabilities,
      subtitle: true,
      silence: false
    },
    settings,
    hasExplicitPlanRequest: false
  });

  return planningRecipe.subtitles.segments.map(
    ({ text, start, end, avgLogprob, noSpeechProbability, compressionRatio }) => ({
      text,
      start,
      end,
      ...(avgLogprob !== undefined ? { avgLogprob } : {}),
      ...(noSpeechProbability !== undefined
        ? { noSpeechProbability }
        : {}),
      ...(compressionRatio !== undefined ? { compressionRatio } : {})
    })
  );
};
