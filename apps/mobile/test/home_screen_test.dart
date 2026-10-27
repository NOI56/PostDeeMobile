import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';
import 'package:video_player/video_player.dart';

Finder _homeScrollable() => find.byType(Scrollable).first;

Future<void> _scrollHomeDown(WidgetTester tester) async {
  await tester.drag(_homeScrollable(), const Offset(0, -700));
  await tester.pumpAndSettle();
}

Future<void> _expectHomeTextAfterScrolling(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);

  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      return;
    }

    await tester.drag(_homeScrollable(), const Offset(0, -260));
    await tester.pumpAndSettle();
  }

  expect(finder, findsOneWidget);
}

Future<void> _tapHomeTextAfterScrolling(
  WidgetTester tester,
  String text,
) async {
  await _expectHomeTextAfterScrolling(tester, text);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _expectHomeTextsNeverAppearAfterScrolling(
  WidgetTester tester,
  List<String> texts,
) async {
  for (var attempt = 0; attempt < 12; attempt += 1) {
    for (final text in texts) {
      expect(find.text(text), findsNothing);
    }

    await tester.drag(_homeScrollable(), const Offset(0, -180));
    await tester.pumpAndSettle();
  }
}

void _expectNoDeveloperTools() {
  expect(find.text('Backend API'), findsNothing);
  expect(find.text('Check API connection'), findsNothing);
  expect(find.text('Test Gemini caption'), findsNothing);
  expect(find.text('Refresh plan'), findsNothing);
  expect(find.text('Phone verification'), findsNothing);
  expect(find.text('Phone number'), findsNothing);
  expect(find.text('Send OTP'), findsNothing);
  expect(find.text('Start Starter subscription'), findsNothing);
  expect(find.text('Start Pro subscription'), findsNothing);
  expect(find.text('Restore Pro purchase'), findsNothing);
  expect(find.text('Next step'), findsNothing);
}

Widget _homeTestApp(Widget child) {
  return MaterialApp(
    locale: const Locale('th'),
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: PostDeeLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

HomeScreen _homePublishingTestScreen({
  required HomeRecentPostsLoader loadRecentPosts,
  bool isActive = true,
}) {
  return HomeScreen(
    isActive: isActive,
    loadAnalytics: () async => const AnalyticsSummaryResult(
      totalViews: 0,
      totalLikes: 0,
      platforms: [],
    ),
    loadSubscription: () async => const SubscriptionStatusResult(
      userId: 'seller-publishing-home',
      plan: 'BASIC',
      status: 'ACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    ),
    loadRecentPosts: loadRecentPosts,
  );
}

PostSummaryResult _homePublishingPost(
  String status, {
  String id = 'polling-post',
  DateTime? scheduledAt,
}) {
  return PostSummaryResult(
    id: id,
    caption: 'Publishing home clip $id',
    videoS3Key: 'uploads/$id.mp4',
    platforms: const ['TIKTOK'],
    status: status,
    scheduledAt: scheduledAt,
    createdAt: DateTime(2026, 10, 20),
  );
}

void _prepareHomePublishingTest(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}

class _FakeThumbnailVideoController extends VideoPlayerController {
  _FakeThumbnailVideoController({this.failInitialize = false})
      : super.asset('fake-thumbnail.mp4');

  final bool failInitialize;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    if (failInitialize) {
      throw StateError('fake thumbnail initialization failed');
    }
    value = const VideoPlayerValue(
      duration: Duration(seconds: 10),
      size: Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await super.dispose();
  }
}

void main() {
  testWidgets('replaces the raw Pro analytics error with Thai UI copy',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => throw const ApiException(
            'Unified Analytics requires the Pro plan',
            statusCode: 402,
            code: 'PRO_REQUIRED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsOneWidget);
    expect(find.textContaining('Unified Analytics'), findsNothing);
  });

  testWidgets('does not show demo home metrics when no real data exists',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
        ),
      ),
    );

    expect(find.text('128'), findsNothing);
    expect(find.text('45.2K'), findsNothing);
    expect(find.text('32.1K'), findsNothing);
    expect(find.text('18.7K'), findsNothing);
    expect(find.text('3.2K'), findsNothing);
    expect(find.text('แพ็กเกจโปร'), findsNothing);
    expect(find.text('คงเหลือ 23 วัน'), findsNothing);
  });

  testWidgets('loads real subscription status on the home plan card',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-starter',
            plan: 'STARTER',
            status: 'ACTIVE',
            remainingPostsThisMonth: 8,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แพ็กเกจ Starter'), findsOneWidget);
    expect(find.text('เหลือ 8/120 หน่วย'), findsOneWidget);
    expect(find.text('แพ็กเกจโปร'), findsNothing);
    expect(find.text('คงเหลือ 23 วัน'), findsNothing);
  });

  testWidgets('refreshes the home plan after returning from the paywall',
      (tester) async {
    var subscriptionLoadCalls = 0;

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async {
            subscriptionLoadCalls += 1;
            final isPro = subscriptionLoadCalls >= 3;
            return SubscriptionStatusResult(
              userId: 'seller-refresh',
              plan: isPro ? 'PRO' : 'BASIC',
              status: isPro ? 'ACTIVE' : 'INACTIVE',
              remainingPostsThisMonth: isPro ? 250 : 3,
              canSchedule: isPro,
              canUseAiCaptions: isPro,
              canUseAnalytics: isPro,
            );
          },
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);

    await tester.tap(find.text('แพ็กเกจฟรี'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกแพ็กเกจ'), findsOneWidget);

    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();

    expect(subscriptionLoadCalls, 3);
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
  });

  testWidgets('ignores a stale Basic plan after returning from the paywall',
      (tester) async {
    final initialLoad = Completer<SubscriptionStatusResult>();
    var subscriptionLoadCalls = 0;
    const basic = SubscriptionStatusResult(
      userId: 'seller-stale-home',
      plan: 'BASIC',
      status: 'INACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
    const pro = SubscriptionStatusResult(
      userId: 'seller-stale-home',
      plan: 'PRO',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    );

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () {
            subscriptionLoadCalls += 1;
            return switch (subscriptionLoadCalls) {
              1 => initialLoad.future,
              2 => Future.value(basic),
              _ => Future.value(pro),
            };
          },
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('กำลังโหลดแพ็กเกจ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);

    initialLoad.complete(basic);
    await tester.pumpAndSettle();

    expect(subscriptionLoadCalls, 3);
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
  });

  testWidgets('shows only real user-facing home sections', (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(find.text('ยอดวิวเดือนนี้'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
    expect(find.text('128'), findsNothing);
    expect(find.text('โพสต์ล่าสุด'), findsOneWidget);
    expect(find.text('ดูทั้งหมด'), findsNothing);
    expect(find.text('TikTok'), findsNothing);
    expect(find.text('YouTube Shorts'), findsNothing);
    expect(find.text('Instagram Reels'), findsNothing);
    expect(find.text('Facebook Reels'), findsNothing);
    expect(find.text('โพสต์วันนี้ 2'), findsNothing);
    expect(find.text('กำลังประมวลผล'), findsNothing);
    expect(find.text('45.2K'), findsNothing);
    expect(find.text('3.2K'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsOneWidget,
    );
    _expectNoDeveloperTools();

    await _scrollHomeDown(tester);
    expect(find.text('ทางลัด'), findsNothing);
    expect(find.widgetWithText(TextButton, 'อัปโหลด'), findsNothing);
    expect(find.widgetWithText(TextButton, 'เทมเพลต'), findsNothing);
    _expectNoDeveloperTools();

    await _scrollHomeDown(tester);
    _expectNoDeveloperTools();
  });

  testWidgets('matches the reference home first screen', (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 1240,
            totalLikes: 328,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            remainingPostsThisMonth: 1,
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);
    expect(find.text('เหลือ 1/3 หน่วย'), findsOneWidget);
    final planProgress = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('home-plan-progress-fill')),
    );
    expect(planProgress.widthFactor, moreOrLessEquals(2 / 3));
    expect(find.text('อัปเกรด'), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(
      find.text('ให้ AI ตัดคลิปให้กระชับ ใส่ซับ เป็นสไตล์ไวรัลอัตโนมัติ'),
      findsOneWidget,
    );
    expect(find.text('ยอดวิวเดือนนี้'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(find.text('โพสต์ล่าสุด'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์'), findsOneWidget);
    expect(
      find.text('เริ่มสร้างโพสต์แรกของร้านคุณ\nโพสต์คลิปเดียวไปได้ทุกช่องทาง'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'สร้างโพสต์'), findsOneWidget);

    await _expectHomeTextAfterScrolling(tester, 'เครื่องมือเติบโต');
    expect(find.text('ช่วยให้ขายดี'), findsOneWidget);
  });
  testWidgets('loads and displays total views on the home dashboard',
      (tester) async {
    final analyticsCompleter = Completer<AnalyticsSummaryResult>();

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () => analyticsCompleter.future,
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    // Analytics now loads on init, so the views card shows the loading label
    // without a manual refresh tap.
    await tester.pump();

    expect(find.text('...'), findsNWidgets(2));

    analyticsCompleter.complete(
      const AnalyticsSummaryResult(
        totalViews: 1200,
        totalLikes: 140,
        platforms: [
          PlatformAnalyticsResult(
            platform: 'TIKTOK',
            label: 'TikTok',
            views: 1200,
            likes: 140,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1200'), findsOneWidget);
    expect(find.text('140'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
  });

  testWidgets('latest posts show matching platform logos in post order',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        _homePublishingTestScreen(
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'platform-logos',
              caption: 'โพสต์ครบทุกแพลตฟอร์ม',
              videoS3Key: 'clip.mp4',
              platforms: const [
                'INSTAGRAM_REELS',
                'YOUTUBE_SHORTS',
                'TIKTOK',
                'FACEBOOK_REELS',
              ],
              status: 'PUBLISHED',
              createdAt: DateTime(2026, 10, 25),
            ),
            PostSummaryResult(
              id: 'single-platform-logo',
              caption: 'โพสต์ TikTok',
              videoS3Key: 'single-clip.mp4',
              platforms: const ['TIKTOK'],
              status: 'PUBLISHED',
              createdAt: DateTime(2026, 10, 25),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final logos = find.byType(SocialPlatformLogo);
    expect(
      tester.widgetList<SocialPlatformLogo>(logos).map((logo) => logo.platform),
      [
        SocialPlatform.instagramReels,
        SocialPlatform.youtubeShorts,
        SocialPlatform.tiktok,
        SocialPlatform.facebookReels,
        SocialPlatform.tiktok,
      ],
    );
    expect(
      tester
          .widgetList<Image>(
            find.descendant(of: logos, matching: find.byType(Image)),
          )
          .map((image) => (image.image as AssetImage).assetName),
      [
        'assets/images/platforms/instagram_reels.png',
        'assets/images/platforms/youtube_shorts.png',
        'assets/images/platforms/tiktok.png',
        'assets/images/platforms/facebook_reels.png',
        'assets/images/platforms/tiktok.png',
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows real latest posts on the home dashboard', (tester) async {
    final publishedAt = DateTime.now().subtract(const Duration(hours: 2));

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'p1',
              caption: 'โปรโมตสินค้าใหม่',
              videoS3Key: 'clip.mp4',
              coverImageUrl: Uri.parse(
                'https://media.test/clip-cover.jpg?signature=cover',
              ),
              platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
              status: 'PUBLISHED',
              createdAt: publishedAt,
              publishedAt: publishedAt,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('โปรโมตสินค้าใหม่'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsOneWidget);
    expect(find.text('TikTok · YouTube Shorts'), findsOneWidget);
    final cover = tester.widget<Image>(
      find.byKey(const ValueKey('home-latest-post-cover-p1')),
    );
    expect(
      cover.image,
      isA<NetworkImage>().having(
        (image) => image.url,
        'url',
        'https://media.test/clip-cover.jpg?signature=cover',
      ),
    );
    expect(cover.fit, BoxFit.cover);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
  });

  testWidgets(
      'keeps a play placeholder for an older post without preview media',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'legacy-post',
              caption: 'โพสต์เก่า',
              videoS3Key: 'legacy.mp4',
              platforms: const ['YOUTUBE_SHORTS'],
              status: 'PUBLISHED',
              createdAt: DateTime(2026, 6),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('home-latest-post-placeholder-legacy-post'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('shows a frame from the clip when a recent post has no cover',
      (tester) async {
    final controller = _FakeThumbnailVideoController();
    Uri? requestedVideoUrl;
    final signedVideoUrl =
        Uri.parse('https://media.test/clip.mp4?signature=video');

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          createVideoThumbnailController: (videoUrl) {
            requestedVideoUrl = videoUrl;
            return controller;
          },
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'video-post',
              caption: 'คลิปที่ไม่มีภาพปก',
              videoS3Key: 'clip.mp4',
              videoUrl: signedVideoUrl,
              coverFrameTimeMs: 1250,
              platforms: const ['YOUTUBE_SHORTS'],
              status: 'PUBLISHED',
              createdAt: DateTime(2026, 6),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedVideoUrl, signedVideoUrl);
    expect(
      find.byKey(const ValueKey('home-latest-post-video-video-post')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-latest-post-placeholder-video-post')),
      findsNothing,
    );
    expect(controller.value.position, const Duration(milliseconds: 1250));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposed, isTrue);
  });

  testWidgets('releases a clip preview when the home tab becomes inactive',
      (tester) async {
    final controller = _FakeThumbnailVideoController();
    var homeIsActive = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeScreen(
              isActive: homeIsActive,
              createVideoThumbnailController: (_) => controller,
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: () async => [
                PostSummaryResult(
                  id: 'inactive-video-post',
                  caption: 'คลิปหยุดเมื่อออกจากหน้าหลัก',
                  videoS3Key: 'inactive.mp4',
                  videoUrl: Uri.parse('https://media.test/inactive.mp4'),
                  platforms: const ['YOUTUBE_SHORTS'],
                  status: 'PUBLISHED',
                  createdAt: DateTime(2026, 6),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('home-latest-post-video-inactive-video-post'),
      ),
      findsOneWidget,
    );

    setHostState(() => homeIsActive = false);
    await tester.pumpAndSettle();

    expect(controller.disposed, isTrue);
    expect(
      find.byKey(
        const ValueKey('home-latest-post-placeholder-inactive-video-post'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('falls back to the play icon when a clip preview cannot load',
      (tester) async {
    final controller = _FakeThumbnailVideoController(failInitialize: true);

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          createVideoThumbnailController: (_) => controller,
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'broken-video-post',
              caption: 'คลิปโหลดไม่ได้',
              videoS3Key: 'broken.mp4',
              videoUrl: Uri.parse('https://media.test/broken.mp4'),
              platforms: const ['YOUTUBE_SHORTS'],
              status: 'FAILED',
              createdAt: DateTime(2026, 6),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('home-latest-post-placeholder-broken-video-post'),
      ),
      findsOneWidget,
    );
    expect(controller.disposed, isTrue);
  });

  testWidgets(
      'loads latest posts only while home is active and refreshes on return',
      (tester) async {
    var loadCount = 0;
    var homeIsActive = false;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeScreen(
              isActive: homeIsActive,
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: () async {
                loadCount += 1;
                return const [];
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 0);

    setHostState(() => homeIsActive = true);
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = false);
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = true);
    await tester.pumpAndSettle();
    expect(loadCount, 2);
  });

  testWidgets('queues a home refresh instead of overlapping post loads',
      (tester) async {
    final firstLoad = Completer<List<PostSummaryResult>>();
    var loadCount = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    var homeIsActive = true;
    late StateSetter setHostState;

    Future<List<PostSummaryResult>> loadRecentPosts() async {
      loadCount += 1;
      inFlight += 1;
      if (inFlight > maxInFlight) {
        maxInFlight = inFlight;
      }

      try {
        if (loadCount == 1) {
          return await firstLoad.future;
        }
        return const [];
      } finally {
        inFlight -= 1;
      }
    }

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeScreen(
              isActive: homeIsActive,
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: loadRecentPosts,
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = false);
    await tester.pump();
    setHostState(() => homeIsActive = true);
    await tester.pump();

    expect(loadCount, 1);
    expect(maxInFlight, 1);

    firstLoad.complete(const []);
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(maxInFlight, 1);
  });

  testWidgets(
      'home publishing status polls until published and removes its spinner',
      (tester) async {
    _prepareHomePublishingTest(tester);
    var loadCount = 0;

    await tester.pumpWidget(
      _homeTestApp(
        _homePublishingTestScreen(
          loadRecentPosts: () async {
            loadCount += 1;
            return [
              _homePublishingPost(switch (loadCount) {
                1 => 'QUEUED',
                2 => 'PUBLISHING',
                _ => 'PUBLISHED',
              }),
            ];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final spinner =
        find.byKey(const ValueKey('home-post-publishing-polling-post'));
    expect(loadCount, 1);
    expect(find.text('อยู่ในคิว'), findsOneWidget);
    expect(spinner, findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(spinner).value, isNull);

    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('กำลังโพสต์'), findsOneWidget);
    expect(spinner, findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 3);
    expect(find.text('เผยแพร่'), findsOneWidget);
    expect(spinner, findsNothing);

    await tester.pump(const Duration(seconds: 60));
    expect(loadCount, 3);
  });

  testWidgets(
      'home publishing status pauses polling off tab and cancels on disposal',
      (tester) async {
    _prepareHomePublishingTest(tester);
    var loadCount = 0;
    var homeIsActive = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return _homePublishingTestScreen(
              isActive: homeIsActive,
              loadRecentPosts: () async {
                loadCount += 1;
                return [_homePublishingPost('QUEUED')];
              },
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 2);

    setHostState(() => homeIsActive = false);
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(find.byKey(
            const ValueKey('home-post-publishing-polling-post'),
          ))
          .value,
      0.65,
    );
    await tester.pump(const Duration(seconds: 60));
    expect(loadCount, 2);

    setHostState(() => homeIsActive = true);
    await tester.pump();
    await tester.pump();
    expect(loadCount, 3);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 60));
    expect(loadCount, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home publishing status pauses polling while app is paused',
      (tester) async {
    _prepareHomePublishingTest(tester);
    var loadCount = 0;

    await tester.pumpWidget(
      _homeTestApp(
        _homePublishingTestScreen(
          loadRecentPosts: () async {
            loadCount += 1;
            return [_homePublishingPost('PUBLISHING')];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(loadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(find.byKey(
            const ValueKey('home-post-publishing-polling-post'),
          ))
          .value,
      0.65,
    );
    await tester.pump(const Duration(seconds: 60));
    expect(loadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(loadCount, 2);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 3);
  });

  testWidgets(
      'home publishing status keeps posts during failed polling and retries',
      (tester) async {
    _prepareHomePublishingTest(tester);
    final failedRefresh = Completer<List<PostSummaryResult>>();
    var loadCount = 0;

    await tester.pumpWidget(
      _homeTestApp(
        _homePublishingTestScreen(
          loadRecentPosts: () async {
            loadCount += 1;
            if (loadCount == 2) return failedRefresh.future;
            return [
              _homePublishingPost(loadCount == 1 ? 'QUEUED' : 'PUBLISHED'),
            ];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(loadCount, 1);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('Publishing home clip polling-post'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-post-publishing-polling-post')),
      findsOneWidget,
    );

    failedRefresh.completeError(const ApiException('Temporary connection error'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Publishing home clip polling-post'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loadCount, 3);
    expect(find.text('เผยแพร่'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-post-publishing-polling-post')),
      findsNothing,
    );
  });

  testWidgets(
      'home publishing status keeps future schedules still and respects reduced motion',
      (tester) async {
    _prepareHomePublishingTest(tester);
    var reduceMotion = false;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: _homePublishingTestScreen(
                loadRecentPosts: () async => [
                  _homePublishingPost(
                    'QUEUED',
                    id: 'future-schedule',
                    scheduledAt: DateTime.now().add(const Duration(days: 1)),
                  ),
                  _homePublishingPost('PUBLISHING'),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ตั้งเวลา'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-post-publishing-future-schedule')),
      findsNothing,
    );
    final spinner =
        find.byKey(const ValueKey('home-post-publishing-polling-post'));
    expect(spinner, findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(spinner).value, isNull);

    setHostState(() => reduceMotion = true);
    await tester.pump();
    expect(tester.widget<CircularProgressIndicator>(spinner).value, 0.65);
  });

  testWidgets('shows phase 2 growth tool previews on the home dashboard',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _expectHomeTextAfterScrolling(tester, 'เครื่องมือเติบโต');
    // Home shows two growth tools per the design handoff; "team" moved into
    // the growth detail screen.
    final toolTitles = [
      'ลิงก์หน้าโปรไฟล์',
      'แจ้งเตือนคลิปไวรัล',
    ];

    for (final title in toolTitles) {
      await _expectHomeTextAfterScrolling(tester, title);
    }
    expect(find.text('ทีมและผู้ช่วย'), findsNothing);
  });

  testWidgets('keeps upload and analytics growth tools off home dashboard',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _expectHomeTextsNeverAppearAfterScrolling(
      tester,
      [
        'ตัดคลิปเป็น EP',
        'ใส่ลายน้ำอัตโนมัติ',
        'เรดาร์แฮชแท็กฮิต',
        'ศูนย์คอมเมนต์ AI',
        'คอมเมนต์และคำตอบต้องให้เจ้าของร้านอนุมัติก่อนเผยแพร่',
      ],
    );
  });

  testWidgets('opens Link in Bio builder from the home growth card',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _tapHomeTextAfterScrolling(tester, 'ลิงก์หน้าโปรไฟล์');

    expect(find.text('สร้างหน้า Link in Bio'), findsOneWidget);
    expect(find.text('ตัวอย่าง: postdee.link/ร้านของคุณ'), findsOneWidget);
    expect(find.text('ลิงก์สินค้าและแคมเปญ'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('อัปเดตจากโพสต์ที่ตั้งเวลา'), findsOneWidget);
    expect(find.text('ดูตัวอย่างหน้า'), findsOneWidget);
    expect(find.text('บันทึกแบบร่าง'), findsOneWidget);
  });

  testWidgets('opens growth tool detail settings from home cards',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    final toolTitles = [
      'แจ้งเตือนคลิปไวรัล',
    ];

    for (final title in toolTitles) {
      await _tapHomeTextAfterScrolling(tester, title);

      expect(find.text('รายละเอียดและตั้งค่า'), findsOneWidget);
      expect(find.text('ตั้งค่า: $title'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-real-status-note')),
        findsOneWidget,
      );
      expect(find.text('เร็ว ๆ นี้'), findsWidgets);
      expect(find.text('แบบร่างในเครื่อง'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-enabled-switch')),
        findsNothing,
      );
      expect(find.text('บันทึกแบบร่าง'), findsOneWidget);

      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
    }
  });
}
