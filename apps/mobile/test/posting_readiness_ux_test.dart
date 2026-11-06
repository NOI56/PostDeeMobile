import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _owner = 'readiness-owner';

SubscriptionStatusResult _plan(
        {String plan = 'STARTER', bool phoneGate = false}) =>
    SubscriptionStatusResult(
      userId: _owner,
      plan: plan,
      status: 'ACTIVE',
      monthlyPostLimit: plan == 'BASIC' ? 3 : 120,
      usedPostsThisMonth: 0,
      remainingPostsThisMonth: phoneGate ? 0 : (plan == 'BASIC' ? 3 : 120),
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: false,
      phoneVerified: !phoneGate,
      requiresPhoneVerification: phoneGate,
    );

CaptionQuotaResult _captionQuota(String plan) => CaptionQuotaResult(
    plan: plan,
    quota: RealClipCaptionQuota(
      limit: plan == 'BASIC' ? 0 : 50,
      usedThisMonth: 0,
      remainingThisMonth: plan == 'BASIC' ? 0 : 50,
      availableGenerations: plan == 'BASIC' ? 0 : 50,
    ));

const _connected = [
  SocialConnectionResult(
      platform: 'TIKTOK', connected: true, externalAccountId: 'tiktok-seller'),
];

class _Counts {
  int quotaReads = 0;
  int phoneVerifications = 0;
  int paywallOpens = 0;
  int uploads = 0;
  int generations = 0;
}

