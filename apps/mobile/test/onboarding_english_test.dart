import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/onboarding/onboarding_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

const onboardingEnglishTitles = [
  'Connect your channels once',
  'One video. Every channel.',
  'Schedule and track in one place',
];

const onboardingEnglishDescriptions = [
  'Connect TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels without switching between apps.',
  'Choose one 9:16 video and send it to all your channels, with AI to help write Thai captions.',
  'Plan posts in your calendar, then see views, likes, and engagement across platforms in one place.',
];

const onboardingThaiTitles = [
  'เชื่อมช่องทางครั้งเดียว',
  'คลิปเดียว โพสต์ได้ทุกที่',
  'ตั้งเวลา + ดูยอดที่เดียว',
];

const onboardingThaiDescriptions = [
  'เชื่อม TikTok, YouTube Shorts, Instagram Reels และ Facebook Reels บนเพจ ไม่ต้องสลับหลายแอป',
  'เลือกวิดีโอ 9:16 หนึ่งคลิป แล้วส่งขึ้นทุกช่องทางพร้อมกัน พร้อม AI ช่วยใส่แคปชั่นภาษาไทย',
  'วางแผนโพสต์ในปฏิทิน แล้วดูยอดวิว ไลก์ และเอนเกจเมนต์รวมทุกแพลตฟอร์มในหน้าเดียว',
];

class OnboardingEnglishFixture {
  OnboardingEnglishFixture({
    Locale locale = const Locale('en'),
    this.dark = false,
    this.scale = 1,
  }) : language = ValueNotifier(locale);

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final boundaryKey = GlobalKey();
  final requestedLocales = <Locale>[];
  bool bareMaterialApp = false;
  bool withLanguageSelector = true;
  int finished = 0;

  Widget app() => ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: [
              if (!bareMaterialApp) PostDeeLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundaryKey,
              child: OnboardingFlow(
                onFinished: () => finished++,
                onLocaleChanged: withLanguageSelector
                    ? (value) {
                        requestedLocales.add(value);
                        language.value = value;
                      }
                    : null,
              ),
            ),
          );
        },
      );

  Future<void> mount(WidgetTester tester) async {
    await tester.runAsync(loadOnboardingEnglishFonts);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    language.dispose();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output =
        Platform.environment['POSTDEE_ONBOARDING_ENGLISH_PREVIEW_DIR'];
    if (output == null || output.isEmpty) return;
    await tester.pumpAndSettle();
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

Future<void> loadOnboardingEnglishFonts() async {
  final fonts = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(
      rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'),
    );
  }
  await fonts.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> nextOnboardingEnglish(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('onboarding-next')));
  await tester.pumpAndSettle();
}

Future<void> revealOnboardingEnglish(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void expectOnboardingEnglishReadable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)).first,
  );
  final rect = tester.getRect(finder);
  final description = '${tester.widget<Text>(finder).data}: '
      '${paragraph.size}, rect=$rect';
  expect(paragraph.didExceedMaxLines, isFalse, reason: description);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(
      paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5,
    ),
    reason: description,
  );
  expect(rect.left, greaterThanOrEqualTo(-.5), reason: description);
  expect(rect.right, lessThanOrEqualTo(320.5), reason: description);
}

