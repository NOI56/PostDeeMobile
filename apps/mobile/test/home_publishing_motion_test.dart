import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_publishing_motion.dart';

PostSummaryResult _post({
  String status = 'PUBLISHING',
  List<String> platforms = const ['TIKTOK', 'YOUTUBE_SHORTS'],
  List<PostPlatformResult> results = const [
    PostPlatformResult(
      postId: 'sending-post',
      platform: 'TIKTOK',
      status: 'PUBLISHED',
      deliveryOutcome: 'DRAFT',
    ),
  ],
}) =>
    PostSummaryResult(
      id: 'sending-post',
      caption: 'คลิปของร้าน',
      videoS3Key: '',
      platforms: platforms,
      status: status,
      platformResults: results,
      createdAt: DateTime.utc(2026, 10, 18),
    );

Widget _app({
  required Future<List<PostSummaryResult>> Function() loader,
  bool active = true,
  double textScale = 1,
  bool reducedMotion = false,
  bool tickerEnabled = true,
}) =>
    MaterialApp(
      locale: const Locale('th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: Scaffold(
        body: HomeScreen(
          isActive: active,
          loadRecentPosts: loader,
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'sending-owner',
            plan: 'PRO',
            status: 'ACTIVE',
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
    );

Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _resume(TestWidgetsFlutterBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  setUp(() {
    _resume(TestWidgetsFlutterBinding.ensureInitialized());
    PostDeeAuthSessionStore.instance.signIn(
      AuthSession.authenticated(
        userId: 'sending-owner',
        idToken: 'sending-test-token',
      ),
    );
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    _resume(TestWidgetsFlutterBinding.ensureInitialized());
  });

  testWidgets('publishing card keeps sending until every channel is confirmed',
      (tester) async {
    await tester.pumpWidget(_app(loader: () async => [_post()]));
    await _load(tester);
    expect(find.text('กำลังส่ง'), findsOneWidget);
    expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('Shorts · รอผล'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('postdee-publishing-rail')), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('foreground polling stops sending after the real result arrives',
      (tester) async {
    var calls = 0;
    var current = _post();
    Future<List<PostSummaryResult>> load() async {
      calls++;
      return [current];
    }

    await tester.pumpWidget(_app(loader: load));
    await _load(tester);
    expect(calls, 1);
    current = _post(status: 'PUBLISHED', results: const [
      PostPlatformResult(
        postId: 'sending-post',
        platform: 'TIKTOK',
        status: 'PUBLISHED',
        deliveryOutcome: 'DRAFT',
      ),
      PostPlatformResult(
        postId: 'sending-post',
        platform: 'YOUTUBE_SHORTS',
        status: 'PUBLISHED',
        deliveryOutcome: 'LIVE',
      ),
    ]);
    await tester.pump(const Duration(seconds: 30));
    await _load(tester);
    expect(calls, 2);
    expect(find.text('กำลังส่ง'), findsNothing);
    expect(find.text('ส่งสำเร็จ'), findsOneWidget);
    expect(find.byKey(const ValueKey('postdee-publishing-rail')), findsNothing);
    await tester.pump(const Duration(seconds: 65));
    await _load(tester);
    expect(calls, 2, reason: 'Terminal posts must not retain a poll timer.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('sending feedback follows the calendar badge rail channel order',
      (tester) async {
    await tester.pumpWidget(_app(loader: () async => [_post()]));
    await _load(tester);
    final card = find.byKey(const ValueKey('home-publishing-sending-post'));
    final badge = find.descendant(
        of: card, matching: find.byType(PostDeePublishingBadge));
    final rail = find.byKey(const ValueKey('home-publishing-rail-sending-post'));
    final channels =
        find.byKey(const ValueKey('home-publishing-channels-sending-post'));
    expect(rail, findsOneWidget);
    expect(channels, findsOneWidget);
    expect(tester.getTopLeft(badge).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('คลิปของร้าน')).dy));
    expect(tester.getTopLeft(rail).dy, greaterThan(tester.getBottomLeft(badge).dy));
    expect(tester.getBottomLeft(rail).dy, lessThan(tester.getTopLeft(channels).dy));
    expect(tester.getTopLeft(rail).dx,
        greaterThanOrEqualTo(tester.getTopLeft(card).dx + 9));
    expect(tester.getTopRight(rail).dx,
        lessThanOrEqualTo(tester.getTopRight(card).dx - 9));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('sending layout gives caption space without duplicate channel names',
      (tester) async {
    await tester.pumpWidget(_app(loader: () async => [_post()]));
    await _load(tester);
    expect(tester.widget<Text>(find.text('คลิปของร้าน')).maxLines, 2);
    expect(find.text('TikTok · YouTube Shorts'), findsNothing);
    expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('Shorts · รอผล'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('mixed outcomes share one activity clock across ordinary rebuilds',
      (tester) async {
    final post = _post(platforms: const [
      'TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS',
    ], results: const [
      PostPlatformResult(postId: 'sending-post', platform: 'TIKTOK',
          status: 'PUBLISHED', deliveryOutcome: 'DRAFT'),
      PostPlatformResult(postId: 'sending-post', platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHING'),
      PostPlatformResult(postId: 'sending-post', platform: 'FACEBOOK_REELS',
          status: 'FAILED'),
    ]);
    var reads = 0;
    Future<List<PostSummaryResult>> load() async {
      reads++;
      return [post];
    }
    await tester.pumpWidget(_app(loader: load));
    await _load(tester);
    final card = find.byKey(const ValueKey('home-publishing-sending-post'));
    final rotations = find.descendant(
        of: card, matching: find.byType(RotationTransition));
    expect(rotations, findsNWidgets(2));
    final clock = tester.widget<RotationTransition>(rotations.first).turns;
    expect(identical(clock,
        tester.widget<RotationTransition>(rotations.last).turns), isTrue);
    final phase = clock.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(clock.value, isNot(phase));
    final advanced = clock.value;
    await tester.pumpWidget(_app(loader: load));
    expect(identical(clock,
        tester.widget<RotationTransition>(rotations.first).turns), isTrue);
    expect(clock.value, advanced);
    expect(reads, 1, reason: 'Activity must not repeat a network read or publish.');
    expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('Shorts · กำลังส่ง'), findsOneWidget);
    expect(find.textContaining('· ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('· รอผล'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('unconfirmed outcome does not acquire sending decoration',
      (tester) async {
    await tester.pumpWidget(_app(loader: () async => [_post(results: const [
      PostPlatformResult(postId: 'sending-post', platform: 'TIKTOK',
          status: 'PUBLISHED', deliveryOutcome: 'UNKNOWN'),
    ])]));
    await _load(tester);
    expect(find.text('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('กำลังส่ง'), findsNothing);
    expect(find.byKey(const ValueKey('postdee-publishing-rail')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final guard in ['inactive', 'reduced', 'ticker']) {
    testWidgets('home $guard guard pauses sending feedback without losing results',
        (tester) async {
      Future<List<PostSummaryResult>> load() async => [_post()];
      await tester.pumpWidget(_app(loader: load));
      await _load(tester);
      await tester.pumpWidget(_app(loader: load,
          active: guard != 'inactive',
          reducedMotion: guard == 'reduced',
          tickerEnabled: guard != 'ticker'));
      await _load(tester);
      final card = find.byKey(const ValueKey('home-publishing-sending-post'));
      final rotation = find.descendant(
          of: card, matching: find.byType(RotationTransition)).first;
      final clock = tester.widget<RotationTransition>(rotation).turns;
      expect(clock.value, 0);
      await tester.pump(const Duration(milliseconds: 350));
      expect(clock.value, 0);
      expect(find.text('กำลังส่ง'), findsOneWidget);
      expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
      expect(find.byKey(const ValueKey('postdee-publishing-rail')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('sending feedback card still opens the existing post details',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(_app(loader: () async {
      reads++;
      return [_post()];
    }));
    await _load(tester);
    final card = find.byKey(const ValueKey('home-publishing-sending-post'));
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('คลิปของร้าน'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(reads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('inactive home does not poll and resume refreshes once',
      (tester) async {
    var calls = 0;
    Future<List<PostSummaryResult>> load() async {
      calls++;
      return [_post()];
    }

    await tester.pumpWidget(_app(loader: load));
    await _load(tester);
    await tester.pumpWidget(_app(loader: load, active: false));
    await tester.pump(const Duration(seconds: 65));
    expect(calls, 1);
    await tester.pumpWidget(_app(loader: load));
    await _load(tester);
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pump(const Duration(seconds: 65));
    expect(calls, 2);
    _resume(tester.binding);
    await _load(tester);
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending card fits 320 pixels with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
        loader: () async => [
              _post(platforms: const [
                'TIKTOK',
                'YOUTUBE_SHORTS',
                'INSTAGRAM_REELS',
                'FACEBOOK_REELS',
              ])
            ],
        textScale: 2));
    await _load(tester);
    expect(find.text('กำลังส่ง'), findsOneWidget);
    expect(find.text('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final status in ['FAILED', 'PARTIAL_PUBLISHED']) {
    testWidgets('terminal $status does not animate stale sending results',
        (tester) async {
      await tester.pumpWidget(_app(
          loader: () async => [
                _post(status: status, results: const [
                  PostPlatformResult(
                      postId: 'sending-post',
                      platform: 'TIKTOK',
                      status: 'PUBLISHING'),
                ])
              ]));
      await _load(tester);
      expect(
          find.byKey(const ValueKey('postdee-publishing-rail')), findsNothing);
      expect(find.text('กำลังส่ง'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
