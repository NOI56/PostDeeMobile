import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_activity_section.dart';
import 'package:postdee_mobile/features/home/home_draft_thumbnail.dart';
import 'package:postdee_mobile/features/shared/postdee_skeleton.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:video_player/video_player.dart';

final _now = DateTime.utc(2026, 10, 11, 3);

PublishDraft _draft(
  String id, {
  String owner = 'seller',
  int age = 0,
  String? caption,
  bool needsReview = false,
  Set<String>? platforms,
  PublishDraftCover? cover,
}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: owner,
      submissionRequestId: 'submit-$id',
      createdAt: _now.subtract(const Duration(days: 1)),
      updatedAt: _now.subtract(Duration(minutes: age)),
      videoPath: '/drafts/$id.mp4',
      videoName: '$id.mp4',
      videoSizeBytes: 100,
      caption: caption ?? 'แคปชัน $id',
      captionNeedsReview: needsReview,
      aiGuidance: '',
      watermarkEnabled: true,
      platformApiValues: platforms ?? const {'TIKTOK'},
      cover: cover,
    );

PostSummaryResult _post(String id, int minutes,
        {String status = 'QUEUED', bool scheduled = true}) =>
    PostSummaryResult(
      id: id,
      caption: 'โพสต์ $id',
      videoS3Key: 'uploads/seller/$id.mp4',
      platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
      status: status,
      createdAt: _now.subtract(const Duration(days: 1)),
      scheduledAt: scheduled ? _now.add(Duration(minutes: minutes)) : null,
    );

void _signIn(String owner) => PostDeeAuthSessionStore.instance.signIn(
      AuthSession.authenticated(userId: owner, idToken: 'test-$owner'),
    );

Widget _app(HomeActivitySection child,
        {double textScale = 1,
        double width = 390,
        bool reducedMotion = true,
        bool tickerEnabled = true}) =>
    MaterialApp(
      locale: const Locale('th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion),
          child: TickerMode(
              enabled: tickerEnabled,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(child: child),
                ),
              )),
        ),
      ),
    );

HomeActivitySection _section({
  GlobalKey<HomeActivitySectionState>? key,
  bool isActive = true,
  int refreshToken = 0,
  bool? hasPosts,
  HomeDraftsLoader? loadDrafts,
  HomeConnectionsLoader? loadConnections,
  HomeUpcomingPostsLoader? loadScheduledPosts,
  Future<void> Function()? onCreatePost,
  Future<void> Function(PublishDraft)? onResumeDraft,
  VoidCallback? onOpenConnections,
  VoidCallback? onOpenCalendar,
}) =>
    HomeActivitySection(
      key: key,
      isActive: isActive,
      refreshToken: refreshToken,
      hasPosts: hasPosts,
      loadDrafts: loadDrafts ?? () async => [],
      loadConnections: loadConnections ?? () async => [],
      loadScheduledPosts: loadScheduledPosts ?? () async => [],
      onCreatePost: onCreatePost ?? () async {},
      onResumeDraft: onResumeDraft ?? (_) async {},
      onOpenConnections: onOpenConnections,
      onOpenCalendar: onOpenCalendar,
      now: () => _now,
      createDraftThumbnailController: (_) => _StillThumbnailController(),
    );

