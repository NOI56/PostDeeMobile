import '../../core/network/postdee_api_client.dart';
import 'subtitle_burn_video_processor.dart';

class AiEditTimelineEvidence {
  const AiEditTimelineEvidence({
    required this.boundarySegments,
    required this.protectedSpeechRanges,
  });

  final List<SubtitleSegment> boundarySegments;
  final List<SilenceCutRange> protectedSpeechRanges;

  bool get hasReliableBoundaries => boundarySegments.isNotEmpty;
}

AiEditTimelineEvidence mapAiEditTimelineEvidence(
  AiEditTranscriptResult transcript,
) {
  final duration = transcript.durationSeconds;

  bool isValid(double start, double end) =>
      duration.isFinite &&
      duration > 0 &&
      start.isFinite &&
      end.isFinite &&
      start >= 0 &&
      end > start &&
      end <= duration;

  bool isReliable(ClipTranscriptSegment segment) {
    final text = segment.text.trim().toLowerCase();
    const leakedSignals = [
      'ชื่อแอปให้เขียนเป็นภาษาไทยว่า',
      'คำศัพท์เฉพาะ',
    ];
    final unexpectedScript = RegExp(
      r'[\u0400-\u04FF\u4E00-\u9FFF\uAC00-\uD7AF'
      r'\u0600-\u06FF\u0900-\u097F\u3040-\u30FF\uFFFD]',
      unicode: true,
    );
    final avgLogprob = segment.avgLogprob;
    final noSpeechProbability = segment.noSpeechProbability;
    final compressionRatio = segment.compressionRatio;

    return text.isNotEmpty &&
        !leakedSignals.any(text.contains) &&
        !unexpectedScript.hasMatch(text) &&
        (avgLogprob == null || (avgLogprob.isFinite && avgLogprob >= -1)) &&
        (noSpeechProbability == null ||
            (noSpeechProbability.isFinite && noSpeechProbability <= 0.6)) &&
        (compressionRatio == null ||
            (compressionRatio.isFinite && compressionRatio <= 2.4));
  }

  final boundaryCandidates = transcript.boundarySegments
      .where(
        (segment) => isReliable(segment) && isValid(segment.start, segment.end),
      )
      .map(
        (segment) => SubtitleSegment(
          text: segment.text.trim(),
          start: segment.start,
          end: segment.end,
        ),
      )
      .toList(growable: false)
    ..sort((left, right) {
      final byStart = left.start.compareTo(right.start);
      return byStart != 0 ? byStart : left.end.compareTo(right.end);
    });
  final boundariesOverlap = boundaryCandidates.asMap().entries.any(
        (entry) =>
            entry.key > 0 &&
            entry.value.start < boundaryCandidates[entry.key - 1].end,
      );
  final boundarySegments =
      boundariesOverlap ? const <SubtitleSegment>[] : boundaryCandidates;

  final protected = <SilenceCutRange>[
    for (final segment in transcript.segments)
      if (isValid(segment.start, segment.end))
        SilenceCutRange(start: segment.start, end: segment.end),
    for (final word in transcript.words)
      if (isValid(word.start, word.end))
        SilenceCutRange(start: word.start, end: word.end),
    for (final segment in transcript.segments)
      for (final word in segment.words ?? const <AiEditTranscriptWordResult>[])
        if (isValid(word.start, word.end))
          SilenceCutRange(start: word.start, end: word.end),
  ];

  return AiEditTimelineEvidence(
    boundarySegments: List<SubtitleSegment>.unmodifiable(boundarySegments),
    protectedSpeechRanges:
        List<SilenceCutRange>.unmodifiable(_mergeRanges(protected)),
  );
}

List<SilenceCutRange> _mergeRanges(List<SilenceCutRange> ranges) {
  if (ranges.isEmpty) return const [];

  final sorted = List<SilenceCutRange>.of(ranges)
    ..sort((left, right) {
      final byStart = left.start.compareTo(right.start);
      return byStart != 0 ? byStart : left.end.compareTo(right.end);
    });
  final merged = <SilenceCutRange>[];

  for (final range in sorted) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
      continue;
    }

    final previous = merged.removeLast();
    merged.add(
      SilenceCutRange(
        start: previous.start,
        end: range.end > previous.end ? range.end : previous.end,
      ),
    );
  }

  return merged;
}
