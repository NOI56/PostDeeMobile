import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_time_picker.dart';

const _hourKey = ValueKey('postdee-time-hour-picker');
const _minuteKey = ValueKey('postdee-time-minute-picker');
const _confirmKey = ValueKey('postdee-time-confirm');
const _cancelKey = ValueKey('postdee-time-cancel');
const _summaryKey = ValueKey('postdee-time-summary');

class _Harness {
  _Harness({
    this.initial = const TimeOfDay(hour: 18, minute: 30),
    this.date,
    this.textScale = 1,
    this.dark = false,
    this.keyboardInset = 0,
    this.reducedMotion = false,
  });

  TimeOfDay initial;
  final DateTime? date;
  final double textScale;
  final bool dark;
  final double keyboardInset;
  final bool reducedMotion;
  TimeOfDay? result;
  var completions = 0;

  Widget app() => MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(builder: (context) {
            return Center(
              child: FilledButton(
                key: const ValueKey('open-picker'),
                onPressed: () async {
                  result = await showPostDeeTimePicker(
                    context: context,
                    initialTime: initial,
                    date: date,
                  );
                  completions++;
                  if (result != null) initial = result!;
                },
                child: const Text('เลือกเวลา'),
              ),
            );
          }),
        ),
      );
}

bool _fontsLoaded = false;

Future<void> _open(WidgetTester tester, _Harness harness) async {
  if (!_fontsLoaded) {
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
    });
    _fontsLoaded = true;
  }
  await tester.pumpWidget(harness.app());
  await tester.tap(find.byKey(const ValueKey('open-picker')));
  await tester.pumpAndSettle();
}

CupertinoPicker _wheel(WidgetTester tester, Key key) =>
    tester.widget<CupertinoPicker>(find.byKey(key));

Future<void> _jump(WidgetTester tester, Key key, int index) async {
  _wheel(tester, key).scrollController!.jumpToItem(index);
  await tester.pump();
}

