import 'subtitle_burn_video_processor.dart';

/// User fine-tuning applied on top of a chosen style. All fields optional; null
/// means "use the style/clip default".
class EditStyleOptions {
  const EditStyleOptions({
    this.targetSeconds,
    this.subtitleMaxChars,
    this.silenceMinGapSec,
    this.speed,
    this.filterIndex,
    this.subtitleFontSize,
    this.subtitleAtBottom,
    this.brightness,
    this.contrast,
  });

  /// Trim the clip to roughly this length (null = keep original length).
  final int? targetSeconds;

  /// Max characters per burned subtitle line (null = no re-chunking). Uses
  /// characters (not words) because Thai has no spaces between words.
  final int? subtitleMaxChars;

  /// Override the auto silence-cut gap threshold (null = use the style's value).
  final double? silenceMinGapSec;

  /// Playback/export speed override (null = keep the style's speed).
  final double? speed;

  /// Color-grade filter index override (null = keep the style's look).
  final int? filterIndex;

  /// Burned subtitle font size and position (null = defaults).
  final double? subtitleFontSize;
  final bool? subtitleAtBottom;

  /// Brightness / contrast adjustments (-1..1; null = keep current).
  final double? brightness;
  final double? contrast;

  EditStyleOptions copyWith({
    int? targetSeconds,
    int? subtitleMaxChars,
    double? silenceMinGapSec,
    double? speed,
    int? filterIndex,
    double? subtitleFontSize,
    bool? subtitleAtBottom,
    double? brightness,
    double? contrast,
    bool clearTarget = false,
    bool clearSubtitle = false,
    bool clearSilence = false,
  }) {
    return EditStyleOptions(
      targetSeconds: clearTarget ? null : (targetSeconds ?? this.targetSeconds),
      subtitleMaxChars:
          clearSubtitle ? null : (subtitleMaxChars ?? this.subtitleMaxChars),
      silenceMinGapSec:
          clearSilence ? null : (silenceMinGapSec ?? this.silenceMinGapSec),
      speed: speed ?? this.speed,
      filterIndex: filterIndex ?? this.filterIndex,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleAtBottom: subtitleAtBottom ?? this.subtitleAtBottom,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
    );
  }
}

List<SilenceCutRange> _normalizeCutRanges(
  List<SilenceCutRange> cuts,
  double duration,
) {
  final normalized = <SilenceCutRange>[];
  final sorted = [...cuts]..sort((a, b) => a.start.compareTo(b.start));

  for (final cut in sorted) {
    final start = cut.start.clamp(0.0, duration);
    final end = cut.end.clamp(0.0, duration);
    if (end <= start) {
      continue;
    }
    if (normalized.isNotEmpty && start <= normalized.last.end + 0.001) {
      final previous = normalized.removeLast();
      normalized.add(
        SilenceCutRange(
          start: previous.start,
          end: end > previous.end ? end : previous.end,
        ),
      );
    } else {
      normalized.add(SilenceCutRange(start: start, end: end));
    }
  }

  return normalized;
}

/// Gaps in [0, duration] not covered by [cuts], merged and sorted. Pure.
List<List<double>> _complement(List<SilenceCutRange> cuts, double duration) {
  final normalizedCuts = _normalizeCutRanges(cuts, duration);
  if (normalizedCuts.isEmpty) {
    return [
      [0, duration],
    ];
  }

  final result = <List<double>>[];
  var cursor = 0.0;

  for (final cut in normalizedCuts) {
    final start = cut.start;
    final end = cut.end;
    if (start > cursor) {
      result.add([cursor, start]);
    }
    if (end > cursor) {
      cursor = end;
    }
  }

  if (cursor < duration) {
    result.add([cursor, duration]);
  }

  return result;
}

