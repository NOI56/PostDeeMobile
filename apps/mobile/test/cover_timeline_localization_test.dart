import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/review_video_timeline.dart';

String _englishValue(String elapsed, String duration, int remaining) =>
    '$elapsed of $duration, $remaining ${remaining == 1 ? 'second' : 'seconds'} remaining';
String _englishRemaining(int remaining) => '$remaining sec remaining';
void _ignore(Duration _) {}

Widget _app(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))));

ReviewVideoTimeline _timeline({
  Duration position = const Duration(seconds: 8),
  Duration duration = const Duration(seconds: 25),
  Duration? maxPosition,
  bool enabled = true,
  bool english = true,
  ValueChanged<Duration> onStart = _ignore,
  ValueChanged<Duration> onChanged = _ignore,
  ValueChanged<Duration> onEnd = _ignore,
}) =>
    ReviewVideoTimeline(
        position: position,
        duration: duration,
        maxPosition: maxPosition,
        enabled: enabled,
        positionLabel: english ? 'Video position' : 'ตำแหน่งวิดีโอ',
        semanticValueFormatter: english ? _englishValue : null,
        remainingLabelFormatter: english ? _englishRemaining : null,
        onSeekStart: onStart,
        onSeekChanged: onChanged,
        onSeekEnd: onEnd);

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const ValueKey('ai-review-seek-slider')));

Semantics _positionSemantics(WidgetTester tester, String label) =>
    tester.widget<Semantics>(find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label));

void main() {
  testWidgets(
      'timeline retains exact original Thai defaults without formatters',
      (tester) async {
    await tester.pumpWidget(_app(ReviewVideoTimeline(
        position: const Duration(seconds: 8),
        duration: const Duration(seconds: 25),
        enabled: true,
        onSeekStart: _ignore,
        onSeekChanged: _ignore,
        onSeekEnd: _ignore)));
    expect(find.text('00:08 / 00:25'), findsOneWidget);
    expect(find.text('เหลือ 17 วิ'), findsOneWidget);
    expect(_positionSemantics(tester, 'ตำแหน่งวิดีโอ').properties.value,
        '00:08 จาก 00:25 เหลือ 17 วินาที');
    expect(_slider(tester).semanticFormatterCallback!(24000),
        '00:24 จาก 00:25 เหลือ 1 วินาที');
    expect(_slider(tester).value, 8000);
    expect(_slider(tester).max, 25000);
  });

  for (final sample in [
    (
      position: Duration.zero,
      duration: Duration.zero,
      clock: '00:00 / 00:00',
      value: '00:00 of 00:00, 0 seconds remaining',
      remaining: 0
    ),
    (
      position: const Duration(seconds: 25),
      duration: const Duration(milliseconds: 25500),
      clock: '00:25 / 00:25',
      value: '00:25 of 00:25, 1 second remaining',
      remaining: 1
    ),
    (
      position: const Duration(milliseconds: 25500),
      duration: const Duration(milliseconds: 25500),
      clock: '00:25 / 00:25',
      value: '00:25 of 00:25, 0 seconds remaining',
      remaining: 0
    ),
    (
      position: const Duration(hours: 1, minutes: 2, seconds: 2),
      duration: const Duration(hours: 1, minutes: 2, seconds: 3),
      clock: '01:02:02 / 01:02:03',
      value: '01:02:02 of 01:02:03, 1 second remaining',
      remaining: 1
    ),
  ]) {
    testWidgets('custom English timeline formats ${sample.value}',
        (tester) async {
      await tester.pumpWidget(_app(
          _timeline(position: sample.position, duration: sample.duration)));
      expect(find.text(sample.clock), findsOneWidget);
      expect(find.text('${sample.remaining} sec remaining'), findsOneWidget);
      expect(_positionSemantics(tester, 'Video position').properties.value,
          sample.value);
      expect(
          _slider(tester).semanticFormatterCallback!(
              sample.position.inMilliseconds.toDouble()),
          sample.value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'custom formatter receives existing capped elapsed and remaining semantics',
      (tester) async {
    await tester.pumpWidget(_app(_timeline(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 20),
        maxPosition: const Duration(milliseconds: 19900))));
    expect(find.text('00:19 / 00:20'), findsOneWidget);
    expect(find.text('0 sec remaining'), findsOneWidget);
    expect(_positionSemantics(tester, 'Video position').properties.value,
        '00:19 of 00:20, 0 seconds remaining');
    expect(_slider(tester).value, 19900);
    expect(_slider(tester).max, 19900);
    expect(_slider(tester).semanticFormatterCallback!(20000),
        '00:19 of 00:20, 1 second remaining');
  });

  testWidgets(
      'localized timeline preserves start change end rounding and frame clamp',
      (tester) async {
    final starts = <Duration>[];
    final changes = <Duration>[];
    final ends = <Duration>[];
    await tester.pumpWidget(_app(_timeline(
        duration: const Duration(seconds: 20),
        maxPosition: const Duration(milliseconds: 19900),
        onStart: starts.add,
        onChanged: changes.add,
        onEnd: ends.add)));
    final slider = _slider(tester);
    slider.onChangeStart!(-100);
    slider.onChanged!(19999.6);
    slider.onChangeEnd!(35000);
    expect(starts, [Duration.zero]);
    expect(changes, [const Duration(milliseconds: 19900)]);
    expect(ends, [const Duration(milliseconds: 19900)]);
  });

  for (final sample in [
    (enabled: false, duration: const Duration(seconds: 20), max: null),
    (enabled: true, duration: Duration.zero, max: null),
    (enabled: true, duration: const Duration(seconds: 20), max: Duration.zero),
  ]) {
    testWidgets('localized timeline retains disabled callbacks for $sample',
        (tester) async {
      await tester.pumpWidget(_app(_timeline(
          enabled: sample.enabled,
          duration: sample.duration,
          maxPosition: sample.max)));
      expect(_slider(tester).onChangeStart, isNull);
      expect(_slider(tester).onChanged, isNull);
      expect(_slider(tester).onChangeEnd, isNull);
    });
  }

  testWidgets(
      'changing timeline formatters updates language without seek callbacks',
      (tester) async {
    final language = ValueNotifier(false);
    addTearDown(language.dispose);
    final changes = <Duration>[];
    await tester.pumpWidget(_app(ValueListenableBuilder<bool>(
        valueListenable: language,
        builder: (_, english, __) => _timeline(
            english: english,
            onStart: changes.add,
            onChanged: changes.add,
            onEnd: changes.add))));
    expect(find.text('เหลือ 17 วิ'), findsOneWidget);
    language.value = true;
    await tester.pump();
    expect(find.text('17 sec remaining'), findsOneWidget);
    expect(_positionSemantics(tester, 'Video position').properties.value,
        '00:08 of 00:25, 17 seconds remaining');
    expect(_slider(tester).value, 8000);
    expect(changes, isEmpty);
    language.value = false;
    await tester.pump();
    expect(find.text('เหลือ 17 วิ'), findsOneWidget);
    expect(changes, isEmpty);
  });
}
