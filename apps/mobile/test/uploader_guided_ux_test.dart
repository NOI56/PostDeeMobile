import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/models/caption_writing_style.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/captions/caption_writing_style_store.dart';
import 'package:postdee_mobile/features/shared/postdee_press_feedback.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

const _connections = [
  SocialConnectionResult(
    platform: 'TIKTOK',
    connected: true,
    displayName: 'ร้านของเรา',
    externalAccountId: 'tiktok-account',
  ),
  SocialConnectionResult(
    platform: 'YOUTUBE_SHORTS',
    connected: true,
    externalAccountId: 'youtube-channel-verified',
  ),
  SocialConnectionResult(
    platform: 'INSTAGRAM_REELS',
    connected: true,
  ),
  SocialConnectionResult(
    platform: 'FACEBOOK_REELS',
    connected: true,
    displayName: 'เพจร้านขายของที่มีชื่อยาวเพื่อทดสอบหน้าจอมือถือ',
    externalAccountId: 'facebook-page',
  ),
];

class _StyleStore implements CaptionWritingStyleStore {
  var profile = const CaptionWritingStyleProfile();

  @override
  Future<CaptionWritingStyleProfile> load(String ownerUserId) async => profile;

  @override
  Future<void> save(String ownerUserId, CaptionWritingStyleProfile next) async {
    profile = next;
  }

  @override
  Future<void> clear(String ownerUserId) async {
    profile = const CaptionWritingStyleProfile();
  }
}

class _Fixture {
  _Fixture() {
    final directory = Directory.systemTemp.createTempSync('postdee-guided-ux-');
    addTearDown(() => directory.deleteSync(recursive: true));
    video = File('${directory.path}${Platform.pathSeparator}seller.mp4')
      ..writeAsBytesSync(List<int>.filled(512, 1));
  }

  late final File video;
  final drafts = TestPublishDraftStore(ownerUserId: 'guided-owner');
  final style = _StyleStore();
  final requests = <GenerateRealClipCaptionRequest>[];
  var uploads = 0;
  var readiness = 0;
  var posts = 0;
  var dimensionsKnown = true;
  var hasVideo = true;
  var injectDraftStore = true;
  UploaderConnectionsLoader loadConnections = () async => _connections;

  Widget app({
    bool reducedMotion = false,
    bool tickerEnabled = true,
    double textScale = 1,
  }) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: TickerMode(
            enabled: tickerEnabled,
            child: UploaderScreen(
              probePublishMedia: probeValidPublishMedia,
              loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
              fullScreen: true,
              draftStore: injectDraftStore ? drafts : null,
              captionWritingStyleStore: style,
              initialVideoPath: hasVideo ? video.path : null,
              initialVideoName: hasVideo ? 'seller.mp4' : null,
              initialVideoSizeBytes: hasVideo ? video.lengthSync() : null,
              initialVideoWidth: dimensionsKnown && hasVideo ? 1080 : null,
              initialVideoHeight: dimensionsKnown && hasVideo ? 1920 : null,
              initialScheduleDate: DateTime(2026, 10, 15),
              now: () => DateTime(2026, 10, 12, 9),
              loadSocialConnections: () => loadConnections(),
              enableRevenueCatBilling: false,
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'guided-owner',
                plan: 'STARTER',
                status: 'ACTIVE',
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: false,
              ),
              createUpload: (request) async {
                uploads++;
                return UploadResult(
                  id: 'upload-$uploads',
                  videoS3Key: 'uploads/guided-owner/${request.fileName}',
                  storageProvider: 's3',
                );
              },
              uploadVideoFile: (_, __) async {},
              generateRealClipCaption: (request) async {
                requests.add(request);
                return const RealClipCaptionResult(
                  caption: 'แคปชันจากคลิปจริง',
                  captionOptions: [],
                  hooks: [],
                  hashtags: [],
                  seoKeywords: [],
                  searchTitle: 'คลิปจริง',
                  source: RealClipCaptionSource(
                    videoS3Key: 'uploads/guided-owner/seller.mp4',
                    mode: 'AUDIO_ONLY',
                    selectedFrameCount: 0,
                  ),
                  quota: RealClipCaptionQuota(
                    limit: 50,
                    usedThisMonth: 1,
                    remainingThisMonth: 49,
                  ),
                );
              },
              checkPublishingReadiness: () async {
                readiness++;
                throw StateError('UX navigation must not prepare publishing');
              },
              createPost: (_) async {
                posts++;
                throw StateError('UX navigation must not publish');
              },
            ),
          ),
        ),
      );

  void expectNoSubmission({int expectedUploads = 0}) {
    expect(uploads, expectedUploads);
    expect(readiness, 0);
    expect(posts, 0);
    expect(drafts.savedRequests, isEmpty);
  }
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _openOptions(WidgetTester tester) async {
  final options = _key('uploader-ai-open-panel');
  final title =
      find.descendant(of: options, matching: find.text('ปรับสไตล์และคำแนะนำ'));
  await _show(tester, title);
  if (_key('uploader-ai-guidance-field').evaluate().isEmpty) {
    await tester.tap(title);
    await tester.pumpAndSettle();
  }
}

