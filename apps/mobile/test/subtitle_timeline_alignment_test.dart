import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/edit_styles.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_timeline_alignment.dart';

void main() {
  test('moves a target tail cut to the end of a crossing subtitle cue', () {
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: const [SilenceCutRange(start: 20, end: 30)],
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ประโยคท้ายต้องแสดงให้จบ',
          start: 19.4,
          end: 20.6,
        ),
      ],
      durationSeconds: 30,
      targetSeconds: 20,
    );

    expect(adjusted, hasLength(1));
    expect(adjusted.single.start, closeTo(20.6, 0.001));
    expect(adjusted.single.end, 30);
    expect(
      estimateResultSeconds(durationSeconds: 30, cutRanges: adjusted),
      closeTo(20.6, 0.001),
    );
  });

  test('moves a target tail cut before a cue when its end exceeds tolerance',
      () {
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: const [SilenceCutRange(start: 20, end: 30)],
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ประโยคยาวที่ไม่ควรถูกตัดครึ่ง',
          start: 19.5,
          end: 22,
        ),
      ],
      durationSeconds: 30,
      targetSeconds: 20,
    );

    expect(adjusted.single.start, closeTo(19.5, 0.001));
  });

  test('keeps a target boundary when no subtitle cue crosses it', () {
    const cuts = [SilenceCutRange(start: 20, end: 30)];
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ประโยคก่อนหน้า', start: 18, end: 19.8),
        SubtitleSegment(text: 'ประโยคถัดไป', start: 20.2, end: 21),
      ],
      durationSeconds: 30,
      targetSeconds: 20,
    );

    expect(adjusted, cuts);
  });

  test(
      'keeps the opening exactly and extends the real Thai fixture to a complete phrase',
      () {
    const cuts = [
      SilenceCutRange(start: 0, end: 109.308),
      SilenceCutRange(start: 126.711, end: 127.387),
      SilenceCutRange(start: 140.548, end: 148.709),
    ];
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ครั้งนึงแล้วก็นั่งล่อง',
          start: 109.308,
          end: 110.782,
        ),
        SubtitleSegment(
          text: 'เรือไปเรื่อยๆ',
          start: 110.782,
          end: 112.081,
        ),
        SubtitleSegment(
          text: 'โชคดีที่',
          start: 137.734,
          end: 138.561,
        ),
        SubtitleSegment(
          text: 'ออฟฟิศอยู่',
          start: 138.561,
          end: 139.720,
        ),
        SubtitleSegment(
          text: 'ที่บ้านก็',
          start: 139.720,
          end: 140.548,
        ),
        SubtitleSegment(
          text: 'ไม่ต้องออก',
          start: 140.548,
          end: 141.403,
        ),
        SubtitleSegment(
          text: 'เดินทางมาก',
          start: 141.403,
          end: 142.256,
        ),
        SubtitleSegment(
          text: 'แต่ก็จะมีออกไป',
          start: 142.256,
          end: 143.088,
        ),
      ],
      durationSeconds: 148.709,
      targetSeconds: 30,
    );

    expect(adjusted[0].start, cuts[0].start);
    expect(adjusted[0].end, cuts[0].end);
    expect(adjusted[1].start, cuts[1].start);
    expect(adjusted[1].end, cuts[1].end);
    expect(adjusted.last.start, closeTo(142.256, 0.001));
    expect(adjusted.last.end, cuts.last.end);

    final resultSeconds = estimateResultSeconds(
      durationSeconds: 148.709,
      cutRanges: adjusted,
    );
    expect(resultSeconds, closeTo(32.272, 0.001));
    expect((resultSeconds - 30).abs(), lessThanOrEqualTo(3));
  });

  test('completes the real Thai phrase when the old tail crosses its first cue',
      () {
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: const [
        SilenceCutRange(start: 0, end: 109.308),
        SilenceCutRange(start: 126.711, end: 127.387),
        SilenceCutRange(start: 140.4, end: 148.709),
      ],
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ที่บ้านก็',
          start: 139.720,
          end: 140.548,
        ),
        SubtitleSegment(
          text: 'ไม่ต้องออก',
          start: 140.548,
          end: 141.403,
        ),
        SubtitleSegment(
          text: 'เดินทางมาก',
          start: 141.403,
          end: 142.256,
        ),
        SubtitleSegment(
          text: 'แต่ก็จะมีออกไป',
          start: 142.256,
          end: 143.088,
        ),
      ],
      durationSeconds: 148.709,
      targetSeconds: 30,
    );

    expect(adjusted.first.end, 109.308);
    expect(adjusted.last.start, closeTo(142.256, 0.001));
    final resultSeconds = estimateResultSeconds(
      durationSeconds: 148.709,
      cutRanges: adjusted,
    );
    expect((resultSeconds - 30).abs(), lessThanOrEqualTo(3));
  });

  test('never treats Thai substrings as standalone continuation words', () {
    for (final completeThaiWord in ['แต่งตัว', 'สถานที่', 'เมื่อวาน']) {
      const cuts = [
        SilenceCutRange(start: 0, end: 10),
        SilenceCutRange(start: 40, end: 50),
      ];

      final adjusted = alignTargetTailToSubtitleBoundary(
        cuts: cuts,
        subtitleSegments: [
          SubtitleSegment(
            text: completeThaiWord,
            start: 38,
            end: 40,
          ),
          const SubtitleSegment(
            text: 'ประโยคใหม่ที่ไม่เกี่ยวกัน',
            start: 40,
            end: 41,
          ),
        ],
        durationSeconds: 50,
        targetSeconds: 30,
      );

      expect(adjusted, cuts, reason: completeThaiWord);
    }
  });

  test('does not move the opening while completing a dangling Thai tail', () {
    for (final openingText in ['แต่งตัว', 'เมื่อวาน']) {
      const cuts = [
        SilenceCutRange(start: 0, end: 10),
        SilenceCutRange(start: 40, end: 50),
      ];

      final adjusted = alignTargetTailToSubtitleBoundary(
        cuts: cuts,
        subtitleSegments: [
          SubtitleSegment(text: openingText, start: 10, end: 12),
          const SubtitleSegment(text: 'ที่บ้านก็', start: 39, end: 40),
          const SubtitleSegment(text: 'จบครบแล้ว', start: 40, end: 41),
        ],
        durationSeconds: 50,
        targetSeconds: 30,
      );

      expect(adjusted.first.start, cuts.first.start, reason: openingText);
      expect(adjusted.first.end, cuts.first.end, reason: openingText);
      expect(adjusted.last.start, 41, reason: openingText);
    }
  });

  test('recognizes common Thai continuation endings without spaces', () {
    for (final danglingText in [
      'โชคดีที่',
      'กำลังจะ',
      'เพราะว่า',
    ]) {
      const cuts = [
        SilenceCutRange(start: 0, end: 10),
        SilenceCutRange(start: 40, end: 50),
      ];

      final adjusted = alignTargetTailToSubtitleBoundary(
        cuts: cuts,
        subtitleSegments: [
          SubtitleSegment(text: danglingText, start: 39, end: 40),
          const SubtitleSegment(
            text: 'ประโยคนี้จบสมบูรณ์',
            start: 40,
            end: 41,
          ),
        ],
        durationSeconds: 50,
        targetSeconds: 30,
      );

      expect(adjusted.first, cuts.first, reason: danglingText);
      expect(adjusted.last.start, 41, reason: danglingText);
      expect(adjusted.last.end, 50, reason: danglingText);
    }
  });

  test('continues a Thai location phrase ending in อยู่', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    for (final danglingText in ['ออฟฟิศอยู่', 'ออฟฟิศ อยู่', 'อยู่']) {
      final adjusted = alignTargetTailToSubtitleBoundary(
        cuts: cuts,
        subtitleSegments: [
          SubtitleSegment(text: danglingText, start: 39, end: 40),
          const SubtitleSegment(text: 'ที่บ้าน', start: 40, end: 41),
        ],
        durationSeconds: 50,
        targetSeconds: 30,
      );

      expect(adjusted.first, cuts.first, reason: danglingText);
      expect(adjusted.last.start, 41, reason: danglingText);
      expect(adjusted.last.end, 50, reason: danglingText);
    }
  });

  test('does not extend complete Thai sentences that end in อยู่', () {
    for (final completeText in [
      'ฉันรออยู่',
      'ฉันรอ อยู่',
      'ร้านยังเปิดอยู่',
      'ฉันทำงานอยู่',
      'อยู่',
    ]) {
      const cuts = [
        SilenceCutRange(start: 0, end: 10),
        SilenceCutRange(start: 40, end: 50),
      ];

      final adjusted = alignTargetTailToSubtitleBoundary(
        cuts: cuts,
        subtitleSegments: [
          SubtitleSegment(text: completeText, start: 39, end: 40),
          const SubtitleSegment(
            text: 'ประโยคใหม่ไม่เกี่ยวกัน',
            start: 40,
            end: 41,
          ),
        ],
        durationSeconds: 50,
        targetSeconds: 30,
      );

      expect(adjusted, cuts, reason: completeText);
    }
  });

  test(
      'extends the live Thai clip from an exact cue edge to the next phrase boundary',
      () {
    const cuts = [
      SilenceCutRange(start: 4.532, end: 5.168),
      SilenceCutRange(start: 30.889, end: 59.348),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ไม่ใช่อาหารที่ขาย',
          start: 30.056,
          end: 30.889,
        ),
        SubtitleSegment(
          text: 'นักท่องเที่ยวไม่ใช่',
          start: 30.889,
          end: 31.723,
        ),
        SubtitleSegment(
          text: 'ร้านอาหาร',
          start: 31.723,
          end: 32.235,
        ),
        SubtitleSegment(
          text: 'แต่จะเป็นอาหาร',
          start: 32.236,
          end: 33.076,
        ),
      ],
      durationSeconds: 59.348,
      targetSeconds: 30,
    );

    expect(adjusted.first, cuts.first);
    expect(adjusted.last.start, closeTo(32.235, 0.001));
    expect(adjusted.last.end, cuts.last.end);
    expect(
      estimateResultSeconds(
        durationSeconds: 59.348,
        cutRanges: adjusted,
      ),
      closeTo(31.599, 0.001),
    );
  });

  test(
      'shortens the latest Thai clip to a complete phrase when forward completion is too long',
      () {
    const cuts = [
      SilenceCutRange(start: 16.829, end: 17.505),
      SilenceCutRange(start: 31.610, end: 40.753),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ที่บ้านทำงาน',
          start: 27.020,
          end: 27.852,
        ),
        SubtitleSegment(
          text: 'โชคดีที่',
          start: 27.852,
          end: 28.679,
        ),
        SubtitleSegment(
          text: 'ออฟฟิศอยู่',
          start: 28.679,
          end: 29.838,
        ),
        SubtitleSegment(
          text: 'ที่บ้านก็',
          start: 29.838,
          end: 30.666,
        ),
        SubtitleSegment(
          text: 'ไม่ต้องออกเดิน',
          start: 30.666,
          end: 31.610,
        ),
        SubtitleSegment(
          text: 'ทางมากแต่ก็',
          start: 31.610,
          end: 32.383,
        ),
        SubtitleSegment(
          text: 'จะมีออกไปเดิน',
          start: 32.383,
          end: 33.327,
        ),
        SubtitleSegment(
          text: 'พาข้างนอก',
          start: 33.327,
          end: 34.047,
        ),
      ],
      durationSeconds: 40.753,
      targetSeconds: 30,
    );

    expect(adjusted.first, cuts.first);
    expect(adjusted.last.start, closeTo(27.852, 0.001));
    expect(adjusted.last.end, cuts.last.end);
    expect(
      estimateResultSeconds(
        durationSeconds: 40.753,
        cutRanges: adjusted,
      ),
      closeTo(27.176, 0.001),
    );
  });

  test('keeps the target when no complete earlier phrase fits the tolerance',
      () {
    const cuts = [
      SilenceCutRange(start: 10, end: 11),
      SilenceCutRange(start: 31, end: 40),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ประโยคก่อนหน้า', start: 25, end: 27),
        SubtitleSegment(text: 'โชคดีที่', start: 27, end: 28),
        SubtitleSegment(text: 'ออฟฟิศอยู่', start: 28, end: 29),
        SubtitleSegment(text: 'ที่บ้านก็', start: 29, end: 30),
        SubtitleSegment(text: 'ไม่ต้องออกเดิน', start: 30, end: 31),
        SubtitleSegment(text: 'ทางมากแต่ก็', start: 31, end: 33.5),
        SubtitleSegment(text: 'จะมีออกไปเดิน', start: 33.5, end: 35),
      ],
      durationSeconds: 40,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('rolls back a standalone Thai noun at the end of the selected clip', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 2.714),
      SilenceCutRange(start: 32.714, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'คนในกลุ่ม',
          start: 29.281,
          end: 29.994,
        ),
        SubtitleSegment(
          text: 'ต่างๆชาติต่างๆ',
          start: 29.994,
          end: 31.113,
        ),
        SubtitleSegment(
          text: 'หรือศาสนา',
          start: 31.193,
          end: 32.004,
        ),
        SubtitleSegment(
          text: 'เหตุการณ์',
          start: 32.004,
          end: 32.714,
        ),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, closeTo(32.004, 0.001));
    expect(
      estimateResultSeconds(durationSeconds: 50, cutRanges: adjusted),
      inInclusiveRange(27, 33),
    );
  });

  test('extends a Thai ranking phrase through its country complement', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 0.502),
      SilenceCutRange(start: 30.502, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ที่อันดับหนึ่ง',
          start: 29.516,
          end: 30.502,
        ),
        SubtitleSegment(
          text: 'ของประเทศ',
          start: 30.502,
          end: 31.611,
        ),
        SubtitleSegment(
          text: 'เลยสำหรับ',
          start: 31.611,
          end: 32.473,
        ),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, closeTo(31.611, 0.001));
    expect(
      estimateResultSeconds(durationSeconds: 50, cutRanges: adjusted),
      inInclusiveRange(27, 33),
    );
  });

  test('extends the live zoo vote phrase to its complete audience count', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 0.018),
      SilenceCutRange(start: 30.018, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'โหวตของสวน',
          start: 29.281,
          end: 30.018,
        ),
        SubtitleSegment(
          text: 'สัตว์เขาเขียวที่',
          start: 30.018,
          end: 30.830,
        ),
        SubtitleSegment(
          text: 'มีผู้โหวตถึง',
          start: 30.830,
          end: 31.695,
        ),
        SubtitleSegment(
          text: 'สองหมื่นคน',
          start: 31.695,
          end: 32.560,
        ),
        SubtitleSegment(
          text: 'เลือกชื่อหมูเด้ง',
          start: 32.560,
          end: 33.750,
        ),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, closeTo(32.560, 0.001));
    expect(
      estimateResultSeconds(durationSeconds: 50, cutRanges: adjusted),
      inInclusiveRange(27, 33),
    );
  });

  test('keeps the live hippo superstar name complete at the target tail', () {
    const cuts = [
      SilenceCutRange(start: 28.916, end: 45),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'เป็นน้องของ',
          start: 27.964,
          end: 28.916,
        ),
        SubtitleSegment(
          text: 'พี่หมูตุ๋นฮิปโปซุปเปอร์สตาร์',
          start: 28.916,
          end: 30.927,
        ),
        SubtitleSegment(
          text: 'ของ',
          start: 30.927,
          end: 31.244,
        ),
        SubtitleSegment(
          text: 'สวนสัตว์เปิดเขาเขียว',
          start: 31.244,
          end: 32.879,
        ),
        SubtitleSegment(
          text: 'โดยน้องเป็นลูกตัวที่เจ็ด',
          start: 32.879,
          end: 34.2,
        ),
      ],
      durationSeconds: 45,
      targetSeconds: 30,
    );

    expect(adjusted.single.start, closeTo(30.927, 0.001));
    expect(
      estimateResultSeconds(durationSeconds: 45, cutRanges: adjusted),
      inInclusiveRange(27, 33),
    );
  });

  test('stops before a dangling comparison clause after ครั้งหนึ่ง', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 0.956),
      SilenceCutRange(start: 30.956, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ก็มาชิงกันอีก',
          start: 28.801,
          end: 29.674,
        ),
        SubtitleSegment(
          text: 'ครั้งหนึ่ง',
          start: 29.674,
          end: 30.256,
        ),
        SubtitleSegment(
          text: 'ว่านกใครร้องมาก',
          start: 30.256,
          end: 30.956,
        ),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, closeTo(30.256, 0.001));
    expect(
      estimateResultSeconds(durationSeconds: 50, cutRanges: adjusted),
      inInclusiveRange(27, 33),
    );
  });

  test('keeps a punctuated Thai noun as a complete ending', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(
          text: 'สรุปเรื่องทั้งหมด',
          start: 38,
          end: 39,
        ),
        SubtitleSegment(
          text: 'เหตุการณ์.',
          start: 39,
          end: 40,
        ),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('keeps ว่า as a complement after a speech verb', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'เขาบอก', start: 38, end: 39),
        SubtitleSegment(text: 'ว่าเรื่องนี้ดี', start: 39, end: 40),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('does not remove a complete standalone noun after an imperative', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ดู', start: 38, end: 39),
        SubtitleSegment(text: 'รายละเอียด', start: 39, end: 40),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('does not extend into a new phrase merely because it starts with ของ',
      () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'จบแล้ว', start: 39, end: 40),
        SubtitleSegment(text: 'ของใหม่เข้าพรุ่งนี้', start: 40, end: 41),
        SubtitleSegment(text: 'เตรียมตัวได้เลย', start: 41, end: 42),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('keeps a normal possessive complement that starts with ของ', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ยอดขาย', start: 39, end: 40),
        SubtitleSegment(text: 'ของร้านเพิ่มขึ้น', start: 40, end: 41),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, 41);
  });

  test('keeps a standalone ของ cue linked to its following complement', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ยอดขาย', start: 39, end: 40),
        SubtitleSegment(text: 'ของ', start: 40, end: 40.3),
        SubtitleSegment(text: 'ร้านเพิ่มขึ้น', start: 40.3, end: 41),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, 41);
  });

  test('never ends on a standalone ของ before a real pause', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40.3, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ยอดขาย', start: 39, end: 40),
        SubtitleSegment(text: 'ของ', start: 40, end: 40.3),
        SubtitleSegment(text: 'ร้านเพิ่มขึ้น', start: 40.8, end: 41.5),
      ],
      durationSeconds: 50,
      targetSeconds: 30.3,
    );

    expect(adjusted.last.start, 40);
  });

  test('does not treat a normal word ending in ของ as a dangling relation', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ซื้อของ', start: 39, end: 40),
        SubtitleSegment(text: 'วันนี้กลับบ้าน', start: 40, end: 41),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('does not roll back เหตุการณ์ after an incomplete หรือ cue', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'หรือดู', start: 38, end: 39),
        SubtitleSegment(text: 'เหตุการณ์', start: 39, end: 40),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('does not treat ประเทศ as complete before its country name', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'กำลังจะ', start: 39, end: 40),
        SubtitleSegment(text: 'เดินทางไปประเทศ', start: 40, end: 41),
        SubtitleSegment(text: 'ญี่ปุ่นเพื่อทำงาน', start: 41, end: 44),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    expect(adjusted.last.start, 39);
  });

  test('does not shorten to an arbitrary cue inside continuous Thai speech',
      () {
    const cuts = [
      SilenceCutRange(start: 10, end: 11),
      SilenceCutRange(start: 31, end: 40),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ประโยคก่อนหน้า', start: 27, end: 28),
        SubtitleSegment(text: 'ฉันอยากซื้อ', start: 28, end: 29),
        SubtitleSegment(text: 'โทรศัพท์เครื่องใหม่', start: 29, end: 30),
        SubtitleSegment(text: 'ราคาไม่แพง', start: 30, end: 31),
        SubtitleSegment(text: 'รุ่นนี้ใช้งานได้ดี', start: 31, end: 33.5),
        SubtitleSegment(text: 'เหมาะกับทุกคน', start: 33.5, end: 35),
      ],
      durationSeconds: 40,
      targetSeconds: 30,
    );

    expect(adjusted, cuts);
  });

  test('keeps an exact Thai cue edge when the next cue starts a new thought',
      () {
    const cuts = [SilenceCutRange(start: 20, end: 30)];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ประโยคนี้จบแล้ว', start: 19, end: 20),
        SubtitleSegment(text: 'แต่จะเริ่มเรื่องใหม่', start: 20, end: 21),
      ],
      durationSeconds: 30,
      targetSeconds: 20,
    );

    expect(adjusted, cuts);
  });

  test('keeps phrase completion that ends exactly at source EOF', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 49, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'กำลังจะ', start: 48, end: 49),
        SubtitleSegment(text: 'จบประโยคพอดี', start: 49, end: 50),
      ],
      durationSeconds: 50,
      targetSeconds: 39,
    );

    expect(adjusted, const [SilenceCutRange(start: 0, end: 10)]);
    expect(
      estimateResultSeconds(durationSeconds: 50, cutRanges: adjusted),
      40,
    );
  });

  test('does not extend a Thai phrase beyond three seconds from target', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 10),
      SilenceCutRange(start: 40, end: 50),
    ];

    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: cuts,
      subtitleSegments: const [
        SubtitleSegment(text: 'ที่บ้านก็', start: 39, end: 40),
        SubtitleSegment(text: 'ยังเล่าต่อ', start: 40, end: 42.5),
        SubtitleSegment(text: 'เกินเวลาที่อนุญาต', start: 42.5, end: 43.2),
      ],
      durationSeconds: 50,
      targetSeconds: 30,
    );

    final resultSeconds = estimateResultSeconds(
      durationSeconds: 50,
      cutRanges: adjusted,
    );
    expect(adjusted.first.end, cuts.first.end);
    expect(adjusted.last.start, 39);
    expect((resultSeconds - 30).abs(), lessThanOrEqualTo(3));
  });

  test('bounds semantic tail tolerance for short and long targets', () {
    expect(aiEditSemanticTailToleranceSeconds(targetSeconds: 5), 1);
    expect(aiEditSemanticTailToleranceSeconds(targetSeconds: 30), 3);
    expect(aiEditSemanticTailToleranceSeconds(targetSeconds: 60), 3);
  });

  test('keeps the renderer cap aligned with the semantic tail allowance', () {
    expect(
      aiEditMaximumOutputDurationSeconds(
        targetSeconds: 30,
        estimatedOutputSeconds: 32.272,
      ),
      closeTo(32.272, 0.001),
    );
    expect(
      aiEditMaximumOutputDurationSeconds(
        targetSeconds: 30,
        estimatedOutputSeconds: 100,
      ),
      33,
    );
    expect(
      aiEditMaximumOutputDurationSeconds(
        targetSeconds: 5,
        estimatedOutputSeconds: 8,
      ),
      6,
    );
  });
}
