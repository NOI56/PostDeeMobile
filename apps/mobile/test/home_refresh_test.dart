import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

class _RefreshData {
  final calls = <String, int>{};
  final gates = <String, Completer<void>>{};
  String? failing;
  static const keys = [
    'plan',
    'posts',
    'drafts',
    'connections',
    'queue',
    'shop'
  ];

  Future<T> read<T>(String name, T value) async {
    calls[name] = (calls[name] ?? 0) + 1;
    await gates[name]?.future;
    if (failing == name) throw StateError('offline');
    return value;
  }

  void block() {
    for (final key in keys) {
      gates[key] = Completer<void>();
    }
  }

  void completeExcept([String? pending]) {
    for (final entry in gates.entries) {
      if (entry.key != pending && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
  }

  HomeScreen home({bool active = true, bool empty = false}) => HomeScreen(
        isActive: active,
        loadSubscription: () => read(
          'plan',
          const SubscriptionStatusResult(
            userId: 'refresh-owner',
            plan: 'PRO',
            status: 'ACTIVE',
            remainingPostsThisMonth: 248,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
        ),
        loadRecentPosts: () => read('posts', <PostSummaryResult>[
          if (!empty)
            PostSummaryResult(
              id: 'post-owned',
              caption: 'โพสต์เดิมที่ยังอ่านได้',
              videoS3Key: '',
              platforms: const ['YOUTUBE_SHORTS'],
              status: 'PUBLISHED',
              createdAt: DateTime.utc(2026, 10, 11),
            ),
        ]),
        loadDrafts: () => read('drafts', <PublishDraft>[]),
        loadConnections: () => read('connections', <SocialConnectionResult>[
          if (!empty)
            const SocialConnectionResult(
              platform: 'YOUTUBE_SHORTS',
              connected: true,
              externalAccountId: 'owned-channel',
            ),
        ]),
        loadScheduledPosts: () => read('queue', <PostSummaryResult>[]),
        loadLinkProfile: () => read<LinkInBioProfileResult?>(
          'shop',
          empty
              ? null
              : LinkInBioProfileResult(
                  storeName: 'ร้านของฉัน',
                  slug: 'my-shop',
                  links: const [],
                  isPublished: true,
                  updatedAt: DateTime.utc(2026, 10, 11),
                  publicUrl: Uri.parse('https://example.com/p/my-shop'),
                ),
        ),
        onCreatePost: () async {},
      );
}

Widget _app(HomeScreen home) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('th'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: home),
    );

Future<void> _refresh(WidgetTester tester) => tester
    .widget<RefreshIndicator>(find.byKey(const ValueKey('home-pull-refresh')))
    .onRefresh();

void main() {
  setUp(() => PostDeeAuthSessionStore.instance
      .signIn(const AuthSession(userId: 'refresh-owner', idToken: 'token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);

  testWidgets('pull refresh keeps content and waits for every Home resource',
      (tester) async {
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home()));
    await tester.pumpAndSettle();
    data.block();
    var completed = false;
    final pending = _refresh(tester).then((_) => completed = true);
    await tester.pump();
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
    expect(find.text('โพสต์เดิมที่ยังอ่านได้'), findsOneWidget);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsNothing);
    data.completeExcept('shop');
    await tester.pump();
    await tester.pump();
    expect(completed, isFalse);
    data.gates['shop']!.complete();
    await tester.pumpAndSettle();
    await pending;
    expect(completed, isTrue);
    expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsOneWidget);
    for (final key in _RefreshData.keys) {
      expect(data.calls[key], 2, reason: '$key should refresh once');
    }
  });

  testWidgets('repeated pull and lifecycle resume share pending owner reads',
      (tester) async {
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home()));
    await tester.pumpAndSettle();
    data.block();
    final first = _refresh(tester);
    final second = _refresh(tester);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    for (final key in _RefreshData.keys) {
      expect(data.calls[key], 2,
          reason: '$key must not duplicate pending reads');
    }
    data.completeExcept();
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    for (final key in _RefreshData.keys) {
      expect(data.calls[key], 2, reason: '$key must not queue another read');
    }
  });

  testWidgets('partial refresh reports failure and retains previous content',
      (tester) async {
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home()));
    await tester.pumpAndSettle();
    data.failing = 'posts';
    await _refresh(tester);
    await tester.pumpAndSettle();
    expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsNothing);
    expect(find.text('อัปเดตข้อมูลยังไม่ครบ ลองใหม่ในส่วนที่มีปัญหา'),
        findsOneWidget);
    expect(find.text('โพสต์เดิมที่ยังอ่านได้'), findsOneWidget);
    expect(find.text('โหลดโพสต์ล่าสุดไม่สำเร็จ'), findsOneWidget);
  });

  for (final resource in ['plan', 'drafts', 'connections', 'queue', 'shop']) {
    testWidgets('refresh cannot report success when $resource fails',
        (tester) async {
      final data = _RefreshData();
      await tester.pumpWidget(_app(data.home()));
      await tester.pumpAndSettle();
      data.failing = resource;
      await _refresh(tester);
      await tester.pumpAndSettle();
      expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsNothing);
      expect(find.text('อัปเดตข้อมูลยังไม่ครบ ลองใหม่ในส่วนที่มีปัญหา'),
          findsOneWidget);
      expect(find.text('โพสต์เดิมที่ยังอ่านได้'), findsOneWidget);
      expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
    });
  }

  testWidgets('tab reactivation coalesces a refresh still in progress',
      (tester) async {
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home()));
    await tester.pumpAndSettle();
    data.block();
    final pending = _refresh(tester);
    await tester.pump();
    await tester.pumpWidget(_app(data.home(active: false)));
    await tester.pump();
    await tester.pumpWidget(_app(data.home()));
    await tester.pump();
    for (final key in _RefreshData.keys) {
      expect(data.calls[key], 2,
          reason: '$key must share its current owner read');
    }
    data.completeExcept();
    await tester.pumpAndSettle();
    await pending;
    for (final key in _RefreshData.keys) {
      expect(data.calls[key], 2, reason: '$key must not enqueue another read');
    }
  });

  testWidgets('old owner refresh completion never reports success',
      (tester) async {
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home()));
    await tester.pumpAndSettle();
    data.block();
    final pending = _refresh(tester);
    await tester.pump();
    final previousGates = Map<String, Completer<void>>.of(data.gates);
    data.gates.clear();
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'new-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    for (final gate in previousGates.values) {
      gate.complete();
    }
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsNothing);
    expect(find.text('อัปเดตข้อมูลยังไม่ครบ ลองใหม่ในส่วนที่มีปัญหา'),
        findsNothing);
  });

  testWidgets('short empty Home remains scrollable for pull refresh',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = _RefreshData();
    await tester.pumpWidget(_app(data.home(empty: true)));
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(data.calls['posts'], 2);
    expect(find.text('อัปเดตข้อมูลล่าสุดแล้ว'), findsOneWidget);
  });
}
