import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';

import 'cover_editor_english_test.dart'
    show
        CoverEnglishFixture,
        CoverEnglishResult,
        loadCoverEnglishFonts,
        revealCoverEnglish,
        tapCoverEnglish;

class _FlowFixture extends CoverEnglishFixture {
  _FlowFixture({super.locale});
  final gates = <Completer<CoverEditorResult>>[];

  Completer<CoverEditorResult> pending() {
    final gate = Completer<CoverEditorResult>();
    gates.add(gate);
    processGate = gate.future;
    return gate;
  }

  Future<void> cleanup(WidgetTester tester) async {
    await close(tester);
    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete(CoverEnglishResult(design: const CoverDesign()));
      }
    }
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

_FlowFixture _fixture(WidgetTester tester,
    {Locale locale = const Locale('en')}) {
  final fixture = _FlowFixture(locale: locale);
  addTearDown(fixture.dispose);
  addTearDown(() => fixture.cleanup(tester));
  return fixture;
}

Future<void> _error(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await revealCoverEnglish(tester, finder);
  expect(finder, findsOneWidget);
}

Future<void> _type(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('cover-text-field'));
  await revealCoverEnglish(tester, field);
  await tester.enterText(field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

void main() {
  setUpAll(loadCoverEnglishFonts);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets(
      'pending cover creation follows locale and ignores rapid duplicate saves',
      (tester) async {
    final fixture = _fixture(tester);
    final gate = fixture.pending();
    await fixture.mount(tester);
    await _type(tester, 'ข้อความลูกค้า');
    final save = find.byKey(const ValueKey('cover-save-button'));
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Creating cover...'), findsOneWidget);
    expect(fixture.requests, hasLength(1));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final probes = fixture.probeReads;
    fixture.language.value = const Locale('th');
    await tester.pump();
    expect(find.text('กำลังสร้างหน้าปก...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(find.text('Creating cover...'), findsOneWidget);
    expect(fixture.requests, hasLength(1));
    expect(fixture.probeReads, probes);
    expect(fixture.native.sources, hasLength(1));
    final result = CoverEnglishResult(
        design: fixture.requests.single.design,
        durationMs: fixture.requests.single.durationMs);
    gate.complete(result);
    await tester.pumpAndSettle();
    expect(fixture.savedResults.single, same(result));
    expect(fixture.routeResults.single, same(result));
    expect(result.cleanups, 0);
    expect(tester.takeException(), isNull);
  });

  for (final error in [
    (
      thai: 'ไม่พบไฟล์วิดีโอสำหรับสร้างหน้าปก',
      english: 'Video file not found. Choose your video again.'
    ),
    (
      thai: 'ไม่พบรูปหน้าปก กรุณาเลือกรูปใหม่',
      english: 'Cover image not found. Choose another image.'
    ),
    (
      thai: 'สร้างภาพหน้าปกไม่สำเร็จ กรุณาลองเลือกเฟรมหรือรูปใหม่',
      english:
          'Could not create the cover image. Choose another frame or image.'
    ),
  ]) {
    testWidgets(
        'known cover error follows locale without repeating export: ${error.thai}',
        (tester) async {
      final fixture = _fixture(tester, locale: const Locale('th'));
      fixture.processError = CoverImageException(error.thai);
      await fixture.mount(tester);
      await tapCoverEnglish(tester, 'cover-save-button');
      await _error(tester, error.thai);
      fixture.language.value = const Locale('en');
      await tester.pump();
      await _error(tester, error.english);
      expect(fixture.requests, hasLength(1));
      expect(fixture.savedResults, isEmpty);
      expect(fixture.routeResults, isEmpty);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('cover-save-button')))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'unknown cover provider message stays raw across language changes',
      (tester) async {
    final fixture = _fixture(tester);
    const message = 'ผู้ให้บริการทดสอบ: frame unavailable (E42)';
    fixture.processError = const CoverImageException(message);
    await fixture.mount(tester);
    await tapCoverEnglish(tester, 'cover-save-button');
    await _error(tester, message);
    fixture.language.value = const Locale('th');
    await tester.pump();
    await _error(tester, message);
    fixture.language.value = const Locale('en');
    await tester.pump();
    await _error(tester, message);
    expect(fixture.requests, hasLength(1));
    expect(fixture.savedResults, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'generic cover retry preserves raw text font styling and frame time',
      (tester) async {
    final fixture = _fixture(tester);
    fixture.processError = StateError('fake renderer unavailable');
    await fixture.mount(tester);
    await _type(tester, '  แต่งหน้าปก  ');
    final slider = find.byKey(const ValueKey('cover-frame-slider'));
    await revealCoverEnglish(tester, slider);
    tester.widget<Slider>(slider).onChangeEnd!(20000);
    await tester.pump();
    for (final key in [
      'cover-font-anuphan',
      'cover-weight-900',
      'cover-size-64',
      'cover-position-bottom'
    ]) {
      await tapCoverEnglish(tester, key);
    }
    await tapCoverEnglish(tester, 'cover-save-button');
    await _error(tester, 'Could not create the cover. Try again.');
    fixture.language.value = const Locale('th');
    await tester.pump();
    await _error(tester, 'สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    fixture.language.value = const Locale('en');
    await tester.pump();
    fixture.processError = null;
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests, hasLength(2));
    for (final request in fixture.requests) {
      expect(request.design.text, 'แต่งหน้าปก');
      expect(request.design.fontFamily, CoverFontFamily.anuphan);
      expect(request.design.fontWeight, 900);
      expect(request.design.fontSize, 64);
      expect(request.design.dy, .78);
      expect(request.design.coverFrameTimeMs, 19900);
      expect(request.durationMs, 20000);
      expect(request.sourceKind, CoverSourceKind.videoFrame);
      expect(request.sourceImageFile, isNull);
    }
    expect(fixture.savedResults.single, same(fixture.routeResults.single));
    expect((fixture.savedResults.single as CoverEnglishResult).cleanups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'back without saving leaves cover input unexported and returns null',
      (tester) async {
    final fixture = _fixture(tester);
    await fixture.mount(tester);
    await _type(tester, 'ไม่ต้องสร้างไฟล์นี้');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fixture.routeResults, [null]);
    expect(fixture.savedResults, isEmpty);
    expect(fixture.requests, isEmpty);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(fixture.native.disposeCounts, {1: 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'leaving during pending cover creation cleans its late result once',
      (tester) async {
    final fixture = _fixture(tester);
    final gate = fixture.pending();
    await fixture.mount(tester);
    await tapCoverEnglish(tester, 'cover-save-button', settle: false);
    expect(fixture.requests, hasLength(1));
    await tester.pageBack();
    await tester.pumpAndSettle();
    final result = CoverEnglishResult(design: fixture.requests.single.design);
    gate.complete(result);
    await tester.pump();
    expect(result.cleanups, 1);
    expect(fixture.savedResults, isEmpty);
    expect(fixture.routeResults, [null]);
    expect(fixture.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'successful English save returns the exact result and retains its files',
      (tester) async {
    final fixture = _fixture(tester);
    fixture.videoName = 'แต่งหน้าปก';
    final result = CoverEnglishResult(
        localImagePath: 'raw-output.jpg',
        design: const CoverDesign(
            text: 'แคปชันลูกค้า',
            fontFamily: CoverFontFamily.anuphan,
            coverFrameTimeMs: 3000),
        durationMs: 20000);
    fixture.processor = (_) async => result;
    await fixture.mount(tester);
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests.single.fileName, 'แต่งหน้าปก');
    expect(fixture.savedResults.single, same(result));
    expect(fixture.routeResults.single, same(result));
    expect(result.localImagePath, 'raw-output.jpg');
    expect(result.cleanups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English restored cover keeps the existing last-frame safety margin',
      (tester) async {
    final fixture = _fixture(tester);
    fixture.initialResult =
        CoverEnglishResult(design: const CoverDesign(coverFrameTimeMs: 20000));
    await fixture.mount(tester);
    final slider = find.byKey(const ValueKey('cover-frame-slider'));
    await revealCoverEnglish(tester, slider);
    expect(tester.widget<Slider>(slider).max, 19900);
    expect(tester.widget<Slider>(slider).value, 19900);
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests.single.design.coverFrameTimeMs, 19900);
    expect(fixture.requests.single.durationMs, 20000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English very short video never selects its exact end frame',
      (tester) async {
    final fixture = _fixture(tester);
    fixture.probeSeconds = .08;
    fixture.native.duration = const Duration(milliseconds: 80);
    await fixture.mount(tester);
    final slider = find.byKey(const ValueKey('cover-frame-slider'));
    await revealCoverEnglish(tester, slider);
    expect(tester.widget<Slider>(slider).max, 79);
    tester.widget<Slider>(slider).onChangeEnd!(80);
    await tester.pump();
    await tapCoverEnglish(tester, 'cover-save-button');
    expect(fixture.requests.single.design.coverFrameTimeMs, 79);
    expect(fixture.requests.single.durationMs, 80);
    expect(tester.takeException(), isNull);
  });
}
