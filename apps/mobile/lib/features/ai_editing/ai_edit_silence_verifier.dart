import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import 'subtitle_burn_video_processor.dart';

class AiEditSilenceDetectOutput {
  const AiEditSilenceDetectOutput({
    required this.succeeded,
    required this.logs,
  });

  final bool succeeded;
  final String logs;
}

class AiEditSilenceVerificationResult {
  const AiEditSilenceVerificationResult({
    required this.cutRanges,
    required this.probeSucceeded,
  });

  const AiEditSilenceVerificationResult.failed()
      : cutRanges = const [],
        probeSucceeded = false;

  final List<SilenceCutRange> cutRanges;
  final bool probeSucceeded;
}

typedef AiEditSilenceDetectRunner = Future<AiEditSilenceDetectOutput> Function(
  List<String> arguments,
);

const _sourceEdgeEpsilonSeconds = 0.001;

List<SilenceCutRange> parseAiEditSilenceLog(
  String logs, {
  required double sourceDurationSeconds,
}) {
  if (!sourceDurationSeconds.isFinite || sourceDurationSeconds <= 0) {
    return const [];
  }

  // Capture malformed markers too. Encountering one closes any pending pair
  // so a later timestamp can never be joined across corrupt log evidence.
  final eventPattern = RegExp(
    r'silence_(start|end)(?:\s*:\s*([^\s|]+))?',
  );
  final parsed = <SilenceCutRange>[];
  double? openStart;

  for (final match in eventPattern.allMatches(logs)) {
    final valueText = match.group(2);
    final value = valueText == null ? null : double.tryParse(valueText);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > sourceDurationSeconds) {
      openStart = null;
      continue;
    }

    if (match.group(1) == 'start') {
      if (openStart != null) {
        // Two starts without an end make both markers ambiguous.
        openStart = null;
        continue;
      }
      openStart = value;
      continue;
    }

    final start = openStart;
    openStart = null;
    if (start == null || value <= start) {
      continue;
    }
    parsed.add(SilenceCutRange(start: start, end: value));
  }

  return List<SilenceCutRange>.unmodifiable(parsed);
}

List<SilenceCutRange> intersectVerifiedSilenceCuts({
  required List<SilenceCutRange> transcriptCandidates,
  required List<SilenceCutRange> waveformSilences,
  required List<SilenceCutRange> protectedSpeechRanges,
  required double sourceDurationSeconds,
  double safetyPaddingSeconds = 0.10,
  double minimumCutSeconds = 0.25,
}) {
  if (!sourceDurationSeconds.isFinite ||
      sourceDurationSeconds <= 0 ||
      !safetyPaddingSeconds.isFinite ||
      safetyPaddingSeconds < 0 ||
      !minimumCutSeconds.isFinite ||
      minimumCutSeconds < 0) {
    return const [];
  }

  bool isValidRange(SilenceCutRange range) =>
      range.start.isFinite &&
      range.end.isFinite &&
      range.start >= 0 &&
      range.end > range.start &&
      range.end <= sourceDurationSeconds;

  final candidates = transcriptCandidates
      .where(
        (range) =>
            isValidRange(range) &&
            range.start > _sourceEdgeEpsilonSeconds &&
            range.end < sourceDurationSeconds - _sourceEdgeEpsilonSeconds,
      )
      .toList(growable: false)
    ..sort(_compareRanges);
  final waveform = waveformSilences.where(isValidRange).toList(growable: false)
    ..sort(_compareRanges);
  final protected = protectedSpeechRanges
      .where(isValidRange)
      .toList(growable: false)
    ..sort(_compareRanges);

  final verified = <SilenceCutRange>[];
  for (final candidate in candidates) {
    for (final detectedSilence in waveform) {
      if (detectedSilence.end <= candidate.start) {
        continue;
      }
      if (detectedSilence.start >= candidate.end) {
        break;
      }

      final overlapStart = math.max(candidate.start, detectedSilence.start);
      final overlapEnd = math.min(candidate.end, detectedSilence.end);
      final paddedStart = overlapStart + safetyPaddingSeconds;
      final paddedEnd = overlapEnd - safetyPaddingSeconds;
      if (paddedEnd <= paddedStart ||
          paddedEnd - paddedStart < minimumCutSeconds) {
        continue;
      }

      final overlapsProtectedSpeech = protected.any(
        (speech) => paddedStart < speech.end && paddedEnd > speech.start,
      );
      if (overlapsProtectedSpeech) {
        // Do not split around speech: that would invent a new cut.
        continue;
      }

      verified.add(
        SilenceCutRange(start: paddedStart, end: paddedEnd),
      );
    }
  }

  return List<SilenceCutRange>.unmodifiable(_mergeRanges(verified));
}

class AiEditSilenceVerifier {
  AiEditSilenceVerifier({AiEditSilenceDetectRunner? runFfmpeg})
      : _runFfmpeg = runFfmpeg ?? _runNativeFfmpeg;

  final AiEditSilenceDetectRunner _runFfmpeg;

  Future<AiEditSilenceVerificationResult> call({
    required File sourceFile,
    required double sourceDurationSeconds,
    required List<SilenceCutRange> transcriptCandidates,
    required List<SilenceCutRange> protectedSpeechRanges,
  }) async {
    if (!sourceDurationSeconds.isFinite || sourceDurationSeconds <= 0) {
      return const AiEditSilenceVerificationResult.failed();
    }

    final arguments = <String>[
      '-hide_banner',
      '-nostats',
      '-i',
      sourceFile.path,
      '-af',
      'silencedetect=noise=-40dB:d=0.20',
      '-f',
      'null',
      '-',
    ];

    try {
      final output = await _runFfmpeg(arguments);
      if (!output.succeeded) {
        return const AiEditSilenceVerificationResult.failed();
      }

      final waveformSilences = parseAiEditSilenceLog(
        output.logs,
        sourceDurationSeconds: sourceDurationSeconds,
      );
      final cutRanges = intersectVerifiedSilenceCuts(
        transcriptCandidates: transcriptCandidates,
        waveformSilences: waveformSilences,
        protectedSpeechRanges: protectedSpeechRanges,
        sourceDurationSeconds: sourceDurationSeconds,
      );
      return AiEditSilenceVerificationResult(
        cutRanges: cutRanges,
        probeSucceeded: true,
      );
    } catch (_) {
      return const AiEditSilenceVerificationResult.failed();
    }
  }
}

Future<AiEditSilenceDetectOutput> _runNativeFfmpeg(
  List<String> arguments,
) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  final returnCode = await session.getReturnCode();
  final logs = await session.getAllLogsAsString();
  return AiEditSilenceDetectOutput(
    succeeded: ReturnCode.isSuccess(returnCode),
    logs: logs ?? '',
  );
}

int _compareRanges(SilenceCutRange left, SilenceCutRange right) {
  final byStart = left.start.compareTo(right.start);
  return byStart != 0 ? byStart : left.end.compareTo(right.end);
}

List<SilenceCutRange> _mergeRanges(List<SilenceCutRange> ranges) {
  if (ranges.isEmpty) {
    return const [];
  }

  final sorted = List<SilenceCutRange>.of(ranges)..sort(_compareRanges);
  final merged = <SilenceCutRange>[];
  for (final range in sorted) {
    if (merged.isEmpty ||
        range.start > merged.last.end + _sourceEdgeEpsilonSeconds) {
      merged.add(range);
      continue;
    }

    final previous = merged.removeLast();
    merged.add(
      SilenceCutRange(
        start: previous.start,
        end: math.max(previous.end, range.end),
      ),
    );
  }
  return merged;
}