void expectOnboardingEnglishAction(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

void main() {
  setUp(
      () => SharedPreferences.setMockInitialValues({'other_setting': 'keep'}));
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English onboarding introduces the supported channels',
      (tester) async {
    final fixture = OnboardingEnglishFixture();
    await fixture.mount(tester);
    expect(find.text(onboardingEnglishTitles[0]), findsOneWidget);
    expect(find.text(onboardingEnglishDescriptions[0]), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(fixture.finished, 0);
    await fixture.close(tester);
  });

  testWidgets('English next visits all three steps and finishes only on last',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = OnboardingEnglishFixture();
    await fixture.mount(tester);
    for (var step = 0; step < 3; step++) {
      expect(find.text(onboardingEnglishTitles[step]), findsOneWidget);
      expect(find.text(onboardingEnglishDescriptions[step]), findsOneWidget);
      expect(fixture.finished, 0);
      expect(find.text(step == 2 ? 'Get started' : 'Next'), findsOneWidget);
      await fixture.capture(tester, 'step-${step + 1}-en-1x');
      await nextOnboardingEnglish(tester);
    }
    expect(fixture.finished, 1);
    await fixture.close(tester);
  });

  testWidgets('changing locale preserves the current onboarding step',
      (tester) async {
    final fixture = OnboardingEnglishFixture(locale: const Locale('th'));
    await fixture.mount(tester);
    await nextOnboardingEnglish(tester);
    expect(find.text(onboardingThaiTitles[1]), findsOneWidget);
    final previousState = tester.state(find.byType(OnboardingFlow));
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text(onboardingEnglishTitles[1]), findsOneWidget);
    expect(tester.state(find.byType(OnboardingFlow)), same(previousState));
    expect(fixture.finished, 0);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text(onboardingThaiTitles[1]), findsOneWidget);
    expect(fixture.finished, 0);
    await fixture.close(tester);
  });

  testWidgets('progress and Back semantics follow navigation without finishing',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = OnboardingEnglishFixture();
      await fixture.mount(tester);
      final back = find.byKey(const ValueKey('onboarding-back'));
      final progress = find.byKey(const ValueKey('onboarding-progress'));
      expect(back, findsNothing);
      expect(tester.getSemantics(progress).label, 'Step 1 of 3');
      await nextOnboardingEnglish(tester);
      expect(tester.getSemantics(progress).label, 'Step 2 of 3');
      final backData = tester.getSemantics(back).getSemanticsData();
      expect(backData.label, 'Back');
      expect(backData.flagsCollection.isButton, isTrue);
      expect(backData.hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text(onboardingEnglishTitles[0]), findsOneWidget);
      expect(tester.getSemantics(progress).label, 'Step 1 of 3');
      expect(back, findsNothing);
      expect(fixture.finished, 0);
      await nextOnboardingEnglish(tester);
      await nextOnboardingEnglish(tester);
      expect(tester.getSemantics(progress).label, 'Step 3 of 3');
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(tester.getSemantics(progress).label, 'ขั้นตอนที่ 3 จาก 3');
      expect(tester.getSemantics(back).label, 'ย้อนกลับ');
      expect(fixture.finished, 0);
      await fixture.close(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Skip completes once from every onboarding step', (tester) async {
    for (var step = 0; step < 3; step++) {
      final fixture = OnboardingEnglishFixture();
      await fixture.mount(tester);
      for (var next = 0; next < step; next++) {
        await nextOnboardingEnglish(tester);
      }
      expect(fixture.finished, 0);
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(fixture.finished, 1);
      await fixture.close(tester);
    }
  });

  testWidgets(
      'language popup switches native choices and retains the same step',
      (tester) async {
    final fixture = OnboardingEnglishFixture();
    await fixture.mount(tester);
    await nextOnboardingEnglish(tester);
    final originalState = tester.state(find.byType(OnboardingFlow));
    final language = find.byKey(const ValueKey('onboarding-language'));
    expect(find.byTooltip('Change language'), findsOneWidget);
    await tester.tap(language);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<PopupMenuItem<Locale>>(
                find.byType(PopupMenuItem<Locale>))
            .map((item) => item.value),
        [const Locale('th'), const Locale('en')]);
    expect(find.text('ไทย'), findsOneWidget);
    expect(find.text('English'), findsNWidgets(2));
    await tester.tap(find.text('ไทย'));
    await tester.pumpAndSettle();
    expect(fixture.requestedLocales, [const Locale('th')]);
    expect(find.text(onboardingThaiTitles[1]), findsOneWidget);
    expect(tester.state(find.byType(OnboardingFlow)), same(originalState));
    expect(find.byTooltip('เปลี่ยนภาษา'), findsOneWidget);
    await tester.tap(language);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(fixture.requestedLocales, [const Locale('th'), const Locale('en')]);
    expect(find.text(onboardingEnglishTitles[1]), findsOneWidget);
    expect(tester.state(find.byType(OnboardingFlow)), same(originalState));
    expect(fixture.finished, 0);
    await fixture.close(tester);
  });

  testWidgets('dismissing the language popup does not select or finish',
      (tester) async {
    final fixture = OnboardingEnglishFixture();
    await fixture.mount(tester);
    await nextOnboardingEnglish(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-language')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 450));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<Locale>), findsNothing);
    expect(fixture.requestedLocales, isEmpty);
    expect(find.text(onboardingEnglishTitles[1]), findsOneWidget);
    expect(fixture.finished, 0);
    await fixture.close(tester);
  });

  testWidgets('omitting the optional callback keeps the legacy standalone API',
      (tester) async {
    final fixture = OnboardingEnglishFixture()..withLanguageSelector = false;
    await fixture.mount(tester);
    expect(find.byKey(const ValueKey('onboarding-language')), findsNothing);
    expect(find.text(onboardingEnglishTitles[0]), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(fixture.finished, 1);
    expect(fixture.requestedLocales, isEmpty);
    await fixture.close(tester);
  });

  testWidgets(
      'standalone navigation and locale changes do not persist settings',
      (tester) async {
    final fixture = OnboardingEnglishFixture();
    await fixture.mount(tester);
    await nextOnboardingEnglish(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ไทย'));
    await tester.pumpAndSettle();
    await nextOnboardingEnglish(tester);
    await nextOnboardingEnglish(tester);
    expect(fixture.finished, 1);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'other_setting'});
    expect(preferences.getString('other_setting'), 'keep');
    await fixture.close(tester);
  });

  testWidgets('plain MaterialApp keeps the original three Thai steps',
      (tester) async {
    final fixture = OnboardingEnglishFixture()
      ..bareMaterialApp = true
      ..withLanguageSelector = false;
    await fixture.mount(tester);
    for (var step = 0; step < 3; step++) {
      expect(find.text(onboardingThaiTitles[step]), findsOneWidget);
      expect(find.text(onboardingThaiDescriptions[step]), findsOneWidget);
      expect(find.text(step == 2 ? 'เริ่มใช้งาน' : 'ถัดไป'), findsOneWidget);
      await nextOnboardingEnglish(tester);
    }
    expect(fixture.finished, 1);
    await fixture.close(tester);
  });

  testWidgets('a supported non-Thai locale uses the English onboarding copy',
      (tester) async {
    final fixture = OnboardingEnglishFixture(locale: const Locale('vi'));
    await fixture.mount(tester);
    expect(find.text(onboardingEnglishTitles[0]), findsOneWidget);
    expect(find.text(onboardingEnglishDescriptions[0]), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    await fixture.close(tester);
  });

  for (final scale in [2.0, 3.0]) {
    for (final dark in [false, true]) {
      testWidgets(
          'all English steps are readable at 320dp ${scale}x '
          '${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = OnboardingEnglishFixture(dark: dark, scale: scale);
        await fixture.mount(tester);
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('onboarding-content')),
          matching: find.byType(Scrollable),
        );
        for (var step = 0; step < 3; step++) {
          expect(tester.takeException(), isNull);
          final title = find.text(onboardingEnglishTitles[step]);
          final description = find.text(onboardingEnglishDescriptions[step]);
          await revealOnboardingEnglish(tester, title);
          expectOnboardingEnglishReadable(tester, title);
          await revealOnboardingEnglish(tester, description);
          expectOnboardingEnglishReadable(tester, description);
          final position = tester.state<ScrollableState>(scroll).position;
          expect(position.maxScrollExtent, greaterThan(0));
          await tester.drag(scroll, const Offset(0, -170));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          expect(tester.takeException(), isNull);
          final next = find.byKey(const ValueKey('onboarding-next'));
          expectOnboardingEnglishAction(tester, next);
          expectOnboardingEnglishReadable(
              tester, find.text(step == 2 ? 'Get started' : 'Next'));
          expectOnboardingEnglishAction(
              tester, find.byKey(const ValueKey('onboarding-skip')));
          final language = find.byKey(const ValueKey('onboarding-language'));
          expectOnboardingEnglishAction(tester, language);
          expectOnboardingEnglishReadable(tester, find.text('Skip'));
          expectOnboardingEnglishReadable(tester, find.text('English'));
          if (step > 0) {
            expectOnboardingEnglishAction(
                tester, find.byKey(const ValueKey('onboarding-back')));
          }
          if (step == 0) {
            await tester.tap(language);
            await tester.pumpAndSettle();
            for (final label in ['ไทย', 'English']) {
              final item = find.descendant(
                of: find.byType(PopupMenuItem<Locale>),
                matching: find.text(label),
              );
              expectOnboardingEnglishReadable(tester, item);
              final action = find.ancestor(
                of: item,
                matching: find.byType(PopupMenuItem<Locale>),
              );
              expectOnboardingEnglishAction(tester, action);
            }
            await tester.tap(find.text('ไทย'));
            await tester.pumpAndSettle();
            expect(find.text(onboardingThaiTitles[0]), findsOneWidget);
            await tester.tap(language);
            await tester.pumpAndSettle();
            await tester.tap(find.text('English'));
            await tester.pumpAndSettle();
          }
          await fixture.capture(tester,
              'step-${step + 1}-en-${scale.toInt()}x-${dark ? 'dark' : 'light'}');
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
        expect(fixture.finished, 1);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      });
    }
  }
}
