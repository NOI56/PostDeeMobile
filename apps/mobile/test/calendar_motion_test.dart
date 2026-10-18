import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_skeleton.dart';

final _now = DateTime(2026, 10, 12, 9);

ScheduledPostResult _post(String id, int day,
        {String platform = 'TIKTOK', String? owner}) =>
    ScheduledPostResult(
      id: id,
      caption: id,
      videoS3Key: 'uploads/$id.mp4',
      platforms: [platform],
      status: 'PUBLISHED',
      scheduledAt: DateTime(2026, 10, day, 10),
      publishedAt: DateTime(2026, 10, day, 10),
      createdAt: _now.subtract(const Duration(days: 1)),
      userId: owner,
    );

Widget _app(CalendarScreen screen,
        {bool reducedMotion = false,
        bool tickerEnabled = true,
        double width = 390,
        double textScale = 1}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData().copyWith(
          size: Size(width, 844),
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: TickerMode(enabled: tickerEnabled, child: screen),
        ),
      ),
    );

Finder _day(int day) => find.byKey(ValueKey('calendar-day-2026-10-$day'));

Finder _dayPress(int day) => find.descendant(
      of: _day(day),
      matching: find.byKey(const ValueKey('postdee-press-transform')),
    );

double _dayScale(WidgetTester tester, int day) =>
    tester.widget<Transform>(_dayPress(day)).transform.entry(0, 0);

double _contentOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find.byKey(const ValueKey('calendar-day-content-opacity')))
    .opacity;

Color? _selectionColor(WidgetTester tester, Finder control) => (tester
        .widget<DecoratedBox>(find
            .descendant(of: control, matching: find.byType(DecoratedBox))
            .first)
        .decoration as BoxDecoration)
    .color;

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

