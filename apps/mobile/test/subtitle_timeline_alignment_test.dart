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
    expect(adjusted.single.start, greaterThanOrEqualTo(3));
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

    expect(adjusted, hasLength(1));
    expect(adjusted.single.start, closeTo(19.5, 0.001));
    expect(adjusted.single.end, 30);
    expect(
      estimateResultSeconds(durationSeconds: 30, cutRanges: adjusted),
      closeTo(19.5, 0.001),
    );
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

  test('keeps the real 30-second replay tail cue complete', () {
    final adjusted = alignTargetTailToSubtitleBoundary(
      cuts: const [
        SilenceCutRange(start: 1.759, end: 2.519),
        SilenceCutRange(start: 10.279, end: 11.439),
        SilenceCutRange(start: 15.794, end: 16.434),
        SilenceCutRange(start: 22.519, end: 30.035),
      ],
      subtitleSegments: const [
        SubtitleSegment(
          text: 'ที่นึงระยะทาง',
          start: 21.435,
          end: 22.778,
        ),
        SubtitleSegment(
          text: 'ใกล้ๆ',
          start: 22.778,
          end: 23.315,
        ),
        SubtitleSegment(
          text: 'ไม่ควรข้ามช่วงเงียบใหญ่',
          start: 23.8,
          end: 24.2,
        ),
      ],
      durationSeconds: 30.035,
      targetSeconds: 20,
    );

    expect(adjusted.last.start, closeTo(23.315, 0.001));
    final resultSeconds = estimateResultSeconds(
      durationSeconds: 30.035,
      cutRanges: adjusted,
    );
    expect(resultSeconds, closeTo(20.755, 0.001));
    expect(resultSeconds, lessThanOrEqualTo(21));
  });
}
