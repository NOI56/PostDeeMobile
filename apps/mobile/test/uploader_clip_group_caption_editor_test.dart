import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/caption_language.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/caption_language_picker.dart';
import 'package:postdee_mobile/features/uploader/clip_group_caption_context.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'uploader_caption_english_test.dart';

const _captionKey = 'uploader-caption-field';
const _languageKey = 'uploader-caption-language';
const _originalId = 'retained-original';
const _context = ClipGroupCaptionContext(
    aiGuidance: 'Group guidance', captionLanguage: 'ru');

class _Fixture extends CaptionEnglishFixture {
  _Fixture() : super(withVideo: false);

  final shared = TextEditingController(text: 'Shared seller text');
  final enabled = ValueNotifier(true);
  final busy = <bool>[];
  final contexts = <ClipGroupCaptionContext>[];
  late final session = PostDeeAuthSessionStore.instance.captureSession();
  ClipGroupCaptionContext? initialContext = _context;
  ValueChanged<bool>? onBusy;
  bool contextValid = true;
  Future<bool> Function()? validationHook;
  int validations = 0;
  bool nestedGroupRoute = false;
  late String originalPath;

  Future<void> seed() async {
    final original = makeVideo('retained-original.mp4');
    originalPath = original.path;
    final now = DateTime.utc(2026, 11, 5);
    await store.saveDraft(PublishDraftSaveRequest(
      id: _originalId,
      createdAt: now,
      updatedAt: now,
      videoFile: File(original.path),
      videoName: original.name,
      videoSizeBytes: original.sizeBytes,
      videoWidth: original.width,
      videoHeight: original.height,
      caption: 'Backup source caption must stay separate',
      aiGuidance: 'Source guidance',
      captionLanguage: 'ja',
      watermarkEnabled: false,
      platformApiValues: const {'INSTAGRAM_REELS'},
      platformSettings:
          const PlatformPublishSettings(usePlatformCaptions: true),
      clipGroupId: 'caption-group',
      isClipGroupSource: true,
    ));
  }

  @override
  UploaderScreen screen() => UploaderScreen(
        key: const ValueKey('inline-caption-instance'),
        clipGroupEditor: true,
        clipGroupOwnerSession: session,
        clipGroupSharedCaptionController: shared,
        clipGroupCaptionContext: initialContext,
        clipGroupCaptionEnabled: enabled.value,
        onClipGroupCaptionBusyChanged: (value) {
          busy.add(value);
          onBusy?.call(value);
        },
        onClipGroupCaptionContextChanged: contexts.add,
        validateClipGroupCaptionContext: () async {
          validations++;
          return validationHook == null
              ? contextValid
              : await validationHook!();
        },
        initialDraftId: _originalId,
        draftStore: store,
        enableRevenueCatBilling: false,
        captionWritingStyleStore: styles,
        loadTemplates: () async {
          templateReads++;
          return templates;
        },
        loadSubscription: () async => quota,
        loadPostQuota: () async => quota,
        loadCaptionQuota: () async => aiQuota,
        loadSocialConnections: () async => const [],
        loadSocialPublishingReadiness: () async => const [],
        readVideoMetadata: (_) async => const VideoDimensions(
            width: 1080, height: 1920, durationSeconds: 10),
        probePublishMedia: probeValidPublishMedia,
        extractFrames: (_, {maxFrames = 3}) async => const [],
        createUpload: (request) async {
          uploadRequests.add(request);
          return const UploadResult(
              id: 'caption-upload',
              videoS3Key: 'uploads/original-for-caption.mp4',
              storageProvider: 'mock');
        },
        uploadVideoFile: (_, file) async => uploadedFiles.add(file.path),
        generateRealClipCaption: (request) async {
          requests.add(request);
          return aiGate == null ? result : await aiGate!;
        },
        createPost: (_) async {
          apiWrites++;
          throw StateError('An inline caption editor cannot publish');
        },
      );

