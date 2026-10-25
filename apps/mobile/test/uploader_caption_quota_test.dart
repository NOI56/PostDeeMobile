import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_card.dart';
import 'package:postdee_mobile/features/uploader/caption_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

CaptionQuotaResult _quota(
    {int used = 12, int addon = 0, String plan = 'STARTER'}) {
  final limit = plan == 'BASIC' ? 0 : (plan == 'PRO' ? 120 : 50);
  final remaining = (limit - used).clamp(0, limit);
  return CaptionQuotaResult(
      plan: plan,
      quota: RealClipCaptionQuota(
        limit: limit,
        usedThisMonth: used,
        remainingThisMonth: remaining,
        addonRemaining: addon,
        availableGenerations: plan == 'BASIC' ? 0 : remaining + addon,
      ));
}

RealClipCaptionResult _generated(
        {int used = 13,
        int addon = 0,
        int limit = 50,
        bool refreshPending = false}) =>
    RealClipCaptionResult.fromJson({
      'caption': 'แคปชั่นใหม่',
      'captionOptions': <String>[],
      'hooks': <String>[],
      'hashtags': <String>[],
      'seoKeywords': <String>[],
      'searchTitle': '',
      'source': {
        'videoS3Key': 'uploads/owner-a/clip.mp4',
        'mode': 'AUDIO_ONLY',
        'selectedFrameCount': 0
      },
      'quota': {
        'limit': limit,
        'usedThisMonth': used,
        'remainingThisMonth': (limit - used).clamp(0, limit),
        'addonRemaining': addon,
        'availableGenerations': (limit - used).clamp(0, limit) + addon,
        'usageRefreshPending': refreshPending,
      },
      'platformCaptions': {
        for (final platform in _platforms)
          platform: {'caption': 'แคปชั่น $platform', 'hashtags': <String>[]}
      },
    });

const _action = ValueKey('uploader-ai-generate-button');
const _platforms = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS',
];

