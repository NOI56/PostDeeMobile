import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:video_player/video_player.dart';

import 'link_in_bio_test_navigation.dart';

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

Widget _homeTestApp(
  Widget child, {
  double textScale = 1,
  Locale locale = const Locale('th'),
}) {
  return MaterialApp(
    locale: locale,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
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

class _PreviewVideoController extends VideoPlayerController {
  _PreviewVideoController({this.initializeGate, this.failInitialize = false})
      : super.asset('fake-preview.mp4');

  final Completer<void>? initializeGate;
  final bool failInitialize;
  bool disposed = false;
  int initializeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  double? requestedVolume;
  Duration? requestedPosition;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await initializeGate?.future;
    if (disposed) return;
    if (failInitialize) throw StateError('unavailable preview');
    value = const VideoPlayerValue(
      duration: Duration(seconds: 10),
      size: Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    requestedVolume = volume;
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> seekTo(Duration position) async {
    requestedPosition = position;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await super.dispose();
  }
}

PostSummaryResult _previewPost(
        {Uri? coverImageUrl, Uri? videoUrl, int? frameTimeMs}) =>
    PostSummaryResult(
      id: 'preview-p1',
      caption: 'คลิปสินค้าล่าสุด',
      videoS3Key: 'uploads/seller/clip/video.mp4',
      platforms: const ['TIKTOK'],
      status: 'QUEUED',
      createdAt: DateTime.utc(2026, 6, 1),
      coverImageUrl: coverImageUrl,
      videoUrl: videoUrl,
      coverFrameTimeMs: frameTimeMs,
    );

Future<SubscriptionStatusResult> _previewSubscription() async =>
    const SubscriptionStatusResult(
      userId: 'seller',
      plan: 'BASIC',
      status: 'ACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );

void main() {
  testWidgets('uses a cover preview before starting any video controller',
      (tester) async {
    var videoControllers = 0;
    final coverUrl = Uri.parse('https://media.test/cover.jpg?expires=60');
    await tester.pumpWidget(_homeTestApp(HomeScreen(
      loadSubscription: _previewSubscription,
      loadRecentPosts: () async => [
        _previewPost(
          coverImageUrl: coverUrl,
          videoUrl: Uri.parse('https://media.test/video.mp4'),
        )
      ],
      createVideoThumbnailController: (_) {
        videoControllers += 1;
        return _PreviewVideoController();
      },
    )));
    await tester.pump();
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('home-latest-post-cover-preview-p1')),
    );
    final resizedImage = image.image as ResizeImage;
    expect(
        (resizedImage.imageProvider as NetworkImage).url, coverUrl.toString());
    expect(resizedImage.width, 144);
    expect(image.fit, BoxFit.cover);
    expect(videoControllers, 0);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('home-latest-post-placeholder-preview-p1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('ยอดวิวเดือนนี้'), findsNothing);
  });

  testWidgets('keeps latest posts readable when preview media is missing',
      (tester) async {
    await tester.pumpWidget(_homeTestApp(HomeScreen(
      loadSubscription: _previewSubscription,
      loadRecentPosts: () async => [_previewPost()],
    )));
    await tester.pumpAndSettle();
    expect(find.text('คลิปสินค้าล่าสุด'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-latest-post-placeholder-preview-p1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'renders one paused muted frame and clamps the requested cover time',
      (tester) async {
    final controller = _PreviewVideoController();
    final url = Uri.parse('https://media.test/video.mp4?expires=60');
    await tester.pumpWidget(_homeTestApp(HomeScreen(
      loadSubscription: _previewSubscription,
      loadRecentPosts: () async =>
          [_previewPost(videoUrl: url, frameTimeMs: 12000)],
      createVideoThumbnailController: (requested) {
        expect(requested, url);
        return controller;
      },
    )));
    await tester.pumpAndSettle();
    expect(controller.initializeCalls, 1);
    expect(controller.playCalls, 0);
    expect(controller.pauseCalls, 1);
    expect(controller.requestedVolume, 0);
    expect(controller.requestedPosition, const Duration(milliseconds: 9999));
    expect(find.byKey(const ValueKey('home-latest-post-video-preview-p1')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not initialize a video on an inactive home tab',
      (tester) async {
    final controller = _PreviewVideoController();
    var active = false;
    late StateSetter setHomeState;
    await tester
        .pumpWidget(_homeTestApp(StatefulBuilder(builder: (context, setState) {
      setHomeState = setState;
      return HomeScreen(
        isActive: active,
        loadSubscription: _previewSubscription,
        loadRecentPosts: () async =>
            [_previewPost(videoUrl: Uri.parse('https://media.test/video.mp4'))],
        createVideoThumbnailController: (_) => controller,
      );
    })));
    await tester.pumpAndSettle();
    expect(controller.initializeCalls, 0);
    setHomeState(() => active = true);
    await tester.pumpAndSettle();
    expect(controller.initializeCalls, 1);
    setHomeState(() => active = false);
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(find.byKey(const ValueKey('home-latest-post-video-preview-p1')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final timesOut in [false, true]) {
    testWidgets(
        'falls back safely when preview ${timesOut ? 'times out' : 'fails'}',
        (tester) async {
      final gate = timesOut ? Completer<void>() : null;
      final controller = _PreviewVideoController(
        initializeGate: gate,
        failInitialize: !timesOut,
      );
      await tester.pumpWidget(_homeTestApp(HomeScreen(
        loadSubscription: _previewSubscription,
        loadRecentPosts: () async =>
            [_previewPost(videoUrl: Uri.parse('https://media.test/video.mp4'))],
        createVideoThumbnailController: (_) => controller,
      )));
      await tester.pump();
      await tester.pump();
      if (timesOut) await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(controller.disposed, isTrue);
      expect(
          find.byKey(const ValueKey('home-latest-post-placeholder-preview-p1')),
          findsOneWidget);
      expect(find.text('คลิปสินค้าล่าสุด'), findsOneWidget);
      gate?.complete();
      await tester.pumpAndSettle();
      expect(controller.requestedPosition, isNull);
      expect(controller.playCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ignores initialization completing after leaving the home tab',
      (tester) async {
    final gate = Completer<void>();
    final controller = _PreviewVideoController(initializeGate: gate);
    var active = true;
    late StateSetter setHomeState;
    await tester
        .pumpWidget(_homeTestApp(StatefulBuilder(builder: (context, setState) {
      setHomeState = setState;
      return HomeScreen(
        isActive: active,
        loadSubscription: _previewSubscription,
        loadRecentPosts: () async =>
            [_previewPost(videoUrl: Uri.parse('https://media.test/video.mp4'))],
        createVideoThumbnailController: (_) => controller,
      );
    })));
    await tester.pump();
    await tester.pump();
    expect(controller.initializeCalls, 1);
    setHomeState(() => active = false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(controller.requestedPosition, isNull);
    expect(find.byKey(const ValueKey('home-latest-post-video-preview-p1')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'replaces an expired video URL without accepting its late initialization',
      (tester) async {
    final oldGate = Completer<void>();
    final oldController = _PreviewVideoController(initializeGate: oldGate);
    final newController = _PreviewVideoController();
    final oldUrl = Uri.parse('https://media.test/video.mp4?signature=old');
    final newUrl = Uri.parse('https://media.test/video.mp4?signature=new');
    var active = true;
    var currentUrl = oldUrl;
    late StateSetter setHomeState;
    VideoPlayerController factory(Uri url) =>
        url == oldUrl ? oldController : newController;
    await tester
        .pumpWidget(_homeTestApp(StatefulBuilder(builder: (context, setState) {
      setHomeState = setState;
      return HomeScreen(
        isActive: active,
        loadSubscription: _previewSubscription,
        loadRecentPosts: () async => [_previewPost(videoUrl: currentUrl)],
        createVideoThumbnailController: factory,
      );
    })));
    await tester.pump();
    await tester.pump();
    expect(oldController.initializeCalls, 1);
    setHomeState(() => active = false);
    await tester.pump();
    setHomeState(() {
      active = true;
      currentUrl = newUrl;
    });
    await tester.pump();
    await tester.pumpAndSettle();
    oldGate.complete();
    await tester.pumpAndSettle();
    expect(oldController.disposed, isTrue);
    expect(oldController.requestedPosition, isNull);
    expect(newController.initializeCalls, 1);
    expect(newController.playCalls, 0);
    expect(find.byKey(const ValueKey('home-latest-post-video-preview-p1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'falls back if a prepared native video controller later reports an error',
      (tester) async {
    final controller = _PreviewVideoController();
    await tester.pumpWidget(_homeTestApp(HomeScreen(
      loadSubscription: _previewSubscription,
      loadRecentPosts: () async =>
          [_previewPost(videoUrl: Uri.parse('https://media.test/video.mp4'))],
      createVideoThumbnailController: (_) => controller,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-latest-post-video-preview-p1')),
        findsOneWidget);
    controller.value =
        controller.value.copyWith(errorDescription: 'expired media');
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(
        find.byKey(const ValueKey('home-latest-post-placeholder-preview-p1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final plan in const ['BASIC', 'STARTER', 'PRO']) {
    for (final languageCode in const ['th', 'en']) {
      testWidgets(
          'hides monthly views and likes on home for $plan in $languageCode',
          (tester) async {
        await tester.pumpWidget(
          _homeTestApp(
            HomeScreen(
              loadSubscription: () async => SubscriptionStatusResult(
                userId: 'seller-$plan',
                plan: plan,
                status: 'ACTIVE',
                canSchedule: plan != 'BASIC',
                canUseAiCaptions: plan != 'BASIC',
                canUseAnalytics: plan == 'PRO',
              ),
              loadRecentPosts: () async => const [],
            ),
            locale: Locale(languageCode),
          ),
        );
        await tester.pumpAndSettle();

        await _expectHomeTextsNeverAppearAfterScrolling(
          tester,
          [
            'ยอดวิวเดือนนี้',
            'ไลก์เดือนนี้',
            'Views this month',
            'Likes this month',
            'เฉพาะแพ็กเกจ Pro',
            'Pro plan only',
          ],
        );
        expect(
            find.byKey(const ValueKey('home-views-metric-card')), findsNothing);
        expect(
            find.byKey(const ValueKey('home-likes-metric-card')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('shows Thai service-unavailable copy for a gateway failure',
      (tester) async {
    await tester.pumpWidget(_homeTestApp(HomeScreen(
      loadSubscription: () async =>
          throw const ApiException('Request failed', statusCode: 503),
      loadRecentPosts: () async => const [],
    )));
    await tester.pumpAndSettle();
    expect(find.text('ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง'),
        findsOneWidget);
    expect(find.text('Request failed'), findsNothing);
  });

  testWidgets('does not call the user Free when subscription loading fails',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadSubscription: () async =>
              throw const SocketException('subscription offline'),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบแพ็กเกจไม่ได้'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsNothing);
    expect(find.text('อัปเกรด'), findsNothing);
  });

  testWidgets('shows a latest-post load error instead of an empty account',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => throw const SocketException('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-latest-posts-error')),
      findsOneWidget,
    );
    expect(find.text('โหลดโพสต์ล่าสุดไม่สำเร็จ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
  });

  testWidgets('does not show demo home values when no real data exists',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    expect(find.text('128'), findsNothing);
    expect(find.text('45.2K'), findsNothing);
    expect(find.text('32.1K'), findsNothing);
    expect(find.text('18.7K'), findsNothing);
    expect(find.text('3.2K'), findsNothing);
    expect(find.text('แพ็กเกจโปร'), findsNothing);
    expect(find.text('คงเหลือ 23 วัน'), findsNothing);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'keeps profile link and latest posts compact at ${width}dp and ${textScale}x text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _homeTestApp(
            HomeScreen(
              key: ValueKey('home-layout-$width-$textScale'),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller-compact-home',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: () async => const [],
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();

        final linkShortcut =
            find.byKey(const ValueKey('home-link-in-bio-shortcut'));
        await tester.ensureVisible(linkShortcut);
        await tester.pumpAndSettle();

        final linkShortcutRect = tester.getRect(linkShortcut);
        expect(linkShortcutRect.left, greaterThanOrEqualTo(0));
        expect(linkShortcutRect.right, lessThanOrEqualTo(width));
        expect(linkShortcutRect.height, greaterThanOrEqualTo(44));
        expect(linkShortcutRect.height, lessThanOrEqualTo(144));
        final latestPostsTop = tester.getTopLeft(find.text('โพสต์ล่าสุด')).dy;
        expect(
          latestPostsTop - linkShortcutRect.bottom,
          inInclusiveRange(12, 20),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('loads real subscription status on the home plan card',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
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

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'keeps the Pro plan readable at ${width}dp and ${textScale}x text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _homeTestApp(
            HomeScreen(
              key: ValueKey('$width-$textScale'),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller-pro',
                plan: 'PRO',
                status: 'ACTIVE',
                remainingPostsThisMonth: 250,
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: true,
              ),
              loadRecentPosts: () async => const [],
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
        expect(find.text('เหลือ 250/250 หน่วย'), findsOneWidget);
        expect(find.text('อัปเกรด'), findsNothing);
        final title = tester.widget<Text>(
          find.byKey(const ValueKey('home-plan-title')),
        );
        final subtitle = tester.widget<Text>(
          find.byKey(const ValueKey('home-plan-subtitle')),
        );
        expect(title.overflow, isNull);
        expect(title.maxLines, isNull);
        expect(subtitle.overflow, isNull);
        expect(subtitle.maxLines, isNull);
        final planProgress = tester.widget<FractionallySizedBox>(
          find.byKey(const ValueKey('home-plan-progress-fill')),
        );
        expect(planProgress.widthFactor, 1);
        expect(tester.takeException(), isNull);

        for (var attempt = 0; attempt < 20; attempt += 1) {
          final scrollable = tester.state<ScrollableState>(_homeScrollable());
          if (scrollable.position.pixels >=
              scrollable.position.maxScrollExtent) {
            break;
          }
          await tester.drag(_homeScrollable(), const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('refreshes the home plan after returning from the paywall',
      (tester) async {
    var subscriptionLoadCalls = 0;

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
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

    expect(find.text('อัปเกรด'), findsNothing);
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
    expect(find.text('ตัดต่อด้วย AI'), findsNothing);
    expect(find.text('ลิงก์หน้าโปรไฟล์'), findsOneWidget);
    expect(find.text('ยอดวิวเดือนนี้'), findsNothing);
    expect(find.text('ไลก์เดือนนี้'), findsNothing);
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
    expect(planProgress.widthFactor, moreOrLessEquals(1 / 3));
    expect(find.text('อัปเกรด'), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsNothing);
    expect(
      find.text('ให้ AI ตัดคลิปให้กระชับ ใส่ซับ เป็นสไตล์ไวรัลอัตโนมัติ'),
      findsNothing,
    );
    expect(find.text('ยอดวิวเดือนนี้'), findsNothing);
    expect(find.text('ไลก์เดือนนี้'), findsNothing);
    expect(find.text('สร้างโพสต์ใหม่'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-link-in-bio-shortcut')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('ลิงก์หน้าโปรไฟล์'), findsOneWidget);
    expect(find.text('ลิงก์หน้าโปรไฟล์'), findsOneWidget);
    expect(find.text('โพสต์ล่าสุด'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์'), findsOneWidget);
    expect(
      find.text('เริ่มสร้างโพสต์แรกของร้านคุณ\nโพสต์คลิปเดียวไปได้ทุกช่องทาง'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'สร้างโพสต์'), findsNothing);

    final linkShortcutRect = tester.getRect(
      find.byKey(const ValueKey('home-link-in-bio-shortcut')),
    );
    final latestPostsTop = tester.getTopLeft(find.text('โพสต์ล่าสุด')).dy;
    expect(
      latestPostsTop - linkShortcutRect.bottom,
      inInclusiveRange(12, 20),
    );

    await _expectHomeTextsNeverAppearAfterScrolling(
      tester,
      ['เครื่องมือเติบโต', 'ช่วยให้ขายดี', 'แจ้งเตือนคลิปไวรัล'],
    );
  });
  testWidgets('shows real latest posts on the home dashboard', (tester) async {
    final publishedAt = DateTime.now().subtract(const Duration(hours: 2));

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
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
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
  });

  testWidgets('shows a provider draft outcome on the home dashboard',
      (tester) async {
    final deliveredAt = DateTime.now().subtract(const Duration(hours: 1));
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
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
              id: 'draft-p1',
              caption: 'ส่งร่าง TikTok',
              videoS3Key: 'clip.mp4',
              platforms: const ['TIKTOK'],
              status: 'PUBLISHED',
              createdAt: deliveredAt,
              publishedAt: deliveredAt,
              platformResults: const [
                PostPlatformResult(
                  postId: 'draft-p1',
                  platform: 'TIKTOK',
                  status: 'PUBLISHED',
                  deliveryOutcome: 'DRAFT',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsNothing);
  });

  testWidgets('does not present an unknown provider outcome as published',
      (tester) async {
    final deliveredAt = DateTime.now().subtract(const Duration(hours: 1));
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
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
              id: 'unknown-p1',
              caption: 'ผลใหม่จากผู้ให้บริการ',
              videoS3Key: 'clip.mp4',
              platforms: const ['TIKTOK'],
              status: 'PUBLISHED',
              createdAt: deliveredAt,
              publishedAt: deliveredAt,
              platformResults: const [
                PostPlatformResult(
                  postId: 'unknown-p1',
                  platform: 'TIKTOK',
                  status: 'PUBLISHED',
                  deliveryOutcome: 'FUTURE_OUTCOME',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsNothing);
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

  testWidgets('shows profile link shortcut without retired home growth cards',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    expect(
      find.byKey(const ValueKey('home-link-in-bio-shortcut')),
      findsOneWidget,
    );
    expect(find.text('ลิงก์หน้าโปรไฟล์'), findsOneWidget);
    await _expectHomeTextsNeverAppearAfterScrolling(
      tester,
      ['เครื่องมือเติบโต', 'ช่วยให้ขายดี', 'แจ้งเตือนคลิปไวรัล'],
    );
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

  testWidgets('opens Link in Bio manager from the home shortcut',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _tapHomeTextAfterScrolling(tester, 'ลิงก์หน้าโปรไฟล์');

    expect(find.text('ลิงก์ร้าน'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-back')), findsOneWidget);
    expect(find.textContaining('postdee.link/'), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-store-name')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-next')), findsNothing);
    expect(find.byKey(const ValueKey('link-in-bio-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-publish')), findsNothing);

    await tapBioControl(tester, 'link-in-bio-more');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('link-in-bio-save-draft')),
            matching: find.text('บันทึกแบบร่าง')),
        findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await showBioStep(tester, 'review');

    expect(find.text('อัปเดตจากโพสต์ที่ตั้งเวลา'), findsNothing);
    expect(find.text('ดูตัวอย่างเต็มหน้า'), findsOneWidget);
    expect(find.byKey(const ValueKey('link-in-bio-publish')), findsOneWidget);
  });

  testWidgets('does not show the prototype viral alert on home',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _expectHomeTextsNeverAppearAfterScrolling(
      tester,
      ['แจ้งเตือนคลิปไวรัล', 'เตือนเมื่อยอดวิวโตเร็วกว่าปกติ', 'เร็ว ๆ นี้'],
    );
  });
}
