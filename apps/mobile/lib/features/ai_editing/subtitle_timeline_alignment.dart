import 'dart:math' as math;

import 'edit_styles.dart';
import 'subtitle_burn_video_processor.dart';

const _standaloneThaiContinuationWords = <String>{
  'ก็',
  'แต่',
  'แล้ว',
  'และ',
  'ที่',
  'เพื่อ',
  'โดย',
  'ซึ่ง',
  'เพราะ',
  'ถ้า',
  'เมื่อ',
  'หรือ',
  'กับ',
  'จะ',
  'ต้อง',
  'ไม่',
  'อยู่',
};

const _joinedThaiContinuationEndings = <String>{
  'ก็',
  'ดีที่',
  'กำลังจะ',
  'อยากจะ',
  'ต้องการจะ',
  'แล้วจะ',
  'ก็จะ',
  'เพราะว่า',
  'เนื่องจาก',
};

const _thaiLocationComplementPrefixes = <String>{
  'ที่',
  'ใน',
  'แถว',
  'ใกล้',
  'ตรง',
  'บน',
  'ข้าง',
  'หน้า',
  'หลัง',
  'ริม',
};

const _joinedThaiThoughtTransitions = <String>{
  'แต่ก็',
  'แต่ว่า',
  'แต่ถ้า',
  'แต่ยัง',
  'แต่จะ',
  'แต่ไม่',
  'แล้วก็',
  'จากนั้น',
  'ดังนั้น',
  'เพราะฉะนั้น',
  'สุดท้าย',
  'ต่อมา',
  'ทีนี้',
};

final _trailingSubtitleSeparators = RegExp(r'[\s.,!?;:ฯๆ…]+$');
final _leadingSubtitleSeparators = RegExp(r'^[\s.,!?;:ฯๆ…]+');
final _subtitleTokenSeparators = RegExp(r'[\s.,!?;:ฯๆ…]+');

String _normalizedTailText(String text) =>
    text.trim().toLowerCase().replaceFirst(_trailingSubtitleSeparators, '');

/// Conservative Thai tail check.
///
/// Most continuation words are accepted only as a complete token. This avoids
/// treating substrings inside real words such as "แต่งตัว", "สถานที่", or
/// "เมื่อวาน" as grammar signals. A short allowlist covers high-confidence
/// endings that are commonly joined in Thai captions, such as "โชคดีที่",
/// "กำลังจะ", and "เพราะว่า". A cue ending in "อยู่" continues only when the
/// next cue starts with a location complement such as "ที่บ้าน" or "ในเมือง".
bool _thaiCueNeedsContinuation(
  String text, {
  String? followingText,
}) {
  final normalized = _normalizedTailText(text);
  if (normalized.isEmpty) return false;

  final tokens = normalized
      .split(_subtitleTokenSeparators)
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isNotEmpty &&
      _standaloneThaiContinuationWords.contains(tokens.last) &&
      (tokens.length > 1 || tokens.single == normalized)) {
    return true;
  }

  if (_joinedThaiContinuationEndings.any(normalized.endsWith)) {
    return true;
  }

  final normalizedFollowing = followingText
      ?.trim()
      .toLowerCase()
      .replaceFirst(_leadingSubtitleSeparators, '');
  return normalized.endsWith('อยู่') &&
      normalizedFollowing != null &&
      normalizedFollowing.isNotEmpty &&
      _thaiLocationComplementPrefixes.any(normalizedFollowing.startsWith);
}

bool _startsNewThaiThought(String text) {
  final normalized =
      text.trim().toLowerCase().replaceFirst(_leadingSubtitleSeparators, '');
  if (normalized.isEmpty) return false;
  if (_joinedThaiThoughtTransitions.any(normalized.startsWith)) {
    return true;
  }

  final tokens = normalized
      .split(_subtitleTokenSeparators)
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  return tokens.isNotEmpty &&
      _standaloneThaiContinuationWords.contains(tokens.first) &&
      (tokens.length > 1 || tokens.single == normalized);
}

/// Allows a small semantic tail without turning a very short request into a
/// much longer clip: 10% of target, bounded to 1..3 seconds by default.
double aiEditSemanticTailToleranceSeconds({
  required double targetSeconds,
  double baseToleranceSeconds = 1,
  double maximumToleranceSeconds = 3,
}) {
  if (!targetSeconds.isFinite ||
      targetSeconds <= 0 ||
      !baseToleranceSeconds.isFinite ||
      baseToleranceSeconds < 0 ||
      !maximumToleranceSeconds.isFinite ||
      maximumToleranceSeconds < 0) {
    return 0;
  }
  return math.min(
    maximumToleranceSeconds,
    math.max(baseToleranceSeconds, targetSeconds * 0.1),
  );
}

