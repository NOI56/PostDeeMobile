import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/cover_editor_screen.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
// Uses the same native seam as the accepted preview test fake.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'post_video_preview_english_test.dart'
    show PreviewEnglishPlatform, expectPreviewEnglishReadable;

class CoverEnglishPlatform extends PreviewEnglishPlatform {
  CoverEnglishPlatform() {
    duration = const Duration(seconds: 20);
  }
}

class CoverEnglishResult extends CoverEditorResult {
  CoverEnglishResult(
      {required super.design,
      super.durationMs,
      super.localImagePath = 'fake-cover-result.png',
      super.sizeBytes = 32});
  int cleanups = 0;
  @override
  Future<void> cleanupTemporaryFiles() async {
    cleanups++;
  }
}

class CoverEnglishFixture {
  CoverEnglishFixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = ValueNotifier(locale);
  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final native = CoverEnglishPlatform();
  final requests = <CoverImageRequest>[];
  final savedResults = <CoverEditorResult>[];
  final routeResults = <CoverEditorResult?>[];
  String videoName = 'คลิปภาพปกของลูกค้า.mp4';
  File video = File('fake-cover-video.mp4');
  List<SocialPlatform> platforms = const [
    SocialPlatform.tiktok,
    SocialPlatform.youtubeShorts,
    SocialPlatform.instagramReels,
    SocialPlatform.facebookReels
  ];
  CoverEditorResult? initialResult;
  double? probeSeconds = 20;
  int probeReads = 0;
  Future<double?>? probeGate;
  Object? processError;
  Future<CoverEditorResult>? processGate;
  Future<CoverEditorResult> Function(CoverImageRequest)? processor;
  CoverEnglishResult? lastResult;
  bool bareMaterialApp = false;

  CoverEditorScreen screen() => CoverEditorScreen(
      videoFile: video,
      videoName: videoName,
      platforms: platforms,
      initialResult: initialResult,
      probeDuration: (_) async {
        probeReads++;
        return probeGate == null ? probeSeconds : await probeGate!;
      },
      processCover: (request) async {
        requests.add(request);
        if (processor != null) return processor!(request);
        if (processError != null) throw processError!;
        if (processGate != null) return await processGate!;
        return lastResult = CoverEnglishResult(
            design: request.design, durationMs: request.durationMs);
      },
      onSaved: savedResults.add);

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: [
              if (!bareMaterialApp) PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        key: const ValueKey('cover-english-open'),
                        onPressed: () async {
                          final result = await Navigator.of(context)
                              .push<CoverEditorResult>(
                                  MaterialPageRoute(builder: (_) => screen()));
                          routeResults.add(result);
                        },
                        child: const Text('Open cover fixture')))));
      });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    // Store the platform interface through the same public test seam as preview.
    _savedPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = native;
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('cover-english-open')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  VideoPlayerPlatform? _savedPlatform;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  void dispose() {
    if (_savedPlatform != null) VideoPlayerPlatform.instance = _savedPlatform!;
    language.dispose();
  }
}

