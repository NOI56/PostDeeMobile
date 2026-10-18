import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';

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
        ),
        child: child!,
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