void _expectTime(WidgetTester tester, String time) {
  expect(
      find.descendant(
          of: find.byKey(_summaryKey), matching: find.text('$time น.')),
      findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'opens native looping wheels at the supplied 23:59 and local date',
      (tester) async {
    final harness = _Harness(
        initial: const TimeOfDay(hour: 23, minute: 59),
        date: DateTime(2026, 10, 24));
    await _open(tester, harness);
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);
    expect(find.text('เลือกเวลาโพสต์'), findsOneWidget);
    expect(find.text('ชั่วโมง'), findsOneWidget);
    expect(find.text('นาที'), findsOneWidget);
    expect(find.textContaining('24 ต.ค.'), findsOneWidget);
    expect(find.textContaining('เวลาตามเครื่อง'), findsOneWidget);
    expect(_wheel(tester, _hourKey).childDelegate,
        isA<ListWheelChildLoopingListDelegate>());
    expect(_wheel(tester, _minuteKey).childDelegate,
        isA<ListWheelChildLoopingListDelegate>());
    expect(_wheel(tester, _hourKey).scrollController!.selectedItem, 23);
    expect(_wheel(tester, _minuteKey).scrollController!.selectedItem, 59);
    _expectTime(tester, '23:59');
    expect(harness.completions, 0);
  });

  testWidgets(
      'hours roll forward and backward without changing minutes or date',
      (tester) async {
    await _open(tester, _Harness(date: DateTime(2026, 10, 24)));
    for (final entry in {
      23: '23:30',
      24: '00:30',
      25: '01:30',
      -1: '23:30',
      -2: '22:30'
    }.entries) {
      await _jump(tester, _hourKey, entry.key);
      _expectTime(tester, entry.value);
      expect(find.textContaining('24 ต.ค.'), findsOneWidget);
      expect(_wheel(tester, _minuteKey).scrollController!.selectedItem, 30);
    }
  });

  testWidgets('minutes roll forward and backward independently of hours',
      (tester) async {
    await _open(tester, _Harness(date: DateTime(2026, 10, 24)));
    for (final entry in {
      59: '18:59',
      60: '18:00',
      61: '18:01',
      -1: '18:59',
      -2: '18:58'
    }.entries) {
      await _jump(tester, _minuteKey, entry.key);
      _expectTime(tester, entry.value);
      expect(find.textContaining('24 ต.ค.'), findsOneWidget);
      expect(_wheel(tester, _hourKey).scrollController!.selectedItem, 18);
    }
  });

  testWidgets('a real drag passes the last hour and returns across zero',
      (tester) async {
    await _open(
        tester, _Harness(initial: const TimeOfDay(hour: 23, minute: 30)));
    final wheel = _wheel(tester, _hourKey);
    await tester.timedDrag(find.byKey(_hourKey),
        Offset(0, -wheel.itemExtent * 1.3), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final afterForward = wheel.scrollController!.selectedItem;
    expect(afterForward, greaterThanOrEqualTo(24));
    _expectTime(tester, '${(afterForward % 24).toString().padLeft(2, '0')}:30');
    await _jump(tester, _hourKey, 0);
    await tester.timedDrag(find.byKey(_hourKey),
        Offset(0, wheel.itemExtent * 1.3), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final afterBackward = wheel.scrollController!.selectedItem;
    expect(afterBackward, lessThan(0));
    _expectTime(
        tester, '${(afterBackward % 24).toString().padLeft(2, '0')}:30');
  });

  testWidgets('a real minute drag rolls without carrying into the hour',
      (tester) async {
    await _open(
        tester, _Harness(initial: const TimeOfDay(hour: 18, minute: 59)));
    final wheel = _wheel(tester, _minuteKey);
    await tester.timedDrag(find.byKey(_minuteKey),
        Offset(0, -wheel.itemExtent * 1.3), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final afterForward = wheel.scrollController!.selectedItem;
    expect(afterForward, greaterThanOrEqualTo(60));
    _expectTime(tester, '18:${(afterForward % 60).toString().padLeft(2, '0')}');
    await _jump(tester, _minuteKey, 0);
    await tester.timedDrag(find.byKey(_minuteKey),
        Offset(0, wheel.itemExtent * 1.3), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final afterBackward = wheel.scrollController!.selectedItem;
    expect(afterBackward, lessThan(0));
    _expectTime(
        tester, '18:${(afterBackward % 60).toString().padLeft(2, '0')}');
  });

  testWidgets('accessibility adjusts both loop boundaries independently',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _open(
          tester, _Harness(initial: const TimeOfDay(hour: 23, minute: 59)));
      final hour = tester.getSemantics(find.byKey(_hourKey));
      expect(
          hour,
          isSemantics(
            label: 'ชั่วโมง',
            value: '23',
            increasedValue: '00',
            decreasedValue: '22',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ));
      hour.owner!.performAction(hour.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      _expectTime(tester, '00:59');
      final minute = tester.getSemantics(find.byKey(_minuteKey));
      expect(
          minute,
          isSemantics(
            label: 'นาที',
            value: '59',
            increasedValue: '00',
            decreasedValue: '58',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
          ));
      minute.owner!.performAction(minute.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      _expectTime(tester, '00:00');
      minute.owner!.performAction(minute.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      _expectTime(tester, '00:59');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reduced motion taps jump directly to the adjacent wrapped value',
      (tester) async {
    await _open(
        tester,
        _Harness(
          initial: const TimeOfDay(hour: 23, minute: 59),
          reducedMotion: true,
        ));
    final zero =
        find.descendant(of: find.byKey(_hourKey), matching: find.text('00'));
    await tester.tap(zero);
    await tester.pump();
    _expectTime(tester, '00:59');
    expect(
        _wheel(tester, _hourKey)
            .scrollController!
            .position
            .isScrollingNotifier
            .value,
        isFalse);
  });

  testWidgets(
      'narrow large-text actions stack and keep the Thai cancel word whole',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _open(tester, _Harness(textScale: 1.7, dark: true));
    await tester.ensureVisible(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    final cancel = tester.getRect(find.byKey(_cancelKey));
    final confirm = tester.getRect(find.byKey(_confirmKey));
    expect(cancel.width, closeTo(confirm.width, .1));
    expect(confirm.top, greaterThan(cancel.bottom));
    final text = find.descendant(
        of: find.byKey(_cancelKey), matching: find.text('ยกเลิก'));
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 'ยกเลิก'.length));
    expect(boxes.map((box) => box.top).toSet(), hasLength(1));
    expect(cancel.top, greaterThanOrEqualTo(0));
    expect(confirm.bottom, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel returns null and reopening preserves the previous time',
      (tester) async {
    final harness = _Harness();
    await _open(tester, harness);
    await _jump(tester, _hourKey, 22);
    await _jump(tester, _minuteKey, 17);
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(harness.completions, 1);
    expect(harness.result, isNull);
    expect(harness.initial, const TimeOfDay(hour: 18, minute: 30));
    await tester.tap(find.byKey(const ValueKey('open-picker')));
    await tester.pumpAndSettle();
    _expectTime(tester, '18:30');
  });

  testWidgets('confirm returns only the selected time across both rollovers',
      (tester) async {
    final harness = _Harness(date: DateTime(2026, 10, 24));
    await _open(tester, harness);
    await _jump(tester, _hourKey, 24);
    await _jump(tester, _minuteKey, 60);
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    expect(harness.completions, 1);
    expect(harness.result, const TimeOfDay(hour: 0, minute: 0));
    expect(harness.date, DateTime(2026, 10, 24));
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsNothing);
  });

  testWidgets('confirm during movement commits the nearest visible minute',
      (tester) async {
    final harness = _Harness();
    await _open(tester, harness);
    final controller = _wheel(tester, _minuteKey).scrollController!;
    unawaited(controller.animateToItem(40,
        duration: const Duration(seconds: 1), curve: Curves.linear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nearest = controller.selectedItem % 60;
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    expect(harness.result, TimeOfDay(hour: 18, minute: nearest));
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back dismisses without a selected result',
      (tester) async {
    final harness = _Harness();
    await _open(tester, harness);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.completions, 1);
    expect(harness.result, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'small large-text ${dark ? 'dark' : 'light'} picker remains usable with keyboard insets',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = _Harness(
        initial: const TimeOfDay(hour: 23, minute: 59),
        date: DateTime(2026, 10, 24),
        textScale: 1.7,
        dark: dark,
        keyboardInset: 120,
        reducedMotion: true,
      );
      await _open(tester, harness);
      expect(tester.takeException(), isNull);
      final hour = _wheel(tester, _hourKey);
      final hourNumber =
          find.descendant(of: find.byKey(_hourKey), matching: find.text('23'));
      expect(tester.getSize(hourNumber).height,
          lessThanOrEqualTo(hour.itemExtent));
      await tester.ensureVisible(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(_confirmKey)).bottom,
          lessThanOrEqualTo(480));
      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      expect(harness.result, const TimeOfDay(hour: 23, minute: 59));
    });
  }
}
