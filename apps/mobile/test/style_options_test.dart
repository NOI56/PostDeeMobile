import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/edit_styles.dart';
import 'package:postdee_mobile/features/ai_editing/style_options.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

void main() {
  test('target length adds a tail cut to fit', () {
    final cuts = withTargetLength(const [], 10, 4);

    expect(cuts, hasLength(1));
    expect(cuts.first.start, closeTo(4, 0.001));
    expect(cuts.first.end, 10);
  });

  test('target length accounts for existing cuts', () {
    final cuts = withTargetLength(
      const [SilenceCutRange(start: 0, end: 2)],
      10,
      4,
    );

    // Kept span is [2,10]; keep 4s of it → cut from 6s onward.
    expect(
      cuts.any((c) => (c.start - 6).abs() < 0.001 && c.end == 10),
      isTrue,
    );
  });

  test('no trim when the clip is already under target', () {
    expect(withTargetLength(const [], 5, 30), isEmpty);
  });

  test('restores context when AI cuts leave less than the target length', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 4),
      SilenceCutRange(start: 4.5, end: 9.3),
      SilenceCutRange(start: 9.7, end: 14.2),
      SilenceCutRange(start: 14.7, end: 20.3),
      SilenceCutRange(start: 20.4, end: 33.44),
      SilenceCutRange(start: 33.7, end: 107.881),
      SilenceCutRange(start: 108.321, end: 150.641),
    ];

    final adjusted = withTargetLength(cuts, 150.641, 30);
    final resultSeconds = estimateResultSeconds(
      durationSeconds: 150.641,
      cutRanges: adjusted,
    );

    expect(resultSeconds, closeTo(30, 0.01));
    for (final selectedMoment in [4.25, 9.5, 14.45, 20.35, 33.57, 108.1]) {
      expect(
        adjusted.any(
          (cut) => cut.start < selectedMoment && selectedMoment < cut.end,
        ),
        isFalse,
      );
    }
  });

  test('splits a line on spaces and hard-splits long runs', () {
    expect(splitLineByMaxChars('a bb cc dd', 5), ['a bb', 'cc dd']);
    expect(splitLineByMaxChars('aaaaaaaaaa', 4), ['aaaa', 'aaaa', 'aa']);
  });

  test('keeps an unspaced Thai run whole instead of splitting a word', () {
    const thaiCue = 'กำลังทดสอบซับภาษาไทย';

    final pieces = splitLineByMaxChars(thaiCue, 4);

    expect(pieces, [thaiCue]);
  });

  test('splits Thai cues only at explicit spaces', () {
    expect(splitLineByMaxChars('คลิป ตัด ไทย', 5), [
      'คลิป',
      'ตัด',
      'ไทย',
    ]);
  });

  test('copyWith overrides speed and filter, keeps the rest', () {
    const base = EditStyleOptions(targetSeconds: 30, subtitleMaxChars: 24);
    final updated = base.copyWith(speed: 2.0, filterIndex: 4);

    expect(updated.speed, 2.0);
    expect(updated.filterIndex, 4);
    expect(updated.targetSeconds, 30);
    expect(updated.subtitleMaxChars, 24);
  });

  test('rechunks subtitle segments proportionally by length', () {
    final out = rechunkSubtitleByMaxChars(
      const [SubtitleSegment(text: 'aaaa bbbb', start: 0, end: 10)],
      4,
    );

    expect(out, hasLength(2));
    expect(out[0].text, 'aaaa');
    expect(out[0].start, 0);
    expect(out[0].end, closeTo(5, 0.01));
    expect(out[1].text, 'bbbb');
    expect(out[1].end, 10);
  });

  test('does not create tiny mid-word cues from a long Thai cue', () {
    const thaiCue = 'กำลังทดสอบซับภาษาไทย';
    final out = rechunkSubtitleByMaxChars(
      const [
        SubtitleSegment(text: thaiCue, start: 2, end: 8),
      ],
      4,
    );

    expect(out, hasLength(1));
    expect(out.single.text, thaiCue);
    expect(out.single.start, 2);
    expect(out.single.end, 8);
  });

  test('merges a subtitle fragment that is too short to read', () {
    final out = mergeShortSubtitleSegments(
      const [
        SubtitleSegment(text: 'เช่น', start: 0, end: 0.18),
        SubtitleSegment(text: 'ช่วงเสาร์อาทิตย์', start: 0.18, end: 1.2),
      ],
    );

    expect(out, hasLength(1));
    expect(out.single.text, 'เช่นช่วงเสาร์อาทิตย์');
    expect(out.single.start, 0);
    expect(out.single.end, 1.2);
  });

  test('moves a short subtitle-free opening to the end of the clip', () {
    final adjusted = alignLeadingCutToFirstSubtitle(
      const [
        SilenceCutRange(start: 0, end: 5),
        SilenceCutRange(start: 15, end: 20),
      ],
      const [
        SubtitleSegment(text: 'เริ่มพูดตรงนี้', start: 10, end: 12),
      ],
      20,
    );

    expect(adjusted, hasLength(2));
    expect(adjusted.first.start, 0);
    expect(adjusted.first.end, closeTo(9.85, 0.001));
    expect(adjusted.last.start, closeTo(19.85, 0.001));
    expect(adjusted.last.end, 20);
    expect(
      estimateResultSeconds(durationSeconds: 20, cutRanges: adjusted),
      closeTo(10, 0.001),
    );
  });

  test('does not move an intentionally long visual opening', () {
    const cuts = [
      SilenceCutRange(start: 0, end: 2),
      SilenceCutRange(start: 15, end: 20),
    ];

    final adjusted = alignLeadingCutToFirstSubtitle(
      cuts,
      const [
        SubtitleSegment(text: 'เริ่มพูดภายหลัง', start: 10, end: 12),
      ],
      20,
    );

    expect(adjusted.first.start, 0);
    expect(adjusted.first.end, 2);
  });
}
