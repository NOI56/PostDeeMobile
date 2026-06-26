import 'package:flutter_test/flutter_test.dart';
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

  test('splits a line on spaces and hard-splits long runs', () {
    expect(splitLineByMaxChars('a bb cc dd', 5), ['a bb', 'cc dd']);
    expect(splitLineByMaxChars('aaaaaaaaaa', 4), ['aaaa', 'aaaa', 'aa']);
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
}
