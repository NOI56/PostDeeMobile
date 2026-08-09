import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_timeline_mapper.dart';

void main() {
  AiEditTranscriptResult transcriptFixture({
    List<ClipTranscriptSegment> segments = const [],
    List<ClipTranscriptSegment> boundarySegments = const [],
    List<AiEditTranscriptWordResult> words = const [],
    double durationSeconds = 20,
  }) =>
      AiEditTranscriptResult(
        text: segments.map((segment) => segment.text).join(' '),
        language: 'th',
        durationSeconds: durationSeconds,
        segments: segments,
        boundarySegments: boundarySegments,
        words: words,
        model: 'test-elevenlabs',
      );

  test('maps repaired boundaries without using raw provider split points', () {
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [
          ClipTranscriptSegment(text: 'ดุ๊ก', start: 0, end: 1),
          ClipTranscriptSegment(text: 'ดิ๊กมาก', start: 1, end: 2),
        ],
        boundarySegments: const [
          ClipTranscriptSegment(text: 'ดุ๊กดิ๊กมาก', start: 0, end: 2),
        ],
      ),
    );

    expect(evidence.hasReliableBoundaries, isTrue);
    expect(evidence.boundarySegments, hasLength(1));
    expect(evidence.boundarySegments.single.text, 'ดุ๊กดิ๊กมาก');
    expect(evidence.boundarySegments.single.start, 0);
    expect(evidence.boundarySegments.single.end, 2);
    expect(
      evidence.boundarySegments.any(
        (segment) => segment.start == 1 || segment.end == 1,
      ),
      isFalse,
    );
    expect(evidence.protectedSpeechRanges, hasLength(1));
    expect(evidence.protectedSpeechRanges.single.start, 0);
    expect(evidence.protectedSpeechRanges.single.end, 2);
  });

  test('fails closed when an older payload has no repaired boundaries', () {
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [
          ClipTranscriptSegment(
            text: 'ขอบดิบไม่ใช่ขอบประโยค',
            start: 1,
            end: 3,
          ),
        ],
      ),
    );

    expect(evidence.hasReliableBoundaries, isFalse);
    expect(evidence.boundarySegments, isEmpty);
    expect(evidence.protectedSpeechRanges, hasLength(1));
  });

  test('drops invalid timing instead of clamping or guessing', () {
    final invalidSegments = <ClipTranscriptSegment>[
      const ClipTranscriptSegment(text: 'ย้อนเวลา', start: 5, end: 4),
      const ClipTranscriptSegment(text: 'ติดลบ', start: -0.1, end: 1),
      const ClipTranscriptSegment(text: 'เกินคลิป', start: 19, end: 21),
      ClipTranscriptSegment(text: 'ไม่ใช่ตัวเลข', start: double.nan, end: 1),
      ClipTranscriptSegment(
        text: 'ไม่มีที่สิ้นสุด',
        start: 1,
        end: double.infinity,
      ),
    ];

    for (final invalid in invalidSegments) {
      final evidence = mapAiEditTimelineEvidence(
        transcriptFixture(
          segments: [invalid],
          boundarySegments: [invalid],
        ),
      );

      expect(evidence.boundarySegments, isEmpty, reason: invalid.text);
      expect(evidence.protectedSpeechRanges, isEmpty, reason: invalid.text);
    }
  });

  test('rejects all timeline evidence when source duration is invalid', () {
    const segment = ClipTranscriptSegment(
      text: 'ช่วงที่ดูเหมือนถูกต้อง',
      start: 0,
      end: 1,
    );

    for (final duration in [0.0, -1.0, double.nan, double.infinity]) {
      final evidence = mapAiEditTimelineEvidence(
        transcriptFixture(
          durationSeconds: duration,
          segments: const [segment],
          boundarySegments: const [segment],
          words: const [
            AiEditTranscriptWordResult(word: 'ช่วง', start: 0, end: 0.5),
          ],
        ),
      );

      expect(evidence.boundarySegments, isEmpty);
      expect(evidence.protectedSpeechRanges, isEmpty);
    }
  });

  for (final segment in const [
    ClipTranscriptSegment(
      text: 'confidence ต่ำ',
      start: 1,
      end: 2,
      avgLogprob: -1.01,
    ),
    ClipTranscriptSegment(
      text: 'อาจไม่มีเสียง',
      start: 1,
      end: 2,
      noSpeechProbability: 0.61,
    ),
    ClipTranscriptSegment(
      text: 'ข้อความบีบอัดซ้ำ',
      start: 1,
      end: 2,
      compressionRatio: 2.41,
    ),
    ClipTranscriptSegment(
      text: 'ชื่อแอปให้เขียนเป็นภาษาไทยว่า PostDee',
      start: 1,
      end: 2,
    ),
    ClipTranscriptSegment(
      text: 'คำศัพท์เฉพาะ PostDee',
      start: 1,
      end: 2,
    ),
    ClipTranscriptSegment(text: '   ', start: 1, end: 2),
  ]) {
    test('rejects unreliable boundary but protects ${segment.text}', () {
      final evidence = mapAiEditTimelineEvidence(
        transcriptFixture(
          segments: [segment],
          boundarySegments: [segment],
        ),
      );

      expect(evidence.boundarySegments, isEmpty);
      expect(evidence.protectedSpeechRanges, hasLength(1));
      expect(evidence.protectedSpeechRanges.single.start, 1);
      expect(evidence.protectedSpeechRanges.single.end, 2);
    });
  }

  for (final text in const [
    'ภาษาไทย русский',
    'ภาษาไทย 中文',
    'ภาษาไทย 한국어',
    'ภาษาไทย العربية',
    'ภาษาไทย हिन्दी',
    'ภาษาไทย 日本語',
    'ภาษาไทย �',
  ]) {
    test('rejects unexpected script boundary but still protects $text', () {
      final segment = ClipTranscriptSegment(text: text, start: 2, end: 3);
      final evidence = mapAiEditTimelineEvidence(
        transcriptFixture(
          segments: [segment],
          boundarySegments: [segment],
        ),
      );

      expect(evidence.boundarySegments, isEmpty);
      expect(evidence.protectedSpeechRanges, hasLength(1));
    });
  }

  test('accepts reliability values exactly on the supported thresholds', () {
    const segment = ClipTranscriptSegment(
      text: 'ประโยคที่เชื่อถือได้',
      start: 1,
      end: 2,
      avgLogprob: -1,
      noSpeechProbability: 0.6,
      compressionRatio: 2.4,
    );
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [segment],
        boundarySegments: const [segment],
      ),
    );

    expect(evidence.boundarySegments, hasLength(1));
    expect(evidence.protectedSpeechRanges, hasLength(1));
  });

  test('overlapping repaired boundaries fail closed as a whole timeline', () {
    const first = ClipTranscriptSegment(
      text: 'ประโยคแรก',
      start: 0,
      end: 2,
    );
    const second = ClipTranscriptSegment(
      text: 'ประโยคที่สอง',
      start: 1.5,
      end: 3,
    );
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [first, second],
        boundarySegments: const [second, first],
      ),
    );

    expect(evidence.boundarySegments, isEmpty);
    expect(evidence.protectedSpeechRanges, hasLength(1));
    expect(evidence.protectedSpeechRanges.single.start, 0);
    expect(evidence.protectedSpeechRanges.single.end, 3);
  });

  test('keeps touching sentence boundaries separate and sorts them', () {
    const first = ClipTranscriptSegment(
      text: ' ประโยคแรก ',
      start: 0,
      end: 1,
    );
    const second = ClipTranscriptSegment(
      text: 'ประโยคที่สอง',
      start: 1,
      end: 2,
    );
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        boundarySegments: const [second, first],
      ),
    );

    expect(evidence.boundarySegments.map((segment) => segment.text), [
      'ประโยคแรก',
      'ประโยคที่สอง',
    ]);
    expect(evidence.boundarySegments.map((segment) => segment.start), [0, 1]);
  });

  test('protects raw segments, global words, and validated segment words', () {
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [
          ClipTranscriptSegment(
            text: 'ช่วงดิบ',
            start: 10,
            end: 11,
            words: [
              AiEditTranscriptWordResult(word: 'คำหนึ่ง', start: 1, end: 2),
              AiEditTranscriptWordResult(word: 'คำเสีย', start: -1, end: 0),
            ],
          ),
        ],
        words: const [
          AiEditTranscriptWordResult(word: 'คำรวม', start: 5, end: 6),
          AiEditTranscriptWordResult(word: 'คำเกิน', start: 20, end: 21),
        ],
      ),
    );

    expect(evidence.protectedSpeechRanges, hasLength(3));
    expect(
      evidence.protectedSpeechRanges.map((range) => (range.start, range.end)),
      [(1.0, 2.0), (5.0, 6.0), (10.0, 11.0)],
    );
  });

  test('sorts, deduplicates, and merges only touching protected ranges', () {
    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: const [
          ClipTranscriptSegment(text: 'ท้าย', start: 5, end: 7),
          ClipTranscriptSegment(text: 'ต้น', start: 1, end: 2),
          ClipTranscriptSegment(text: 'ท้ายซ้ำ', start: 5, end: 7),
        ],
        words: const [
          AiEditTranscriptWordResult(word: 'แตะต้น', start: 2, end: 3),
          AiEditTranscriptWordResult(word: 'แตะท้าย', start: 4, end: 5),
        ],
      ),
    );

    expect(
      evidence.protectedSpeechRanges.map((range) => (range.start, range.end)),
      [(1.0, 3.0), (4.0, 7.0)],
    );
  });

  test('does not mutate source lists while sorting derived evidence', () {
    const late = ClipTranscriptSegment(text: ' ทีหลัง ', start: 3, end: 4);
    const early = ClipTranscriptSegment(text: ' ก่อน ', start: 1, end: 2);
    final segments = <ClipTranscriptSegment>[late, early];
    final boundaries = <ClipTranscriptSegment>[late, early];
    final words = <AiEditTranscriptWordResult>[
      const AiEditTranscriptWordResult(word: 'หลัง', start: 3, end: 4),
      const AiEditTranscriptWordResult(word: 'ก่อน', start: 1, end: 2),
    ];
    final originalSegments = List<ClipTranscriptSegment>.of(segments);
    final originalBoundaries = List<ClipTranscriptSegment>.of(boundaries);
    final originalWords = List<AiEditTranscriptWordResult>.of(words);

    final evidence = mapAiEditTimelineEvidence(
      transcriptFixture(
        segments: segments,
        boundarySegments: boundaries,
        words: words,
      ),
    );

    expect(segments, orderedEquals(originalSegments));
    expect(boundaries, orderedEquals(originalBoundaries));
    expect(words, orderedEquals(originalWords));
    expect(boundaries.first.text, ' ทีหลัง ');
    expect(evidence.boundarySegments.map((segment) => segment.text), [
      'ก่อน',
      'ทีหลัง',
    ]);
    expect(
      () => evidence.boundarySegments.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => evidence.protectedSpeechRanges.clear(),
      throwsUnsupportedError,
    );
  });
}