class _StillThumbnailController extends VideoPlayerController {
  _StillThumbnailController() : super.asset('fake-home-thumbnail.mp4');
  @override
  Future<void> initialize() async {
    value = const VideoPlayerValue(
        duration: Duration(seconds: 10),
        size: Size(1080, 1920),
        isInitialized: true);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void _resumeMotion(TestWidgetsFlutterBinding binding) {
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

double _heroOpacity(WidgetTester tester) {
  final opacity = find.byKey(const ValueKey('home-hero-content-opacity'));
  if (opacity.evaluate().isNotEmpty) {
    return tester.widget<Opacity>(opacity).opacity;
  }
  return tester
      .widget<FadeTransition>(find
          .descendant(
              of: find.byKey(const ValueKey('home-hero-owner-0')),
              matching: find.byType(FadeTransition))
          .last)
      .opacity
      .value;
}

void main() {
  setUp(() {
    AppTheme.applyThemeMode(ThemeMode.light);
    _signIn('seller');
  });
  tearDown(() => PostDeeAuthSessionStore.instance.clear());

  for (final mode in ['inactive', 'reduced', 'ticker', 'background']) {
    testWidgets('motion audit $mode stops a live hero fade without replay',
        (tester) async {
      _resumeMotion(tester.binding);
      addTearDown(() => _resumeMotion(tester.binding));
      final key = GlobalKey<HomeActivitySectionState>();
      final drafts = Completer<List<PublishDraft>>();
      Future<List<PublishDraft>> loadDrafts() => drafts.future;
      Widget host(bool blocked) => _app(
            _section(
              key: key,
              isActive: mode != 'inactive' || !blocked,
              loadDrafts: loadDrafts,
            ),
            reducedMotion: mode == 'reduced' && blocked,
            tickerEnabled: mode != 'ticker' || !blocked,
          );
      await tester.pumpWidget(host(false));
      drafts.complete([_draft('current')]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('แคปชัน current'), findsOneWidget);
      expect(_heroOpacity(tester), inExclusiveRange(0, 1));
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      } else {
        await tester.pumpWidget(host(true));
      }
      expect(_heroOpacity(tester), 1);
      expect(find.text('แคปชัน current'), findsOneWidget);
      if (mode == 'background') {
        _resumeMotion(tester.binding);
        await tester.pump();
      } else {
        await tester.pumpWidget(host(false));
      }
      expect(_heroOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 30));
      expect(_heroOpacity(tester), 1);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('motion audit hero replacement removes previous actionable draft',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final key = GlobalKey<HomeActivitySectionState>();
    var current = _draft('old');
    final opened = <String>[];
    await tester.pumpWidget(_app(
      _section(
        key: key,
        loadDrafts: () async => [current],
        onResumeDraft: (draft) async => opened.add(draft.id),
      ),
      reducedMotion: false,
    ));
    await tester.pumpAndSettle();
    current = _draft('new');
    final refresh = key.currentState!.refresh();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('แคปชัน old'), findsNothing);
    expect(find.text('แคปชัน new'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-resume-draft')), findsOneWidget);
    expect(find.bySemanticsLabel('ทำต่อ'), findsOneWidget);
    await _tap(tester, 'home-resume-draft');
    await tester.pumpAndSettle();
    expect(opened, ['new']);
    expect(await refresh, isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('starts the first post without requiring a connected channel',
      (tester) async {
    var created = 0;
    await tester.pumpWidget(_app(_section(
      hasPosts: false,
      onCreatePost: () async => created++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsOneWidget);
    expect(find.text('เลือกคลิป แล้วโพสต์ได้หลายช่องทาง'), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsOneWidget);
    await _tap(tester, 'home-create-post');
    expect(created, 1);
  });

  testWidgets('uses new-post copy when the seller already has posts',
      (tester) async {
    await tester.pumpWidget(_app(_section(hasPosts: true)));
    await tester.pumpAndSettle();
    expect(find.text('สร้างโพสต์ใหม่'), findsWidgets);
    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsNothing);
  });

  testWidgets(
      'does not claim this is the first post while post history is unknown',
      (tester) async {
    await tester.pumpWidget(_app(_section()));
    await tester.pumpAndSettle();
    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsNothing);
    expect(find.text('สร้างโพสต์ใหม่'), findsWidgets);
  });

  testWidgets('continues the latest saved draft of this owner only',
      (tester) async {
    PublishDraft? restored;
    var created = 0;
    final newest = _draft('newest', age: 1);
    await tester.pumpWidget(_app(_section(
      loadDrafts: () async => [
        _draft('older', age: 8),
        _draft('foreign', owner: 'someone-else'),
        newest,
      ],
      onResumeDraft: (draft) async => restored = draft,
      onCreatePost: () async => created++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('ทำโพสต์ต่อ'), findsOneWidget);
    expect(find.text('ร่างที่บันทึกไว้'), findsOneWidget);
    expect(find.text('แคปชัน newest'), findsOneWidget);
    expect(find.text('แคปชัน foreign'), findsNothing);
    await _tap(tester, 'home-resume-draft');
    expect(restored, same(newest));
    await _tap(tester, 'home-create-post');
    expect(created, 1);
  });

  testWidgets('counts each supported connected platform once', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_app(_section(
      loadConnections: () async => const [
        SocialConnectionResult(platform: 'TIKTOK', connected: true),
        SocialConnectionResult(platform: 'TIKTOK', connected: true),
        SocialConnectionResult(platform: 'YOUTUBE_SHORTS', connected: true),
        SocialConnectionResult(platform: 'INSTAGRAM_REELS', connected: false),
        SocialConnectionResult(platform: 'SHOPEE_VIDEO', connected: true),
      ],
      onOpenConnections: () => opened++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมแล้ว 2/4 ช่องทาง'), findsOneWidget);
    expect(find.textContaining('พร้อมโพสต์'), findsNothing);
    await _tap(tester, 'home-manage-connections');
    expect(opened, 1);
  });

  testWidgets('shows only the earliest future queued post', (tester) async {
    var calendarOpened = 0;
    await tester.pumpWidget(_app(_section(
      loadScheduledPosts: () async => [
        _post('later', 120),
        _post('past', -30),
        _post('published', 1, status: 'PUBLISHED'),
        _post('failed', 2, status: 'FAILED'),
        _post('no-time', 3, scheduled: false),
        _post('now', 0),
        _post('earliest', 30),
      ],
      onOpenCalendar: () => calendarOpened++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ earliest'), findsOneWidget);
    for (final id in [
      'later',
      'past',
      'published',
      'failed',
      'no-time',
      'now'
    ]) {
      expect(find.text('โพสต์ $id'), findsNothing);
    }
    expect(find.text('TikTok · YouTube Shorts'), findsOneWidget);
    await _tap(tester, 'home-open-calendar');
    expect(calendarOpened, 1);
  });

  testWidgets('pending sources never look like empty or zero data',
      (tester) async {
    final drafts = Completer<List<PublishDraft>>();
    final connections = Completer<List<SocialConnectionResult>>();
    final posts = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(_app(_section(
      hasPosts: false,
      loadDrafts: () => drafts.future,
      loadConnections: () => connections.future,
      loadScheduledPosts: () => posts.future,
    )));
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsNothing);
    expect(find.text('ยังไม่มีโพสต์ตั้งเวลา'), findsNothing);
    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsNothing);
    drafts.complete([]);
    connections.complete([]);
    posts.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('a connections error retries without replacing it with zero',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_section(loadConnections: () async {
      if (++calls == 1) throw StateError('network');
      return const [
        SocialConnectionResult(platform: 'TIKTOK', connected: true)
      ];
    })));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบช่องทางไม่ได้'), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsNothing);
    await _tap(tester, 'home-retry-connections');
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมแล้ว 1/4 ช่องทาง'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a draft error does not masquerade as no saved draft',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_section(
      hasPosts: false,
      loadDrafts: () async {
        if (++calls == 1) throw StateError('storage');
        return [_draft('recovered')];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบร่างไม่ได้'), findsOneWidget);
    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsNothing);
    await _tap(tester, 'home-retry-drafts');
    await tester.pumpAndSettle();
    expect(find.text('แคปชัน recovered'), findsOneWidget);
  });

  testWidgets('a schedule error is distinct from an empty queue and retries',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_section(loadScheduledPosts: () async {
      if (++calls == 1) throw StateError('network');
      return [_post('recovered', 60)];
    })));
    await tester.pumpAndSettle();
    expect(find.text('โหลดคิวโพสต์ไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์ตั้งเวลา'), findsNothing);
    await _tap(tester, 'home-retry-upcoming');
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ recovered'), findsOneWidget);
  });

  testWidgets('does not load hidden home and refreshes on activation',
      (tester) async {
    var calls = 0;
    Future<List<PublishDraft>> loader() async {
      calls++;
      return <PublishDraft>[];
    }

    await tester
        .pumpWidget(_app(_section(isActive: false, loadDrafts: loader)));
    await tester.pump();
    expect(calls, 0);
    await tester.pumpWidget(_app(_section(loadDrafts: loader)));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester
        .pumpWidget(_app(_section(isActive: false, loadDrafts: loader)));
    await tester.pumpWidget(_app(_section(loadDrafts: loader)));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
      'refreshes saved drafts after the composer returns and blocks duplicate taps',
      (tester) async {
    final composer = Completer<void>();
    var draftLoads = 0;
    var created = 0;
    await tester.pumpWidget(_app(_section(
      loadDrafts: () async =>
          ++draftLoads == 1 ? [] : [_draft('saved-in-composer')],
      onCreatePost: () {
        created++;
        return composer.future;
      },
    )));
    await tester.pumpAndSettle();
    await _tap(tester, 'home-create-post');
    await _tap(tester, 'home-create-post');
    expect(created, 1);
    composer.complete();
    await tester.pumpAndSettle();
    expect(find.text('แคปชัน saved-in-composer'), findsOneWidget);
    expect(draftLoads, 2);
  });

  testWidgets('refreshes on returning to the app', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(_section(loadConnections: () async {
      calls++;
      return [];
    })));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('late data from a former owner cannot overwrite the new owner',
      (tester) async {
    final oldDrafts = Completer<List<PublishDraft>>();
    final oldConnections = Completer<List<SocialConnectionResult>>();
    final oldPosts = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(_app(_section(
      loadDrafts: () =>
          PostDeeAuthSessionStore.instance.session.stableUserId == 'seller'
              ? oldDrafts.future
              : Future.value([_draft('new-owner', owner: 'buyer')]),
      loadConnections: () =>
          PostDeeAuthSessionStore.instance.session.stableUserId == 'seller'
              ? oldConnections.future
              : Future.value([]),
      loadScheduledPosts: () =>
          PostDeeAuthSessionStore.instance.session.stableUserId == 'seller'
              ? oldPosts.future
              : Future.value([_post('new-owner', 40)]),
    )));
    _signIn('buyer');
    await tester.pumpAndSettle();
    oldDrafts.complete([_draft('old-owner')]);
    oldConnections.complete(
        const [SocialConnectionResult(platform: 'TIKTOK', connected: true)]);
    oldPosts.complete([_post('old-owner', 1)]);
    await tester.pumpAndSettle();
    expect(find.text('แคปชัน new-owner'), findsOneWidget);
    expect(find.text('โพสต์ new-owner'), findsOneWidget);
    expect(find.text('แคปชัน old-owner'), findsNothing);
    expect(find.text('โพสต์ old-owner'), findsNothing);
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsOneWidget);
  });

  testWidgets(
      'sign-out clears loaded private content and disables draft action',
      (tester) async {
    await tester.pumpWidget(_app(_section(
      loadDrafts: () async => [_draft('private')],
      loadScheduledPosts: () async => [_post('private', 10)],
    )));
    await tester.pumpAndSettle();
    PostDeeAuthSessionStore.instance.clear();
    await tester.pump();
    expect(find.text('แคปชัน private'), findsNothing);
    expect(find.text('โพสต์ private'), findsNothing);
    expect(find.byKey(const ValueKey('home-resume-draft')), findsNothing);
  });

  testWidgets(
      'refresh token reloads after changes elsewhere without rebuilding loaders',
      (tester) async {
    var calls = 0;
    Future<List<PublishDraft>> drafts() async => [];
    Future<List<SocialConnectionResult>> connections() async => [];
    Future<List<PostSummaryResult>> posts() async {
      calls++;
      return [_post('version-$calls', 30)];
    }

    HomeActivitySection section(int token) => _section(
          refreshToken: token,
          loadDrafts: drafts,
          loadConnections: connections,
          loadScheduledPosts: posts,
        );
    await tester.pumpWidget(_app(section(0)));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ version-1'), findsOneWidget);
    await tester.pumpWidget(_app(section(0)));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(_app(section(1)));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('โพสต์ version-2'), findsOneWidget);
  });

  testWidgets(
      'an old request stays rejected when the same owner signs in again',
      (tester) async {
    final oldDrafts = Completer<List<PublishDraft>>();
    var calls = 0;
    await tester.pumpWidget(_app(_section(loadDrafts: () {
      calls++;
      if (calls == 1) return oldDrafts.future;
      final owner = PostDeeAuthSessionStore.instance.session.stableUserId!;
      return Future.value([_draft('current-$calls', owner: owner)]);
    })));
    _signIn('buyer');
    await tester.pumpAndSettle();
    _signIn('seller');
    await tester.pumpAndSettle();
    oldDrafts.complete([_draft('obsolete')]);
    await tester.pumpAndSettle();
    expect(find.text('แคปชัน current-3'), findsOneWidget);
    expect(find.text('แคปชัน obsolete'), findsNothing);
  });

  testWidgets('a refresh token shares an in-flight refresh for this owner',
      (tester) async {
    final oldPosts = Completer<List<PostSummaryResult>>();
    var calls = 0;
    Future<List<PublishDraft>> drafts() async => [];
    Future<List<SocialConnectionResult>> connections() async => [];
    Future<List<PostSummaryResult>> posts() {
      return ++calls == 1
          ? oldPosts.future
          : Future.value([_post('current', 50)]);
    }

    HomeActivitySection section(int token) => _section(
          refreshToken: token,
          loadDrafts: drafts,
          loadConnections: connections,
          loadScheduledPosts: posts,
        );
    await tester.pumpWidget(_app(section(0)));
    await tester.pump();
    await tester.pumpWidget(_app(section(1)));
    await tester.pumpAndSettle();
    expect(calls, 1);
    oldPosts.complete([_post('original-request', 5)]);
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ original-request'), findsOneWidget);
    expect(find.text('โพสต์ current'), findsNothing);
  });

  testWidgets(
      'initial unknown work uses skeletons and a usable new-post action',
      (tester) async {
    final drafts = Completer<List<PublishDraft>>();
    final connections = Completer<List<SocialConnectionResult>>();
    final posts = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(_app(_section(
      loadDrafts: () => drafts.future,
      loadConnections: () => connections.future,
      loadScheduledPosts: () => posts.future,
    )));
    expect(find.byType(PostDeeSkeleton), findsWidgets);
    expect(find.byKey(const ValueKey('home-create-post')), findsOneWidget);
    drafts.complete([]);
    connections.complete([]);
    posts.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(PostDeeSkeleton), findsNothing);
  });

  testWidgets(
      'public refresh waits for all sources and coalesces simultaneous calls',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    final drafts = Completer<List<PublishDraft>>();
    final connections = Completer<List<SocialConnectionResult>>();
    final posts = Completer<List<PostSummaryResult>>();
    var draftLoads = 0;
    var connectionLoads = 0;
    var postLoads = 0;
    await tester.pumpWidget(_app(_section(
      key: key,
      loadDrafts: () {
        draftLoads++;
        return drafts.future;
      },
      loadConnections: () {
        connectionLoads++;
        return connections.future;
      },
      loadScheduledPosts: () {
        postLoads++;
        return posts.future;
      },
    )));
    final first = key.currentState!.refresh();
    final second = key.currentState!.refresh();
    expect(identical(first, second), isTrue);
    bool? result;
    first.then((value) => result = value);
    drafts.complete([]);
    connections.complete([]);
    await tester.pump();
    expect(result, isNull);
    posts.complete([]);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect([draftLoads, connectionLoads, postLoads], [1, 1, 1]);
  });

  testWidgets(
      'refresh preserves loaded cards and confirmed counts while pending',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    final drafts = Completer<List<PublishDraft>>();
    final connections = Completer<List<SocialConnectionResult>>();
    final posts = Completer<List<PostSummaryResult>>();
    var draftLoads = 0;
    var connectionLoads = 0;
    var postLoads = 0;
    await tester.pumpWidget(_app(_section(
      key: key,
      loadDrafts: () =>
          ++draftLoads == 1 ? Future.value([_draft('kept')]) : drafts.future,
      loadConnections: () => ++connectionLoads == 1
          ? Future.value(const [
              SocialConnectionResult(platform: 'TIKTOK', connected: true)
            ])
          : connections.future,
      loadScheduledPosts: () =>
          ++postLoads == 1 ? Future.value([_post('kept', 30)]) : posts.future,
    )));
    await tester.pumpAndSettle();
    final refresh = key.currentState!.refresh();
    await tester.pump();
    expect(find.text('แคปชัน kept'), findsOneWidget);
    expect(find.text('โพสต์ kept'), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 1/4 ช่องทาง'), findsOneWidget);
    expect(find.byType(PostDeeSkeleton), findsNothing);
    drafts.complete([]);
    connections.complete([]);
    posts.complete([]);
    await tester.pumpAndSettle();
    expect(await refresh, isTrue);
  });

  testWidgets(
      'refresh returns false on any source error and retains known content',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    var calls = 0;
    await tester.pumpWidget(_app(_section(
      key: key,
      loadDrafts: () async => [_draft('kept')],
      loadConnections: () async {
        if (++calls > 1) throw StateError('network');
        return const [
          SocialConnectionResult(platform: 'TIKTOK', connected: true)
        ];
      },
    )));
    await tester.pumpAndSettle();
    final refresh = key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(await refresh, isFalse);
    expect(find.text('แคปชัน kept'), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 1/4 ช่องทาง'), findsOneWidget);
    expect(find.text('ตรวจสอบช่องทางไม่ได้'), findsOneWidget);
  });

  testWidgets(
      'owner changes start an independent refresh and invalidate the old completion',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    final oldDrafts = Completer<List<PublishDraft>>();
    var calls = 0;
    await tester.pumpWidget(_app(_section(
        key: key,
        loadDrafts: () {
          calls++;
          return calls == 1
              ? oldDrafts.future
              : Future.value([_draft('buyer', owner: 'buyer')]);
        })));
    final oldRefresh = key.currentState!.refresh();
    _signIn('buyer');
    final newRefresh = key.currentState!.refresh();
    expect(identical(oldRefresh, newRefresh), isFalse);
    await tester.pumpAndSettle();
    expect(await newRefresh, isTrue);
    oldDrafts.complete([_draft('seller')]);
    await tester.pumpAndSettle();
    expect(await oldRefresh, isFalse);
    expect(find.text('แคปชัน buyer'), findsOneWidget);
    expect(find.text('แคปชัน seller'), findsNothing);
  });

  testWidgets(
      'all failed sources complete refresh with false and individual retry states',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    await tester.pumpWidget(_app(_section(
      key: key,
      loadDrafts: () async => throw StateError('storage'),
      loadConnections: () async => throw StateError('connections'),
      loadScheduledPosts: () async => throw StateError('scheduled'),
    )));
    final completion = key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(await completion, isFalse);
    expect(find.byKey(const ValueKey('home-retry-drafts')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-retry-connections')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-retry-upcoming')), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsNothing);
    expect(find.byType(PostDeeSkeleton), findsNothing);
  });

  testWidgets('known empty sources remain confirmed content during a refresh',
      (tester) async {
    final key = GlobalKey<HomeActivitySectionState>();
    final drafts = Completer<List<PublishDraft>>();
    final connections = Completer<List<SocialConnectionResult>>();
    final posts = Completer<List<PostSummaryResult>>();
    var draftLoads = 0;
    var connectionLoads = 0;
    var postLoads = 0;
    await tester.pumpWidget(_app(_section(
      key: key,
      hasPosts: false,
      loadDrafts: () => ++draftLoads == 1 ? Future.value([]) : drafts.future,
      loadConnections: () =>
          ++connectionLoads == 1 ? Future.value([]) : connections.future,
      loadScheduledPosts: () =>
          ++postLoads == 1 ? Future.value([]) : posts.future,
    )));
    await tester.pumpAndSettle();
    final completion = key.currentState!.refresh();
    await tester.pump();
    expect(find.text('เริ่มโพสต์แรกของคุณ'), findsOneWidget);
    expect(find.text('เชื่อมแล้ว 0/4 ช่องทาง'), findsOneWidget);
    expect(find.byType(PostDeeSkeleton), findsNothing);
    expect(find.text('โพสต์ถัดไป'), findsNothing);
    drafts.complete([]);
    connections.complete([]);
    posts.complete([]);
    await tester.pumpAndSettle();
    expect(await completion, isTrue);
  });

  testWidgets(
      'signed-out home does not start a refresh or keep loading skeletons',
      (tester) async {
    PostDeeAuthSessionStore.instance.clear();
    final key = GlobalKey<HomeActivitySectionState>();
    var calls = 0;
    await tester.pumpWidget(_app(_section(
      key: key,
      loadDrafts: () async {
        calls++;
        return [];
      },
    )));
    await tester.pumpAndSettle();
    expect(await key.currentState!.refresh(), isFalse);
    expect(calls, 0);
    expect(find.byType(PostDeeSkeleton), findsNothing);
    expect(find.byType(HomeDraftThumbnail), findsNothing);
  });

  for (final entry in <({String name, PublishDraft draft, String step})>[
    (
      name: 'blank caption',
      draft: _draft('blank', caption: ''),
      step: 'แคปชัน'
    ),
    (
      name: 'caption review',
      draft: _draft('review', needsReview: true),
      step: 'แคปชัน'
    ),
    (
      name: 'no channels',
      draft: _draft('channels', platforms: {}),
      step: 'ช่องทาง'
    ),
    (name: 'ready for review', draft: _draft('review-ready'), step: 'ตรวจทาน'),
  ]) {
    testWidgets('next action is derived from ${entry.name}', (tester) async {
      await tester
          .pumpWidget(_app(_section(loadDrafts: () async => [entry.draft])));
      await tester.pumpAndSettle();
      expect(find.text('ถัดไป: ${entry.step}'), findsOneWidget);
      final thumbnail =
          tester.widget<HomeDraftThumbnail>(find.byType(HomeDraftThumbnail));
      expect(thumbnail.videoPath, entry.draft.videoPath);
      expect(thumbnail.coverPath, isNull);
    });
  }

  testWidgets('draft cover spans the card and buttons share the bottom row',
      (tester) async {
    await tester.pumpWidget(
        _app(_section(loadDrafts: () async => [_draft('cover-layout')])));
    await tester.pumpAndSettle();
    final preview = tester.getRect(find.byType(HomeDraftThumbnail));
    final caption = tester.getRect(find.text('แคปชัน cover-layout'));
    final primary =
        tester.getRect(find.byKey(const ValueKey('home-resume-draft')));
    final secondary =
        tester.getRect(find.byKey(const ValueKey('home-create-post')));
    expect(preview.width, greaterThan(300));
    expect(preview.height, 120);
    expect(preview.bottom, lessThanOrEqualTo(caption.top));
    expect(primary.top, secondary.top);
    expect(primary.right, lessThanOrEqualTo(secondary.left));
  });

  testWidgets('readable real saved cover is handed to the thumbnail',
      (tester) async {
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('home-cover-test-'));
    final file = File('${directory!.path}${Platform.pathSeparator}cover.png');
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Zb8AAAAASUVORK5CYII=');
    await tester.runAsync(() => file.writeAsBytes(bytes));
    try {
      final key = GlobalKey<HomeActivitySectionState>();
      await tester.pumpWidget(_app(_section(
          key: key,
          loadDrafts: () async => [
                _draft(
                  'real-cover',
                  cover: PublishDraftCover(
                      imagePath: file.path,
                      sizeBytes: bytes.length,
                      design: const CoverDesign(),
                      sourceKind: CoverSourceKind.videoFrame),
                )
              ])));
      // File.open/close completes outside Flutter's fake clock. Let each real
      // IO completion arrive, then flush the widget's queued continuations.
      for (var attempt = 0;
          attempt < 20 && find.byType(HomeDraftThumbnail).evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final thumbnail =
          tester.widget<HomeDraftThumbnail>(find.byType(HomeDraftThumbnail));
      expect(thumbnail.coverPath, file.path);
      expect(thumbnail.videoPath, '/drafts/real-cover.mp4');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });

  testWidgets('a failed draft lookup still allows creating a fresh post',
      (tester) async {
    var created = 0;
    await tester.pumpWidget(_app(_section(
      loadDrafts: () async => throw StateError('storage unavailable'),
      onCreatePost: () async => created++,
    )));
    await tester.pumpAndSettle();
    await _tap(tester, 'home-create-post');
    expect(created, 1);
  });

  testWidgets('confirmed empty schedules do not add an unnecessary card',
      (tester) async {
    await tester.pumpWidget(_app(_section()));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ถัดไป'), findsNothing);
    expect(find.byKey(const ValueKey('home-open-calendar')), findsNothing);
  });

  testWidgets('narrow screens and larger text do not overflow', (tester) async {
    await tester.pumpWidget(_app(
        _section(
          loadDrafts: () async => [_draft('a-very-long-name-that-must-wrap')],
          loadScheduledPosts: () async =>
              [_post('a-very-long-name-that-must-wrap', 30)],
        ),
        width: 320,
        textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
