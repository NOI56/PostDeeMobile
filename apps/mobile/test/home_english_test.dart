import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_publishing_motion.dart';

final _now = DateTime.utc(2026, 10, 27, 9);
const _plan = SubscriptionStatusResult(
  userId: 'english-home-owner',
  plan: 'BASIC',
  status: 'ACTIVE',
  monthlyPostLimit: 3,
  remainingPostsThisMonth: 3,
  canSchedule: false,
  canUseAiCaptions: false,
  canUseAnalytics: false,
);

PostSummaryResult _post({
  String status = 'PUBLISHED',
  String caption = 'Product video',
  DateTime? createdAt,
  DateTime? scheduledAt,
  List<String> platforms = const ['YOUTUBE_SHORTS'],
  List<PostPlatformResult> results = const [],
}) =>
    PostSummaryResult(
      id: 'english-post',
      caption: caption,
      videoS3Key: '',
      platforms: platforms,
      status: status,
      createdAt: createdAt ?? _now,
      scheduledAt: scheduledAt,
      platformResults: results,
    );

HomeScreen _home({
  HomeSubscriptionLoader? subscription,
  HomeRecentPostsLoader? posts,
}) =>
    HomeScreen(
      key: const ValueKey('english-home'),
      loadSubscription: subscription ?? () async => _plan,
      loadRecentPosts: posts ?? () async => [],
      loadDrafts: () async => [],
      loadConnections: () async => [],
      loadScheduledPosts: () async => [],
      loadLinkProfile: () async => null,
      onCreatePost: () async {},
      now: () => _now,
    );

Widget _app(
  HomeScreen home, {
  Locale locale = const Locale('en'),
  double scale = 1,
  bool dark = false,
}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: locale,
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
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: Scaffold(body: home),
  );
}