Future<void> _selectTikTok(WidgetTester tester) async {
  await _show(tester, _key('uploader-platform-TIKTOK'));
  await tester.tap(_key('uploader-platform-TIKTOK'));
  await tester.pumpAndSettle();
}

double _stepOpacity(WidgetTester tester, int index) => tester
    .widget<Opacity>(find
        .descendant(
          of: _key('uploader-step-motion-$index'),
          matching: find.byType(Opacity),
        )
        .first)
    .opacity;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() => sessions.signIn(previous));
    sessions.signIn(const AuthSession(
        userId: 'guided-owner', idToken: 'test-guided-token'));
  });

  testWidgets(
      'AI is ready on the caption step with optional controls collapsed',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    expect(_key('uploader-ai-caption-panel'), findsOneWidget);
    expect(_key('uploader-ai-generate-button'), findsOneWidget);
    expect(_key('uploader-ai-style-summary'), findsOneWidget);
    expect(find.text('ปรับสไตล์และคำแนะนำ'), findsOneWidget);
    expect(_key('uploader-ai-guidance-field'), findsNothing);
    expect(_key('uploader-ai-style-button'), findsNothing);
    await _show(tester, _key('uploader-ai-generate-button'));
    expect(_key('uploader-ai-generate-button').hitTestable(), findsOneWidget);
    expect(fixture.requests, isEmpty);
    fixture.expectNoSubmission();
  });

  testWidgets(
      'guidance and selected writing style survive moving between steps',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _openOptions(tester);
    await _show(tester, _key('uploader-ai-guidance-field'));
    await tester.enterText(_key('uploader-ai-guidance-field'),
        'เขียนให้เป็นกันเองและไม่กล่าวอ้างเกินคลิป');
    await _show(tester, _key('uploader-ai-style-button'));
    await tester.tap(_key('uploader-ai-style-button'));
    await tester.pumpAndSettle();
    await tester.tap(_key('uploader-ai-style-tone-friendly'));
    await _show(tester, _key('uploader-ai-style-save'));
    await tester.tap(_key('uploader-ai-style-save'));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await goToUploaderStep(tester, 1);
    expect(tester.widget<Text>(_key('uploader-ai-style-summary')).data,
        contains('เป็นกันเอง'));
    await _openOptions(tester);
    expect(
        tester
            .widget<TextField>(_key('uploader-ai-guidance-field'))
            .controller!
            .text,
        'เขียนให้เป็นกันเองและไม่กล่าวอ้างเกินคลิป');
    expect(fixture.requests, isEmpty);
    fixture.expectNoSubmission();
  });

  testWidgets(
      'collapsed AI generates only on explicit tap with retained guidance',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await _openOptions(tester);
    await _show(tester, _key('uploader-ai-guidance-field'));
    await tester.enterText(_key('uploader-ai-guidance-field'), 'ขอแบบสั้น');
    await _show(tester, find.text('ปรับสไตล์และคำแนะนำ'));
    await tester.tap(find.text('ปรับสไตล์และคำแนะนำ'));
    await tester.pumpAndSettle();
    expect(_key('uploader-ai-guidance-field'), findsNothing);
    expect(fixture.requests, isEmpty);
    fixture.expectNoSubmission();
    await _show(tester, _key('uploader-ai-generate-button'));
    await tester.tap(_key('uploader-ai-generate-button'));
    await tester.pumpAndSettle();
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.guidance, 'ขอแบบสั้น');
    expect(
        fixture.requests.single.videoS3Key, 'uploads/guided-owner/seller.mp4');
    expect(fixture.requests.single.writingStyle, isNotNull);
    expect(
        tester
            .widget<TextField>(_key('uploader-caption-field'))
            .controller!
            .text,
        'แคปชันจากคลิปจริง');
    fixture.expectNoSubmission(expectedUploads: 1);
  });

  testWidgets(
      'destinations use verified identities and missing identity blocks review',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    expect(tester.widget<Text>(_key('uploader-platform-account-TIKTOK')).data,
        'ร้านของเรา');
    expect(
        tester
            .widget<Text>(_key('uploader-platform-account-YOUTUBE_SHORTS'))
            .data,
        'youtube-channel-verified');
    expect(
        tester
            .widget<Text>(_key('uploader-platform-account-INSTAGRAM_REELS'))
            .data,
        contains('ยังยืนยัน'));
    expect(find.text('Facebook Page Video'), findsOneWidget);
    expect(find.text('Facebook Reels'), findsNothing);
    await _show(tester, _key('uploader-platform-INSTAGRAM_REELS'));
    await tester.tap(_key('uploader-platform-INSTAGRAM_REELS'));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 3);
    expect(_key('uploader-sticky-summary'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('publish-review-confirm')).onPressed,
        isNull);
    fixture.expectNoSubmission();
  });

  testWidgets(
      'loading and failed connection checks never show promised identities',
      (tester) async {
    final gate = Completer<List<SocialConnectionResult>>();
    final fixture = _Fixture()..loadConnections = () => gate.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    expect(_key('uploader-platform-account-TIKTOK'), findsNothing);
    gate.completeError(StateError('offline fixture'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตรวจสอบช่องทางที่เชื่อมต่อไม่สำเร็จ'),
        findsOneWidget);
    expect(_key('uploader-platform-account-TIKTOK'), findsNothing);
    fixture.loadConnections = () async => _connections;
    await _show(tester, _key('uploader-retry-connections'));
    await tester.tap(_key('uploader-retry-connections'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('uploader-platform-account-TIKTOK')).data,
        'ร้านของเรา');
    fixture.expectNoSubmission();
  });

  testWidgets(
      'a late response from the previous owner cannot replace destination identities',
      (tester) async {
    final oldOwner = Completer<List<SocialConnectionResult>>();
    final currentOwner = Completer<List<SocialConnectionResult>>();
    var loads = 0;
    final fixture = _Fixture()
      ..injectDraftStore = false
      ..loadConnections =
          () => ++loads == 1 ? oldOwner.future : currentOwner.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'new-owner', idToken: 'new-owner-token'));
    await tester.pumpAndSettle();
    currentOwner.complete(const [
      SocialConnectionResult(
          platform: 'TIKTOK', connected: true, displayName: 'ร้านเจ้าของใหม่'),
    ]);
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    expect(tester.widget<Text>(_key('uploader-platform-account-TIKTOK')).data,
        'ร้านเจ้าของใหม่');
    oldOwner.complete(_connections);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('uploader-platform-account-TIKTOK')).data,
        'ร้านเจ้าของใหม่');
    expect(find.text('ร้านของเรา'), findsNothing);
    fixture.expectNoSubmission();
  });

  testWidgets(
      'press cancellation and rapid step changes retain only current controls',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await goToUploaderStep(tester, 2);
      final row = _key('uploader-platform-TIKTOK');
      await _show(tester, row);
      final feedback = find
          .ancestor(of: row, matching: find.byType(PostDeePressFeedback))
          .first;
      expect(feedback, findsOneWidget);
      final transform = find.descendant(
          of: feedback, matching: _key('postdee-press-transform'));
      final bounds = tester.getRect(row);
      final originalSize = tester.getSize(row);
      final hitTargetBounds = tester.getRect(feedback);
      final gesture = await tester.startGesture(bounds.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<Transform>(transform).transform.entry(0, 0),
          closeTo(.97, .001));
      expect(tester.getSize(row), originalSize);
      expect(tester.getRect(feedback), hitTargetBounds);
      expect(tester.widget<Transform>(transform).transformHitTests, isFalse);
      await gesture.cancel();
      await tester.pump();
      expect(_key('uploader-platform-settings-TIKTOK'), findsNothing);
      final edgeGesture =
          await tester.startGesture(Offset(bounds.left + 1, bounds.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await edgeGesture.up();
      await tester.pumpAndSettle();
      expect(_key('uploader-platform-settings-TIKTOK'), findsOneWidget);
      await tester.tap(_key('uploader-progress-1'));
      await tester.pump();
      expect(_key('uploader-step-motion-1'), findsOneWidget);
      expect(_stepOpacity(tester, 1), lessThan(1));
      expect(row, findsNothing);
      expect(_key('publish-review-confirm'), findsNothing);
      await tester.tap(_key('uploader-progress-3'));
      await tester.pump();
      expect(_key('uploader-step-motion-3'), findsOneWidget);
      expect(_key('uploader-step-motion-1'), findsNothing);
      expect(_key('uploader-caption-field'), findsNothing);
      expect(find.bySemanticsLabel('แคปชั่น'), findsNothing);
      expect(find.text('ยืนยันส่ง 1 ช่องทาง'), findsOneWidget);
      await tester.pumpAndSettle();
      fixture.expectNoSubmission();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'reduced motion ticker suspension and background suppress step effects',
      (tester) async {
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    for (final mode in ['reduced', 'ticker', 'background']) {
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.app(
          reducedMotion: mode == 'reduced', tickerEnabled: mode != 'ticker'));
      await tester.pumpAndSettle();
      if (mode == 'background') {
        await tester.tap(_key('uploader-progress-2'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(_stepOpacity(tester, 2), lessThan(1));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        fixture.expectNoSubmission();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      } else {
        await tester.tap(_key('uploader-progress-2'));
        await tester.pump();
      }
      expect(_key('uploader-step-motion-2'), findsOneWidget, reason: mode);
      expect(_stepOpacity(tester, 2), 1);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      final row = _key('uploader-platform-TIKTOK');
      await _show(tester, row);
      final gesture = await tester.startGesture(tester.getCenter(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final transform = find.descendant(
          of: find
              .ancestor(of: row, matching: find.byType(PostDeePressFeedback))
              .first,
          matching: _key('postdee-press-transform'));
      expect(tester.widget<Transform>(transform).transform.entry(0, 0),
          mode == 'background' ? closeTo(.97, .001) : 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      fixture.expectNoSubmission();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'reducing motion mid transition finishes visible content immediately',
      (tester) async {
    for (final mode in ['reduced', 'ticker']) {
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(_key('uploader-progress-2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_stepOpacity(tester, 2), greaterThan(0));
      expect(_stepOpacity(tester, 2), lessThan(1));
      await tester.pumpWidget(fixture.app(
          reducedMotion: mode == 'reduced', tickerEnabled: mode != 'ticker'));
      expect(_stepOpacity(tester, 2), 1, reason: mode);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      fixture.expectNoSubmission();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      '320dp large text keeps populated stages and final controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app(textScale: 1.8));
    await tester.pumpAndSettle();
    for (var step = 0; step < 4; step++) {
      await goToUploaderStep(tester, step);
      if (step == 0) {
        await _show(tester, _key('uploader-video-metadata'));
        expect(_key('uploader-video-metadata'), findsOneWidget);
      } else if (step == 1) {
        await _show(tester, _key('uploader-caption-field'));
        await tester.enterText(_key('uploader-caption-field'),
            'แคปชันที่เจ้าของร้านเขียนเองและต้องการเก็บไว้');
        await tester.pumpAndSettle();
        await _show(tester, _key('uploader-ai-generate-button'));
        expect(
            _key('uploader-ai-generate-button').hitTestable(), findsOneWidget,
            reason:
                'AI button ${tester.getRect(_key('uploader-ai-generate-button'))} '
                'sticky bar ${tester.getRect(_key('uploader-sticky-action-bar'))} '
                'scroll ${tester.widget<ListView>(_key('uploader-scroll')).controller!.offset}');
      } else if (step == 2) {
        await _selectTikTok(tester);
      } else {
        expect(find.text('ยืนยันส่ง 1 ช่องทาง'), findsOneWidget);
        final button = _key('publish-review-confirm');
        final bounds = tester.getRect(button);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(bounds.bottom, lessThanOrEqualTo(900));
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        await _show(tester, _key('uploader-schedule-later'));
        await tester.tap(_key('uploader-schedule-later'));
        await tester.pumpAndSettle();
        expect(find.text('ยืนยันตั้งเวลา'), findsOneWidget);
      }
      expect(_key('uploader-sticky-summary'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'guided step $step');
    }
    fixture.expectNoSubmission();
  });

  testWidgets(
      'video metadata describes measured dimensions and omits unknown claims',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final metadata = _key('uploader-video-metadata');
    await _show(tester, metadata);
    expect(metadata, findsOneWidget);
    final measured = find.descendant(
        of: metadata, matching: find.byType(Text), matchRoot: true);
    expect(tester.widgetList<Text>(measured).map((t) => t.data ?? '').join(' '),
        matches(RegExp(r'1080\s*[×x]\s*1920')));
    await tester.pumpWidget(const SizedBox.shrink());
    final unknown = _Fixture()..dimensionsKnown = false;
    await tester.pumpWidget(unknown.app());
    await tester.pumpAndSettle();
    await _show(tester, metadata);
    expect(find.textContaining('1080'), findsNothing);
    expect(find.textContaining('1920'), findsNothing);
    expect(find.textContaining('00:15'), findsNothing);
    unknown.expectNoSubmission();
  });
}
