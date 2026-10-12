import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_theme_picker.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_ui_motion.dart';

Widget _app(Widget child,
        {bool reduced = false, bool active = true, bool ticker = true}) =>
    MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                    enabled: ticker,
                    child: BioUiMotionScope(
                        enabled: active, child: Center(child: child))))));

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('postdee-press-transform')))
    .transform
    .entry(0, 0);

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.descendant(
        of: find.byType(BioUiEntrance), matching: find.byType(Opacity)))
    .opacity;

void _resume(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

class _OriginTicker extends ValueNotifier<TickerModeData> {
  _OriginTicker(bool enabled)
      : super(TickerModeData(enabled: enabled, forceFrames: false));

  bool get isObserved => hasListeners;

  void setEnabled(bool enabled) {
    value = TickerModeData(enabled: enabled, forceFrames: false);
  }
}

void main() {
  testWidgets('press preserves native action semantics layout and hit target',
      (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(BioUiPress(
        child: TextButton(
            style: TextButton.styleFrom(fixedSize: const Size(160, 48)),
            onPressed: () => taps++,
            child: const Text('ใช้แบบนี้')))));
    final button = find.byType(TextButton);
    final bounds = tester.getRect(find.byType(BioUiPress));
    final size = tester.getSize(button);
    final gesture =
        await tester.startGesture(bounds.topLeft + const Offset(2, 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scale(tester), closeTo(.97, .001));
    expect(tester.getSize(button), size);
    expect(tester.getRect(find.byType(BioUiPress)), bounds);
    expect(
        tester
            .widget<Transform>(
                find.byKey(const ValueKey('postdee-press-transform')))
            .transformHitTests,
        isFalse);
    expect(find.bySemanticsLabel('ใช้แบบนี้'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_scale(tester), 1);
    semantics.dispose();
  });

  testWidgets('cancel and disabled controls do not invoke an action',
      (tester) async {
    var taps = 0;
    for (final enabled in [true, false]) {
      await tester.pumpWidget(_app(BioUiPress(
          enabled: enabled,
          child: TextButton(
              onPressed: enabled ? () => taps++ : null,
              child: const Text('เลือกแบบ')))));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('เลือกแบบ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scale(tester), enabled ? lessThan(1) : 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      expect(taps, 0);
    }
  });

  testWidgets('entrance is finite and only the current child is retained',
      (tester) async {
    Widget section(String id) => BioUiEntrance(
        key: ValueKey(id), child: Text(id, key: ValueKey('child-$id')));
    await tester.pumpWidget(_app(section('first')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpWidget(_app(section('second')));
    expect(find.byKey(const ValueKey('child-first')), findsNothing);
    expect(find.byKey(const ValueKey('child-second')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_app(section('second')));
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced ticker and inactive modes stop motion immediately',
      (tester) async {
    for (final mode in ['reduced', 'ticker', 'inactive']) {
      final child = BioUiEntrance(
          key: ValueKey(mode),
          child: BioUiPress(
              child: TextButton(onPressed: () {}, child: const Text('ต่อ'))));
      await tester.pumpWidget(_app(child));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_opacity(tester), inExclusiveRange(0, 1));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ต่อ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scale(tester), lessThan(1));
      await tester.pumpWidget(_app(child,
          reduced: mode == 'reduced',
          active: mode != 'inactive',
          ticker: mode != 'ticker'));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1, reason: mode);
      expect(_scale(tester), 1, reason: mode);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: mode);
      await gesture.cancel();
      await tester.pumpWidget(_app(child));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1, reason: 'no replay on $mode resume');
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('scope respects current lifecycle and stops background motion',
      (tester) async {
    addTearDown(() => _resume(tester));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Real background apps do not render frames. Force a test frame to inspect
    // a scope created while already paused and its fully visible static child.
    tester.binding.scheduleForcedFrame();
    const child = BioUiEntrance(child: Text('ตัวอย่าง'));
    await tester.pumpWidget(_app(child));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    await tester.pumpWidget(
        _app(const BioUiEntrance(key: ValueKey('fresh'), child: Text('ใหม่'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('category entrance retains only its 20 candidates without apply',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    appearance: const LinkInBioAppearance(),
                    onChanged: (_) => changes++)))));
    await tester.pumpAndSettle();
    expect(find.byType(BioUiMotionScope), findsOneWidget);
    expect(profileTemplates, hasLength(100));
    for (final category in profileTemplateCategories.keys) {
      final chip = find.byKey(ValueKey('link-in-bio-category-$category'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(find.byKey(ValueKey('link-in-bio-category-motion-$category')),
          findsOneWidget);
      for (final template in profileTemplates) {
        expect(find.byKey(ValueKey('link-in-bio-template-${template.id}')),
            template.category == category ? findsOneWidget : findsNothing);
      }
      expect(profileTemplates.where((item) => item.category == category),
          hasLength(20));
      expect(changes, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('origin scope swaps listeners and ignores deferred disposal work',
      (tester) async {
    final first = _OriginTicker(true);
    final second = _OriginTicker(true);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget host(_OriginTicker origin, {bool remove = false}) =>
        _app(Builder(builder: (_) {
          if (remove) {
            // Notify during build, then dispose the subscriber before the
            // coalesced post-frame refresh. It must not update disposed state.
            origin.setEnabled(false);
            return const SizedBox.shrink();
          }
          return BioUiOriginScope(
              originTicker: origin,
              child: const BioUiEntrance(child: Text('ตัวอย่างลิงก์')));
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

  testWidgets('disabled picker retains native disabled chips and callbacks',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: BioThemePicker(
                    appearance: const LinkInBioAppearance(),
                    enabled: false,
                    onChanged: (_) => changes++)))));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('link-in-bio-category-cute'));
    expect(tester.widget<ChoiceChip>(chip).onSelected, isNull);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final first = profileTemplates.first;
    final card = find.byKey(ValueKey('link-in-bio-template-${first.id}'));
    expect(tester.widget<InkWell>(card).onTap, isNull);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-in-bio-template-preview')),
        findsNothing);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });
}