void main() {
  setUp(() {
    final session = PostDeeAuthSessionStore.instance;
    final previous = session.session;
    addTearDown(() => session.signIn(previous));
    session.signIn(const AuthSession(userId: 'motion-user', idToken: 'test'));
  });

  testWidgets(
      'sending row shows actual channel outcomes without invented progress',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(CalendarScreen(
        now: () => _now,
        loadCalendarPosts: () async => [
          CalendarPostResult(
            id: 'sending',
            caption: 'คลิปที่กำลังส่ง',
            videoS3Key: 'uploads/sending.mp4',
            platforms: const [
              'TIKTOK',
              'YOUTUBE_SHORTS',
              'INSTAGRAM_REELS',
              'FACEBOOK_REELS',
            ],
            status: 'PUBLISHING',
            createdAt: _now,
            platformResults: const [
              PostPlatformResult(
                  postId: 'sending',
                  platform: 'TIKTOK',
                  status: 'PUBLISHED',
                  deliveryOutcome: 'DRAFT'),
              PostPlatformResult(
                  postId: 'sending',
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHING'),
              PostPlatformResult(
                  postId: 'sending',
                  platform: 'INSTAGRAM_REELS',
                  status: 'FAILED'),
            ],
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('calendar-publishing-rail-sending')),
          findsOneWidget);
      expect(find.text('กำลังส่ง'), findsWidgets);
      expect(find.textContaining('ส่งเป็นร่างแล้ว'), findsOneWidget);
      expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
      expect(find.textContaining('รอผล'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(
              '.*TikTok ส่งเป็นร่างแล้ว.*Shorts กำลังส่ง.*Reels ส่งไม่สำเร็จ.*Facebook รอผล.*')),
          findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an incomplete draft result keeps the publishing post sending',
      (tester) async {
    await tester.pumpWidget(_app(
        CalendarScreen(
          now: () => _now,
          loadCalendarPosts: () async => [
            CalendarPostResult(
              id: 'incomplete',
              caption: 'ยังส่งไม่ครบทุกช่องทาง',
              videoS3Key: 'uploads/incomplete.mp4',
              platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
              status: 'PUBLISHING',
              createdAt: _now,
              platformResults: const [
                PostPlatformResult(
                    postId: 'incomplete',
                    platform: 'TIKTOK',
                    status: 'PUBLISHED',
                    deliveryOutcome: 'DRAFT'),
              ],
            ),
          ],
        ),
        reducedMotion: true));
    await tester.pumpAndSettle();
    expect(find.text('กำลังส่ง'), findsOneWidget);
    expect(find.textContaining('ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.textContaining('รอผล'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-publishing-rail-incomplete')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['inactive', 'reduced', 'ticker', 'background']) {
    testWidgets(
        'sending row pauses for $mode and resumes without losing content',
        (tester) async {
      _resumeMotion(tester.binding);
      addTearDown(() => _resumeMotion(tester.binding));
      final key = GlobalKey();
      Widget host(bool blocked) => _app(
            CalendarScreen(
              key: key,
              now: () => _now,
              isActive: mode != 'inactive' || !blocked,
              loadScheduledPosts: () async => [
                ScheduledPostResult(
                  id: 'sending',
                  caption: 'คลิปที่กำลังส่ง',
                  videoS3Key: 'uploads/sending.mp4',
                  platforms: const ['TIKTOK'],
                  scheduledAt: _now,
                  status: 'PUBLISHING',
                  createdAt: _now,
                ),
              ],
            ),
            reducedMotion: mode == 'reduced' && blocked,
            tickerEnabled: mode != 'ticker' || !blocked,
          );
      await tester.pumpWidget(host(false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      } else {
        await tester.pumpWidget(host(true));
      }
      await tester.pumpAndSettle();
      expect(find.text('คลิปที่กำลังส่ง'), findsOneWidget);
      expect(find.text('กำลังส่ง'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      if (mode == 'background') {
        _resumeMotion(tester.binding);
        await tester.pump();
      } else {
        await tester.pumpWidget(host(false));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sending refresh stops its motion at a real private result',
      (tester) async {
    var finished = false;
    await tester.pumpWidget(_app(CalendarScreen(
      now: () => _now,
      loadCalendarPosts: () async => [
        CalendarPostResult(
          id: 'sending',
          caption: 'คลิปที่กำลังส่ง',
          videoS3Key: 'uploads/sending.mp4',
          platforms: const ['TIKTOK'],
          status: finished ? 'PUBLISHED' : 'PUBLISHING',
          createdAt: _now,
          publishedAt: finished ? _now : null,
          platformResults: finished
              ? const [
                  PostPlatformResult(
                      postId: 'sending',
                      platform: 'TIKTOK',
                      status: 'PUBLISHED',
                      deliveryOutcome: 'PRIVATE'),
                ]
              : const [],
        ),
      ],
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    finished = true;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('ส่วนตัว'), findsOneWidget);
    expect(find.text('กำลังส่ง'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-publishing-rail-sending')),
        findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['inactive', 'reduced', 'ticker', 'background']) {
    testWidgets('motion audit $mode finishes a live day fade without replay',
        (tester) async {
      _resumeMotion(tester.binding);
      addTearDown(() => _resumeMotion(tester.binding));
      final key = GlobalKey();
      Widget host(bool blocked) => _app(
            CalendarScreen(
              key: key,
              isActive: mode != 'inactive' || !blocked,
              now: () => _now,
              loadScheduledPosts: () async => [
                _post('Monday current', 12),
                _post('Tuesday current', 13),
              ],
            ),
            reducedMotion: mode == 'reduced' && blocked,
            tickerEnabled: mode != 'ticker' || !blocked,
          );
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      await tester.tap(_day(13));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_contentOpacity(tester), inExclusiveRange(0, 1));
      expect(find.text('Monday current'), findsNothing);
      if (mode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      } else {
        await tester.pumpWidget(host(true));
      }
      expect(_contentOpacity(tester), 1);
      expect(find.text('Tuesday current'), findsOneWidget);
      if (mode == 'background') {
        _resumeMotion(tester.binding);
        await tester.pump();
      } else {
        await tester.pumpWidget(host(false));
      }
      expect(_contentOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 30));
      expect(_contentOpacity(tester), 1);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final control in ['day', 'view', 'platform']) {
      testWidgets('motion audit $mode snaps live $control selection color',
          (tester) async {
        _resumeMotion(tester.binding);
        addTearDown(() => _resumeMotion(tester.binding));
        final key = GlobalKey();
        Widget host(bool blocked) => _app(
              CalendarScreen(
                key: key,
                isActive: mode != 'inactive' || !blocked,
                now: () => _now,
                loadScheduledPosts: () async => const [],
              ),
              reducedMotion: mode == 'reduced' && blocked,
              tickerEnabled: mode != 'ticker' || !blocked,
            );
        await tester.pumpWidget(host(false));
        await tester.pumpAndSettle();
        final selected = control == 'day'
            ? _day(13)
            : find.byKey(ValueKey(control == 'view'
                ? 'calendar-month-view'
                : 'calendar-filter-YOUTUBE_SHORTS'));
        final target = control == 'platform'
            ? AppTheme.accent.withValues(alpha: .12)
            : AppTheme.accent;
        await tester.tap(selected);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(_selectionColor(tester, selected), isNot(target));
        if (mode == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding.scheduleForcedFrame();
          await tester.pump();
        } else {
          await tester.pumpWidget(host(true));
        }
        expect(_selectionColor(tester, selected), target);
        if (mode == 'background') {
          _resumeMotion(tester.binding);
          await tester.pump();
        } else {
          await tester.pumpWidget(host(false));
        }
        expect(_selectionColor(tester, selected), target);
        await tester.pump(const Duration(milliseconds: 30));
        expect(_selectionColor(tester, selected), target);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('day press keeps its hit target and cancellation keeps selection',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(CalendarScreen(
        now: () => _now,
        loadScheduledPosts: () async => const [],
      )));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(_day(13));
      expect(_dayPress(13), findsOneWidget);
      final gesture = await tester.startGesture(bounds.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_dayScale(tester, 13), closeTo(.97, .001));
      expect(tester.getRect(_day(13)), bounds);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_dayScale(tester, 13), 1);
      expect(tester.getSemantics(_day(12)),
          isSemantics(isButton: true, isSelected: true, hasTapAction: true));
      expect(tester.getSemantics(_day(13)),
          isSemantics(isButton: true, isSelected: false, hasTapAction: true));
      await tester.tap(_day(13));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(_day(13)),
          isSemantics(isButton: true, isSelected: true, hasTapAction: true));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'rapid day and filter changes keep only the current actionable row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final opened = <String>[];
      await tester.pumpWidget(_app(CalendarScreen(
        now: () => _now,
        loadScheduledPosts: () async => [
          _post('Monday clip', 12),
          _post('Tuesday TikTok', 13),
          _post('Tuesday YouTube', 13, platform: 'YOUTUBE_SHORTS'),
          _post('Wednesday YouTube', 14, platform: 'YOUTUBE_SHORTS'),
        ],
        onOpenPostDetail: (post) => opened.add(post.id),
      )));
      await tester.pumpAndSettle();
      await tester.tap(_day(13));
      await tester.pump();
      expect(_contentOpacity(tester), lessThan(1));
      expect(find.text('Monday clip'), findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('calendar-filter-YOUTUBE_SHORTS')));
      await tester.pump();
      await tester.tap(_day(14));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Monday clip'), findsNothing);
      expect(find.text('Tuesday TikTok'), findsNothing);
      expect(find.text('Tuesday YouTube'), findsNothing);
      expect(find.text('Wednesday YouTube'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('.*Wednesday YouTube.*')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('.*Tuesday.*')), findsNothing);
      await tester.ensureVisible(
          find.byKey(const ValueKey('calendar-post-Wednesday YouTube')));
      await tester
          .tap(find.byKey(const ValueKey('calendar-post-Wednesday YouTube')));
      await tester.pumpAndSettle();
      expect(opened, ['Wednesday YouTube']);
      expect(_contentOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('initial loading announces once and refresh keeps existing rows',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final first = Completer<List<ScheduledPostResult>>();
      final refresh = Completer<List<ScheduledPostResult>>();
      var loads = 0;
      await tester.pumpWidget(_app(CalendarScreen(
        now: () => _now,
        loadScheduledPosts: () => ++loads == 1 ? first.future : refresh.future,
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PostDeeSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('กำลังโหลดปฏิทินโพสต์...'), findsOneWidget);
      expect(
          tester
              .getSemantics(find.byKey(const ValueKey('calendar-loading')))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);
      first.complete([_post('Retained clip', 12)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Retained clip'), findsOneWidget);
      expect(find.byType(PostDeeSkeleton), findsNothing);
      await tester.pumpAndSettle();
      final indicator =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final pending = indicator.onRefresh();
      await tester.pump();
      expect(find.text('Retained clip'), findsOneWidget);
      expect(find.byType(PostDeeSkeleton), findsNothing);
      expect(_contentOpacity(tester), 1);
      refresh.complete([_post('Retained clip', 12)]);
      await pending;
      await tester.pumpAndSettle();
      expect(find.text('Retained clip'), findsOneWidget);
      expect(loads, 2);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reduced motion applies selections immediately and stops frames',
      (tester) async {
    await tester.pumpWidget(_app(
        CalendarScreen(
          now: () => _now,
          loadScheduledPosts: () async => [
            _post('Monday clip', 12),
            _post('Tuesday clip', 13, platform: 'YOUTUBE_SHORTS'),
          ],
        ),
        reducedMotion: true));
    await tester.pumpAndSettle();
    await tester.tap(_day(13));
    await tester.pump();
    expect(_contentOpacity(tester), 1);
    expect(find.text('Monday clip'), findsNothing);
    expect(find.text('Tuesday clip'), findsOneWidget);
    expect(_day(31), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pump();
    expect(_day(31), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final gesture = await tester.startGesture(tester.getCenter(_day(13)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_dayScale(tester, 13), 1);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('initial skeleton stops when inactive or TickerMode is disabled',
      (tester) async {
    for (final stopMode in ['inactive', 'ticker']) {
      final loading = Completer<List<ScheduledPostResult>>();
      CalendarScreen screen(bool active) => CalendarScreen(
            now: () => _now,
            isActive: active,
            loadScheduledPosts: () => loading.future,
          );
      await tester.pumpWidget(_app(screen(true)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(PostDeeSkeleton), findsWidgets);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(_app(screen(stopMode != 'inactive'),
          tickerEnabled: stopMode != 'ticker'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDeeSkeleton), findsWidgets);
      expect(tester.binding.hasScheduledFrame, isFalse);
      loading.complete(const []);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('loading skeleton stops in background and resumes in foreground',
      (tester) async {
    final loading = Completer<List<ScheduledPostResult>>();
    await tester.pumpWidget(_app(CalendarScreen(
      now: () => _now,
      loadScheduledPosts: () => loading.future,
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PostDeeSkeleton), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    loading.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(PostDeeSkeleton), findsNothing);
  });

  testWidgets('owner replacement removes previous rows even during transition',
      (tester) async {
    final loading = Completer<List<ScheduledPostResult>>();
    final session = PostDeeAuthSessionStore.instance;
    session.signIn(const AuthSession(userId: 'owner-a', idToken: 'a'));
    CalendarScreen screen(String owner) => CalendarScreen(
          ownerUserId: owner,
          now: () => _now,
          loadScheduledPosts: () => owner == 'owner-a'
              ? Future.value([
                  _post('Owner A Monday', 12, owner: owner),
                  _post('Owner A Tuesday', 13, owner: owner),
                ])
              : loading.future,
        );
    await tester.pumpWidget(_app(screen('owner-a')));
    await tester.pumpAndSettle();
    await tester.tap(_day(13));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_contentOpacity(tester), lessThan(1));
    session.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    await tester.pumpWidget(_app(screen('owner-b')));
    expect(find.text('Owner A Monday'), findsNothing);
    expect(find.text('Owner A Tuesday'), findsNothing);
    expect(find.byType(PostDeeSkeleton), findsWidgets);
    loading.complete([_post('Owner B Monday', 12, owner: 'owner-b')]);
    await tester.pumpAndSettle();
    expect(find.text('Owner B Monday'), findsOneWidget);
    expect(find.text('Owner A Tuesday'), findsNothing);
  });

  testWidgets('week to month motion fits 320dp with large Thai text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
        CalendarScreen(
          now: () => _now,
          loadScheduledPosts: () async => [_post('คลิปทดสอบปฏิทิน', 12)],
          onAddPostForDate: (_) {},
        ),
        width: 320,
        textScale: 1.8));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.tap(_day(13));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
