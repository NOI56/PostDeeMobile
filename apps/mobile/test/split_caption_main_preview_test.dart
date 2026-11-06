// Opt-in design preview only. This does not change the app's navigation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_group_caption_context.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/split_caption_page_preview.dart';
import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'uploader_caption_english_test.dart' show CaptionEnglishStyleStore;

const _captureDirectory = String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR');
const _sourcePath = String.fromEnvironment('POSTDEE_PREVIEW_SOURCE');
const _captureKey = ValueKey('split-caption-main-capture');
const _owner = 'split-caption-offline-preview';

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final loader = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await loader.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_captureDirectory).create(recursive: true);
      await File('$_captureDirectory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in [
    (name: 'th', english: false, dark: false, width: 430.0, scale: 1.0),
    (name: 'en', english: true, dark: false, width: 430.0, scale: 1.0),
    (
      name: 'th-dark-small',
      english: false,
      dark: true,
      width: 320.0,
      scale: 1.5
    ),
  ]) {
    testWidgets('offline split-to-main-caption example ${mode.name}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sessions = PostDeeAuthSessionStore.instance;
      final previous = sessions.session;
      final previousMode =
          AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
      sessions.signIn(AuthSession.authenticated(
          userId: _owner, idToken: 'offline-preview-token'));
      final binding = sessions.captureSession();
      final caption = TextEditingController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        caption.dispose();
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear();
        AppTheme.applyThemeMode(previousMode);
      });
      tester.view.physicalSize = Size(mode.width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(mode.dark ? ThemeMode.dark : ThemeMode.light);
      await _fonts(tester);

      final source = File(_sourcePath);
      expect(source.existsSync(), isTrue,
          reason: 'Supply the existing 180-second source fixture.');
      final store = TestPublishDraftStore(ownerUserId: _owner);
      final now = DateTime.utc(2026, 11, 5);
      await store.saveDraft(PublishDraftSaveRequest(
        id: 'preview-source',
        createdAt: now,
        updatedAt: now,
        videoFile: source,
        videoName: '1000001341.mp4',
        videoSizeBytes: source.lengthSync(),
        videoWidth: 360,
        videoHeight: 640,
        caption: '',
        aiGuidance: '',
        captionLanguage: 'auto',
        watermarkEnabled: false,
        platformApiValues: const {'FACEBOOK_REELS'},
        clipGroupId: 'preview-set',
        isClipGroupSource: true,
      ));
      final seedWrites = store.savedRequests.length;
      final plan = ClipSplitPlan.create(
          sourceDurationSeconds: 180,
          platforms: const {SocialPlatform.facebookReels});
      final segments = plan.channelPlans.single.segments;
      expect(segments.length, 2);
      var externalWrites = 0;
      var continues = 0;
      var backs = 0;
      var saves = 0;
      const basic = SubscriptionStatusResult(
          userId: _owner,
          plan: 'BASIC',
          status: 'ACTIVE',
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
      final editor = UploaderScreen(
        key: const ValueKey('split-caption-real-editor'),
        clipGroupEditor: true,
        clipGroupOwnerSession: binding,
        clipGroupSharedCaptionController: caption,
        clipGroupCaptionContext: const ClipGroupCaptionContext(
            aiGuidance: '', captionLanguage: 'auto'),
        initialDraftId: 'preview-source',
        draftStore: store,
        enableRevenueCatBilling: false,
        captionWritingStyleStore: CaptionEnglishStyleStore(),
        loadTemplates: () async => const [],
        loadSubscription: () async => basic,
        loadPostQuota: () async => basic,
        loadCaptionQuota: () async => const CaptionQuotaResult(
            plan: 'BASIC',
            quota: RealClipCaptionQuota(
                limit: 0,
                usedThisMonth: 0,
                remainingThisMonth: 0,
                charged: false)),
        loadSocialConnections: () async => const [],
        loadSocialPublishingReadiness: () async => const [],
        readVideoMetadata: (_) async => const VideoDimensions(
            width: 360, height: 640, durationSeconds: 180),
        probePublishMedia: probeValidPublishMedia,
        extractFrames: (_, {maxFrames = 3}) async => const [],
        createUpload: (_) async {
          externalWrites++;
          throw StateError('The design preview cannot upload.');
        },
        generateRealClipCaption: (_) async {
          externalWrites++;
          throw StateError('The design preview cannot generate AI text.');
        },
        createPost: (_) async {
          externalWrites++;
          throw StateError('The design preview cannot publish.');
        },
      );
      await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(mode.english ? 'en' : 'th'),
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: mode.dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(mode.scale)),
              child: child!),
          home: SplitCaptionPagePreview(
            english: mode.english,
            videoName: '1000001341.mp4',
            sourceDurationSeconds: plan.sourceDurationSeconds,
            segments: segments,
            platform: SocialPlatform.facebookReels,
            captionEditor: editor,
            onContinue: () => continues++,
            onBack: () => backs++,
            onSave: () => saves++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('uploader-caption-field'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller, same(caption));
      expect(find.byKey(const ValueKey('uploader-ai-caption-panel')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('uploader-platform-captions-toggle')),
          findsNothing);
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/platforms/facebook_reels.png'),
          tester.element(field)));
      await tester.pumpAndSettle();
      await _capture(tester, 'main-caption-${mode.name}');
      final parts = find.byKey(const ValueKey('split-caption-preview-parts'));
      final partsBounds = tester.getRect(parts);
      if (partsBounds.top < 0 || partsBounds.bottom > 700) {
        await tester.ensureVisible(parts);
      }
      await tester.tap(parts);
      await tester.pumpAndSettle();
      expect(find.textContaining('0:00–1:30'), findsOneWidget);
      expect(find.textContaining('1:30–3:00'), findsOneWidget);
      await _capture(tester, 'parts-${mode.name}');
      final sheetContext = tester.element(
          find.byKey(const ValueKey('split-caption-preview-parts-sheet')));
      Navigator.of(sheetContext).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.enterText(field,
          mode.english ? 'Caption preview' : 'ข้อความตัวอย่างสำหรับทั้งสองตอน');
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(caption.text, isNotEmpty);
      await tester
          .tap(find.byKey(const ValueKey('split-caption-preview-continue')));
      await tester.pumpAndSettle();
      expect(continues, 1);
      expect(backs, 0);
      expect(saves, 0);
      expect(externalWrites, 0);
      expect(store.savedRequests.length, seedWrites);
      expect((await store.loadDraft('preview-source'))!.caption, isEmpty);
    }, skip: _captureDirectory.isEmpty || _sourcePath.isEmpty);
  }
}
