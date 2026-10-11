import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/shared/postdee_press_feedback.dart';
import 'package:postdee_mobile/features/shared/postdee_skeleton.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(child: child),
        ),
      ),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('postdee-press-transform')))
    .transform
    .entry(0, 0);

void main() {
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
