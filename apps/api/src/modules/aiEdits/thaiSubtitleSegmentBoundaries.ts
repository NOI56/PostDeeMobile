import {
  normalizeTranscriptionLanguage,
  type TranscriptSegment
} from './transcriptionProvider.js';

// ElevenLabs word events are normally contiguous. Allow small timestamp jitter
// while staying far below the 0.55-second pause used to start a new segment.
const maximumThaiFragmentGapSeconds = 0.12;
const maximumThaiFragmentOverlapSeconds = 0.02;

const normalizeTranscriptTextForBoundaries = (value: string): string =>
  value
    .normalize('NFC')
    .toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');

const readThaiWordBoundaryOffsets = (value: string): Set<number> => {
  const boundaries = new Set<number>();
  let offset = 0;

  const segments = new Intl.Segmenter('th', {
    granularity: 'word'
  }).segment(value);
  for (const segment of segments) {
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
  const wordBoundaries = readThaiWordBoundaryOffsets(semanticReferenceText);
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
