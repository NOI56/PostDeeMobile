import 'edit_styles.dart';
import 'subtitle_burn_video_processor.dart';

/// Keeps a target-length tail cut from ending in the middle of a subtitle.
///
/// Only the trailing cut moves, so this does not reorder selected moments or
/// change the opening hook. Nearby consecutive cues are kept as one phrase
/// while the result remains inside the configured duration tolerance.
List<SilenceCutRange> alignTargetTailToSubtitleBoundary({
  required List<SilenceCutRange> cuts,
  required List<SubtitleSegment> subtitleSegments,
  required double durationSeconds,
  required double targetSeconds,
  double toleranceSeconds = 1,
  double maximumContinuationGapSeconds = 0.35,
}) {
  if (cuts.isEmpty ||
      subtitleSegments.isEmpty ||
      durationSeconds <= 0 ||
      targetSeconds <= 0 ||
      toleranceSeconds < 0) {
    return cuts;
  }

  final sortedCuts = [...cuts]..sort((left, right) {
      return left.start.compareTo(right.start);
    });
  final trailingIndex = sortedCuts.lastIndexWhere(
    (cut) => cut.end >= durationSeconds - 0.001,
  );
  if (trailingIndex < 0) {
    return cuts;
  }

  final trailingCut = sortedCuts[trailingIndex];
  final boundary = trailingCut.start;
  final sortedSegments = [...subtitleSegments]
    ..sort((left, right) => left.start.compareTo(right.start));
  SubtitleSegment? crossingCue;
  var crossingCueIndex = -1;
  for (var index = 0; index < sortedSegments.length; index += 1) {
    final segment = sortedSegments[index];
    if (segment.text.trim().isEmpty || segment.end <= segment.start) {
      continue;
    }
    if (segment.start < boundary - 0.001 && segment.end > boundary + 0.001) {
      crossingCue = segment;
      crossingCueIndex = index;
      break;
    }
  }
  if (crossingCue == null) {
    return cuts;
  }

  List<SilenceCutRange>? candidateFor(double candidateBoundary) {
    final previousCutEnd =
        trailingIndex == 0 ? 0.0 : sortedCuts[trailingIndex - 1].end;
    if (candidateBoundary <= previousCutEnd + 0.001 ||
        candidateBoundary >= durationSeconds - 0.001) {
      return null;
    }
    final stillCrossesSubtitle = sortedSegments.any(
      (segment) =>
          segment.text.trim().isNotEmpty &&
          segment.start < candidateBoundary - 0.001 &&
          segment.end > candidateBoundary + 0.001,
    );
    if (stillCrossesSubtitle) {
      return null;
    }

    final candidate = [...sortedCuts];
    candidate[trailingIndex] = SilenceCutRange(
      start: candidateBoundary,
      end: trailingCut.end,
    );
    final resultSeconds = estimateResultSeconds(
      durationSeconds: durationSeconds,
      cutRanges: candidate,
    );
    if ((resultSeconds - targetSeconds).abs() > toleranceSeconds + 0.001) {
      return null;
    }
    return candidate;
  }

  var phraseEnd = crossingCue.end;
  var bestCompletePhrase = candidateFor(phraseEnd);
  for (var index = crossingCueIndex + 1;
      index < sortedSegments.length;
      index += 1) {
    final next = sortedSegments[index];
    if (next.text.trim().isEmpty || next.end <= next.start) {
      continue;
    }
    final gap = next.start - phraseEnd;
    if (gap > maximumContinuationGapSeconds + 0.001) {
      break;
    }
    if (next.end <= phraseEnd) {
      continue;
    }
    phraseEnd = next.end;
    final candidate = candidateFor(phraseEnd);
    if (candidate == null) {
      break;
    }
    bestCompletePhrase = candidate;
  }

  return bestCompletePhrase ?? candidateFor(crossingCue.start) ?? cuts;
}