/// Makes the kept (non-cut) length fit [targetSeconds]. If AI/silence cuts
/// remove too much, nearby context is restored around the selected moments
/// instead of returning a clip that is far shorter than the requested length.
/// Pure + testable.
List<SilenceCutRange> withTargetLength(
  List<SilenceCutRange> cuts,
  double durationSeconds,
  double targetSeconds,
) {
  if (targetSeconds <= 0 || durationSeconds <= 0) {
    return cuts;
  }

  final desiredSeconds = targetSeconds.clamp(0.0, durationSeconds);
  if (desiredSeconds >= durationSeconds) {
    return const [];
  }

  final normalizedCuts = _normalizeCutRanges(cuts, durationSeconds);
  final kept = _complement(normalizedCuts, durationSeconds);
  var accumulated = 0.0;
  double? keepUntil;

  for (final interval in kept) {
    final length = interval[1] - interval[0];
    if (accumulated + length >= desiredSeconds) {
      keepUntil = interval[0] + (desiredSeconds - accumulated);
      break;
    }
    accumulated += length;
  }

  if (keepUntil != null && keepUntil < durationSeconds) {
    return _normalizeCutRanges(
      [
        ...normalizedCuts,
        SilenceCutRange(start: keepUntil, end: durationSeconds),
      ],
      durationSeconds,
    );
  }

  // The selected speech/highlight ranges are shorter than requested. Restore
  // context proportionally from the edges of every cut while preserving all
  // moments that AI selected.
  if (accumulated > 0 && normalizedCuts.isNotEmpty) {
    final totalCutSeconds = durationSeconds - accumulated;
    final secondsToRestore = desiredSeconds - accumulated;
    final remainingCutFraction =
        ((totalCutSeconds - secondsToRestore) / totalCutSeconds)
            .clamp(0.0, 1.0);
    final adjusted = <SilenceCutRange>[];

    for (final cut in normalizedCuts) {
      final remainingLength = (cut.end - cut.start) * remainingCutFraction;
      if (remainingLength <= 0.001) {
        continue;
      }

      if (cut.start <= 0.001) {
        adjusted.add(
          SilenceCutRange(start: 0, end: remainingLength),
        );
      } else if (cut.end >= durationSeconds - 0.001) {
        adjusted.add(
          SilenceCutRange(
            start: durationSeconds - remainingLength,
            end: durationSeconds,
          ),
        );
      } else {
        final center = (cut.start + cut.end) / 2;
        adjusted.add(
          SilenceCutRange(
            start: center - remainingLength / 2,
            end: center + remainingLength / 2,
          ),
        );
      }
    }

    return _normalizeCutRanges(adjusted, durationSeconds);
  }

  // No usable selected moment remains. Keep a deterministic opening window
  // rather than exporting an empty/near-empty video.
  return [
    SilenceCutRange(start: desiredSeconds, end: durationSeconds),
  ];
}

/// Splits a line into pieces near [maxChars], preferring to break at spaces.
/// Long Thai runs are kept intact because an arbitrary character boundary can
/// split a word or combining character. Other long runs are hard-split. Pure.
List<String> splitLineByMaxChars(String text, int maxChars) {
  final trimmed = text.trim();
  if (maxChars <= 0 || trimmed.length <= maxChars) {
    return trimmed.isEmpty ? const [] : [trimmed];
  }

  final pieces = <String>[];
  var current = '';

  void flush() {
    if (current.isNotEmpty) {
      pieces.add(current);
      current = '';
    }
  }

  for (final word in trimmed.split(' ')) {
    if (word.isEmpty) {
      continue;
    }

    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length <= maxChars) {
      current = candidate;
      continue;
    }

    flush();

    if (word.length <= maxChars || RegExp(r'[\u0E00-\u0E7F]').hasMatch(word)) {
      current = word;
    } else {
      var rest = word;
      while (rest.length > maxChars) {
        pieces.add(rest.substring(0, maxChars));
        rest = rest.substring(maxChars);
      }
      current = rest;
    }
  }

  flush();
  return pieces.isEmpty ? [trimmed] : pieces;
}

/// Re-chunks subtitle segments so each line is at most [maxChars], splitting a
/// segment's time window proportionally to each piece's length. Pure + testable.
List<SubtitleSegment> rechunkSubtitleByMaxChars(
  List<SubtitleSegment> segments,
  int maxChars,
) {
  if (maxChars <= 0) {
    return segments;
  }

  final out = <SubtitleSegment>[];

  for (final segment in segments) {
    final pieces = splitLineByMaxChars(segment.text, maxChars);
    if (pieces.length <= 1) {
      out.add(segment);
      continue;
    }

    final totalChars = pieces.fold<int>(0, (sum, p) => sum + p.length);
    final span = segment.end - segment.start;
    var cursor = segment.start;

    for (final piece in pieces) {
      final fraction =
          totalChars > 0 ? piece.length / totalChars : 1 / pieces.length;
      final pieceEnd = (cursor + span * fraction).clamp(cursor, segment.end);
      out.add(SubtitleSegment(text: piece, start: cursor, end: pieceEnd));
      cursor = pieceEnd;
    }
  }

  return out;
}
