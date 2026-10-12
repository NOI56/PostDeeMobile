import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/profile/profile_ui_motion.dart';

Widget _app(Widget child,
        {bool reduced = false, bool active = true, bool ticker = true}) =>
    MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                    enabled: ticker,
                    child: AccountUiMotionScope(
                        enabled: active, child: Center(child: child))))));

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('postdee-press-transform')))
    .transform
    .entry(0, 0);

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
        of: find.byType(AccountUiEntrance), matching: find.byType(Opacity)))
    .opacity;

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

class _OriginTicker extends ValueNotifier<TickerModeData> {
  _OriginTicker(bool enabled)
      : super(TickerModeData(enabled: enabled, forceFrames: false));

  bool get isObserved => hasListeners;

  void setEnabled(bool enabled) {
    value = TickerModeData(enabled: enabled, forceFrames: false);
  }
}

void main() {
  for (final release in ['cancel', 'up']) {
    testWidgets('account held press can unmount before pointer $release',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(AccountUiPress(
          child: TextButton(
              onPressed: () => taps++, child: const Text('ตัวเลือก')))));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ตัวเลือก')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester), closeTo(.97, .001));
      await tester.pumpWidget(const SizedBox.shrink());
      if (release == 'cancel') {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('account press preserves native action semantics and edge hit',
      (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(AccountUiPress(
          child: TextButton(
              style: TextButton.styleFrom(fixedSize: const Size(160, 48)),
              onPressed: () => taps++,
              child: const Text('แก้ไขบัญชี')))));
      final button = find.byType(TextButton);
      final bounds = tester.getRect(find.byType(AccountUiPress));
      final size = tester.getSize(button);
      final gesture =
          await tester.startGesture(bounds.topLeft + const Offset(2, 24));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester), closeTo(.97, .001));
      expect(tester.getSize(button), size);
      expect(tester.getRect(find.byType(AccountUiPress)), bounds);
      expect(
          tester
              .widget<Transform>(
                  find.byKey(const ValueKey('postdee-press-transform')))
              .transformHitTests,
          isFalse);
      expect(find.bySemanticsLabel('แก้ไขบัญชี'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_scale(tester), 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('account cancelled and disabled presses do not invoke actions',
      (tester) async {
    var taps = 0;
    for (final enabled in [true, false]) {
      await tester.pumpWidget(_app(AccountUiPress(
          enabled: enabled,
          child: TextButton(
              onPressed: enabled ? () => taps++ : null,
              child: const Text('เลือกค่า')))));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('เลือกค่า')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester), enabled ? lessThan(1) : 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      expect(taps, 0);
    }
  });

  testWidgets('hidden account first activation enters without remounting child',
      (tester) async {
    Widget entrance(bool active, [String label = 'บัญชี']) => AccountUiEntrance(
        key: const ValueKey('stable-account-entrance'),
        isActive: active,
        child: Text(label, key: const ValueKey('stable-account-child')));
    await tester.pumpWidget(_app(entrance(false), active: false));
    await tester.pumpAndSettle();
    final entranceState = tester.state(find.byType(AccountUiEntrance));
    final child =
        tester.element(find.byKey(const ValueKey('stable-account-child')));
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_app(entrance(true)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(entrance(true, 'ข้อมูลใหม่')));
    expect(_opacity(tester), 1);
    expect(tester.state(find.byType(AccountUiEntrance)), same(entranceState));
    expect(tester.element(find.byKey(const ValueKey('stable-account-child'))),
        same(child));
    await tester.pumpWidget(_app(entrance(false), active: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(entrance(true)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.state(find.byType(AccountUiEntrance)), same(entranceState));
    expect(tester.element(find.byKey(const ValueKey('stable-account-child'))),
        same(child));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account reduced and parent ticker interrupt without replay',
      (tester) async {
    for (final mode in ['reduced', 'ticker']) {
      final child = AccountUiEntrance(
          key: ValueKey(mode),
          child: AccountUiPress(
              child: TextButton(onPressed: () {}, child: const Text('ต่อ'))));
      await tester.pumpWidget(_app(child));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_opacity(tester), inExclusiveRange(0, 1));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ต่อ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scale(tester), lessThan(1));
      await tester.pumpWidget(
          _app(child, reduced: mode == 'reduced', ticker: mode != 'ticker'));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1, reason: mode);
      expect(_scale(tester), 1, reason: mode);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: mode);
      await gesture.cancel();
      await tester.pumpWidget(_app(child));
      await tester.pump();
      expect(_opacity(tester), 1, reason: 'no replay on $mode resume');
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('account lifecycle snapshot and background stop finite entrance',
      (tester) async {
    addTearDown(() => _resume(tester));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester
        .pumpWidget(_app(const AccountUiEntrance(child: Text('บัญชี'))));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_app(const AccountUiEntrance(
        key: ValueKey('new-account'), child: Text('บัญชีใหม่'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account reduced motion keeps native disclosure usable',
      (tester) async {
    await tester.pumpWidget(_app(
        const ExpansionTile(
            title: Text('ตัวเลือกบัญชี'), children: [Text('รายละเอียด')]),
        reduced: true));
    final context = tester.element(find.byType(ExpansionTile));
    expect(TickerMode.getValuesNotifier(context).value.enabled, isTrue);
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    await tester.tap(find.text('ตัวเลือกบัญชี'));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียด'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account origin swaps listeners and ignores disposed deferred work',
      (tester) async {
    final first = _OriginTicker(true);
    final second = _OriginTicker(true);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget host(_OriginTicker origin, {bool remove = false}) =>
        _app(Builder(builder: (_) {
          if (remove) {
            origin.setEnabled(false);
            return const SizedBox.shrink();
          }
          return AccountUiOriginScope(
              originTicker: origin,
              child: const AccountUiEntrance(child: Text('ตัวเลือก')));
        }));
    await tester.pumpWidget(host(first));
    await tester.pumpAndSettle();
    expect(first.isObserved, isTrue);
    await tester.pumpWidget(host(second));
    await tester.pumpAndSettle();
    expect(first.isObserved, isFalse);
    expect(second.isObserved, isTrue);
    first.setEnabled(false);
    await tester.pump();
    expect(_opacity(tester), 1);
    second.setEnabled(false);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    second.setEnabled(true);
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(second, remove: true));
    await tester.pumpAndSettle();
    expect(second.isObserved, isFalse);
    second.setEnabled(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('account origin coalesces build notifications and reads latest',
      (tester) async {
    final origin = _OriginTicker(true);
    addTearDown(origin.dispose);
    Widget host({bool notify = false, bool finalEnabled = true}) =>
        _app(Builder(builder: (_) {
          if (notify) {
            origin.setEnabled(false);
            origin.setEnabled(finalEnabled);
          }
          return AccountUiOriginScope(
              originTicker: origin,
              child: AccountUiPress(
                  child:
                      TextButton(onPressed: () {}, child: const Text('ค่า'))));
        }));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('ค่า')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester), closeTo(.97, .001));
    await tester.pumpWidget(host(notify: true));
    await tester.pump();
    expect(_scale(tester), closeTo(.97, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(notify: true, finalEnabled: false));
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
