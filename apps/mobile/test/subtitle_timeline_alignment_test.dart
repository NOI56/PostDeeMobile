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
}
