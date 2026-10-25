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
import 'package:postdee_mobile/features/home/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outputDirectory =
      Platform.environment['POSTDEE_HOME_SENDING_PREVIEW_DIR'];

  testWidgets('renders the real Home sending card with local delivery results',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalThemeMode =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    addTearDown(() => AppTheme.applyThemeMode(originalThemeMode));
    final sessionStore = PostDeeAuthSessionStore.instance;
    final originalSession = sessionStore.session;
    addTearDown(() => sessionStore.signIn(originalSession));
    sessionStore.signIn(AuthSession.authenticated(
      userId: 'preview-home-owner',
      idToken: 'preview-local-token',
    ));

    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

    final now = DateTime(2026, 10, 20, 14, 30);
    final post = PostSummaryResult(
      id: 'preview-home-sending',
      caption: 'คลิปใหม่ของร้าน ส่งต่อครบทุกช่องทาง',
      videoS3Key: '',
      platforms: const [
        'TIKTOK',
        'YOUTUBE_SHORTS',
        'INSTAGRAM_REELS',
        // Facebook Reels are published to the connected Page.
        'FACEBOOK_REELS',
      ],
      status: 'PUBLISHING',
      createdAt: now,
      platformResults: const [
        PostPlatformResult(
          postId: 'preview-home-sending',
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT',
        ),
        PostPlatformResult(
          postId: 'preview-home-sending',
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHING',
        ),
        PostPlatformResult(
          postId: 'preview-home-sending',
          platform: 'INSTAGRAM_REELS',
          status: 'FAILED',
        ),
      ],
    );
    final boundaryKey = GlobalKey();
    final homeKey = GlobalKey();
    final card =
        find.byKey(const ValueKey('home-publishing-preview-home-sending'));
    var recentLoads = 0;

    Widget host({bool dark = false, bool reduced = false, double textScale = 1}) {
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      return RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('th'),
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: HomeScreen(
              key: homeKey,
              userName: 'ร้านของเรา',
              now: () => now,
              loadRecentPosts: () async {
                recentLoads++;
                return [post];
              },
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'preview-home-owner',
                plan: 'PRO',
                status: 'ACTIVE',
                remainingPostsThisMonth: 242,
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: true,
              ),
              loadDrafts: () async => [],
              loadConnections: () async => [],
              loadScheduledPosts: () async => [],
              loadLinkProfile: () async => null,
              onCreatePost: () async {},
            ),
          ),
        ),
      );
    }

    Future<void> showCard() async {
      // Home contains several independent asynchronous sections. Use bounded
      // frames because the real sending animation deliberately never settles.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(card, findsOneWidget);
      await Scrollable.ensureVisible(tester.element(card), alignment: .35);
      await tester.pump();
      final bounds = tester.getRect(card);
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(844));
    }

    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          final directory = Directory(outputDirectory!);
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    void expectRealResults() {
      expect(find.text('กำลังส่ง'), findsOneWidget);
      expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
      expect(find.text('Shorts · กำลังส่ง'), findsOneWidget);
      expect(find.text('Reels · ส่งไม่สำเร็จ'), findsOneWidget);
      expect(find.text('Facebook · รอผล'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
          find.byKey(
              const ValueKey('home-publishing-rail-preview-home-sending')),
          findsOneWidget);
      expect(
          find.byKey(
              const ValueKey('home-publishing-channels-preview-home-sending')),
          findsOneWidget);
    }

    await tester.pumpWidget(host());
    await showCard();
    expectRealResults();
    final rotatingIcon = find.descendant(
        of: card, matching: find.byType(RotationTransition));
    final firstPhase =
        tester.widget<RotationTransition>(rotatingIcon.first).turns.value;
    await capture('home-sending-light-frame-1');
    await tester.pump(const Duration(milliseconds: 460));
    expect(tester.widget<RotationTransition>(rotatingIcon.first).turns.value,
        isNot(firstPhase));
    await capture('home-sending-light-frame-2');

    await tester.pumpWidget(host(dark: true));
    await showCard();
    expect(AppTheme.isLightMode, isFalse);
    expectRealResults();
    await capture('home-sending-dark');

    await tester.pumpWidget(host(reduced: true));
    await showCard();
    expect(AppTheme.isLightMode, isTrue);
    expectRealResults();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await capture('home-sending-reduced-motion');

    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpWidget(host(textScale: 2));
    await showCard();
    expectRealResults();
    await capture('home-sending-320-text-200');
    expect(recentLoads, 1,
        reason: 'Preview frames and theme changes must not reload or send.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: outputDirectory == null || outputDirectory.isEmpty);
}