Future<void> _show(WidgetTester tester, Finder target) async {
  if (find.byKey(const ValueKey('uploader-step-caption')).evaluate().isEmpty) {
    await goToUploaderStep(tester, 1);
  }
  await tester.scrollUntilVisible(target, 200, scrollable: uploaderMainScroll);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tick(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _advanced(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('uploader-platform-captions-toggle'));
  await _show(tester, toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _targets(WidgetTester tester, List<String> platforms) async {
  for (final platform in _platforms) {
    final target = find.byKey(ValueKey('ai-caption-target-$platform'));
    if (tester.widget<FilterChip>(target).selected !=
        platforms.contains(platform)) {
      await _show(tester, target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
  }
  await _show(tester, find.byKey(_action));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
  });

  Future<void> pumpUploader(
    WidgetTester tester, {
    required UploaderCaptionQuotaLoader loadQuota,
    UploaderRealClipCaptionGenerator? generate,
    UploaderUploadCreator? createUpload,
  }) async {
    final directory =
        Directory.systemTemp.createTempSync('caption-quota-main-');
    final file = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: UploaderScreen(
          loadCaptionQuota: loadQuota,
          draftStore: TestPublishDraftStore(ownerUserId: 'owner-a'),
          probePublishMedia: probeValidPublishMedia,
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          initialVideoPath: file.path,
          initialVideoName: 'clip.mp4',
          initialVideoSizeBytes: 512,
          initialVideoWidth: 1080,
          initialVideoHeight: 1920,
          loadSocialConnections: () async => const [],
          enableRevenueCatBilling: false,
          loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'owner-a',
              plan: 'STARTER',
              status: 'ACTIVE',
              canUseAiCaptions: true,
              canSchedule: true,
              canUseAnalytics: false),
          createUpload: createUpload ??
              (_) async => const UploadResult(
                  id: 'clip',
                  videoS3Key: 'uploads/owner-a/clip.mp4',
                  storageProvider: 'mock'),
          uploadVideoFile: (_, __) async {},
          generateRealClipCaption: generate ?? (_) async => _generated(),
        ))));
    await tester.pumpAndSettle();
  }

  CaptionQuotaStrip strip(WidgetTester tester) =>
      tester.widget<CaptionQuotaStrip>(find.byType(CaptionQuotaStrip));

  testWidgets('selected channel count quotes four, two and no caption credits',
      (tester) async {
    await pumpUploader(tester, loadQuota: () async => _quota());
    await _advanced(tester);
    await _targets(tester, _platforms);
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).label,
        'สร้างแคปชั่น · 4 เครดิต');
    await _targets(tester, _platforms.take(2).toList());
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).label,
        'สร้างแคปชั่น · 2 เครดิต');
    await _targets(tester, []);
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNull);
  });

  testWidgets('four channels apply the server balance from 107 to 103',
      (tester) async {
    GenerateRealClipCaptionRequest? request;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 13, plan: 'PRO'),
        generate: (value) async {
          request = value;
          return _generated(used: 17, limit: 120);
        });
    await _advanced(tester);
    await _targets(tester, _platforms);
    expect(strip(tester).quota.remainingThisMonth, 107);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(request!.toJson()['expectedCredits'], 4);
    expect(request!.platforms, _platforms);
    expect(strip(tester).quota.remainingThisMonth, 103);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
  });

  testWidgets('four purchased credits cover four channels with monthly zero',
      (tester) async {
    GenerateRealClipCaptionRequest? request;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 50, addon: 4),
        generate: (value) async {
          request = value;
          return _generated(used: 50);
        });
    await _advanced(tester);
    await _targets(tester, _platforms);
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNotNull);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(request!.toJson()['expectedCredits'], 4);
    expect(strip(tester).quota.addonRemaining, 0);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
  });

  testWidgets('three credits block four channels before upload and allow three',
      (tester) async {
    var uploads = 0;
    final requests = <GenerateRealClipCaptionRequest>[];
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 49, addon: 2),
        createUpload: (_) async {
          uploads++;
          return const UploadResult(id: 'clip',
              videoS3Key: 'uploads/owner-a/clip.mp4', storageProvider: 'mock');
        },
        generate: (request) async {
          requests.add(request);
          return _generated(used: 50);
        });
    await _advanced(tester);
    await _targets(tester, _platforms.take(3).toList());
    final earlierAction =
        tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed!;
    await _targets(tester, _platforms);
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNull);
    expect(find.textContaining('เครดิตไม่พอ'), findsOneWidget);
    expect(find.textContaining('ลดช่องทาง'), findsOneWidget);
    await tester.tap(find.byKey(_action));
    earlierAction();
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(requests, isEmpty);
    await _targets(tester, _platforms.take(3).toList());
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNotNull);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(requests.single.toJson()['expectedCredits'], 3);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
  });

  testWidgets('shared caption confirms one credit and cost rejection reloads quota',
      (tester) async {
    var reads = 0;
    GenerateRealClipCaptionRequest? request;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: ++reads == 1 ? 12 : 13),
        generate: (value) async {
          request = value;
          throw const ApiException('cost confirmation required', statusCode: 409,
              code: 'AI_CAPTION_COST_CONFIRMATION_REQUIRED');
        });
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(request!.toJson()['expectedCredits'], 1);
    expect(request!.platforms, isEmpty);
    expect(reads, 2);
    expect(strip(tester).quota.remainingThisMonth, 37);
    expect(find.textContaining('ตรวจสอบช่องทาง'), findsOneWidget);
  });

  testWidgets('loads real quota and places compact strip above the AI action',
      (tester) async {
    var reads = 0;
    await pumpUploader(tester, loadQuota: () async {
      reads++;
      return _quota();
    });
    await _show(tester, find.byType(CaptionQuotaStrip));
    expect(reads, 1);
    expect(strip(tester).quota.remainingThisMonth, 38);
    expect(tester.getBottomLeft(find.byType(CaptionQuotaStrip)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(_action)).dy));
  });

  testWidgets(
      'unknown quota shows loading and failure retry instead of fake zero',
      (tester) async {
    final initial = Completer<CaptionQuotaResult>();
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () =>
            ++reads == 1 ? initial.future : Future.value(_quota()));
    await _show(
        tester, find.byKey(const ValueKey('uploader-ai-quota-loading')));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    initial.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const ValueKey('uploader-ai-quota-retry')));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-ai-quota-retry')));
    await tester.pumpAndSettle();
    expect(strip(tester).quota.remainingThisMonth, 38);
  });

  testWidgets(
      'generation updates quota even when text was edited during request',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    await pumpUploader(tester,
        loadQuota: () async => _quota(), generate: (_) => gate.future);
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await _tick(tester);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    tester.widget<TextField>(field).controller!.text = 'ข้อความที่เขียนเอง';
    gate.complete(_generated());
    await tester.pumpAndSettle();
    expect(strip(tester).quota.remainingThisMonth, 37);
    expect(
        tester.widget<TextField>(field).controller!.text, 'ข้อความที่เขียนเอง');
  });

  testWidgets('late initial read cannot replace generation balance',
      (tester) async {
    final initial = Completer<CaptionQuotaResult>();
    await pumpUploader(tester, loadQuota: () => initial.future);
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await _tick(tester);
    initial.complete(_quota());
    await tester.pumpAndSettle();
    expect(strip(tester).quota.remainingThisMonth, 37);
  });

  testWidgets('failed generation rereads actual quota', (tester) async {
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: ++reads == 1 ? 12 : 13),
        generate: (_) async =>
            throw const ApiException('provider failed', statusCode: 502));
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(strip(tester).quota.remainingThisMonth, 37);
  });

  testWidgets('monthly exhaustion still allows spending purchased credits',
      (tester) async {
    var generations = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 50, addon: 8),
        generate: (_) async {
          generations++;
          return _generated(used: 50, addon: 7);
        });
    await _show(tester, find.byKey(_action));
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNotNull);
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(generations, 1);
    expect(strip(tester).quota.addonRemaining, 7);
  });

  testWidgets('exhausted total disables AI without blocking manual caption',
      (tester) async {
    await pumpUploader(tester, loadQuota: () async => _quota(used: 50));
    await _show(tester, find.byKey(_action));
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNull);
    final field = find.byKey(const ValueKey('uploader-caption-field'));
    await _show(tester, field);
    await tester.enterText(field, 'เขียนเองได้');
    expect(tester.widget<TextField>(field).controller!.text, 'เขียนเองได้');
  });

  testWidgets('Basic is not shown as an exhausted paid package',
      (tester) async {
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: 0, plan: 'BASIC', addon: 8));
    await _show(tester, find.byKey(_action));
    expect(find.byType(CaptionQuotaStrip), findsNothing);
    expect(tester.widget<PostDeeGradientButton>(find.byKey(_action)).onPressed,
        isNotNull);
  });

  testWidgets('account replacement discards old balance and late generation',
      (tester) async {
    final gate = Completer<RealClipCaptionResult>();
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () async => _quota(used: ++reads == 1 ? 12 : 2),
        generate: (_) => gate.future);
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await _tick(tester);
    PostDeeAuthSessionStore.instance.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    await tester.pumpAndSettle();
    gate.complete(_generated());
    await tester.pumpAndSettle();
    expect(strip(tester).quota.remainingThisMonth, 48);
  });

  testWidgets('canceling platform preview keeps the updated usage',
      (tester) async {
    await pumpUploader(tester, loadQuota: () async => _quota());
    final toggle =
        find.byKey(const ValueKey('uploader-platform-captions-toggle'));
    await _show(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('ai-caption-target-TIKTOK'));
    await _show(tester, target);
    if (!tester.widget<FilterChip>(target).selected) {
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-platform-ai-preview')),
        findsOneWidget);
    expect(strip(tester).quota.remainingThisMonth, 37);
    await tester.tap(find.byTooltip('กลับไปเขียนเอง'));
    await tester.pumpAndSettle();
    expect(strip(tester).quota.remainingThisMonth, 37);
  });

  testWidgets('refund with pending usage refresh rereads authoritative balance',
      (tester) async {
    var reads = 0;
    await pumpUploader(tester,
        loadQuota: () async {
          reads++;
          return _quota();
        },
        generate: (_) async => _generated(refreshPending: true));
    await _show(tester, find.byKey(_action));
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(strip(tester).quota.remainingThisMonth, 38);
  });

  testWidgets(
      'same account signed in again cannot receive an earlier session read',
      (tester) async {
    var reads = 0;
    final firstRead = Completer<CaptionQuotaResult>();
    await pumpUploader(tester,
        loadQuota: () =>
            ++reads == 1 ? firstRead.future : Future.value(_quota(used: 2)));
    PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
        userId: 'owner-a', idToken: 'another-sign-in'));
    await tester.pumpAndSettle();
    firstRead.complete(_quota());
    await tester.pumpAndSettle();
    await _show(tester, find.byType(CaptionQuotaStrip));
    expect(strip(tester).quota.remainingThisMonth, 48);
  });

  testWidgets('app resume refreshes the quota', (tester) async {
    var reads = 0;
    await pumpUploader(tester, loadQuota: () async => _quota(used: ++reads));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
  });
}
