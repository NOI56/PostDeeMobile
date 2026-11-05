import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_language.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/caption_language_picker.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_caption_english_test.dart';

const _languageKey = ValueKey('uploader-caption-language');
final _language = find.byKey(_languageKey);

Future<void> _mount(WidgetTester tester, CaptionEnglishFixture fixture,
    {Size size = const Size(430, 1000)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(fixture.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await fixture.mount(tester);
  final open = find.byKey(const ValueKey('uploader-ai-open-panel'));
  if (open.evaluate().isNotEmpty) {
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
  }
  await revealCaptionEnglishControl(tester, _language);
}

Future<void> _selectLanguage(WidgetTester tester, String name) async {
  await revealCaptionEnglishControl(tester, _language);
  await tester.tap(_language);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const ValueKey('caption-language-search')), name);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

String? _selectedLanguage(WidgetTester tester) =>
    tester.widget<CaptionLanguagePicker>(_language).value;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: captionEnglishOwner, idToken: 'fake-token'));
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  test('caption request omits automatic language and sends an explicit output',
      () {
    const automatic =
        GenerateRealClipCaptionRequest(audioS3Key: 'uploads/owner/clip.m4a');
    expect(automatic.captionLanguage, 'auto');
    expect(automatic.toJson().containsKey('captionLanguage'), isFalse);
    const translated = GenerateRealClipCaptionRequest(
        audioS3Key: 'uploads/owner/clip.m4a', captionLanguage: 'en');
    expect(translated.toJson()['captionLanguage'], 'en');
    expect(translated.toJson().containsKey('detectedSpokenLanguage'), isFalse);
    for (final code in captionOutputLanguages.keys) {
      final request = GenerateRealClipCaptionRequest(
          audioS3Key: 'uploads/owner/clip.m4a', captionLanguage: code);
      expect(request.toJson()['captionLanguage'], code);
    }
  });

  testWidgets('default language preserves automatic caption generation',
      (tester) async {
    final fixture = CaptionEnglishFixture(locale: const Locale('th'));
    await _mount(tester, fixture);
    expect(find.text('ภาษาแคปชั่น'), findsOneWidget);
    expect(find.text('อัตโนมัติ (ตามคลิป)'), findsOneWidget);
    expect(_selectedLanguage(tester), 'auto');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.captionLanguage, 'auto');
    expect(fixture.requests.single.appLanguage, 'th');
    expect(fixture.requests.single.toJson()['appLanguage'], 'th');
    expect(fixture.requests.single.toJson().containsKey('captionLanguage'),
        isFalse);
    expect(fixture.requests.single.platforms, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded output language reaches shared generation',
      (tester) async {
    final fixture = CaptionEnglishFixture(locale: const Locale('th'));
    await _mount(tester, fixture);
    await _selectLanguage(tester, captionOutputLanguages['ru']!);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.captionLanguage, 'ru');
    expect(fixture.requests.single.appLanguage, 'th');
    expect(fixture.requests.single.toJson()['captionLanguage'], 'ru');
    expect(fixture.requests.single.expectedCredits, 1);
    expect(fixture.requests.single.platforms, isEmpty);
    expect(fixture.uploadRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit language also reaches selected platform generation',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = captionEnglishResult(platformCaptions: const {
        'TIKTOK': CaptionResult(caption: 'แคปชั่นภาษาไทย', hashtags: []),
      });
    await _mount(tester, fixture);
    await _selectLanguage(tester, 'ไทย');
    await tapCaptionEnglishControl(tester, 'uploader-platform-captions-toggle');
    await tapCaptionEnglishControl(tester, 'ai-caption-target-TIKTOK');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.captionLanguage, 'th');
    expect(fixture.requests.single.appLanguage, 'en');
    expect(fixture.requests.single.platforms, ['TIKTOK']);
    expect(fixture.requests.single.expectedCredits, 1);
    final preview = find.byKey(const ValueKey('uploader-platform-ai-preview'));
    expect(preview, findsOneWidget);
    Navigator.of(tester.element(preview)).pop(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English labels and locale rebuild keep selected native language',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    expect(find.text('Caption language'), findsOneWidget);
    expect(find.text('Auto (match clip)'), findsOneWidget);
    await _selectLanguage(tester, 'ไทย');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, _language);
    expect(find.text('ภาษาแคปชั่น'), findsOneWidget);
    expect(_selectedLanguage(tester), 'th');
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, _language);
    expect(find.text('Caption language'), findsOneWidget);
    expect(_selectedLanguage(tester), 'th');
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Automatic sends the current UI language after a locale switch',
      (tester) async {
    final fixture = CaptionEnglishFixture(locale: const Locale('th'));
    await _mount(tester, fixture);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.captionLanguage, 'auto');
    expect(fixture.requests.single.appLanguage, 'en');
    expect(fixture.requests.single.toJson()['appLanguage'], 'en');
    expect(tester.takeException(), isNull);
  });

  testWidgets('language choice is disabled while caption request is pending',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = gate.future;
    await _mount(tester, fixture);
    await _selectLanguage(tester, 'English');
    final generate = find.byKey(const ValueKey('uploader-ai-generate-button'));
    await revealCaptionEnglishControl(tester, generate);
    await tester.tap(generate);
    for (var i = 0; i < 40 && fixture.requests.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(fixture.requests, hasLength(1));
    expect(tester.widget<CaptionLanguagePicker>(_language).onChanged, isNull);
    gate.complete(captionEnglishResult());
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, _language);
    expect(
        tester.widget<CaptionLanguagePicker>(_language).onChanged, isNotNull);
    expect(_selectedLanguage(tester), 'en');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'caption preview locks language until dismissed without overwrite',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, caption);
    await tester.enterText(caption, 'ข้อความเดิมที่ร้านต้องการเก็บ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _selectLanguage(tester, 'English');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(find.byKey(const ValueKey('uploader-shared-ai-preview')),
        findsOneWidget);
    final underlyingLanguage = find.byKey(_languageKey, skipOffstage: false);
    expect(tester.widget<CaptionLanguagePicker>(underlyingLanguage).onChanged,
        isNull);
    expect(
        tester.widget<CaptionLanguagePicker>(underlyingLanguage).value, 'en');
    final underlyingCaption = find
        .byKey(const ValueKey('uploader-caption-field'), skipOffstage: false);
    expect(tester.widget<TextField>(underlyingCaption).controller!.text,
        'ข้อความเดิมที่ร้านต้องการเก็บ');
    await tester.tap(find.byKey(const ValueKey('uploader-shared-ai-close')));
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, _language);
    expect(
        tester.widget<CaptionLanguagePicker>(_language).onChanged, isNotNull);
    expect(_selectedLanguage(tester), 'en');
    expect(tester.widget<TextField>(caption).controller!.text,
        'ข้อความเดิมที่ร้านต้องการเก็บ');
    expect(fixture.requests.single.captionLanguage, 'en');
    expect(tester.takeException(), isNull);
  });

  for (final language in [
    ('ja', 'ja'),
    ('ru', 'ru'),
    ('iw', 'he'),
    ('mni', 'mni-Mtei'),
  ]) {
    testWidgets('restored draft retains ${language.$1} as ${language.$2}',
        (tester) async {
      final fixture = CaptionEnglishFixture();
      final video = fixture.initialVideo!;
      fixture.store.drafts['language-draft'] = PublishDraft(
        version: publishDraftManifestVersion,
        id: 'language-draft',
        ownerUserId: captionEnglishOwner,
        submissionRequestId: 'submit_${List.filled(64, 'a').join()}',
        createdAt: DateTime.utc(2026, 11, 4),
        updatedAt: DateTime.utc(2026, 11, 4),
        videoPath: video.path,
        videoName: video.name,
        videoSizeBytes: video.sizeBytes,
        videoWidth: video.width,
        videoHeight: video.height,
        caption: 'ข้อความเดิม',
        aiGuidance: '',
        captionLanguage: language.$1,
        watermarkEnabled: false,
        platformApiValues: const {},
      );
      fixture.initialDraftId = 'language-draft';
      fixture.initialVideo = null;
      await _mount(tester, fixture);
      expect(_selectedLanguage(tester), language.$2);
      expect(find.text(captionOutputLanguages[language.$2]!), findsOneWidget);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'saving a draft retains language without replacing manual caption',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    final caption = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, caption);
    await tester.enterText(caption, 'ข้อความที่ร้านเขียนเอง');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _selectLanguage(tester, 'English');
    await tapCaptionEnglishControl(tester, 'uploader-save-draft-button');
    expect(fixture.store.savedRequests.last.captionLanguage, 'en');
    expect(fixture.store.savedRequests.last.caption, 'ข้อความที่ร้านเขียนเอง');
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing account resets the previous caption language',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _selectLanguage(tester, 'ไทย');
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'other-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, _language);
    expect(_selectedLanguage(tester), 'auto');
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open language sheet cannot write into a different account',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _selectLanguage(tester, 'English');
    await tester.tap(_language);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('caption-language-search')), 'Russian');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('caption-language-option-ru')),
        findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'other-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('caption-language-sheet')), findsNothing);
    await revealCaptionEnglishControl(tester, _language);
    expect(_selectedLanguage(tester), 'auto');
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'caption language fits a narrow ${dark ? 'dark' : 'light'} phone',
        (tester) async {
      final fixture = CaptionEnglishFixture(
          locale: const Locale('th'), dark: dark, scale: 1.2);
      await _mount(tester, fixture, size: const Size(360, 800));
      expect(_language.hitTestable(), findsOneWidget);
      await _selectLanguage(tester, 'English');
      expect(_selectedLanguage(tester), 'en');
      expect(tester.takeException(), isNull);
    });
  }
}
