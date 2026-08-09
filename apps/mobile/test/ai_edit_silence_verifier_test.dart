import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_silence_verifier.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

void main() {
  group('parseAiEditSilenceLog', () {
    test('parses ordered silence pairs across multiple log lines', () {
      final ranges = parseAiEditSilenceLog(
        '''
[silencedetect @ 1] silence_start: 1.25
[silencedetect @ 1] silence_end: 2.75 | silence_duration: 1.50
[silencedetect @ 1] silence_start: 8
[silencedetect @ 1] silence_end: 9.5 | silence_duration: 1.5
''',
        sourceDurationSeconds: 12,
      );

      expect(ranges, hasLength(2));
      expect(ranges[0].start, closeTo(1.25, 0.001));
      expect(ranges[0].end, closeTo(2.75, 0.001));
      expect(ranges[1].start, closeTo(8, 0.001));
      expect(ranges[1].end, closeTo(9.5, 0.001));
    });

    test('does not guess orphan or repeated markers', () {
      final ranges = parseAiEditSilenceLog(
        '''
silence_end: 1
silence_start: 2
silence_start: 3
silence_end: 4
silence_start: 5
silence_end: 6
''',
        sourceDurationSeconds: 10,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, 5);
      expect(ranges.single.end, 6);
    });

    test('a malformed marker invalidates the open pair', () {
      final ranges = parseAiEditSilenceLog(
        '''
silence_start: 2
silence_end: unknown
silence_end: 3
silence_start: 6
silence_end: 7
''',
        sourceDurationSeconds: 10,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, 6);
      expect(ranges.single.end, 7);
    });

    test('rejects an entire pair with a negative or out-of-duration marker',
        () {
      final ranges = parseAiEditSilenceLog(
        '''
silence_start: -1
silence_end: 2
silence_start: 3
silence_end: 999
silence_start: 7
silence_end: 8
''',
        sourceDurationSeconds: 10,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, 7);
      expect(ranges.single.end, 8);
    });

    test('returns no ranges for an invalid source duration', () {
      expect(
        parseAiEditSilenceLog(
          'silence_start: 1\nsilence_end: 2',
          sourceDurationSeconds: double.nan,
        ),
        isEmpty,
      );
      expect(
        parseAiEditSilenceLog(
          'silence_start: 1\nsilence_end: 2',
          sourceDurationSeconds: 0,
        ),
        isEmpty,
      );
    });
  });

  group('intersectVerifiedSilenceCuts', () {
    test('keeps only the padded candidate and waveform intersection', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 4.8, end: 6.2),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 5, end: 6),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, closeTo(5.1, 0.001));
      expect(ranges.single.end, closeTo(5.9, 0.001));
    });

    test('pads after intersecting with the narrower transcript candidate', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 5.2, end: 5.8),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 5, end: 6),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, closeTo(5.3, 0.001));
      expect(ranges.single.end, closeTo(5.7, 0.001));
    });

    test('drops an intersection shorter than the minimum after padding', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 5, end: 5.44),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 4.5, end: 6),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, isEmpty);
    });

    test('drops candidates that touch either source edge', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 0, end: 1),
          SilenceCutRange(start: 5, end: 6),
          SilenceCutRange(start: 19, end: 20),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 0, end: 1),
          SilenceCutRange(start: 5, end: 6),
          SilenceCutRange(start: 19, end: 20),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, closeTo(5.1, 0.001));
      expect(ranges.single.end, closeTo(5.9, 0.001));
    });

    test('rejects a whole verified range when any protected speech overlaps',
        () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 5, end: 7),
          SilenceCutRange(start: 10, end: 12),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 5, end: 7),
          SilenceCutRange(start: 10, end: 12),
        ],
        protectedSpeechRanges: const [
          SilenceCutRange(start: 6.8, end: 7.2),
        ],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, closeTo(10.1, 0.001));
      expect(ranges.single.end, closeTo(11.9, 0.001));
    });

    test('sorts merges and deduplicates overlapping verified ranges', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: 8, end: 9),
          SilenceCutRange(start: 5.5, end: 6.5),
          SilenceCutRange(start: 5, end: 6),
          SilenceCutRange(start: 5, end: 6),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 4, end: 10),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(2));
      expect(ranges[0].start, closeTo(5.1, 0.001));
      expect(ranges[0].end, closeTo(6.4, 0.001));
      expect(ranges[1].start, closeTo(8.1, 0.001));
      expect(ranges[1].end, closeTo(8.9, 0.001));
    });

    test('drops invalid candidate and waveform ranges without clamping', () {
      final ranges = intersectVerifiedSilenceCuts(
        transcriptCandidates: const [
          SilenceCutRange(start: -1, end: 2),
          SilenceCutRange(start: 5, end: 6),
          SilenceCutRange(start: 8, end: 30),
        ],
        waveformSilences: const [
          SilenceCutRange(start: 4.8, end: 6.2),
          SilenceCutRange(start: 8, end: 9),
        ],
        protectedSpeechRanges: const [],
        sourceDurationSeconds: 20,
      );

      expect(ranges, hasLength(1));
      expect(ranges.single.start, closeTo(5.1, 0.001));
      expect(ranges.single.end, closeTo(5.9, 0.001));
    });
  });

  group('AiEditSilenceVerifier', () {
    test('uses the exact silencedetect arguments', () async {
      List<String>? capturedArguments;
      final verifier = AiEditSilenceVerifier(
        runFfmpeg: (arguments) async {
          capturedArguments = List<String>.of(arguments);
          return const AiEditSilenceDetectOutput(
            succeeded: true,
            logs: 'silence_start: 5\nsilence_end: 6',
          );
        },
      );

      final result = await verifier.call(
        sourceFile: File(r'C:\fixtures\clip.mp4'),
        sourceDurationSeconds: 20,
        transcriptCandidates: const [
          SilenceCutRange(start: 4.8, end: 6.2),
        ],
        protectedSpeechRanges: const [],
      );

      expect(capturedArguments, const [
        '-hide_banner',
        '-nostats',
        '-i',
        r'C:\fixtures\clip.mp4',
        '-af',
        'silencedetect=noise=-40dB:d=0.20',
        '-f',
        'null',
        '-',
      ]);
      expect(result.probeSucceeded, isTrue);
      expect(result.cutRanges, hasLength(1));
    });

    test('keeps only padded waveform intersections away from speech', () async {
      final verifier = AiEditSilenceVerifier(
        runFfmpeg: (_) async => const AiEditSilenceDetectOutput(
          succeeded: true,
          logs: 'silence_start: 5.0\nsilence_end: 6.0 | silence_duration: 1.0',
        ),
      );

      final result = await verifier.call(
        sourceFile: File('clip.mp4'),
        sourceDurationSeconds: 20,
        transcriptCandidates: const [
          SilenceCutRange(start: 4.8, end: 6.2),
        ],
        protectedSpeechRanges: const [],
      );

      expect(result.probeSucceeded, isTrue);
      expect(result.cutRanges.single.start, closeTo(5.1, 0.001));
      expect(result.cutRanges.single.end, closeTo(5.9, 0.001));
    });

    test('reports a thrown native probe as failed', () async {
      final verifier = AiEditSilenceVerifier(
        runFfmpeg: (_) async => throw StateError('native failure'),
      );

      final result = await verifier.call(
        sourceFile: File('clip.mp4'),
        sourceDurationSeconds: 20,
        transcriptCandidates: const [
          SilenceCutRange(start: 5, end: 6),
        ],
        protectedSpeechRanges: const [],
      );

      expect(result.probeSucceeded, isFalse);
      expect(result.cutRanges, isEmpty);
    });

    test('reports a non-zero native probe as failed', () async {
      final verifier = AiEditSilenceVerifier(
        runFfmpeg: (_) async => const AiEditSilenceDetectOutput(
          succeeded: false,
          logs: 'ffmpeg failed',
        ),
      );

      final result = await verifier.call(
        sourceFile: File('clip.mp4'),
        sourceDurationSeconds: 20,
        transcriptCandidates: const [
          SilenceCutRange(start: 5, end: 6),
        ],
        protectedSpeechRanges: const [],
      );

      expect(result.probeSucceeded, isFalse);
      expect(result.cutRanges, isEmpty);
    });

    test('distinguishes a successful probe with no silence markers', () async {
      final verifier = AiEditSilenceVerifier(
        runFfmpeg: (_) async => const AiEditSilenceDetectOutput(
          succeeded: true,
          logs: 'audio contains no detected silence',
        ),
      );

      final result = await verifier.call(
        sourceFile: File('clip.mp4'),
        sourceDurationSeconds: 20,
        transcriptCandidates: const [
          SilenceCutRange(start: 5, end: 6),
        ],
        protectedSpeechRanges: const [],
      );

      expect(result.probeSucceeded, isTrue);
      expect(result.cutRanges, isEmpty);
    });
  });
}