Future<void> _openAiCardForTest(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final toggle = find.byKey(const ValueKey('uploader-ai-card-toggle'));
  await tester.scrollUntilVisible(toggle, 160, scrollable: uploaderMainScroll);
  await Scrollable.ensureVisible(tester.element(toggle), alignment: .5);
  await tester.pumpAndSettle();
  final content = find.byKey(const ValueKey('uploader-ai-card-content'),
      skipOffstage: false);
  if (tester.widget<Offstage>(content).offstage) {
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
}

void main() {
  late Directory directory;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: _owner, idToken: 'token-a'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    directory = Directory.systemTemp.createTempSync('posting-readiness-');
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  PickedVideoFile clip({int width = 1080, int height = 1920}) {
    final file = File('${directory.path}/clip-${width}x$height.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    return PickedVideoFile(
        name: 'clip-${width}x$height.mp4',
        path: file.path,
        sizeBytes: 512,
        width: width,
        height: height);
  }

  Future<_Counts> pump(
    WidgetTester tester, {
    PickedVideoFile? initialClip,
    PickedVideoFile? picked,
    SubscriptionStatusResult? plan,
    CaptionQuotaResult? captionQuota,
    UploaderConnectionsLoader? loadConnections,
    bool withVerifyPhone = true,
    Locale locale = const Locale('th'),
    double width = 430,
    double textScale = 1,
  }) async {
    final counts = _Counts();
    final subscription = plan ?? _plan();
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: UploaderScreen(
          draftStore: TestPublishDraftStore(ownerUserId: _owner),
          enableRevenueCatBilling: false,
          initialVideoPath: initialClip?.path,
          initialVideoName: initialClip?.name,
          initialVideoSizeBytes: initialClip?.sizeBytes,
          initialVideoWidth: initialClip?.width,
          initialVideoHeight: initialClip?.height,
          pickVideo: () async => picked,
          probePublishMedia: probeValidPublishMedia,
          loadTemplates: () async => const [],
          loadSubscription: () async => subscription,
          loadPostQuota: () async {
            counts.quotaReads++;
            return subscription;
          },
          loadCaptionQuota: () async =>
              captionQuota ?? _captionQuota(subscription.plan),
          loadSocialConnections: loadConnections ?? () async => _connected,
          loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
          verifyPhone: withVerifyPhone
              ? (_) async => counts.phoneVerifications++
              : null,
          openPaywall: (_) async => counts.paywallOpens++,
          createUpload: (_) async {
            counts.uploads++;
            throw StateError('Readiness checks must not upload');
          },
          uploadVideoFile: (_, __) async {},
          generateRealClipCaption: (_) async {
            counts.generations++;
            throw StateError('Readiness checks must not spend AI credits');
          },
        ))));
    await tester.pumpAndSettle();
    return counts;
  }

  Future<void> show(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 120, scrollable: uploaderMainScroll);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  group('clip ratio', () {
    testWidgets('a landscape clip is flagged on the clip step, not at submit',
        (tester) async {
      await pump(tester, picked: clip(width: 1920, height: 1080));
      final picker = find.byKey(const ValueKey('uploader-video-preview-picker'));
      await show(tester, picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();

      // Inspect the preview badge before scrolling it outside ListView's
      // cache to read the inline warning and the duration guide below it.
      expect(find.byKey(const ValueKey('uploader-video-ratio-warning')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('uploader-video-ratio-ok')),
          findsNothing);
      final warning = find.byKey(const ValueKey('uploader-aspect-warning'));
      await show(tester, warning);
      expect(
          find.descendant(
              of: warning,
              matching: find.textContaining('ไม่ใช่แนวตั้ง 9:16')),
          findsOneWidget);
      // AI captions accept any ratio, so the seller can still continue.
      await goToUploaderStep(tester, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a vertical clip shows no ratio warning', (tester) async {
      await pump(tester, initialClip: clip());
      expect(find.byKey(const ValueKey('uploader-aspect-warning')),
          findsNothing);
      expect(find.byKey(const ValueKey('uploader-video-ratio-ok')),
          findsOneWidget);
    });

    testWidgets('the ratio warning is translated to English', (tester) async {
      await pump(tester,
          initialClip: clip(width: 1280, height: 720),
          locale: const Locale('en'));
      final warning = find.byKey(const ValueKey('uploader-aspect-warning'));
      await show(tester, warning);
      expect(
          find.descendant(
              of: warning, matching: find.textContaining('not vertical 9:16')),
          findsOneWidget);
    });
  });

  group('posting checklist', () {
    testWidgets('lists phone and channel blockers with direct actions',
        (tester) async {
      final counts = await pump(tester,
          initialClip: clip(),
          plan: _plan(plan: 'BASIC', phoneGate: true),
          loadConnections: () async => const []);
      final checklist =
          find.byKey(const ValueKey('uploader-posting-checklist'));
      await show(tester, checklist);
      expect(find.byKey(const ValueKey('uploader-checklist-verify-phone')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('uploader-checklist-connect')),
          findsOneWidget);
      expect(counts.quotaReads, 1);

      final verify =
          find.byKey(const ValueKey('uploader-checklist-verify-phone-button'));
      await show(tester, verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(counts.phoneVerifications, 1);
      // The quota is read again, so a verified phone unlocks it at once.
      expect(counts.quotaReads, 2);
      expect(
          find.byKey(const ValueKey('uploader-checklist-connect-button')),
          findsOneWidget);
      expect(counts.uploads, 0);
    });

    testWidgets('fits a narrow screen with large text', (tester) async {
      await pump(tester,
          initialClip: clip(),
          plan: _plan(plan: 'BASIC', phoneGate: true),
          loadConnections: () async => const [],
          width: 320,
          textScale: 2);
      final connect =
          find.byKey(const ValueKey('uploader-checklist-connect-button'));
      await show(tester, connect);
      expect(connect, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays hidden when the account can already post',
        (tester) async {
      await pump(tester, initialClip: clip());
      expect(find.byKey(const ValueKey('uploader-posting-checklist')),
          findsNothing);
    });

    testWidgets('a failed channel lookup is not reported as not connected',
        (tester) async {
      await pump(tester,
          initialClip: clip(),
          loadConnections: () async => throw StateError('offline'));
      expect(find.byKey(const ValueKey('uploader-checklist-connect')),
          findsNothing);
    });

    testWidgets('without a phone flow the row points to the Account tab',
        (tester) async {
      await pump(tester,
          initialClip: clip(),
          plan: _plan(plan: 'BASIC', phoneGate: true),
          withVerifyPhone: false);
      final row = find.byKey(const ValueKey('uploader-checklist-verify-phone'));
      await show(tester, row);
      expect(
          find.byKey(const ValueKey('uploader-checklist-verify-phone-button')),
          findsNothing);
      expect(find.descendant(of: row, matching: find.textContaining('บัญชี')),
          findsOneWidget);
    });

    testWidgets('checklist copy is translated to English', (tester) async {
      await pump(tester,
          initialClip: clip(),
          plan: _plan(plan: 'BASIC', phoneGate: true),
          loadConnections: () async => const [],
          locale: const Locale('en'));
      final checklist =
          find.byKey(const ValueKey('uploader-posting-checklist'));
      await show(tester, checklist);
      expect(find.text('Before you can post'), findsOneWidget);
      expect(find.text('Verify your phone number'), findsOneWidget);
      expect(find.text('Connect at least 1 social account'), findsOneWidget);
    });

    for (final locale in const [Locale('th'), Locale('en')]) {
      testWidgets(
          'channels step omits the duplicate connect button in ${locale.languageCode}',
          (tester) async {
        await pump(tester,
            initialClip: clip(),
            loadConnections: () async => const [],
            locale: locale);
        await goToUploaderStep(tester, 2);
        final status = find.text(locale.languageCode == 'en'
            ? 'No channels connected'
            : 'ยังไม่ได้เชื่อมต่อช่องทาง');
        await show(tester, status);
        expect(status, findsOneWidget);
        expect(find.byKey(const ValueKey('uploader-connect-platforms-button')),
            findsNothing);
        expect(find.text('เชื่อมต่อช่องทาง'), findsNothing);
        expect(find.text('Connect channels'), findsNothing);
        expect(find.textContaining('TikTok, YouTube Shorts'), findsOneWidget);
        final statusAction = tester.widget<GestureDetector>(find
            .ancestor(of: status, matching: find.byType(GestureDetector))
            .first);
        expect(statusAction.onTap, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AI caption access', () {
    testWidgets('Basic sees an upgrade action that opens packages',
        (tester) async {
      final counts = await pump(tester,
          initialClip: clip(), plan: _plan(plan: 'BASIC'));
      await goToUploaderStep(tester, 1);
      await _openAiCardForTest(tester);
      final action = find.byKey(const ValueKey('uploader-ai-generate-button'));
      await show(tester, action);
      expect(find.descendant(of: action, matching: find.text('ดูแพ็กเกจเพื่อใช้ AI')),
          findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(counts.paywallOpens, 1);
      expect(counts.uploads, 0);
      expect(counts.generations, 0);
      expect(find.textContaining('กรุณาตรวจสอบแพ็กเกจของคุณ'), findsNothing);
    });

    testWidgets('paid plans keep the generate action', (tester) async {
      await pump(tester, initialClip: clip());
      await goToUploaderStep(tester, 1);
      await _openAiCardForTest(tester);
      final action = find.byKey(const ValueKey('uploader-ai-generate-button'));
      await show(tester, action);
      expect(
          find.descendant(
              of: action, matching: find.text('สร้างแคปชั่น · 1 เครดิต')),
          findsOneWidget);
    });

    testWidgets('style summary names the style once instead of Auto x3',
        (tester) async {
      await pump(tester, initialClip: clip());
      await goToUploaderStep(tester, 1);
      await _openAiCardForTest(tester);
      final summary = find.byKey(const ValueKey('uploader-ai-style-summary'));
      await show(tester, summary);
      expect(tester.widget<Text>(summary).data, 'สไตล์: อัตโนมัติ');
      expect(find.textContaining('อัตโนมัติ · อัตโนมัติ'), findsNothing);
    });
  });
}