  @override
  Widget app() => ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (_, value, child) => MaterialApp(
          locale: const Locale('en'),
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!),
          initialRoute: nestedGroupRoute ? '/group' : null,
          routes: {'/group': (_) => _groupBody()},
          home: nestedGroupRoute
              ? const Scaffold(body: Text('Parent home'))
              : _groupBody(),
        ),
      );

  Widget _groupBody() => Scaffold(
      key: const ValueKey('parent-group-route'),
      body: SingleChildScrollView(
        key: const ValueKey('parent-group-scroll'),
        padding: const EdgeInsets.all(16),
        child: screen(),
      ));

  @override
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  @override
  void dispose() {
    shared.dispose();
    enabled.dispose();
    super.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {bool seed = true, bool settle = true}) async {
  addTearDown(fixture.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  if (seed) await fixture.seed();
  await fixture.mount(tester, settle: settle);
}

Future<void> _tap(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(
        userId: captionEnglishOwner, idToken: 'inline-caption-test'));
    addTearDown(sessions.clear);
  });

  testWidgets(
      'inline source restore preserves shared text, exposes the real '
      '109-language AI panel, and never saves or generates on mount',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    expect(_key(_captionKey), findsOneWidget);
    expect(tester.widget<TextField>(_key(_captionKey)).controller,
        same(fixture.shared));
    expect(fixture.shared.text, 'Shared seller text');
    expect(_key('uploader-ai-caption-panel'), findsOneWidget);
    expect(_key('uploader-platform-captions-toggle'), findsNothing);
    expect(_key('clip-group-member-save'), findsNothing);
    expect(_key('uploader-header-scroll'), findsNothing);
    expect(_key('uploader-sticky-post-button'), findsNothing);
    expect(_key('uploader-scroll'), findsNothing);
    expect(captionLanguageCatalog, hasLength(109));
    expect(
        tester.widget<CaptionLanguagePicker>(_key(_languageKey)).value, 'ru');
    expect(fixture.contexts, [_context]);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.requests, isEmpty);
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.apiWrites, 0);
    expect(fixture.busy.last, isFalse);
    await _tap(tester, _languageKey);
    await tester.enterText(_key('caption-language-search'), 'Zulu');
    await tester.pumpAndSettle();
    expect(find.text(captionOutputLanguages['zu']!), findsWidgets);
    Navigator.of(tester.element(_key('caption-language-search'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manual AI uses the retained original, preserves preview and undo, '
      'and finishes while the parent locks other group controls',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _Fixture()..aiGate = gate.future;
    fixture.onBusy = (busy) => fixture.enabled.value = !busy;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadedFiles, [fixture.originalPath]);
    expect(fixture.requests.single.guidance, 'Group guidance');
    expect(fixture.requests.single.captionLanguage, 'ru');
    expect(fixture.requests.single.expectedCredits, 1);
    expect(fixture.requests.single.platforms, isEmpty);
    expect(fixture.busy.last, isTrue);
    expect(fixture.enabled.value, isFalse);
    gate.complete(captionEnglishResult(caption: 'Generated for the whole set'));
    await tester.pumpAndSettle();
    expect(_key('uploader-shared-ai-preview'), findsOneWidget);
    expect(fixture.shared.text, 'Shared seller text');
    await _tap(tester, 'uploader-shared-ai-apply');
    expect(fixture.shared.text, contains('Generated for the whole set'));
    expect(fixture.busy.last, isFalse);
    expect(fixture.enabled.value, isTrue);
    await _tap(tester, 'uploader-shared-ai-undo');
    expect(fixture.shared.text, 'Shared seller text');
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts[_originalId]!.caption,
        'Backup source caption must stay separate');
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing text during final async validation keeps it until explicit Apply',
      (tester) async {
    final gate = Completer<bool>();
    var pauseFinalValidation = false;
    var reachedFinalValidation = false;
    final fixture = _Fixture();
    fixture.validationHook = () async {
      if (!pauseFinalValidation) return true;
      reachedFinalValidation = true;
      return gate.future;
    };
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(_key('uploader-shared-ai-preview'), findsOneWidget);
    pauseFinalValidation = true;
    await _tap(tester, 'uploader-shared-ai-apply');
    expect(reachedFinalValidation, isTrue);
    fixture.shared.text = 'Seller typed during the final local check';
    await tester.pumpAndSettle();
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'Seller typed during the final local check');
    expect(_key('uploader-shared-ai-undo'), findsNothing);
    pauseFinalValidation = false;
    await _tap(tester, 'uploader-ai-reopen-result');
    await _tap(tester, 'uploader-shared-ai-apply');
    await _tap(tester, 'uploader-shared-ai-undo');
    expect(fixture.shared.text, 'Seller typed during the final local check');
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
  });

  testWidgets(
      'source loading reports busy without sending default metadata or '
      'overwriting text edited before restore finishes', (tester) async {
    final fixture = _Fixture();
    await fixture.seed();
    final source = fixture.store.drafts[_originalId]!;
    final gate = Completer<PublishDraft?>();
    fixture.store.loadGate = gate.future;
    await _mount(tester, fixture, seed: false, settle: false);
    expect(fixture.contexts, isEmpty);
    expect(fixture.busy.last, isTrue);
    fixture.shared.text = 'Seller typed while source was loading';
    gate.complete(source);
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'Seller typed while source was loading');
    expect(fixture.contexts, [_context]);
    expect(fixture.busy.last, isFalse);
    expect(fixture.busy.toSet(), {true, false});
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'context falls back to source preferences and updates without '
      'saving the original or group', (tester) async {
    final fixture = _Fixture()..initialContext = null;
    await _mount(tester, fixture);
    expect(fixture.contexts, [
      const ClipGroupCaptionContext(
          aiGuidance: 'Source guidance', captionLanguage: 'ja')
    ]);
    await _tap(tester, _languageKey);
    await tester.enterText(_key('caption-language-search'), 'English');
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'uploader-ai-open-panel');
    await tester.ensureVisible(_key('uploader-ai-guidance-input'));
    await tester.enterText(
        _key('uploader-ai-guidance-input'), 'Edited guidance');
    await tester.pumpAndSettle();
    expect(
        fixture.contexts.last,
        const ClipGroupCaptionContext(
            aiGuidance: 'Edited guidance', captionLanguage: 'en'));
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.store.drafts[_originalId]!.aiGuidance, 'Source guidance');
    expect(fixture.store.drafts[_originalId]!.captionLanguage, 'ja');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'external lock disables editing without reporting a self busy loop '
      'and disposal leaves the external controller usable', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final signals = List.of(fixture.busy);
    fixture.enabled.value = false;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_key(_captionKey)).readOnly, isTrue);
    expect(tester.widget<CaptionLanguagePicker>(_key(_languageKey)).onChanged,
        isNull);
    expect(fixture.busy, signals);
    fixture.enabled.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_key(_captionKey)).readOnly, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    fixture.shared.text = 'External owner can still use this controller';
    expect(fixture.shared.text, 'External owner can still use this controller');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late AI results and owner clearing never mutate external text '
      'after a same-owner sign-in lifecycle changes', (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _Fixture()..aiGate = gate.future;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(fixture.requests, hasLength(1));
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
        userId: captionEnglishOwner, idToken: 'new-inline-lifecycle'));
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'Shared seller text');
    fixture.shared.text = 'New group text must survive the old request';
    gate.complete(captionEnglishResult(caption: 'Obsolete result'));
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'New group text must survive the old request');
    expect(_key('uploader-shared-ai-preview'), findsNothing);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.apiWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing original media exposes a disabled error without any '
      'automatic save, upload or AI request', (tester) async {
    final fixture = _Fixture();
    await fixture.seed();
    File(fixture.originalPath).deleteSync();
    await _mount(tester, fixture, seed: false);
    expect(_key('clip-group-shared-caption-source-error'), findsOneWidget);
    expect(_key('uploader-ai-generate-button'), findsNothing);
    expect(fixture.shared.text, 'Shared seller text');
    expect(fixture.contexts, isEmpty);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a changed group context blocks every AI side effect before upload',
      (tester) async {
    final fixture = _Fixture()..contextValid = false;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(fixture.validations, greaterThan(0));
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.requests, isEmpty);
    expect(fixture.shared.text, 'Shared seller text');
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a group changed while AI runs keeps shared text and ignores the '
      'late result without another provider request', (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    final fixture = _Fixture()..aiGate = gate.future;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(fixture.requests, hasLength(1));
    fixture.contextValid = false;
    gate.complete(captionEnglishResult(caption: 'Obsolete group result'));
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'Shared seller text');
    expect(_key('uploader-shared-ai-preview'), findsNothing);
    expect(fixture.requests, hasLength(1));
    expect(fixture.uploadRequests, hasLength(1));
    expect(fixture.store.savedRequests, hasLength(1));
    expect(fixture.busy.last, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a group changed while the AI preview is open cannot apply its '
      'obsolete result', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(_key('uploader-shared-ai-preview'), findsOneWidget);
    fixture.contextValid = false;
    await _tap(tester, 'uploader-shared-ai-apply');
    expect(fixture.shared.text, 'Shared seller text');
    expect(fixture.requests, hasLength(1));
    expect(fixture.busy.last, isFalse);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'owner change dismisses only the inline AI preview and leaves '
      'navigation to its embedding group', (tester) async {
    final fixture = _Fixture()..nestedGroupRoute = true;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-generate-button');
    expect(_key('uploader-shared-ai-preview'), findsOneWidget);
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'new-group-owner', idToken: 'new-token'));
    await tester.pumpAndSettle();
    expect(_key('parent-group-route'), findsOneWidget);
    expect(_key('uploader-shared-ai-preview'), findsNothing);
    expect(fixture.shared.text, 'Shared seller text');
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'style sheet reports busy until dismissed without an external '
      'disabled feedback loop', (tester) async {
    final fixture = _Fixture();
    fixture.onBusy = (busy) => fixture.enabled.value = !busy;
    await _mount(tester, fixture);
    await _tap(tester, 'uploader-ai-open-panel');
    await _tap(tester, 'uploader-ai-style-button');
    expect(fixture.busy.last, isTrue);
    expect(fixture.enabled.value, isFalse);
    Navigator.of(tester.element(_key('uploader-ai-style-sheet'))).pop();
    await tester.pumpAndSettle();
    expect(fixture.busy.last, isFalse);
    expect(fixture.enabled.value, isTrue);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'insufficient existing AI credits leave manual shared text '
      'available without uploading or generating', (tester) async {
    final fixture = _Fixture()
      ..aiQuota = const CaptionQuotaResult(
          plan: 'PRO',
          quota: RealClipCaptionQuota(
              limit: 120, usedThisMonth: 120, remainingThisMonth: 0));
    await _mount(tester, fixture);
    expect(tester.widget<TextField>(_key(_captionKey)).readOnly, isFalse);
    await tester.enterText(_key(_captionKey), 'Manual text with no AI credits');
    await tester.pumpAndSettle();
    expect(fixture.shared.text, 'Manual text with no AI credits');
    expect(fixture.uploadRequests, isEmpty);
    expect(fixture.requests, isEmpty);
    expect(fixture.busy.last, isFalse);
    expect(fixture.store.savedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