double aiEditMaximumOutputDurationSeconds({
  required double targetSeconds,
  double? estimatedOutputSeconds,
}) {
  if (!targetSeconds.isFinite || targetSeconds <= 0) {
    return 0;
  }
  final safeEstimate = estimatedOutputSeconds != null &&
          estimatedOutputSeconds.isFinite &&
          estimatedOutputSeconds > 0
      ? estimatedOutputSeconds
      : targetSeconds;
  return math.min(
    targetSeconds +
        aiEditSemanticTailToleranceSeconds(targetSeconds: targetSeconds),
    math.max(targetSeconds, safeEstimate),
  );
}

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
  double maximumPhraseTargetDeviationSeconds = 3,
}) {
  if (cuts.isEmpty ||
      subtitleSegments.isEmpty ||
      durationSeconds <= 0 ||
      targetSeconds <= 0 ||
      toleranceSeconds < 0 ||
      maximumContinuationGapSeconds < 0 ||
      maximumPhraseTargetDeviationSeconds < 0) {
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
  final semanticTailTolerance = aiEditSemanticTailToleranceSeconds(
    targetSeconds: targetSeconds,
    baseToleranceSeconds: toleranceSeconds,
    maximumToleranceSeconds: maximumPhraseTargetDeviationSeconds,
  );

  final trailingCut = sortedCuts[trailingIndex];
  final boundary = trailingCut.start;
  final sortedSegments = subtitleSegments
      .where(
        (segment) =>
            segment.text.trim().isNotEmpty &&
            segment.start.isFinite &&
            segment.end.isFinite &&
            segment.end > segment.start,
      )
      .toList()
    ..sort((left, right) => left.start.compareTo(right.start));

  bool cueNeedsContinuationAt(int index) {
    final followingText = index + 1 < sortedSegments.length
        ? sortedSegments[index + 1].text
        : null;
    return _thaiCueNeedsContinuation(
      sortedSegments[index].text,
      followingText: followingText,
    );
  }

  List<SilenceCutRange>? candidateFor(
    double candidateBoundary, {
    required double allowedTargetDeviationSeconds,
  }) {
    final previousCutEnd =
        trailingIndex == 0 ? 0.0 : sortedCuts[trailingIndex - 1].end;
    if (candidateBoundary <= previousCutEnd + 0.001 ||
        candidateBoundary > durationSeconds + 0.001) {
      return null;
    }
    final stillCrossesSubtitle = sortedSegments.any(
      (segment) =>
          segment.start < candidateBoundary - 0.001 &&
          segment.end > candidateBoundary + 0.001,
    );
    if (stillCrossesSubtitle) {
      return null;
    }

    final candidate = [...sortedCuts];
    if (candidateBoundary >= durationSeconds - 0.001) {
      candidate.removeAt(trailingIndex);
    } else {
      candidate[trailingIndex] = SilenceCutRange(
        start: candidateBoundary,
        end: trailingCut.end,
      );
    }
    final resultSeconds = estimateResultSeconds(
      durationSeconds: durationSeconds,
      cutRanges: candidate,
    );
    if ((resultSeconds - targetSeconds).abs() >
        allowedTargetDeviationSeconds + 0.001) {
      return null;
    }
    return candidate;
  }

  SubtitleSegment? crossingCue;
  var crossingCueIndex = -1;
  for (var index = 0; index < sortedSegments.length; index += 1) {
    final segment = sortedSegments[index];
    if (segment.start < boundary - 0.001 && segment.end > boundary + 0.001) {
      crossingCue = segment;
      crossingCueIndex = index;
      break;
    }
  }

  if (crossingCue != null) {
    if (!cueNeedsContinuationAt(crossingCueIndex)) {
      return candidateFor(
            crossingCue.end,
            allowedTargetDeviationSeconds: toleranceSeconds,
          ) ??
          candidateFor(
            crossingCue.start,
            allowedTargetDeviationSeconds: toleranceSeconds,
          ) ??
          cuts;
    }
  }

  List<SilenceCutRange>? completePhraseAfter(int startingCueIndex) {
    var phraseEnd = sortedSegments[startingCueIndex].end;
    for (var index = startingCueIndex + 1;
        index < sortedSegments.length;
        index += 1) {
      final next = sortedSegments[index];
      final gap = next.start - phraseEnd;
      if (gap > maximumContinuationGapSeconds + 0.001 ||
          _startsNewThaiThought(next.text)) {
        break;
      }
      if (next.end <= phraseEnd) {
        continue;
      }
      phraseEnd = next.end;
      final candidate = candidateFor(
        phraseEnd,
        allowedTargetDeviationSeconds: semanticTailTolerance,
      );
      if (candidate == null) {
        break;
      }

      final hasFollowingCue = index + 1 < sortedSegments.length;
      final nextStartsNewThought = hasFollowingCue &&
          _startsNewThaiThought(sortedSegments[index + 1].text);
      final nextGap = hasFollowingCue
          ? sortedSegments[index + 1].start - phraseEnd
          : double.infinity;
      final isPhraseBoundary = !hasFollowingCue ||
          nextStartsNewThought ||
          nextGap > maximumContinuationGapSeconds + 0.001;
      if (!cueNeedsContinuationAt(index) && isPhraseBoundary) {
        return candidate;
      }
    }
    return null;
  }

  if (crossingCue != null) {
    return completePhraseAfter(crossingCueIndex) ??
        candidateFor(
          crossingCue.start,
          allowedTargetDeviationSeconds: toleranceSeconds,
        ) ??
        cuts;
  }

  var lastRetainedCueIndex = -1;
  for (var index = 0; index < sortedSegments.length; index += 1) {
    final segment = sortedSegments[index];
    if (segment.end <= boundary + 0.001) {
      lastRetainedCueIndex = index;
      continue;
    }
    break;
  }
  if (lastRetainedCueIndex < 0) {
    return cuts;
  }

  final lastRetainedCue = sortedSegments[lastRetainedCueIndex];
  if ((lastRetainedCue.end - boundary).abs() > 0.001 ||
      !cueNeedsContinuationAt(lastRetainedCueIndex)) {
    return cuts;
  }

  return completePhraseAfter(lastRetainedCueIndex) ??
      candidateFor(
        lastRetainedCue.start,
        allowedTargetDeviationSeconds: toleranceSeconds,
      ) ??
      cuts;
}
