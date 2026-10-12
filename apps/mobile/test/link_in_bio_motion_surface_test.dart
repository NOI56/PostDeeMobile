import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_motion.dart';

class _MotionFrame {
  double phase = 0;
  double entrance = 1;
  bool reduced = false;

  Widget build(double phase, double entrance, bool reduced) {
    this.phase = phase;
    this.entrance = entrance;
    this.reduced = reduced;
    return const Text('ร้านเดิม', key: ValueKey('preview-content'));
  }
}

Widget _app(_MotionFrame frame, LinkInBioEffects effects,
        {bool reduced = false, bool ticker = true}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        body: TickerMode(
          enabled: ticker,
          child: BioMotionSurface(
            key: const ValueKey('preview-motion'),
            effects: effects,
            builder: frame.build,
          ),
        ),
      ),
    );

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

Future<void> _dispose(WidgetTester tester) async {
  tester.binding.scheduleForcedFrame();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void main() {
  testWidgets('preview entrance runs once and finishes without idle frames',
      (tester) async {
    final frame = _MotionFrame();
    const effects = LinkInBioEffects(entrance: true);
    await tester.pumpWidget(_app(frame, effects));
    expect(frame.entrance, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(frame.entrance, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(frame.entrance, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_app(frame, effects));
    expect(frame.entrance, 1);
    expect(find.byKey(const ValueKey('preview-content')), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('equal effect values do not replay a finished preview entrance',
      (tester) async {
    final frame = _MotionFrame();
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        _app(frame, LinkInBioEffects.fromJson(const {'entrance': true})));
    expect(frame.entrance, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await _dispose(tester);
  });

  testWidgets('changing ambient effects does not restart preview entrance',
      (tester) async {
    final frame = _MotionFrame();
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(BioMotionSurface));
    await tester.pumpWidget(_app(
        frame, const LinkInBioEffects(entrance: true, stickers: 'flowers')));
    expect(tester.state(find.byType(BioMotionSurface)), same(state));
    expect(frame.entrance, 1);
    final phase = frame.phase;
    await tester.pump(const Duration(milliseconds: 100));
    expect(frame.phase, isNot(phase));
    expect(frame.entrance, 1);
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    expect(frame.entrance, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await _dispose(tester);
  });

  testWidgets('changing another effect preserves an entrance in progress',
      (tester) async {
    final frame = _MotionFrame();
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    await tester.pump(const Duration(milliseconds: 120));
    final entrance = frame.entrance;
    await tester.pumpWidget(
        _app(frame, const LinkInBioEffects(entrance: true, background: true)));
    expect(frame.entrance, entrance);
    await tester.pump(const Duration(milliseconds: 80));
    expect(frame.entrance, greaterThan(entrance));
    await _dispose(tester);
  });

  testWidgets('explicitly enabling entrance starts one fresh preview entrance',
      (tester) async {
    final frame = _MotionFrame();
    await tester.pumpWidget(_app(frame, const LinkInBioEffects()));
    await tester.pumpAndSettle();
    expect(frame.entrance, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    expect(frame.entrance, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(frame.entrance, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(frame.entrance, 1);
    await tester.pumpWidget(_app(frame, const LinkInBioEffects()));
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    expect(frame.entrance, 0);
    await _dispose(tester);
  });

  testWidgets('enabling entrance while reduced does not queue a later replay',
      (tester) async {
    final frame = _MotionFrame();
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(), reduced: true));
    await tester.pumpWidget(
        _app(frame, const LinkInBioEffects(entrance: true), reduced: true));
    expect(frame.entrance, 1);
    await tester
        .pumpWidget(_app(frame, const LinkInBioEffects(entrance: true)));
    expect(frame.entrance, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await _dispose(tester);
  });

  for (final ambient in [false, true]) {
    for (final mode in ['reduced', 'ticker', 'lifecycle']) {
      testWidgets(
          '$mode interruption settles preview and resumes without entrance replay ambient=$ambient',
          (tester) async {
        _resume(tester);
        addTearDown(() => _resume(tester));
        final frame = _MotionFrame();
        final effects = LinkInBioEffects(entrance: true, background: ambient);
        await tester.pumpWidget(_app(frame, effects));
        await tester.pump(const Duration(milliseconds: 120));
        expect(frame.entrance, inExclusiveRange(0, 1));
        final state = tester.state(find.byType(BioMotionSurface));
        if (mode == 'lifecycle') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.scheduleForcedFrame();
          await tester.pump();
        } else {
          await tester.pumpWidget(_app(frame, effects,
              reduced: mode == 'reduced', ticker: mode != 'ticker'));
        }
        expect(frame.entrance, 1);
        expect(frame.reduced, isTrue);
        expect(frame.phase, 0);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        if (mode == 'lifecycle') {
          _resume(tester);
          await tester.pump();
        } else {
          await tester.pumpWidget(_app(frame, effects));
        }
        expect(tester.state(find.byType(BioMotionSurface)), same(state));
        expect(frame.entrance, 1);
        expect(frame.reduced, isFalse);
        final phase = frame.phase;
        await tester.pump(const Duration(milliseconds: 100));
        expect(frame.entrance, 1);
        expect(frame.phase, ambient ? isNot(phase) : phase);
        expect(tester.binding.hasScheduledFrame, ambient);
        await _dispose(tester);
      });
    }
  }

  for (final mode in ['reduced', 'ticker', 'lifecycle']) {
    testWidgets(
        'preview created in $mode is still and does not replay on enable',
        (tester) async {
      _resume(tester);
      addTearDown(() => _resume(tester));
      final frame = _MotionFrame();
      const effects = LinkInBioEffects(entrance: true, featured: true);
      if (mode == 'lifecycle') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
      }
      await tester.pumpWidget(_app(frame, effects,
          reduced: mode == 'reduced', ticker: mode != 'ticker'));
      expect(frame.entrance, 1);
      expect(frame.reduced, isTrue);
      expect(frame.phase, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      if (mode == 'lifecycle') _resume(tester);
      await tester.pumpWidget(_app(frame, effects));
      expect(frame.entrance, 1);
      expect(frame.reduced, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(frame.entrance, 1);
      expect(frame.phase, greaterThan(0));
      await _dispose(tester);
    });
  }

  for (final effects in [
    const LinkInBioEffects(),
    const LinkInBioEffects(entrance: true),
    const LinkInBioEffects(
        background: true, entrance: true, stickers: 'hearts'),
  ]) {
    testWidgets('preview disposal is safe for effects ${effects.toJson()}',
        (tester) async {
      final frame = _MotionFrame();
      await tester.pumpWidget(_app(frame, effects));
      await tester.pump(const Duration(milliseconds: 60));
      await _dispose(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
