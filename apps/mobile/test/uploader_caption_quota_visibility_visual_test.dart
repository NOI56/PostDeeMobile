import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/caption_quota_strip.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('caption-quota-visibility-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_captureDirectory.isEmpty) return;
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Widget _app(Widget body, {required bool dark, required double textScale}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: body),
    );

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 150, scrollable: uploaderMainScroll);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previousTheme =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    addTearDown(() => AppTheme.applyThemeMode(previousTheme));
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    sessions.signIn(AuthSession.authenticated(
        userId: 'caption-quota-visual', idToken: 'visual-token'));
  });

  for (final mode in [
    (name: 'starter-dark', plan: 'STARTER', dark: true, advanced: false),
    (name: 'basic-shared-light', plan: 'BASIC', dark: false, advanced: false),
    (
      name: 'basic-advanced-dark-large',
      plan: 'BASIC',
      dark: true,
      advanced: true
    ),
  ]) {
    testWidgets('real-font caption quota visible in ${mode.name}',
        (tester) async {
      final large = mode.advanced;
      final textScale = large ? 1.7 : 1.0;
      tester.view.physicalSize =
          large ? const Size(320, 900) : const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppTheme.applyThemeMode(mode.dark ? ThemeMode.dark : ThemeMode.light);
      await tester.runAsync(() async {
        final fonts = FontLoader('Anuphan');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(
              rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
        }
        await fonts.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      final paid = mode.plan == 'STARTER';
      final subscription = SubscriptionStatusResult(
        userId: 'caption-quota-visual',
        plan: mode.plan,
        status: 'ACTIVE',
        monthlyPostLimit: paid ? 120 : 3,
        usedPostsThisMonth: 0,
        remainingPostsThisMonth: paid ? 120 : 0,
        canSchedule: paid,
        canUseAiCaptions: paid,
        canUseAnalytics: false,
      );
      final quota = RealClipCaptionQuota(
          limit: paid ? 50 : 0,
          usedThisMonth: 12,
          remainingThisMonth: paid ? 38 : 0,
          addonRemaining: paid ? 0 : 8,
          availableGenerations: paid ? 38 : 0);
      var writes = 0;
      await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: _app(
            UploaderScreen(
              fullScreen: true,
              enableRevenueCatBilling: false,
              draftStore:
                  TestPublishDraftStore(ownerUserId: 'caption-quota-visual'),
              loadSubscription: () async => subscription,
              loadPostQuota: () async => subscription,
              loadCaptionQuota: () async =>
                  CaptionQuotaResult(plan: mode.plan, quota: quota),
              loadSocialConnections: () async => const [],
              createUpload: (_) async {
                writes++;
                throw StateError('Quota visibility must not upload');
              },
              generateRealClipCaption: (_) async {
                writes++;
                throw StateError('Quota visibility must not generate');
              },
              createPost: (_) async {
                writes++;
                throw StateError('Quota visibility must not publish');
              },
            ),
            dark: mode.dark,
            textScale: textScale),
      ));
      await tester.pumpAndSettle();
      await goToUploaderStep(tester, 1);
      if (mode.advanced) {
        final toggle =
            find.byKey(const ValueKey('uploader-platform-captions-toggle'));
        await _show(tester, toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        for (final platform in [
          'TIKTOK',
          'YOUTUBE_SHORTS',
          'INSTAGRAM_REELS',
          'FACEBOOK_REELS'
        ]) {
          final target = find.byKey(ValueKey('ai-caption-target-$platform'));
          await _show(tester, target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
      }
      final strip = find.byType(CaptionQuotaStrip);
      await _show(tester, strip);
      expect(find.text('แคปชั่น AI คงเหลือ'), findsOneWidget);
      expect(
          find.text(paid ? '38 / 50 เครดิต' : '0 / 0 เครดิต',
              findRichText: true),
          findsOneWidget);
      expect(find.text('ใช้ไป 12 เครดิต'), findsOneWidget);
      expect(find.text('Starter/Pro'), findsNothing);
      expect(find.textContaining('เครดิตเติม'), findsNothing);
      expect(find.textContaining('เครดิตไม่พอ'), findsNothing);
      if (!paid) {
        expect(find.text('Basic'), findsOneWidget);
        expect(
            find.text('AI แคปชั่นใช้ได้ใน Starter หรือ Pro'), findsOneWidget);
      }
      if (mode.advanced) {
        expect(find.text('สร้างแคปชั่น · 4 เครดิต'), findsOneWidget);
      }
      expect(writes, 0);
      final card = tester.widget<CaptionQuotaStrip>(strip);
      final cardSize = tester.getSize(strip);
      await _capture(tester, 'caption-quota-${mode.name}-page');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      if (_captureDirectory.isNotEmpty) {
        await tester.pumpWidget(_app(
            Center(
                child: RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                  width: cardSize.width, height: cardSize.height, child: card),
            )),
            dark: mode.dark,
            textScale: textScale));
        await tester.pumpAndSettle();
        await _capture(tester, 'caption-quota-${mode.name}-strip');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
