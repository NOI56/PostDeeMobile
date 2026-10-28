import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/captions/caption_writing_style_store.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_video_english_test.dart'
    show
        VideoEnglishFixture,
        videoEnglishOwner,
        tapVideoEnglishControl,
        expectVideoEnglishReadable;

const captionEnglishOwner = videoEnglishOwner;

class CaptionEnglishStyleStore implements CaptionWritingStyleStore {
  final profiles = <String, CaptionWritingStyleProfile>{};
  CaptionWritingStyleProfile get profile =>
      profiles[captionEnglishOwner] ?? const CaptionWritingStyleProfile();
  set profile(CaptionWritingStyleProfile value) =>
      profiles[captionEnglishOwner] = value;
  final loads = <String>[];
  final saves = <({String owner, CaptionWritingStyleProfile profile})>[];
  Object? loadError;
  Object? saveError;
  Future<CaptionWritingStyleProfile>? loadGate;
  Future<void>? saveGate;
  int saveAttempts = 0;
  Future<CaptionWritingStyleProfile> Function(String)? onLoad;
  Future<void> Function(String, CaptionWritingStyleProfile)? onSave;

  @override
  Future<CaptionWritingStyleProfile> load(String owner) async {
    loads.add(owner);
    if (loadError != null) throw loadError!;
    if (onLoad != null) return onLoad!(owner);
    return loadGate == null
        ? profiles[owner] ?? const CaptionWritingStyleProfile()
        : await loadGate!;
  }

  @override
  Future<void> save(String owner, CaptionWritingStyleProfile value) async {
    saveAttempts++;
    if (saveGate != null) await saveGate!;
    if (saveError != null) throw saveError!;
    if (onSave != null) await onSave!(owner, value);
    saves.add((owner: owner, profile: value));
    profiles[owner] = value;
  }

  @override
  Future<void> clear(String owner) async {
    profiles.remove(owner);
  }
}

RealClipCaptionResult captionEnglishResult({
  String caption = 'แคปชันจากบริการจำลอง',
  bool fallback = false,
  List<String> hashtags = const ['#สินค้า'],
  List<String> keywords = const ['คำค้นลูกค้า'],
  Map<String, CaptionResult> platformCaptions = const {},
}) =>
    RealClipCaptionResult(
        caption: caption,
        isFallback: fallback,
        platformCaptions: platformCaptions,
        captionOptions: const [],
        hooks: const [],
        hashtags: hashtags,
        seoKeywords: keywords,
        searchTitle: 'หัวข้อจากบริการจำลอง',
        source: const RealClipCaptionSource(
            videoS3Key: 'uploads/$captionEnglishOwner/clip.mp4',
            mode: 'AUDIO_ONLY',
            selectedFrameCount: 0),
        quota: const RealClipCaptionQuota(
            limit: 120, usedThisMonth: 1, remainingThisMonth: 119));

class CaptionEnglishFixture extends VideoEnglishFixture {
  CaptionEnglishFixture(
      {super.locale, super.dark, super.scale, bool withVideo = true}) {
    if (withVideo) initialVideo = makeVideo('คลิปแคปชัน.mp4');
  }

  final styles = CaptionEnglishStyleStore();
  final templates = <TextTemplateResult>[];
  int templateReads = 0;
  int subscriptionReads = 0;
  Object? templateError;
  Object? aiError;
  Object? aiQuotaError;
  Future<List<TextTemplateResult>>? templateGate;
  Future<RealClipCaptionResult>? aiGate;
  Future<CaptionQuotaResult>? aiQuotaGate;
  Future<SubscriptionStatusResult>? subscriptionGate;
  Future<RealClipCaptionResult> Function(GenerateRealClipCaptionRequest)?
      generate;
  Future<List<TextTemplateResult>> Function()? templateRespond;
  CaptionQuotaResult aiQuota = const CaptionQuotaResult(
      plan: 'PRO',
      quota: RealClipCaptionQuota(
          limit: 120, usedThisMonth: 0, remainingThisMonth: 120));
  RealClipCaptionResult result = captionEnglishResult();
  final uploadRequests = <CreateUploadRequest>[];
  final uploadedFiles = <String>[];
  final requests = <GenerateRealClipCaptionRequest>[];

