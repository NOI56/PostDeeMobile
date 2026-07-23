import 'package:characters/characters.dart';
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

  test('balances an unspaced Thai run within the character limit', () {
    const thaiCue = 'กำลังทดสอบซับภาษาไทย';

    final pieces = splitLineByMaxChars(thaiCue, 4);

    expect(pieces, hasLength(5));
    expect(pieces.every((piece) => piece.characters.length <= 4), isTrue);
    expect(
        pieces.map((piece) => piece.characters.length).reduce(
              (shortest, length) => length < shortest ? length : shortest,
            ),
        greaterThanOrEqualTo(3));
    expect(pieces.join(), thaiCue);
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

  test('does not create a tiny tail cue from a long Thai cue', () {
    const thaiCue = 'กำลังทดสอบซับภาษาไทย';
    final out = rechunkSubtitleByMaxChars(
      const [
        SubtitleSegment(text: thaiCue, start: 2, end: 8),
      ],
      4,
    );

    expect(out, hasLength(5));
    expect(
      out.every((segment) => segment.text.characters.length <= 4),
      isTrue,
    );
    expect(
      out.every((segment) => segment.end - segment.start >= 1),
      isTrue,
    );
    expect(out.map((segment) => segment.text).join(), thaiCue);
    expect(out.first.start, 2);
    expect(out.last.end, closeTo(8, 0.0001));
  });

  test('keeps a single-line Thai subtitle within the character limit', () {
    const thaiCue = 'หาของของที่ตัวเองต้องการ';
    final out = rechunkSubtitleByMaxChars(
      const [
        SubtitleSegment(text: thaiCue, start: 87.84, end: 89.077),
      ],
      18,
    );

    expect(out, hasLength(2));
    expect(
      out.every((segment) => segment.text.characters.length <= 18),
      isTrue,
    );
    expect(out.map((segment) => segment.text).join(), thaiCue);
    expect(out.first.start, 87.84);
    expect(out.last.end, 89.077);
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

  test('moves a leading cut back when it starts inside a subtitle cue', () {
    final adjusted = alignLeadingCutToFirstSubtitle(
      const [
        SilenceCutRange(start: 0, end: 30.321),
        SilenceCutRange(start: 90.321, end: 150.641),
      ],
      const [
        SubtitleSegment(
          text: 'ที่เดินสำหรับ',
          start: 29.985,
          end: 30.921,
        ),
      ],
      150.641,
    );

    expect(adjusted, hasLength(2));
    expect(adjusted.first.start, 0);
    expect(adjusted.first.end, closeTo(29.835, 0.001));
    expect(adjusted.last.start, closeTo(89.835, 0.001));
    expect(adjusted.last.end, 150.641);
    expect(
      estimateResultSeconds(
        durationSeconds: 150.641,
        cutRanges: adjusted,
      ),
      closeTo(60, 0.001),
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
