import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/onboarding/onboarding_flow.dart';

double contrast(Color a, Color b) {
  final light = a.computeLuminance();
  final dark = b.computeLuminance();
  return light > dark
      ? (light + .05) / (dark + .05)
      : (dark + .05) / (light + .05);
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  test('active secondary text remains legible on light surfaces', () {
    AppTheme.applyThemeMode(ThemeMode.light);
    for (final surface in [
      AppTheme.glass,
      AppTheme.pitchBlack,
      AppTheme.mint
    ]) {
      expect(contrast(AppTheme.textMuted, surface), greaterThanOrEqualTo(4.5));
      expect(
          contrast(AppTheme.accentCyanInk, surface), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('default primary action keeps readable white text',
      (tester) async {
    AppTheme.applyThemeMode(ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body:
                FilledButton(onPressed: () {}, child: const Text('ยืนยัน')))));
    final material = tester.widget<Material>(find
        .descendant(
            of: find.byType(FilledButton), matching: find.byType(Material))
        .first);
    expect(contrast(material.color!, Colors.white), greaterThanOrEqualTo(4.5));
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('onboarding all steps fit 320dp with ${scale}x Thai text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(ThemeMode.light);
      await tester.runAsync(() async {
        final fonts = FontLoader('Anuphan');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(
              rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
        }
        await fonts.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      var completed = false;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('th'),
          supportedLocales: const [Locale('th'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: OnboardingFlow(onFinished: () => completed = true)));
      for (var step = 0; step < 3; step++) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'intro step ${step + 1} must not overflow');
        final next = find.byKey(const ValueKey('onboarding-next'));
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
      }
      expect(completed, isTrue);
    });
  }
}