Finder get coverEnglishScroll => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Future<void> revealCoverEnglish(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(coverEnglishScroll).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 180,
        scrollable: coverEnglishScroll);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> tapCoverEnglish(WidgetTester tester, String key,
    {bool settle = true}) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final finder = find.byKey(ValueKey(key));
  await revealCoverEnglish(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> loadCoverEnglishFonts() async {
  for (final family in ['Anuphan', 'Prompt']) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle
          .load('assets/fonts/${family.toLowerCase()}/$family-$weight.ttf'));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(loadCoverEnglishFonts);
  Future<CoverEnglishFixture> mount(WidgetTester tester,
      [CoverEnglishFixture? value]) async {
    final fixture = value ?? CoverEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    return fixture;
  }

  testWidgets(
      'English cover page explains frame selection without changing media',
      (tester) async {
    final fixture = CoverEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Edit cover'), findsOneWidget);
    expect(find.text('Choose a cover frame'), findsOneWidget);
    await revealCoverEnglish(
        tester, find.byKey(const ValueKey('cover-frame-instruction')));
    expect(find.text('Choose a frame from your video'), findsOneWidget);
    expect(
        find.text(
            'Move the slider to preview a frame, then use it as your cover.'),
        findsOneWidget);
    expect(fixture.requests, isEmpty);
    expect(fixture.native.sources, hasLength(1));
  });

  testWidgets('English cover text label retains customer input across locale',
      (tester) async {
    final fixture = CoverEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    final field = find.byKey(const ValueKey('cover-text-field'));
    await revealCoverEnglish(tester, field);
    expect(find.text('Cover text (optional)'), findsOneWidget);
    final controller = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, 'ข้อความลูกค้าภาษาไทย');
    fixture.language.value = const Locale('th');
    await tester.pump();
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(identical(tester.widget<TextField>(field).controller, controller),
        isTrue);
    expect(controller.text, 'ข้อความลูกค้าภาษาไทย');
    expect(fixture.native.sources, hasLength(1));
    expect(fixture.requests, isEmpty);
  });

  testWidgets('English cover style choices identify their unchanged values',
      (tester) async {
    final fixture = CoverEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    await revealCoverEnglish(tester, find.text('Font'));
    expect(find.text('Font'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Anuphan'), findsOneWidget);
    await revealCoverEnglish(tester, find.text('Weight and size'));
    expect(find.text('Weight and size'), findsOneWidget);
    expect(find.text('Semi-bold'), findsOneWidget);
    expect(find.text('Use this cover'), findsOneWidget);
    expect(fixture.requests, isEmpty);
  });

  testWidgets('export preserves styling, colors and the safe final frame',
      (tester) async {
    final fixture = await mount(
        tester,
        CoverEnglishFixture()
          ..initialResult = CoverEnglishResult(
              design: const CoverDesign(coverFrameTimeMs: 20000)));
    final frame = find.byKey(const ValueKey('cover-frame-slider'));
    await revealCoverEnglish(tester, frame);
    expect(tester.widget<Slider>(frame).max, 19900);
    expect(tester.widget<Slider>(frame).value, 19900);
    final field = find.byKey(const ValueKey('cover-text-field'));
    await revealCoverEnglish(tester, field);
    await tester.enterText(field, '  ข้อความปกลูกค้า  ');
    for (final key in [
      'cover-font-anuphan',
      'cover-weight-700',
      'cover-size-64',
      'cover-text-color-2',
      'cover-background-color-2',
      'cover-position-bottom'
    ]) {
      await tapCoverEnglish(tester, key);
    }
    await tapCoverEnglish(tester, 'cover-save-button');
    final request = fixture.requests.single;
    expect(request.fileName, fixture.videoName);
    expect(request.videoFile.path, fixture.video.path);
    expect(request.durationMs, 20000);
    expect(request.sourceKind, CoverSourceKind.videoFrame);
    expect(request.sourceImageFile, isNull);
    expect(request.design.text, 'ข้อความปกลูกค้า');
    expect(request.design.coverFrameTimeMs, 19900);
    expect(request.design.fontFamily, CoverFontFamily.anuphan);
    expect(request.design.fontWeight, 700);
    expect(request.design.fontSize, 64);
    expect(request.design.textColor, const Color(0xFFFFEB3B));
    expect(request.design.backgroundColor, const Color(0xD900A77A));
    expect(request.design.dx, .5);
    expect(request.design.dy, .78);
    expect(fixture.savedResults.single, same(fixture.routeResults.single));
    expect(fixture.native.sources, hasLength(1));
    expect(fixture.native.played, isEmpty);
  });

  testWidgets('existing custom design values survive locale changes and save',
      (tester) async {
    const design = CoverDesign(
        coverFrameTimeMs: 4200,
        text: 'ข้อความเดิม',
        fontFamily: CoverFontFamily.anuphan,
        fontWeight: 600,
        fontSize: 40,
        textColor: Color(0xFF123456),
        backgroundColor: Color(0x88112233),
        dx: .33,
        dy: .66);
    final fixture = await mount(
        tester,
        CoverEnglishFixture()
          ..initialResult = CoverEnglishResult(design: design));
    fixture.language.value = const Locale('th');
    await tester.pump();
    fixture.language.value = const Locale('en');
    await tester.pump();
    await tapCoverEnglish(tester, 'cover-save-button');
    final saved = fixture.requests.single.design;
    expect(saved.text, design.text);
    expect(saved.coverFrameTimeMs, 4200);
    expect(saved.fontFamily, design.fontFamily);
    expect(saved.fontWeight, 600);
    expect(saved.fontSize, 40);
    expect(saved.textColor, design.textColor);
    expect(saved.backgroundColor, design.backgroundColor);
    expect(saved.dx, .33);
    expect(saved.dy, .66);
    expect(fixture.native.seeks, contains(const Duration(milliseconds: 4200)));
  });

  testWidgets('actual drag changes only normalized customer-text placement',
      (tester) async {
    final fixture = await mount(
        tester,
        CoverEnglishFixture()
          ..initialResult = CoverEnglishResult(
              design: const CoverDesign(text: 'ข้อความลากได้')));
    final overlay = find.byKey(const ValueKey('cover-draggable-text'));
    await revealCoverEnglish(tester, overlay);
    expect(overlay.hitTestable(), findsOneWidget);
    final drag = await tester.startGesture(tester.getCenter(overlay));
    await drag.moveBy(const Offset(60, 0));
    await tester.pump();
    await drag.moveBy(const Offset(20, 30));
    await drag.up();
    await tester.pump();
    await tapCoverEnglish(tester, 'cover-save-button');
    final design = fixture.requests.single.design;
    expect(design.text, 'ข้อความลากได้');
    expect(design.dx, greaterThan(.5));
    expect(design.dy, greaterThan(.22));
    expect(design.dx, inInclusiveRange(.1, .9));
    expect(design.dy, inInclusiveRange(.1, .9));
    expect(design.fontFamily, CoverFontFamily.prompt);
    expect(design.fontSize, 52);
  });

  testWidgets('live locale preserves actual selected font, weight and position',
      (tester) async {
    final fixture = await mount(tester);
    const keys = [
      'cover-font-anuphan',
      'cover-weight-900',
      'cover-size-40',
      'cover-position-center'
    ];
    for (final key in keys) {
      await tapCoverEnglish(tester, key);
    }
    fixture.language.value = const Locale('th');
    await tester.pump();
    fixture.language.value = const Locale('en');
    await tester.pump();
    for (final key in keys) {
      final chip = find.byKey(ValueKey(key));
      await revealCoverEnglish(tester, chip);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    }
    expect(find.text('Center'), findsOneWidget);
    expect(fixture.native.sources, hasLength(1));
    expect(fixture.probeReads, 1);
    expect(fixture.requests, isEmpty);
  });

  testWidgets('unavailable motion preview still allows a timed cover export',
      (tester) async {
    final value = CoverEnglishFixture();
    value.native.failFirstInitialization = true;
    final fixture = await mount(tester, value);
    final message = find.text(
        'Video preview is unavailable. You can still choose a time and create a cover.');
    await revealCoverEnglish(tester, message);
    expect(message, findsOneWidget);
    final frame = find.byKey(const ValueKey('cover-frame-slider'));
    await revealCoverEnglish(tester, frame);
    final slider = tester.widget<Slider>(frame);
    expect(slider.max, 19900);
    slider.onChanged!(14500);
    slider.onChangeEnd!(14500);
    await tester.pump();
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests.single.design.coverFrameTimeMs, 14500);
    expect(fixture.requests.single.durationMs, 20000);
    expect(fixture.savedResults, hasLength(1));
    expect(fixture.native.played, isEmpty);
  });

  testWidgets(
      'editing during native initialization does not create another player',
      (tester) async {
    final pending = Completer<void>();
    final value = CoverEnglishFixture();
    value.native.firstCreationGate = pending;
    final fixture = await mount(tester, value);
    final field = find.byKey(const ValueKey('cover-text-field'));
    await revealCoverEnglish(tester, field);
    await tester.enterText(field, 'ข้อความระหว่างโหลด');
    fixture.language.value = const Locale('th');
    await tester.pump();
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(
        tester.widget<TextField>(field).controller!.text, 'ข้อความระหว่างโหลด');
    expect(fixture.native.sources, hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(fixture.native.sources, hasLength(1));
    expect(fixture.requests, isEmpty);
  });

  testWidgets('text limit and raw customer words remain unchanged',
      (tester) async {
    final fixture = await mount(tester);
    final field = find.byKey(const ValueKey('cover-text-field'));
    await revealCoverEnglish(tester, field);
    await tester.enterText(field, 'ก' * 49);
    expect(tester.widget<TextField>(field).controller!.text, 'ก' * 48);
    await tester.enterText(field, 'ฟอนต์');
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests.single.design.text, 'ฟอนต์');
    expect(fixture.requests.single.fileName, 'คลิปภาพปกของลูกค้า.mp4');
  });

  testWidgets('plain MaterialApp preserves original Thai cover presentation',
      (tester) async {
    final fixture =
        await mount(tester, CoverEnglishFixture()..bareMaterialApp = true);
    expect(find.text('แต่งหน้าปก'), findsOneWidget);
    expect(find.text('ใช้หน้าปกนี้'), findsOneWidget);
    await revealCoverEnglish(tester, find.text('ฟอนต์'));
    expect(find.text('ฟอนต์'), findsOneWidget);
    expect(find.text('Edit cover'), findsNothing);
    expect(fixture.requests, isEmpty);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'narrow real-font 2x controls and saving states are readable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final pending = Completer<CoverEditorResult>();
      final fixture = await mount(
          tester,
          CoverEnglishFixture(dark: dark, scale: 2)
            ..processGate = pending.future);
      expectPreviewEnglishReadable(tester, find.text('Edit cover'));
      for (final value in [
        'Choose a cover frame',
        'Choose a frame from your video',
        'Move the slider to preview a frame, then use it as your cover.'
      ]) {
        final text = find.text(value);
        await revealCoverEnglish(tester, text);
        expectPreviewEnglishReadable(tester, text);
      }
      final frame = find.byKey(const ValueKey('cover-frame-slider'));
      await revealCoverEnglish(tester, frame);
      expect(frame.hitTestable(), findsOneWidget);
      await tester.drag(frame, const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 120));
      expect(fixture.native.seeks.last, greaterThan(Duration.zero));
      final field = find.byKey(const ValueKey('cover-text-field'));
      await revealCoverEnglish(tester, field);
      expectPreviewEnglishReadable(tester, find.text('Cover text (optional)'));
      await tester.showKeyboard(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.enterText(field, 'ข้อความปกภาษาไทย');
      await tester.pump();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(tester.getSemantics(field).label,
            contains('Cover text (optional)'));
      } finally {
        semantics.dispose();
      }
      final editable = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)));
      final position =
          TextPosition(offset: editable.widget.controller.text.length);
      editable.bringIntoView(position);
      await tester.pump();
      final caret = editable.renderEditable
          .getLocalRectForCaret(position)
          .shift(editable.renderEditable.localToGlobal(Offset.zero));
      final viewport = tester.getRect(find.byType(ListView));
      expect(caret.top, greaterThanOrEqualTo(viewport.top - .5));
      expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + .5));
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      for (final key in [
        'cover-font-anuphan',
        'cover-weight-900',
        'cover-size-64',
        'cover-position-bottom'
      ]) {
        await tapCoverEnglish(tester, key);
        expectPreviewEnglishReadable(
            tester,
            find.descendant(
                of: find.byKey(ValueKey(key)), matching: find.byType(Text)));
      }
      final capability =
          find.byKey(const ValueKey('cover-platform-capability-notice'));
      await revealCoverEnglish(tester, capability);
      for (final element in find
          .descendant(of: capability, matching: find.byType(Text))
          .evaluate()
          .toList()) {
        final finder = find.byWidget(element.widget);
        await revealCoverEnglish(tester, finder);
        expectPreviewEnglishReadable(tester, finder);
      }
      expectPreviewEnglishReadable(tester, find.text('Use this cover'));
      await tapCoverEnglish(tester, 'cover-save-button', settle: false);
      expectPreviewEnglishReadable(tester, find.text('Creating cover...'));
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('cover-save-button')))
              .onPressed,
          isNull);
      pending.completeError(StateError('fake processor failure'));
      await tester.pumpAndSettle();
      final error = find.text('Could not create the cover. Try again.');
      await revealCoverEnglish(tester, error);
      expectPreviewEnglishReadable(tester, error);
      expect(fixture.requests, hasLength(1));
      expect(fixture.savedResults, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
