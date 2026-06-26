import '../../core/network/postdee_api_client.dart';
import 'edit_styles.dart';
import 'subtitle_burn_video_processor.dart';

/// A best-effort, client-side reading of a free-form Thai edit instruction.
/// Today it reliably handles a target length and "cut the swear words"; richer
/// natural-language understanding (e.g. "keep the part in the red shirt") is
/// left to a future AI backend.
class CustomPromptInstruction {
  const CustomPromptInstruction({
    this.targetSeconds,
    this.removeProfanity = false,
  });

  final double? targetSeconds;
  final bool removeProfanity;

  bool get isEmpty => targetSeconds == null && !removeProfanity;
}

/// A small starter list of clearly-vulgar Thai words to drop. Extend later or
/// move server-side once an AI moderation pass exists.
const List<String> kProfanityWords = [
  'เหี้ย',
  'สัส',
  'สัด',
  'ควย',
  'เย็ด',
  'แม่ง',
  'ระยำ',
  'ชิบหาย',
  'ฉิบหาย',
  'มึง',
  'กู',
  'เชี่ย',
  'หี',
  'อีดอก',
  'สถุล',
  'ตอแหล',
  'ไอ้สัตว์',
];

/// Parses a Thai instruction into the primitives PostDee can act on. Pure.
CustomPromptInstruction parseCustomPrompt(String prompt) {
  final text = prompt.toLowerCase();

  double? targetSeconds;
  final match =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(วินาที|วิ|นาที|min|sec)').firstMatch(text);
  if (match != null) {
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value != null && value > 0) {
      final unit = match.group(2)!;
      final isMinutes = unit == 'นาที' || unit == 'min';
      targetSeconds = isMinutes ? value * 60 : value;
    }
  }

  final removeProfanity = text.contains('หยาบ') ||
      text.contains('ไม่สุภาพ') ||
      text.contains('เซ็นเซอร์') ||
      text.contains('censor');

  return CustomPromptInstruction(
    targetSeconds: targetSeconds,
    removeProfanity: removeProfanity,
  );
}

/// Turns an instruction into absolute-second cut ranges: drop profane segments,
/// then trim the tail so the kept length fits the target. Pure + testable.
List<SilenceCutRange> buildCustomPromptCutRanges({
  required List<ClipTranscriptSegment> segments,
  required double durationSeconds,
  required CustomPromptInstruction instruction,
}) {
  if (durationSeconds <= 0) {
    return const [];
  }

  final cuts = <SilenceCutRange>[];

  if (instruction.removeProfanity) {
    for (final segment in segments) {
      if (segmentMatchesKeywords(segment.text, kProfanityWords)) {
        cuts.add(SilenceCutRange(start: segment.start, end: segment.end));
      }
    }
  }

  final target = instruction.targetSeconds;
  if (target != null && target > 0) {
    // Walk the still-kept spans and find the wall-clock time where the kept
    // duration reaches the target; cut everything after it.
    final kept = _complement(cuts, durationSeconds);
    var accumulated = 0.0;
    double? keepUntil;

    for (final interval in kept) {
      final length = interval[1] - interval[0];
      if (accumulated + length >= target) {
        keepUntil = interval[0] + (target - accumulated);
        break;
      }
      accumulated += length;
    }

    if (keepUntil != null && keepUntil < durationSeconds) {
      cuts.add(SilenceCutRange(start: keepUntil, end: durationSeconds));
    }
  }

  return cuts;
}

/// The gaps in [0, duration] not covered by [cuts], merged and sorted. Pure.
List<List<double>> _complement(List<SilenceCutRange> cuts, double duration) {
  if (cuts.isEmpty) {
    return [
      [0, duration],
    ];
  }

  final sorted = [...cuts]..sort((a, b) => a.start.compareTo(b.start));
  final result = <List<double>>[];
  var cursor = 0.0;

  for (final cut in sorted) {
    final start = cut.start.clamp(0.0, duration);
    final end = cut.end.clamp(0.0, duration);

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
