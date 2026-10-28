import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uploader_caption_english_test.dart';

const _sharedField = 'uploader-caption-field';

RealClipCaptionResult _result({
  String caption = 'ข้อความ AI ที่ไม่ต้องแปล',
  Map<String, CaptionResult> platforms = const {},
  bool fallback = false,
  bool charged = true,
  int used = 1,
  List<String> keywords = const ['คำค้นลูกค้า'],
}) {
  final base = captionEnglishResult();
  return RealClipCaptionResult(
    caption: caption,
    captionOptions: const [],
    hooks: const [],
    hashtags: const ['#สินค้า'],
    seoKeywords: keywords,
    searchTitle: base.searchTitle,
    source: base.source,
    isFallback: fallback,
    platformCaptions: platforms,
    quota: RealClipCaptionQuota(
        limit: 120, usedThisMonth: used, remainingThisMonth: 120 - used,
        charged: charged),
  );
}

Future<void> _mount(WidgetTester tester, CaptionEnglishFixture fixture) async {
  addTearDown(fixture.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await fixture.mount(tester);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await revealCaptionEnglishControl(tester, finder);
  await tester.enterText(finder, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<String> _value(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await revealCaptionEnglishControl(tester, finder);
  return tester.widget<TextField>(finder).controller!.text;
}

Future<void> _label(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await revealCaptionEnglishControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _advanced(WidgetTester tester, List<String> targets) async {
  await tapCaptionEnglishControl(tester, 'uploader-platform-captions-toggle');
  for (final platform in targets) {
    await tapCaptionEnglishControl(tester, 'ai-caption-target-$platform');
  }
}

Future<void> _style(WidgetTester tester, {bool advanced = false}) async {
  if (!advanced) {
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
  }
  await tapCaptionEnglishControl(tester, 'uploader-ai-style-button');
}

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

  testWidgets('advanced mode retains shared and four independent raw drafts',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _type(tester, _sharedField, '  แคปชันจากลูกค้า  ');
    await _advanced(tester, const []);
    expect(await _value(tester, 'uploader-caption-TIKTOK'),
        '  แคปชันจากลูกค้า  ');
    await _type(tester, 'uploader-caption-TIKTOK', 'ข้อความ TikTok ของลูกค้า');
    await _type(tester, 'uploader-caption-YOUTUBE_SHORTS', 'คำอธิบายลูกค้า');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-platform-captions-toggle');
    expect(await _value(tester, _sharedField), '  แคปชันจากลูกค้า  ');
    await _advanced(tester, const []);
    expect(await _value(tester, 'uploader-caption-TIKTOK'),
        'ข้อความ TikTok ของลูกค้า');
    expect(await _value(tester, 'uploader-caption-YOUTUBE_SHORTS'),
        'คำอธิบายลูกค้า');
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inserting a raw template appends once without spending AI credits',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    fixture.templates.add(TextTemplateResult(id: 'merchant-template',
        title: 'ตั้งค่าขั้นสูง', body: 'เทมเพลตของลูกค้า',
        createdAt: DateTime.utc(2026, 10, 29)));
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ข้อความเดิม  ');
    await tapCaptionEnglishControl(tester, 'uploader-templates-panel');
    await _label(tester, 'Load templates');
    expect(find.text('ตั้งค่าขั้นสูง'), findsOneWidget);
    expect(find.text('เทมเพลตของลูกค้า'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await _label(tester, 'Insert caption');
    expect(await _value(tester, _sharedField),
        'ข้อความเดิม\n\nเทมเพลตของลูกค้า');
    expect(fixture.templateReads, 1);
    expect(fixture.templates.single.title, 'ตั้งค่าขั้นสูง');
    expect(fixture.requests, isEmpty);
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown template error remains raw and retry keeps manual text',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..templateError = const ApiException('ต้นทาง templates: opaque error');
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ข้อความที่ต้องเก็บ');
    await tapCaptionEnglishControl(tester, 'uploader-templates-panel');
    await _label(tester, 'Load templates');
    expect(find.text('ต้นทาง templates: opaque error'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('ต้นทาง templates: opaque error'), findsOneWidget);
    fixture.templateError = null;
    fixture.templates.add(TextTemplateResult(id: 'later-template', title: 'ของใหม่',
        body: 'ข้อความที่ยังไม่เลือก', createdAt: DateTime.utc(2026, 10, 29)));
    await _label(tester, 'Load templates');
    expect(await _value(tester, _sharedField), 'ข้อความที่ต้องเก็บ');
    expect(fixture.templateReads, 2);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared AI keeps Thai output guidance keywords and style payload',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    fixture.styles.profile = const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.friendly,
            examples: ['ตัวอย่างข้อความของลูกค้า']));
    fixture.result = _result(caption: 'ตั้งค่าขั้นสูง', keywords: ['แคปชั่น', 'ร้าน']);
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
    await _type(tester, 'uploader-ai-guidance-field', '  ขายแบบจริงใจ  ');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(await _value(tester, _sharedField), 'ตั้งค่าขั้นสูง\n\n#สินค้า');
    final request = fixture.requests.single;
    expect(request.guidance, 'ขายแบบจริงใจ');
    expect(request.expectedCredits, 1);
    expect(request.platforms, isEmpty);
    expect(request.writingStyle!.toJson(), fixture.styles.profile.style.toJson());
    expect(request.toJson().containsKey('locale'), isFalse);
    await tapCaptionEnglishControl(tester, 'uploader-ai-seo-keywords');
    expect(find.text('แคปชั่น, ร้าน'), findsOneWidget);
    expect(fixture.uploadRequests, hasLength(1));
    expect(fixture.uploadedFiles, hasLength(1));
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared uncharged fallback retains review and a truthful notice',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = _result(fallback: true, charged: false, used: 0);
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(await _value(tester, _sharedField), 'ข้อความ AI ที่ไม่ต้องแปล\n\n#สินค้า');
    final notice = find.byKey(const ValueKey('uploader-ai-caption-fallback'));
    await revealCaptionEnglishControl(tester, notice);
    final text = tester.widget<Text>(
        find.descendant(of: notice, matching: find.byType(Text))).data!;
    expect(text, contains('fallback'));
    expect(text, contains('No AI quota charged'));
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
    expect(fixture.styles.saves, isEmpty);
    expect(fixture.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling an advanced preview keeps manual captions and usage',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = _result(used: 1, platforms: const {
        'TIKTOK': CaptionResult(caption: 'ข้อความใหม่', hashtags: ['#ใหม่'])});
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ต้นฉบับของลูกค้า');
    await _advanced(tester, const ['TIKTOK']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    expect(find.text('ข้อความใหม่\n\n#ใหม่'), findsOneWidget);
    Navigator.of(tester.element(
        find.byKey(const ValueKey('uploader-platform-ai-preview')))).pop(false);
    await tester.pumpAndSettle();
    expect(await _value(tester, 'uploader-caption-TIKTOK'), 'ต้นฉบับของลูกค้า');
    await revealCaptionEnglishControl(tester,
        find.byKey(const ValueKey('uploader-ai-caption-quota-progress')));
    expect(tester.widget<LinearProgressIndicator>(find.byKey(
        const ValueKey('uploader-ai-caption-quota-progress'))).value, 119 / 120);
    expect(fixture.requests.single.platforms, ['TIKTOK']);
    expect(fixture.requests.single.expectedCredits, 1);
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subset Apply and Undo preserve unrelated platform edits',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = _result(platforms: const {
        'TIKTOK': CaptionResult(caption: 'จาก AI', hashtags: [])});
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ต้นฉบับ');
    await _advanced(tester, const ['TIKTOK']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    await tapCaptionEnglishControl(tester, 'uploader-platform-ai-apply');
    expect(await _value(tester, 'uploader-caption-TIKTOK'), 'จาก AI');
    await _type(tester, 'uploader-caption-YOUTUBE_SHORTS', 'แก้เองภายหลัง');
    await tapCaptionEnglishControl(tester, 'uploader-platform-ai-undo');
    expect(await _value(tester, 'uploader-caption-TIKTOK'), 'ต้นฉบับ');
    expect(await _value(tester, 'uploader-caption-YOUTUBE_SHORTS'), 'แก้เองภายหลัง');
    expect(find.byKey(const ValueKey('uploader-platform-ai-undo')), findsNothing);
    expect(fixture.requests, hasLength(1));
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete advanced result cannot replace selected drafts',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = _result(used: 2, platforms: const {
        'TIKTOK': CaptionResult(caption: 'คำตอบที่ยังไม่ครบ', hashtags: [])});
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'แคปชันเดิม');
    await _advanced(tester, const ['TIKTOK', 'YOUTUBE_SHORTS']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')), findsNothing);
    expect(await _value(tester, 'uploader-caption-TIKTOK'), 'แคปชันเดิม');
    expect(await _value(tester, 'uploader-caption-YOUTUBE_SHORTS'), 'แคปชันเดิม');
    expect(fixture.requests.single.expectedCredits, 2);
    expect(fixture.requests.single.platforms, ['TIKTOK', 'YOUTUBE_SHORTS']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced uncharged fallback applies only after confirmation',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = _result(fallback: true, charged: false, used: 0,
          platforms: const {
        'TIKTOK': CaptionResult(caption: 'ข้อความสำรองของผู้ให้บริการ', hashtags: [])});
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ข้อความของลูกค้า');
    await _advanced(tester, const ['TIKTOK']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(find.text('ข้อความสำรองของผู้ให้บริการ'), findsOneWidget);
    expect(find.textContaining('No AI quota charged'), findsOneWidget);
    await tapCaptionEnglishControl(tester, 'uploader-platform-ai-apply');
    expect(await _value(tester, 'uploader-caption-TIKTOK'),
        'ข้อความสำรองของผู้ให้บริการ');
    final notice = find.byKey(const ValueKey('uploader-ai-caption-fallback'));
    await revealCaptionEnglishControl(tester, notice);
    expect(tester.widget<Text>(
        find.descendant(of: notice, matching: find.byType(Text))).data,
        contains('No AI quota charged'));
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual edits during AI work win while the charged quota updates',
      (tester) async {
    final pending = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = pending.future;
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ข้อความก่อนรอ');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    await _type(tester, _sharedField, 'ลูกค้าแก้ระหว่างรอ');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    pending.complete(_result());
    await tester.pumpAndSettle();
    expect(await _value(tester, _sharedField), 'ลูกค้าแก้ระหว่างรอ');
    expect(fixture.requests, hasLength(1));
    expect(find.byKey(const ValueKey('uploader-ai-caption-ready')), findsNothing);
    await revealCaptionEnglishControl(tester,
        find.byKey(const ValueKey('uploader-ai-caption-quota-progress')));
    expect(tester.widget<LinearProgressIndicator>(find.byKey(
        const ValueKey('uploader-ai-caption-quota-progress'))).value, 119 / 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner replacement rejects a pending old AI result', (tester) async {
    final pending = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = pending.future;
    await _mount(tester, fixture);
    await _type(tester, _sharedField, 'ข้อความที่ยังไม่ส่ง');
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'caption-owner-b', idToken: 'new-token'));
    pending.complete(_result(caption: 'ผลของบัญชีเก่า'));
    await tester.pumpAndSettle();
    expect(await _value(tester, _sharedField), 'ข้อความที่ยังไม่ส่ง');
    expect(find.textContaining('ผลของบัญชีเก่า'), findsNothing);
    expect(fixture.requests, hasLength(1));
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late AI result cannot reopen a disposed caption route',
      (tester) async {
    final pending = Completer<RealClipCaptionResult>();
    final fixture = CaptionEnglishFixture()..aiGate = pending.future;
    await _mount(tester, fixture);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    pending.complete(_result());
    await tester.pumpAndSettle();
    expect(find.byType(UploaderScreen), findsNothing);
    expect(fixture.requests, hasLength(1));
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel discards style choices and advanced guidance without AI',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _advanced(tester, const []);
    await _style(tester, advanced: true);
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-tone-playful');
    await _type(tester, 'uploader-ai-guidance-field', 'คำแนะนำที่ยกเลิก');
    await _label(tester, 'Cancel');
    expect(fixture.styles.saves, isEmpty);
    await _style(tester, advanced: true);
    expect(await _value(tester, 'uploader-ai-guidance-field'), isEmpty);
    expect(tester.widget<ChoiceChip>(find.byKey(
        const ValueKey('uploader-ai-style-tone-auto'))).selected, isTrue);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('style Save retains enum IDs raw guidance and owner on generation',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    await _mount(tester, fixture);
    await _advanced(tester, const ['TIKTOK']);
    await _style(tester, advanced: true);
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-tone-friendly');
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-length-short');
    await _type(tester, 'uploader-ai-guidance-field', 'คำแนะนำเพิ่มเติม (ถ้ามี)');
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-save');
    expect(fixture.styles.saves.single.owner, captionEnglishOwner);
    expect(fixture.styles.profile.style.tone.value, 'friendly');
    expect(fixture.styles.profile.style.length.value, 'short');
    fixture.result = _result(platforms: const {
      'TIKTOK': CaptionResult(caption: 'ผลลัพธ์จำลอง', hashtags: [])});
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.guidance, 'คำแนะนำเพิ่มเติม (ถ้ามี)');
    expect(fixture.requests.single.writingStyle!.tone.value, 'friendly');
    expect(fixture.requests.single.writingStyle!.length.value, 'short');
    expect(tester.takeException(), isNull);
  });

  testWidgets('remember off keeps stored examples but excludes them from AI',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    fixture.styles.profile = const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(examples: ['ข้อความตัวอย่างเดิม']));
    await _mount(tester, fixture);
    await _style(tester);
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-remember');
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-save');
    expect(fixture.styles.profile.rememberEdits, isFalse);
    expect(fixture.styles.profile.style.examples, ['ข้อความตัวอย่างเดิม']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests.single.writingStyle!.examples, isEmpty);
    expect(fixture.styles.profile.style.examples, ['ข้อความตัวอย่างเดิม']);
    expect(fixture.styles.saves, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear remembered examples keeps manual style and spends nothing',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    fixture.styles.profile = const CaptionWritingStyleProfile(
        style: CaptionWritingStyle(tone: CaptionWritingTone.softSell,
            length: CaptionWritingLength.short, examples: ['ตัวอย่างเก่า']));
    await _mount(tester, fixture);
    await _style(tester);
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-clear');
    expect(fixture.styles.profile.style.examples, isEmpty);
    expect(fixture.styles.profile.style.tone.value, 'soft_sell');
    expect(fixture.styles.profile.style.length.value, 'short');
    expect(find.byKey(const ValueKey('uploader-ai-style-sheet')), findsOneWidget);
    expect(fixture.styles.saves, hasLength(1));
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed style save follows locale and can retry raw preferences',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..styles.saveError = const FileSystemException('fake local error');
    await _mount(tester, fixture);
    await _style(tester);
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-tone-direct_review');
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-save');
    expect(fixture.styles.saves, isEmpty);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('บันทึกสไตล์ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not save your style. Please try again.'), findsOneWidget);
    fixture.styles.saveError = null;
    await tapCaptionEnglishControl(tester, 'uploader-ai-style-save');
    expect(fixture.styles.saveAttempts, 2);
    expect(fixture.styles.profile.style.tone.value, 'direct_review');
    expect(fixture.styles.saves, hasLength(1));
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three credits block four AI targets while manual fields stay usable',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..aiQuota = const CaptionQuotaResult(plan: 'PRO',
          quota: RealClipCaptionQuota(limit: 120, usedThisMonth: 117,
              remainingThisMonth: 3));
    await _mount(tester, fixture);
    await _advanced(tester,
        const ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS']);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    await _type(tester, 'uploader-caption-TIKTOK', 'ยังเขียนเองได้ตามเดิม');
    expect(await _value(tester, 'uploader-caption-TIKTOK'), 'ยังเขียนเองได้ตามเดิม');
    expect(fixture.styles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
