import { readThaiSubtitleWordParts } from './thaiSubtitleSegmentBoundaries.js';
import type {
  TranscriptSegment,
  TranscriptWord
} from './transcriptionProvider.js';

export type ThaiTimedWordReconstructionInput = {
  segments: readonly TranscriptSegment[];
  fragments: readonly TranscriptWord[];
  durationSeconds: number;
};

const maximumFragmentGapSeconds = 0.15;
const punctuationOrSymbolOnly = /^(?:[\p{P}\p{S}]|ฯ)+$/u;

const normalizeExactThaiText = (value: string): string =>
  value.normalize('NFC');

const readExactThaiWordParts = (value: string) =>
  readThaiSubtitleWordParts(
    normalizeExactThaiText(value).replace(/ฯ/gu, ' ฯ ')
  ).map((part) => ({
    segment: part.segment,
    isWordLike: part.isWordLike && part.segment !== 'ฯ'
  }));

const isValidDuration = (value: number): boolean =>
  Number.isFinite(value) && value > 0;

const hasValidOrderedTimeline = (
  ranges: readonly { start: number; end: number }[],
  durationSeconds: number
): boolean => {
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
      return false;
    }
    previousEnd = range.end;
  }

  return true;
};

const readFollowingPunctuationSuffix = (
  parts: ReturnType<typeof readExactThaiWordParts>,
  wordPartIndex: number
): string | undefined => {
  const suffix: string[] = [];

  for (let index = wordPartIndex + 1; index < parts.length; index += 1) {
    const part = parts[index]!;
    if (part.isWordLike) {
      break;
    }
    suffix.push(part.segment.replace(/\s+/gu, ''));
  }

  const normalizedSuffix = suffix.join('').normalize('NFC');
  if (
    normalizedSuffix.length > 0 &&
    !punctuationOrSymbolOnly.test(normalizedSuffix)
  ) {
    return undefined;
  }
  return normalizedSuffix;
};

const hasUnsupportedLeadingContent = (
  parts: ReturnType<typeof readExactThaiWordParts>
): boolean => {
  for (const part of parts) {
    if (part.isWordLike) {
      return false;
    }
    if (part.segment.replace(/\s+/gu, '').length > 0) {
      return true;
    }
  }
  return false;
};

const exceedsFragmentGap = (start: number, previousEnd: number): boolean =>
  start - previousEnd > maximumFragmentGapSeconds + Number.EPSILON;

/**
 * Rebuilds semantic Thai words from provider fragments only when every text
 * and timing boundary can be proven exactly. An undefined result means callers
 * must keep the original speech instead of estimating an automatic cut.
 */
export const reconstructThaiTimedWords = ({
  segments,
  fragments,
  durationSeconds
}: ThaiTimedWordReconstructionInput): TranscriptWord[] | undefined => {
  if (
    !Array.isArray(segments) ||
    !Array.isArray(fragments) ||
    !isValidDuration(durationSeconds) ||
    !hasValidOrderedTimeline(segments, durationSeconds) ||
    !hasValidOrderedTimeline(fragments, durationSeconds)
  ) {
    return undefined;
  }

  if (segments.length === 0 || fragments.length === 0) {
    return segments.length === 0 && fragments.length === 0 ? [] : undefined;
  }

  for (const fragment of fragments) {
    if (typeof fragment.word !== 'string') {
      return undefined;
    }
    const providerText = normalizeExactThaiText(fragment.word.trim());
    if (
      providerText.length === 0 ||
      /\s/u.test(providerText)
    ) {
      return undefined;
    }
  }

  const reconstructed: TranscriptWord[] = [];
  let fragmentIndex = 0;

  for (const segment of segments) {
    if (typeof segment.text !== 'string') {
      return undefined;
    }
    const parts = readExactThaiWordParts(segment.text);
    const semanticWords = parts
      .map((part, index) => ({ part, index }))
      .filter(({ part }) => part.isWordLike);

    if (
      semanticWords.length === 0 ||
      hasUnsupportedLeadingContent(parts)
    ) {
      return undefined;
    }

    for (const { part, index: partIndex } of semanticWords) {
      const semanticWord = normalizeExactThaiText(part.segment);
      const punctuationSuffix = readFollowingPunctuationSuffix(parts, partIndex);
      if (semanticWord.length === 0 || punctuationSuffix === undefined) {
        return undefined;
      }

      const first = fragments[fragmentIndex];
      if (
        !first ||
        first.start < segment.start ||
        first.end > segment.end
      ) {
        return undefined;
      }

      const start = first.start;
      let end = first.end;
      let rebuilt = '';
      let consumedAttachedPunctuation = false;

      while (rebuilt.length < semanticWord.length) {
        const fragment = fragments[fragmentIndex];
        if (
          !fragment ||
          fragment.start < segment.start ||
          fragment.end > segment.end ||
          (rebuilt.length > 0 && exceedsFragmentGap(fragment.start, end))
        ) {
          return undefined;
        }

        const providerText = normalizeExactThaiText(fragment.word.trim());
        const remainingWord = semanticWord.slice(rebuilt.length);
        if (
          punctuationSuffix.length > 0 &&
          providerText === `${remainingWord}${punctuationSuffix}`
        ) {
          rebuilt += remainingWord;
          consumedAttachedPunctuation = true;
        } else {
          rebuilt += providerText;
        }

        fragmentIndex += 1;
        end = fragment.end;
        if (!semanticWord.startsWith(rebuilt)) {
          return undefined;
        }
      }

      if (rebuilt !== semanticWord) {
        return undefined;
      }

      const punctuationFragment = fragments[fragmentIndex];
      const providerPunctuation = punctuationFragment?.word
        ? normalizeExactThaiText(punctuationFragment.word.trim())
        : undefined;
      if (
        !consumedAttachedPunctuation &&
        providerPunctuation &&
        punctuationOrSymbolOnly.test(providerPunctuation)
      ) {
        if (
          providerPunctuation !== punctuationSuffix ||
          !punctuationFragment ||
          punctuationFragment.start < segment.start ||
          punctuationFragment.end > segment.end ||
          exceedsFragmentGap(punctuationFragment.start, end)
        ) {
          return undefined;
        }
        end = punctuationFragment.end;
        fragmentIndex += 1;
      }

      reconstructed.push({
        word: `${semanticWord}${punctuationSuffix}`,
        start,
        end
      });
    }
  }

  return fragmentIndex === fragments.length ? reconstructed : undefined;
};
