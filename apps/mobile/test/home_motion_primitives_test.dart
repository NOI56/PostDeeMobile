import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/shared/postdee_press_feedback.dart';
import 'package:postdee_mobile/features/shared/postdee_skeleton.dart';

Widget _app(Widget child,
        {bool reduceMotion = false, bool tickerEnabled = true}) =>
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child:
              TickerMode(enabled: tickerEnabled, child: Center(child: child)),
        ),
      ),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('postdee-press-transform')))
    .transform
    .entry(0, 0);

void _resume(TestWidgetsFlutterBinding binding) {
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

AnimationController _skeletonController(WidgetTester tester) => tester
    .widget<AnimatedBuilder>(find.descendant(
        of: find.byType(PostDeeSkeleton),
        matching: find.byType(AnimatedBuilder)))
    .animation as AnimationController;

void main() {
  setUp(() => _resume(TestWidgetsFlutterBinding.ensureInitialized()));
  tearDown(() => _resume(TestWidgetsFlutterBinding.ensureInitialized()));

  for (final mode in ['disabled', 'reduced', 'ticker', 'background']) {
    for (final phase in ['pressing', 'held', 'releasing']) {
      testWidgets('$mode interrupts $phase feedback without stale replay',
          (tester) async {
        var taps = 0;
        Widget host(bool blocked) => _app(
              PostDeePressFeedback(
                enabled: mode != 'disabled' || !blocked,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('ทำต่อ'),
                ),
              ),
              reduceMotion: mode == 'reduced' && blocked,
              tickerEnabled: mode != 'ticker' || !blocked,
            );
        await tester.pumpWidget(host(false));
        final bounds = tester.getRect(find.byType(TextButton));
        final gesture = await tester.startGesture(bounds.center);
        await tester.pump();
        await tester
            .pump(Duration(milliseconds: phase == 'pressing' ? 50 : 120));
        expect(_scale(tester), lessThan(1));
        if (phase == 'releasing') {
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          expect(_scale(tester), lessThan(1));
          expect(taps, 1);
        }
        if (mode == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.scheduleForcedFrame();
          await tester.pump();
        } else {
          await tester.pumpWidget(host(true));
        }
        expect(_scale(tester), 1,
            reason: 'Blocking motion must finish the transform immediately.');
        expect(tester.getRect(find.byType(TextButton)), bounds);
        if (phase != 'releasing') await gesture.cancel();
        await tester.pumpAndSettle();
        expect(taps, phase == 'releasing' ? 1 : 0);
        if (mode == 'background') {
          _resume(tester.binding);
          await tester.pump();
        } else {
          await tester.pumpWidget(host(false));
        }
        expect(_scale(tester), 1);
        await tester.pump(const Duration(milliseconds: 30));
        expect(_scale(tester), 1,
            reason: 'Returning to the page must not replay the old press.');
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        final fresh = await tester
            .startGesture(tester.getCenter(find.byType(TextButton)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(_scale(tester), closeTo(.97, .001));
        await fresh.cancel();
        await tester.pumpAndSettle();
        expect(_scale(tester), 1);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$mode at creation keeps native action and static feedback',
        (tester) async {
      var taps = 0;
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
      }
      await tester.pumpWidget(_app(
        PostDeePressFeedback(
          enabled: mode != 'disabled',
          child: TextButton(
            onPressed: () => taps++,
            child: const Text('ทำต่อ'),
          ),
        ),
        reduceMotion: mode == 'reduced',
        tickerEnabled: mode != 'ticker',
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(TextButton)));
      if (mode == 'background') tester.binding.scheduleForcedFrame();
      await tester.pump();
      if (mode == 'background') tester.binding.scheduleForcedFrame();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester), 1);
      await gesture.up();
      if (mode == 'background') tester.binding.scheduleForcedFrame();
      await tester.pumpAndSettle();
      expect(taps, 1,
          reason: 'The feedback guard must not replace the native action.');
      expect(_scale(tester), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('skeleton stops and resets in background then resumes fresh',
      (tester) async {
    await tester.pumpWidget(_app(const PostDeeSkeleton(width: 120)));
    await tester.pump(const Duration(milliseconds: 400));
    final controller = _skeletonController(tester);
    expect(controller.isAnimating, isTrue);
    expect(controller.value, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(controller.isAnimating, isFalse);
    expect(controller.value, 0);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester.binding);
    await tester.pump();
    expect(controller.isAnimating, isTrue);
    expect(controller.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('skeleton created while paused remains static until resumed',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pumpWidget(_app(const PostDeeSkeleton(width: 120)));
    final controller = _skeletonController(tester);
    expect(controller.isAnimating, isFalse);
    expect(controller.value, 0);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester.binding);
    await tester.pump();
    expect(controller.isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary skeleton rebuild retains the current sweep phase',
      (tester) async {
    await tester.pumpWidget(_app(const PostDeeSkeleton(width: 120)));
    await tester.pump(const Duration(milliseconds: 400));
    final controller = _skeletonController(tester);
    final progress = controller.value;
    await tester.pumpWidget(_app(const PostDeeSkeleton(width: 140)));
    expect(_skeletonController(tester), same(controller));
    expect(controller.value, progress);
    expect(controller.isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('press feedback keeps the native action and original hit region',
      (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(PostDeePressFeedback(
      child: TextButton(
        onPressed: () => taps++,
        style: TextButton.styleFrom(fixedSize: const Size(160, 48)),
        child: const Text('ทำต่อ'),
      ),
    )));
    final button = find.byType(TextButton);
    final bounds = tester.getRect(button);
    final originalSize = tester.getSize(button);
    final gesture =
        await tester.startGesture(bounds.topLeft + const Offset(2, 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester), closeTo(.97, .001));
    expect(tester.getSize(button), originalSize);
    final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('postdee-press-transform')));
    expect(transform.transformHitTests, isFalse);
    expect(find.bySemanticsLabel('ทำต่อ'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_scale(tester), 1);
    semantics.dispose();
  });

  testWidgets('cancelled presses reset without firing the native action',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(PostDeePressFeedback(
      child: TextButton(onPressed: () => taps++, child: const Text('ทำต่อ')),
    )));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('ทำต่อ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester), lessThan(1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(taps, 0);
  });

  testWidgets('disabled and reduced-motion controls do not shrink',
      (tester) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(_app(
        PostDeePressFeedback(
          enabled: reduced,
          child: TextButton(
              onPressed: reduced ? () {} : null, child: const Text('ทำต่อ')),
        ),
        reduceMotion: reduced,
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ทำต่อ')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_scale(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'skeleton stops ticking when motion is reduced or tab is inactive',
      (tester) async {
    for (final mode in ['reduced', 'inactive', 'static']) {
      await tester.pumpWidget(_app(
        TickerMode(
          enabled: mode != 'inactive',
          child: PostDeeSkeleton(
              width: 120, height: 14, animate: mode != 'static'),
        ),
        reduceMotion: mode == 'reduced',
      ));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getSize(find.byType(PostDeeSkeleton)), const Size(120, 14));
    }
  });

  testWidgets(
      'an active skeleton sweeps then stops after accessibility changes',
      (tester) async {
    await tester.pumpWidget(_app(const PostDeeSkeleton(width: 120)));
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(
        _app(const PostDeeSkeleton(width: 120), reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