  @override
  UploaderScreen screen() => UploaderScreen(
      fullScreen: true,
      draftStore: store,
      enableRevenueCatBilling: false,
      captionWritingStyleStore: styles,
      initialDraftId: initialDraftId,
      initialVideoPath: initialVideo?.path,
      initialVideoName: initialVideo?.name,
      initialVideoSizeBytes: initialVideo?.sizeBytes,
      initialVideoWidth: initialVideo?.width,
      initialVideoHeight: initialVideo?.height,
      initialVideoDurationSeconds: initialVideo?.durationSeconds,
      pickVideo: () async {
        picks++;
        return picked;
      },
      readVideoMetadata: (path) async {
        metadataReads.add(path);
        return const VideoDimensions(
            width: 1080, height: 1920, durationSeconds: 10);
      },
      probePublishMedia: probeValidPublishMedia,
      loadTemplates: () async {
        templateReads++;
        if (templateError != null) throw templateError!;
        if (templateRespond != null) return templateRespond!();
        return templateGate == null ? List.of(templates) : await templateGate!;
      },
      loadSubscription: () async {
        subscriptionReads++;
        return subscriptionGate == null ? quota : await subscriptionGate!;
      },
      loadPostQuota: () async {
        quotaReads++;
        return quota;
      },
      loadCaptionQuota: () async {
        captionQuotaReads++;
        if (aiQuotaError != null) throw aiQuotaError!;
        return aiQuotaGate == null ? aiQuota : await aiQuotaGate!;
      },
      loadSocialConnections: () async {
        connectionReads++;
        return const [];
      },
      loadSocialPublishingReadiness: () async => const [],
      createUpload: (request) async {
        uploadRequests.add(request);
        return UploadResult(
            id: 'fake-upload-${uploadRequests.length}',
            videoS3Key: 'uploads/$captionEnglishOwner/clip.mp4',
            storageProvider: 'mock');
      },
      uploadVideoFile: (_, file) async {
        uploadedFiles.add(file.path);
      },
      extractFrames: (_, {maxFrames = 3}) async => const [],
      generateRealClipCaption: (request) async {
        requests.add(request);
        if (aiError != null) throw aiError!;
        if (generate != null) return generate!(request);
        return aiGate == null ? result : await aiGate!;
      },
      createPost: (_) async {
        apiWrites++;
        throw StateError('Unexpected publish');
      });

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await super.mount(tester, settle: settle);
    await tapVideoEnglishControl(tester, 'uploader-progress-1');
  }
}

