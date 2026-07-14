import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/review_video_timeline.dart';

void main() {
  test('formats original and AI duration comparisons honestly', () {
    expect(
      formatReviewVideoComparison(
        originalDuration: const Duration(seconds: 25),
        aiDuration: const Duration(seconds: 20),
      ),
      'ต้นฉบับ 00:25 → ผล AI 00:20 · สั้นลง 5 วิ',
    );
    expect(
      formatReviewVideoComparison(
        originalDuration: const Duration(seconds: 20),
        aiDuration: const Duration(seconds: 20),
      ),
      'ต้นฉบับ 00:20 → ผล AI 00:20 · ความยาวเท่าเดิม',
    );
    expect(
      formatReviewVideoComparison(
        originalDuration: const Duration(seconds: 20),
        aiDuration: const Duration(seconds: 23),
      ),
      'ต้นฉบับ 00:20 → ผล AI 00:23 · ยาวขึ้น 3 วิ',
    );
    expect(
      formatReviewVideoComparison(
        originalDuration: const Duration(seconds: 20),
        aiDuration: const Duration(milliseconds: 19500),
      ),
      'ต้นฉบับ 00:20 → ผล AI 00:19 · สั้นลงน้อยกว่า 1 วิ',
    );
    expect(
      formatReviewVideoComparison(
        originalDuration: null,
        aiDuration: null,
      ),
      'ต้นฉบับ --:-- → ผล AI --:-- · กำลังอ่านความยาวคลิป',
    );
  });

  testWidgets('switches between original and AI review sources',
      (tester) async {
    final selectedSources = <ReviewVideoSource>[];

    await tester.pumpWidget(
      _testApp(
        ReviewVideoCompareHeader(
          selectedSource: ReviewVideoSource.ai,
          originalDuration: const Duration(seconds: 25),
          aiDuration: const Duration(seconds: 20),
          enabled: true,
          onSourceSelected: selectedSources.add,
        ),
      ),
    );

    expect(
      find.text('ต้นฉบับ 00:25 → ผล AI 00:20 · สั้นลง 5 วิ'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('ai-review-source-ai')),
      ),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('ai-review-source-original')),
    );
    expect(selectedSources, [ReviewVideoSource.original]);
  });

  test('formats review video clocks and clamps the remaining seconds', () {
    expect(formatReviewVideoClock(Duration.zero), '00:00');
    expect(
      formatReviewVideoClock(const Duration(minutes: 2, seconds: 7)),
      '02:07',
    );
    expect(
      formatReviewVideoClock(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '01:02:03',
    );
    expect(
      reviewVideoRemainingSeconds(
        position: const Duration(seconds: 8),
        duration: const Duration(seconds: 25),
      ),
      17,
    );
    expect(
      reviewVideoRemainingSeconds(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 25),
      ),
      0,
    );
    expect(
      reviewVideoRemainingSeconds(
        position: const Duration(seconds: 25),
        duration: const Duration(milliseconds: 25500),
      ),
      1,
    );
  });

  testWidgets('shows elapsed, total, and remaining review time',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        ReviewVideoTimeline(
          position: const Duration(seconds: 8),
          duration: const Duration(seconds: 25),
          enabled: true,
          onSeekStart: (_) {},
          onSeekChanged: (_) {},
          onSeekEnd: (_) {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ai-review-time-elapsed-total')),
      findsOneWidget,
    );
    expect(find.text('00:08 / 00:25'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-review-time-remaining')),
      findsOneWidget,
    );
    expect(find.text('เหลือ 17 วิ'), findsOneWidget);

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    expect(slider.value, 8000);
    expect(slider.max, 25000);
  });

  testWidgets('reports seek start, live movement, and seek end',
      (tester) async {
    final starts = <Duration>[];
    final changes = <Duration>[];
    final ends = <Duration>[];

    await tester.pumpWidget(
      _testApp(
        ReviewVideoTimeline(
          position: Duration.zero,
          duration: const Duration(seconds: 25),
          enabled: true,
          onSeekStart: starts.add,
          onSeekChanged: changes.add,
          onSeekEnd: ends.add,
        ),
      ),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    slider.onChangeStart!(12000);
    slider.onChanged!(12000);
    slider.onChangeEnd!(12000);

    expect(starts, [const Duration(seconds: 12)]);
    expect(changes, [const Duration(seconds: 12)]);
    expect(ends, [const Duration(seconds: 12)]);
  });

  testWidgets('disables seeking while a new preview is rendering',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        ReviewVideoTimeline(
          position: const Duration(seconds: 3),
          duration: const Duration(seconds: 25),
          enabled: false,
          onSeekStart: (_) {},
          onSeekChanged: (_) {},
          onSeekEnd: (_) {},
        ),
      ),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ai-review-seek-slider')),
    );
    expect(slider.onChanged, isNull);
    expect(slider.onChangeStart, isNull);
    expect(slider.onChangeEnd, isNull);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 360, child: child),
      ),
    ),
  );
}
