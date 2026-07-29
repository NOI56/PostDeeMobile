import {
  normalizeTranscriptionLanguage,
  type TranscriptSegment
} from './transcriptionProvider.js';

// ElevenLabs word events are normally contiguous. Allow small timestamp jitter
// while staying far below the 0.55-second pause used to start a new segment.
const maximumThaiFragmentGapSeconds = 0.12;
const maximumThaiFragmentOverlapSeconds = 0.02;

// Intl.Segmenter is dictionary-based and can split a real Thai word at a
// dictionary boundary. Keep confirmed production words together before the
// boundaries are used by transcript repair or subtitle cue construction.
const indivisibleThaiSubtitleTerms = [
  'ดุ๊กดิ๊ก',
  'โซเชียล',
  'ซุปเปอร์สตาร์',
  'ฮิปโปซุปเปอร์สตาร์',
  'สวนสัตว์เขาเขียว',
  'สวนสัตว์เปิดเขาเขียว'
] as const;

export type ThaiSubtitleWordPart = {
  segment: string;
  isWordLike: boolean;
};

const normalizeTranscriptTextForBoundaries = (value: string): string =>
  value
    .normalize('NFC')
    .toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');

const readIndivisibleTermMatch = (
  parts: ThaiSubtitleWordPart[],
  startIndex: number
): {
  endIndex: number;
  matchedEndOffset: number;
} | undefined => {
  for (const term of indivisibleThaiSubtitleTerms) {
    let candidate = '';

    for (let index = startIndex; index < parts.length; index += 1) {
      const part = parts[index]!;
      if (!part.isWordLike) {
        break;
      }

      const previousLength = candidate.length;
      candidate += part.segment;
      if (candidate === term) {
        return {
          endIndex: index,
          matchedEndOffset: part.segment.length
        };
      }
      if (candidate.startsWith(term)) {
        const matchedEndOffset = term.length - previousLength;
        if (
          matchedEndOffset > 0 &&
          matchedEndOffset < part.segment.length
        ) {
          return { endIndex: index, matchedEndOffset };
        }
        break;
      }
      if (!term.startsWith(candidate)) {
        break;
      }
    }
  }

  return undefined;
};

export const readThaiSubtitleWordParts = (
  value: string
): ThaiSubtitleWordPart[] => {
  const rawParts = Array.from(
    new Intl.Segmenter('th', { granularity: 'word' })
      .segment(value.normalize('NFC'))
  ).map((part) => ({
    segment: part.segment,
    isWordLike: part.isWordLike === true
  }));
  const parts: ThaiSubtitleWordPart[] = [];

  for (let index = 0; index < rawParts.length; index += 1) {
    const match = readIndivisibleTermMatch(rawParts, index);
    if (match === undefined) {
      parts.push(rawParts[index]!);
      continue;
    }

    const matchedEndPart = rawParts[match.endIndex]!;
    parts.push({
      segment: [
        ...rawParts
          .slice(index, match.endIndex)
          .map((part) => part.segment),
        matchedEndPart.segment.slice(0, match.matchedEndOffset)
      ]
        .join(''),
      isWordLike: true
    });

    const remainingEndPart = matchedEndPart.segment.slice(
      match.matchedEndOffset
    );
    if (remainingEndPart) {
      rawParts[match.endIndex] = {
        segment: remainingEndPart,
        isWordLike: matchedEndPart.isWordLike
      };
      index = match.endIndex - 1;
    } else {
      index = match.endIndex;
    }
  }

  return parts;
};

export const readThaiSubtitleWordBoundaryOffsets = (
  value: string
): Set<number> => {
  const boundaries = new Set<number>();
  let offset = 0;

  for (const segment of readThaiSubtitleWordParts(value)) {
    const normalizedSegment =
      normalizeTranscriptTextForBoundaries(segment.segment);
    const segmentLength = Array.from(normalizedSegment).length;
    if (segment.isWordLike && segmentLength > 0) {
      boundaries.add(offset);
      boundaries.add(offset + segmentLength);
    }
    offset += segmentLength;
  }

  return boundaries;
};

const joinSubtitleText = (left: string, right: string): string => {
  const first = left.trim();
  const second = right.trim();
  if (!first) return second;
  if (!second) return first;
  if (/^[\)\]\}\.,!?;:ฯๆ]/u.test(second)) {
    return `${first}${second}`;
  }
  const joinsThaiText =
    /[\u0E00-\u0E7F]$/u.test(first) &&
    /^[\u0E00-\u0E7F]/u.test(second);
  return `${first}${joinsThaiText ? '' : ' '}${second}`;
};

/**
 * Repairs stored/provider transcript segments whose timestamp boundary lands
 * inside one semantic Thai word. The same helper is used before highlight
 * planning and subtitle construction so both stages agree on safe boundaries.
 */
export const repairThaiSubtitleSegmentBoundaries = (
  segments: TranscriptSegment[],
  language = 'th',
  referenceText = segments.map((segment) => segment.text).join('')
): TranscriptSegment[] => {
  if (
    normalizeTranscriptionLanguage(language) !== 'th' ||
    segments.length < 2
  ) {
    return segments;
  }

  const normalizedSegmentTexts = segments.map((segment) =>
    normalizeTranscriptTextForBoundaries(segment.text)
  );
  const combinedText = normalizedSegmentTexts.join('');
  const normalizedReferenceText =
    normalizeTranscriptTextForBoundaries(referenceText);
  const semanticReferenceText =
    normalizedReferenceText === combinedText
      ? referenceText
      : segments.map((segment) => segment.text).join('');
  const wordBoundaries =
    readThaiSubtitleWordBoundaryOffsets(semanticReferenceText);
  const repaired: TranscriptSegment[] = [{ ...segments[0]! }];
  let boundaryOffset = Array.from(normalizedSegmentTexts[0]!).length;

  for (let index = 1; index < segments.length; index += 1) {
    const segment = segments[index]!;
    const previous = repaired.at(-1)!;
    const previousText = previous.text.trim().normalize('NFC');
    const nextText = segment.text.trim().normalize('NFC');
    const joinsThaiText =
      /[\u0E00-\u0E7F]$/u.test(previousText) &&
      /^[\u0E00-\u0E7F]/u.test(nextText);
    const timingGap = segment.start - previous.end;
    const hasValidAdjacentTiming =
      Number.isFinite(previous.start) &&
      Number.isFinite(previous.end) &&
      Number.isFinite(segment.start) &&
      Number.isFinite(segment.end) &&
      previous.end > previous.start &&
      segment.end > segment.start &&
      segment.start >= previous.start &&
      segment.end >= previous.end &&
      timingGap >= -maximumThaiFragmentOverlapSeconds &&
      timingGap <= maximumThaiFragmentGapSeconds;
    const splitsSemanticWord =
      joinsThaiText &&
      hasValidAdjacentTiming &&
      !wordBoundaries.has(boundaryOffset);

    if (splitsSemanticWord) {
      repaired[repaired.length - 1] = {
        ...previous,
        text: joinSubtitleText(previous.text, segment.text),
        end: Math.max(previous.end, segment.end)
      };
    } else {
      repaired.push({ ...segment });
    }

    boundaryOffset += Array.from(normalizedSegmentTexts[index]!).length;
  }

  return repaired;
};