void _expectEnglishInterface(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'english-home-owner', idToken: 'fixture-token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English Home includes its empty state and accessible actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_home()));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Latest posts'), findsOneWidget);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('3/3 units left'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^User account\b')), findsOneWidget);
    _expectEnglishInterface(tester);
    semantics.dispose();
  });

  for (final entry in const {
    'PUBLISHED': 'Published',
    'PARTIAL_PUBLISHED': 'Partially delivered',
    'PUBLISHING': 'Sending',
    'FAILED': 'Failed',
    'QUEUED': 'Queued',
  }.entries) {
    testWidgets(
        'English Home translates ${entry.key} without changing sending state',
        (tester) async {
      await tester.pumpWidget(
          _app(_home(posts: () async => [_post(status: entry.key)])));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      final motion = tester.widget<PostDeePublishingMotion>(
          find.byKey(const ValueKey('home-publishing-english-post')));
      expect(motion.sending, entry.key == 'PUBLISHING');
      _expectEnglishInterface(tester);
    });
  }

  for (final entry in const {
    'DRAFT': 'Sent as draft',
    'PRIVATE': 'Private',
    'UNLISTED': 'Unlisted',
    'LIVE': 'Published',
    'FUTURE_PROVIDER_OUTCOME': 'Delivery unconfirmed',
  }.entries) {
    testWidgets('English Home keeps ${entry.key} delivery distinct',
        (tester) async {
      await tester.pumpWidget(_app(_home(
          posts: () async => [
                _post(results: [
                  PostPlatformResult(
                      postId: 'english-post',
                      platform: 'YOUTUBE_SHORTS',
                      status: 'PUBLISHED',
                      deliveryOutcome: entry.key),
                ])
              ])));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 'FUTURE_PROVIDER_OUTCOME') {
        expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
      }
      _expectEnglishInterface(tester);
    });
  }

  testWidgets(
      'English sending row keeps draft outcomes and unanswered channels distinct',
      (tester) async {
    await tester.pumpWidget(_app(_home(
        posts: () async => [
              _post(
                status: 'PUBLISHING',
                platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
                results: const [
                  PostPlatformResult(
                      postId: 'english-post',
                      platform: 'TIKTOK',
                      status: 'PUBLISHED',
                      deliveryOutcome: 'DRAFT'),
                ],
              )
            ])));
    await tester.pumpAndSettle();
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('TikTok · Sent as draft'), findsOneWidget);
    expect(find.text('Shorts · Awaiting result'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-publishing-rail-english-post')),
        findsOneWidget);
    _expectEnglishInterface(tester);
  });

  testWidgets('unconfirmed English delivery never starts the sending animation',
      (tester) async {
    await tester.pumpWidget(_app(_home(
        posts: () async => [
              _post(
                status: 'PUBLISHING',
                results: const [
                  PostPlatformResult(
                      postId: 'english-post',
                      platform: 'YOUTUBE_SHORTS',
                      status: 'PUBLISHED',
                      deliveryOutcome: 'UNKNOWN'),
                ],
              )
            ])));
    await tester.pumpAndSettle();
    expect(find.text('Delivery unconfirmed'), findsOneWidget);
    expect(
        tester
            .widget<PostDeePublishingMotion>(
                find.byKey(const ValueKey('home-publishing-english-post')))
            .sending,
        isFalse);
    expect(find.byKey(const ValueKey('home-publishing-rail-english-post')),
        findsNothing);
  });

  for (final entry in <Duration, String>{
    const Duration(days: 2): '2 days ago',
    const Duration(hours: 1): '1 hour ago',
    const Duration(minutes: 1): '1 minute ago',
    Duration.zero: 'Just now',
    const Duration(days: -2): 'in 2 days',
    const Duration(minutes: -1): 'in 1 minute',
  }.entries) {
    testWidgets('English Home formats relative time: ${entry.value}',
        (tester) async {
      await tester.pumpWidget(_app(_home(
          posts: () async => [
                _post(
                  caption: '',
                  platforms: [],
                  createdAt: _now.subtract(entry.key),
                )
              ])));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsNWidgets(2));
      _expectEnglishInterface(tester);
    });
  }

  for (final error in <Object>[
    const ApiException('<html>Gateway error</html>', statusCode: 503),
    const ApiException('token expired', statusCode: 401),
    const ApiException('too many requests', statusCode: 429),
    const ApiException('ข้อความตรวจสอบจากเซิร์ฟเวอร์', statusCode: 400),
    const SocketException('offline'),
    TimeoutException('slow response'),
  ]) {
    testWidgets(
        'English subscription failure stays English: ${error.runtimeType} $error',
        (tester) async {
      await tester
          .pumpWidget(_app(_home(subscription: () async => throw error)));
      await tester.pumpAndSettle();
      expect(find.text('Could not check package'), findsOneWidget);
      expect(find.text('Free package'), findsNothing);
      expect(find.byKey(const ValueKey('home-plan-retry')), findsOneWidget);
      _expectEnglishInterface(tester);
    });
  }

  testWidgets(
      'changing language updates existing errors without fetching again',
      (tester) async {
    var planReads = 0;
    var postReads = 0;
    final home = _home(subscription: () async {
      planReads++;
      throw const ApiException('gateway', statusCode: 503);
    }, posts: () async {
      postReads++;
      throw StateError('offline');
    });
    await tester.pumpWidget(_app(home, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โหลดโพสต์ล่าสุดไม่สำเร็จ'), findsOneWidget);
    await tester.pumpWidget(_app(home));
    await tester.pumpAndSettle();
    expect(find.text('Could not load latest posts'), findsOneWidget);
    expect(planReads, 1);
    expect(postReads, 1);
    _expectEnglishInterface(tester);
    await tester.pumpWidget(_app(home, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โหลดโพสต์ล่าสุดไม่สำเร็จ'), findsOneWidget);
  });

  testWidgets('English Home preserves the users Thai caption', (tester) async {
    const caption = 'แคปชันที่ผู้ใช้เขียนเอง';
    await tester
        .pumpWidget(_app(_home(posts: () async => [_post(caption: caption)])));
    await tester.pumpAndSettle();
    expect(find.text(caption), findsOneWidget);
    expect(find.text('Published'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English status cards fit a narrow display with large text, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(
          _home(posts: () async => [_post(status: 'PARTIAL_PUBLISHED')]),
          scale: 1.6,
          dark: dark));
      await tester.pumpAndSettle();
      expect(find.text('Partially delivered'), findsOneWidget);
      _expectEnglishInterface(tester);
    });
  }
}