Future<void> revealCaptionEnglishControl(
    WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(captionEnglishScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 140,
        scrollable: captionEnglishScroll);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tapCaptionEnglishControl(WidgetTester tester, String key) async {
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (key == 'uploader-platform-captions-toggle') {
    final tile = find.byKey(ValueKey(key));
    await revealCaptionEnglishControl(tester, tile);
    final previous = tester.widget<SwitchListTile>(tile).value;
    final control = find.descendant(of: tile, matching: find.byType(Switch));
    await Scrollable.ensureVisible(tester.element(control), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, !previous);
  } else {
    final control = find.byKey(ValueKey(key));
    await revealCaptionEnglishControl(tester, control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }
}

Finder get captionEnglishScroll => find.descendant(
    of: find.byKey(const ValueKey('uploader-scroll')),
    matching: find.byWidgetPredicate((widget) =>
        widget is Scrollable &&
        widget.axisDirection == AxisDirection.down &&
        widget.restorationId == null));

void expectCaptionEnglishReadable(WidgetTester tester, Finder finder) =>
    expectVideoEnglishReadable(tester, finder);

Future<void> typeCaptionEnglishWithKeyboard(
    WidgetTester tester, String key, String value,
    {bool inSheet = false}) async {
  final field = find.byKey(ValueKey(key));
  if (inSheet) {
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
  } else {
    await revealCaptionEnglishControl(tester, field);
  }
  await tester.showKeyboard(field);
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final editableFinder =
      find.descendant(of: field, matching: find.byType(EditableText));
  final state = tester.state<EditableTextState>(editableFinder);
  state.bringIntoView(TextPosition(offset: value.length));
  await tester.pumpAndSettle();
  final editable = state.renderEditable;
  final caret = editable
      .getLocalRectForCaret(TextPosition(offset: value.length))
      .shift(editable.localToGlobal(Offset.zero));
  expect(caret.top, greaterThanOrEqualTo(0));
  expect(caret.bottom, lessThanOrEqualTo(440));
  if (!inSheet) {
    final viewport = tester.getRect(captionEnglishScroll);
    expect(caret.top, greaterThanOrEqualTo(viewport.top - 0.5));
    expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
    final actions =
        find.byKey(const ValueKey('uploader-caption-actions-scroll'));
    expect(actions, findsOneWidget);
    await tester.drag(actions, const Offset(0, -120));
    await tester.pumpAndSettle();
    for (final key in ['uploader-wizard-back', 'uploader-wizard-next']) {
      final control = find.byKey(ValueKey(key));
      await Scrollable.ensureVisible(tester.element(control), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(control.hitTestable(), findsOneWidget);
    }
  }
  expect(tester.widget<EditableText>(editableFinder).controller.text, value);
  tester.testTextInput.hide();
  tester.view.resetViewInsets();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
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

  testWidgets(
      'English caption step labels manual editing without changing content',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Advanced settings'), findsOneWidget);
    expect(
        find.text('Write separate captions for each channel'), findsOneWidget);
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-caption-field')));
    expect(find.text('Caption'), findsWidgets);
    expect(
        find.text(
            'Tell the story of your video or what you want customers to know...'),
        findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'ข้อความที่ลูกค้าเขียนเอง');
    expect(find.text('ข้อความที่ลูกค้าเขียนเอง'), findsOneWidget);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored required-caption error follows locale without a request',
      (tester) async {
    final fixture = CaptionEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapCaptionEnglishControl(tester, 'uploader-wizard-next');
    expect(find.text('เพิ่มแคปชันก่อนไปต่อ'), findsOneWidget);
    final quotaReads = fixture.captionQuotaReads;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Add a caption before continuing.'), findsOneWidget);
    expect(fixture.captionQuotaReads, quotaReads);
    expect(fixture.requests, isEmpty);
    expect(fixture.templateReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English AI panel preserves the selected video name without generating',
      (tester) async {
    final fixture = CaptionEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-ai-caption-panel')));
    expect(find.text('AI captions from your video'), findsOneWidget);
    expect(find.text('Let AI write'), findsOneWidget);
    expect(find.textContaining('คลิปแคปชัน.mp4'), findsWidgets);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'locale changes preserve manual text selection guidance and style data',
      (tester) async {
    const profile = CaptionWritingStyleProfile(
        style: CaptionWritingStyle(
            tone: CaptionWritingTone.friendly,
            length: CaptionWritingLength.short,
            emoji: CaptionWritingEmoji.none,
            examples: ['ตัวอย่างลูกค้า']));
    final fixture = CaptionEnglishFixture();
    fixture.styles.profile = profile;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, field);
    await tester.enterText(field, '  แคปชันลูกค้า 😊\nบรรทัดสอง  ');
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 8);
    await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
    final guidance = find.byKey(const ValueKey('uploader-ai-guidance-field'));
    await revealCaptionEnglishControl(tester, guidance);
    await tester.enterText(guidance, 'คำแนะนำตั้งค่าขั้นสูง');
    final reads = fixture.captionQuotaReads;
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    await revealCaptionEnglishControl(tester, field);
    expect(tester.widget<TextField>(field).controller, same(controller));
    expect(controller.text, '  แคปชันลูกค้า 😊\nบรรทัดสอง  ');
    expect(controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8));
    await revealCaptionEnglishControl(tester, guidance);
    expect(tester.widget<TextField>(guidance).controller!.text,
        'คำแนะนำตั้งค่าขั้นสูง');
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-ai-style-summary')));
    expect(
        find.text('Friendly · Short and concise · No emoji'), findsOneWidget);
    expect(fixture.styles.profile, same(profile));
    expect(profile.style.summary, 'เป็นกันเอง · สั้น กระชับ · ไม่ใช้อีโมจิ');
    expect(fixture.styles.loads, [captionEnglishOwner]);
    expect(fixture.styles.saves, isEmpty);
    expect(fixture.captionQuotaReads, reads);
    expect(fixture.requests, isEmpty);
    expect(fixture.templateReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending template labels follow locale while raw results stay unchanged',
      (tester) async {
    final pending = Completer<List<TextTemplateResult>>();
    final fixture = CaptionEnglishFixture()..templateGate = pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapCaptionEnglishControl(tester, 'uploader-templates-panel');
    await revealCaptionEnglishControl(tester, find.text('Load templates'));
    await tester.tap(find.text('Load templates'));
    await tester.pumpAndSettle();
    expect(find.text('Loading templates...'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กำลังโหลดเทมเพลต...'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    pending.complete([
      TextTemplateResult(
          id: 'raw-template',
          title: 'ตั้งค่าขั้นสูง',
          body: 'ใส่แคปชั่น',
          createdAt: DateTime.utc(2026, 10, 29))
    ]);
    await tester.pumpAndSettle();
    expect(find.text('ตั้งค่าขั้นสูง'), findsOneWidget);
    expect(find.text('ใส่แคปชั่น'), findsOneWidget);
    expect(find.text('Insert caption'), findsOneWidget);
    expect(fixture.templateReads, 1);
    expect(fixture.requests, isEmpty);
    expect(fixture.store.savedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'known template error translates without another load and can recover',
      (tester) async {
    final fixture = CaptionEnglishFixture(locale: const Locale('th'))
      ..templateError = StateError('Private template failure');
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapCaptionEnglishControl(tester, 'uploader-templates-panel');
    await revealCaptionEnglishControl(tester, find.text('โหลดเทมเพลต'));
    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pumpAndSettle();
    expect(find.text('เกิดข้อผิดพลาดระหว่างโหลดเทมเพลต'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('An error occurred while loading templates.'),
        findsOneWidget);
    expect(fixture.templateReads, 1);
    fixture.templateError = null;
    await tester.tap(find.text('Load templates'));
    await tester.pumpAndSettle();
    expect(
        find.text('An error occurred while loading templates.'), findsNothing);
    expect(fixture.templateReads, 2);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'quota loading and stored failure change locale without extra reads',
      (tester) async {
    final pending = Completer<CaptionQuotaResult>();
    final fixture = CaptionEnglishFixture()..aiQuotaGate = pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-ai-quota-loading')));
    expect(find.text('Loading AI caption quota...'), findsOneWidget);
    pending.completeError(StateError('Private quota failure'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load AI caption quota.'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('โหลดโควตาไม่สำเร็จ'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(fixture.captionQuotaReads, 1);
    fixture.aiQuotaGate = null;
    await tapCaptionEnglishControl(tester, 'uploader-ai-quota-retry');
    expect(find.text('AI caption credits remaining'), findsOneWidget);
    expect(fixture.captionQuotaReads, 2);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fresh Basic plan check blocks AI despite a previously loaded credit balance',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..quota = const SubscriptionStatusResult(
          userId: captionEnglishOwner,
          plan: 'BASIC',
          status: 'INACTIVE',
          monthlyPostLimit: 3,
          usedPostsThisMonth: 0,
          remainingPostsThisMonth: 3,
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    expect(
        find.text(
            'AI captions are available on Starter or Pro. Please check your plan.'),
        findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, field);
    await tester.enterText(field, 'ยังเขียนเองได้');
    expect(tester.widget<TextField>(field).controller!.text, 'ยังเขียนเองได้');
    expect(tester.takeException(), isNull);
  });

  testWidgets('exhausted paid credits disable only the AI action',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..aiQuota = const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 120, remainingThisMonth: 0));
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-ai-generate-button')));
    expect(find.text('No AI credits remaining'), findsOneWidget);
    expect(
        tester
            .widget<PostDeeGradientButton>(
                find.byKey(const ValueKey('uploader-ai-generate-button')))
            .onPressed,
        isNull);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, field);
    await tester.enterText(field, 'ข้อความที่เขียนเอง');
    expect(tester.widget<TextField>(field).readOnly, isFalse);
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'SEO and generated text keep raw Thai values across locale changes',
      (tester) async {
    final fixture = CaptionEnglishFixture()
      ..result = captionEnglishResult(
          caption: 'ตั้งค่าขั้นสูง',
          hashtags: const ['#ลูกค้า'],
          keywords: const ['แคปชั่น', 'ตั้งค่าขั้นสูง']);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await tapCaptionEnglishControl(tester, 'uploader-ai-generate-button');
    await tapCaptionEnglishControl(tester, 'uploader-ai-seo-keywords');
    expect(find.text('AI-suggested keywords'), findsOneWidget);
    expect(find.text('แคปชั่น, ตั้งค่าขั้นสูง'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    await revealCaptionEnglishControl(tester, field);
    expect(tester.widget<TextField>(field).controller!.text,
        'ตั้งค่าขั้นสูง\n\n#ลูกค้า');
    await revealCaptionEnglishControl(
        tester, find.byKey(const ValueKey('uploader-ai-seo-keywords')));
    expect(find.text('แคปชั่น, ตั้งค่าขั้นสูง'), findsOneWidget);
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.toJson().containsKey('locale'), isFalse);
    expect(fixture.uploadRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact video preview keeps its action within the tile and accessible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = CaptionEnglishFixture(scale: 2);
    addTearDown(fixture.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      final tile = find.byKey(const ValueKey('uploader-video-preview-open'));
      await revealCaptionEnglishControl(tester, tile);
      final bounds = tester.getRect(tile);
      expect(bounds.size, const Size(72, 108));
      final labels = find.descendant(of: tile, matching: find.text('Watch'));
      for (final element in labels.evaluate()) {
        final rect = tester.getRect(find
            .byElementPredicate((candidate) => identical(candidate, element)));
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.right, lessThanOrEqualTo(bounds.right),
            reason:
                'The compact preview action must stay inside its clipping bounds');
        expect(rect.top, greaterThanOrEqualTo(bounds.top));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      final action = tester.getSemantics(tile).getSemanticsData();
      expect(action.label, contains('Watch video'));
      expect(action.hasAction(SemanticsAction.tap), isTrue);
      await revealCaptionEnglishControl(tester, find.text('Watch video'));
      expect(find.text('Watch video').hitTestable(), findsOneWidget);
      expect(fixture.requests, isEmpty);
      expect(fixture.uploadRequests, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
        'manual caption AI and templates fit 320dp 2x with keyboard (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = CaptionEnglishFixture(dark: dark, scale: 2);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(tester.takeException(), isNull);
      for (final text in [
        'Advanced settings',
        'Write separate captions for each channel'
      ]) {
        await revealCaptionEnglishControl(tester, find.text(text));
        expectCaptionEnglishReadable(tester, find.text(text));
      }
      final field = find.byKey(const ValueKey('uploader-caption-field'));
      await revealCaptionEnglishControl(tester, field);
      expectCaptionEnglishReadable(
          tester, find.descendant(of: field, matching: find.text('Caption')));
      await typeCaptionEnglishWithKeyboard(
          tester, 'uploader-caption-field', 'ข้อความลูกค้า 😊');
      for (final text in ['AI captions from your video', 'Let AI write']) {
        await revealCaptionEnglishControl(tester, find.text(text));
        expectCaptionEnglishReadable(tester, find.text(text));
        expect(tester.takeException(), isNull);
      }
      await tapCaptionEnglishControl(tester, 'uploader-ai-open-panel');
      for (final text in [
        'Customize style and instructions',
        'Writing style',
        'Additional instructions (optional)'
      ]) {
        await revealCaptionEnglishControl(tester, find.text(text));
        expectCaptionEnglishReadable(tester, find.text(text));
      }
      await typeCaptionEnglishWithKeyboard(
          tester, 'uploader-ai-guidance-field', 'คำแนะนำของลูกค้า');
      await tapCaptionEnglishControl(tester, 'uploader-templates-panel');
      for (final text in ['Caption templates', 'Templates', 'Load templates']) {
        await revealCaptionEnglishControl(tester, find.text(text));
        expectCaptionEnglishReadable(tester, find.text(text));
      }
      expect(fixture.requests, isEmpty);
      expect(fixture.uploadRequests, isEmpty);
      expect(fixture.styles.saves, isEmpty);
      expect(fixture.templateReads, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('advanced AI and writing style sheet fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = CaptionEnglishFixture(dark: dark, scale: 2);
      fixture.styles.profile = const CaptionWritingStyleProfile(
          style: CaptionWritingStyle(examples: ['ตัวอย่างจากลูกค้า']));
      addTearDown(fixture.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await fixture.mount(tester);
        await tapCaptionEnglishControl(
            tester, 'uploader-platform-captions-toggle');
        expect(tester.takeException(), isNull);
        await revealCaptionEnglishControl(
            tester, find.byKey(const ValueKey('uploader-ai-generate-button')));
        final generateLabel = find
            .descendant(
                of: find.byKey(const ValueKey('uploader-ai-generate-button')),
                matching: find.byType(Text))
            .last;
        expectCaptionEnglishReadable(tester, generateLabel);
        await tapCaptionEnglishControl(tester, 'uploader-ai-style-button');
        final sheet = find.byKey(const ValueKey('uploader-ai-style-sheet'));
        expect(sheet, findsOneWidget);
        final title =
            find.descendant(of: sheet, matching: find.text('Writing style'));
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        expectCaptionEnglishReadable(tester, title);
        final guidance = find.descendant(
            of: sheet,
            matching: find.byKey(const ValueKey('uploader-ai-guidance-field')));
        await tester.ensureVisible(guidance);
        await tester.pumpAndSettle();
        expectCaptionEnglishReadable(
            tester,
            find.descendant(
                of: sheet,
                matching: find.text('Additional instructions (optional)')));
        expect(tester.getSemantics(guidance).getSemanticsData().label,
            contains('Additional instructions (optional)'));
        await typeCaptionEnglishWithKeyboard(
            tester, 'uploader-ai-guidance-field', 'คำแนะนำในหน้าสไตล์',
            inSheet: true);
        for (final key in [
          for (final value in CaptionWritingTone.values)
            'uploader-ai-style-tone-${value.value}',
          for (final value in CaptionWritingLength.values)
            'uploader-ai-style-length-${value.value}',
          for (final value in CaptionWritingEmoji.values)
            'uploader-ai-style-emoji-${value.value}',
          'uploader-ai-style-clear',
          'uploader-ai-style-save'
        ]) {
          final control = find.byKey(ValueKey(key));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          final label =
              find.descendant(of: control, matching: find.byType(Text)).last;
          expectCaptionEnglishReadable(tester, label);
          expect(label.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        for (final text in [
          'Remember my writing edits',
          'Remembered when you edit an AI caption and tap Next. Saved on this device for your account only.',
          'Remembered examples 1/3'
        ]) {
          final label = find.descendant(of: sheet, matching: find.text(text));
          await Scrollable.ensureVisible(tester.element(label), alignment: 0.5);
          await tester.pumpAndSettle();
          expectCaptionEnglishReadable(tester, label);
          expect(label.hitTestable(), findsOneWidget);
        }
        final cancel =
            find.descendant(of: sheet, matching: find.text('Cancel'));
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expectCaptionEnglishReadable(tester, cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(fixture.styles.saves, isEmpty);
        expect(fixture.requests, isEmpty);
        expect(fixture.uploadRequests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
      }
    });
  }
}
