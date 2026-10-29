import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';

SubscriptionStatusResult _scheduleSubscription(String plan) =>
    SubscriptionStatusResult(
        userId: 'calendar-user',
        plan: plan,
        status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
        canSchedule: plan == 'STARTER' || plan == 'PRO',
        canUseAiCaptions: false,
        canUseAnalytics: false);

ScheduledPostResult _queuedFixture(DateTime now) => ScheduledPostResult(
    id: 'existing-queue',
    caption: 'คิวเดิม',
    videoS3Key: 'uploads/existing.mp4',
    platforms: const ['TIKTOK'],
    scheduledAt: now.add(const Duration(days: 20)),
    status: 'QUEUED',
    createdAt: now);

Widget _calendarApp(CalendarScreen calendar) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: calendar),
    );

ScheduledPostResult _compactPost(String id, DateTime date,
        {String status = 'QUEUED',
        List<String> platforms = const ['TIKTOK'],
        String? owner}) =>
    ScheduledPostResult(
      id: id,
      caption: id,
      videoS3Key: 'uploads/$id.mp4',
      platforms: platforms,
      scheduledAt: date,
      status: status,
      userId: owner,
      createdAt: date.subtract(const Duration(days: 1)),
    );

void main() {
  for (final status in ['PUBLISHED', 'PARTIAL_PUBLISHED']) {
    testWidgets(
        'immediate $status appears under Shorts on its local published day',
        (tester) async {
      final publishedAt = DateTime.utc(2026, 10, 13, 18, 30);
      final post = CalendarPostResult(
        id: 'immediate-$status',
        caption: 'Immediate $status clip',
        videoS3Key: 'uploads/immediate.mp4',
        platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
        status: status,
        createdAt: DateTime.utc(2026, 10, 13, 15),
        publishedAt: publishedAt,
        platformResults: [
          PostPlatformResult(
              postId: 'immediate-$status',
              platform: 'TIKTOK',
              status: status == 'PARTIAL_PUBLISHED' ? 'FAILED' : 'PUBLISHED'),
          PostPlatformResult(
              postId: 'immediate-$status',
              platform: 'YOUTUBE_SHORTS',
              status: 'PUBLISHED',
              deliveryOutcome: 'PRIVATE'),
        ],
      );
      CalendarPostResult? opened;
      await tester.pumpWidget(_calendarApp(CalendarScreen(
        now: () => DateTime(2026, 10, 14, 2),
        toLocalTime: (value) => value.toUtc().add(const Duration(hours: 7)),
        loadCalendarPosts: () async => [post],
        onOpenCalendarPostDetail: (value) => opened = value,
      )));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('calendar-filter-YOUTUBE_SHORTS')));
      await tester.pumpAndSettle();
      expect(find.text(post.caption), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(
          find.text(
              status == 'PARTIAL_PUBLISHED' ? 'ส่งบางส่วน' : 'ส่วนตัว'),
          findsOneWidget);
      await tester.ensureVisible(find.text(post.caption));
      await tester.tap(find.text(post.caption));
      await tester.pumpAndSettle();
      expect(opened, same(post));
      expect(opened!.scheduledAt, isNull);
      expect(find.text('เลื่อนเวลา'), findsNothing);
      expect(find.text('ยกเลิกโพสต์'), findsNothing);
    });
  }

  testWidgets(
      'immediate queued and failed activity use created day without queue actions',
      (tester) async {
    final now = DateTime(2026, 10, 14, 10);
    var actions = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async => [
        for (final status in ['QUEUED', 'FAILED'])
          CalendarPostResult(
              id: 'immediate-$status',
              caption: 'Immediate $status',
              videoS3Key: 'uploads/immediate.mp4',
              platforms: const ['YOUTUBE_SHORTS'],
              status: status,
              createdAt: now),
      ],
      cancelPost: (_) async => actions++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Immediate QUEUED'), findsOneWidget);
    expect(find.text('Immediate FAILED'), findsOneWidget);
    await tester.ensureVisible(find.text('Immediate QUEUED'));
    await tester.tap(find.text('Immediate QUEUED'));
    await tester.pumpAndSettle();
    expect(find.text('เลื่อนเวลา'), findsNothing);
    expect(find.text('ยกเลิกโพสต์'), findsNothing);
    expect(actions, 0);
  });

  testWidgets(
      'calendar activity keeps future queue dates and owned legacy actions',
      (tester) async {
    final now = DateTime(2026, 10, 14, 10);
    final queued = _compactPost(
        'Future scheduled clip', now.add(const Duration(days: 1)));
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async => [
        CalendarPostResult.fromScheduledPost(queued),
        CalendarPostResult(
            id: 'foreign',
            caption: 'Foreign clip',
            userId: 'other-owner',
            videoS3Key: 'uploads/foreign.mp4',
            platforms: const ['YOUTUBE_SHORTS'],
            status: 'PUBLISHED',
            createdAt: now,
            publishedAt: now),
      ],
      ownerUserId: 'calendar-owner',
      loadSubscription: () async => _scheduleSubscription('PRO'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Foreign clip'), findsNothing);
    expect(find.text(queued.caption), findsOneWidget);
    await tester.ensureVisible(find.text(queued.caption));
    await tester.tap(find.text(queued.caption));
    await tester.pumpAndSettle();
    expect(find.text('เลื่อนเวลา'), findsOneWidget);
    expect(find.text('ยกเลิกโพสต์'), findsOneWidget);
  });

  for (final activity in [
    (status: 'PUBLISHED', scheduledAt: null, publishedAt: null),
    (
      status: 'PARTIAL_PUBLISHED',
      scheduledAt: DateTime.utc(2026, 10, 13, 18, 30),
      publishedAt: null
    ),
    (
      status: 'FAILED',
      scheduledAt: DateTime.utc(2026, 10, 15),
      publishedAt: DateTime.utc(2026, 10, 13, 18, 30)
    ),
    (
      status: 'QUEUED',
      scheduledAt: DateTime.utc(2026, 10, 13, 18, 30),
      publishedAt: DateTime.utc(2026, 10, 15)
    ),
  ]) {
    testWidgets(
        '${activity.status} calendar uses real activity date fallbacks in Bangkok',
        (tester) async {
      final post = CalendarPostResult(
        id: 'date-fallback',
        caption: 'Activity date fallback',
        videoS3Key: 'uploads/clip.mp4',
        platforms: const ['YOUTUBE_SHORTS'],
        status: activity.status,
        createdAt: activity.status == 'PUBLISHED'
            ? DateTime.utc(2026, 10, 13, 18, 30)
            : DateTime.utc(2026, 10, 1),
        scheduledAt: activity.scheduledAt,
        publishedAt: activity.publishedAt,
      );
      await tester.pumpWidget(_calendarApp(CalendarScreen(
        now: () => DateTime(2026, 10, 14, 2),
        toLocalTime: (value) => value.toUtc().add(const Duration(hours: 7)),
        loadCalendarPosts: () async => [post],
      )));
      await tester.pumpAndSettle();
      expect(find.text(post.caption), findsOneWidget);
      expect(find.text('14 ต.ค. 2026'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
    });
  }

  testWidgets('immediate activity polls while publishing and stops once finished',
      (tester) async {
    final now = DateTime(2026, 10, 14, 10);
    var loads = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async {
        loads++;
        return [
          CalendarPostResult(
            id: 'immediate-polling',
            caption: 'Immediate polling',
            videoS3Key: 'uploads/clip.mp4',
            platforms: const ['YOUTUBE_SHORTS'],
            status: switch (loads) {
              1 => 'QUEUED',
              2 => 'PUBLISHING',
              _ => 'PUBLISHED'
            },
            createdAt: now,
            publishedAt: loads < 3 ? null : now,
          )
        ];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('รอส่ง'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loads, 2);
    expect(find.text('กำลังส่ง'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(loads, 3);
    expect(find.text('ส่งสำเร็จ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(loads, 3);
  });

  testWidgets(
      'compact rows retain all channels and one-line time with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 10, 11, 12, 30);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: Scaffold(
              body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [
              _compactPost('Clip with all channels', now,
                  status: 'PARTIAL_PUBLISHED',
                  platforms: const [
                    'TIKTOK',
                    'YOUTUBE_SHORTS',
                    'INSTAGRAM_REELS',
                    'FACEBOOK_REELS'
                  ])
            ],
            onAddPostForDate: (_) {},
          )),
        )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('12:30')).maxLines, 1);
    final channels =
        find.byKey(const ValueKey('calendar-channels-Clip with all channels'));
    expect(
        find.descendant(
            of: channels, matching: find.byType(SocialPlatformLogo)),
        findsNWidgets(4));
    final status = find
        .ancestor(
            of: find.text('ส่งสำเร็จบางช่องทาง'),
            matching: find.byType(Container))
        .first;
    final decoration =
        tester.widget<Container>(status).decoration! as BoxDecoration;
    expect(decoration.color, AppTheme.accentPinkInk.withValues(alpha: 0.09));
  });

  testWidgets(
      'normal filters share one row and show platform icons above labels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => DateTime(2026, 10, 11),
      loadScheduledPosts: () async => const [],
    )));
    await tester.pumpAndSettle();
    final keys = [
      'all',
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS',
      'FACEBOOK_REELS'
    ];
    final first =
        tester.getRect(find.byKey(ValueKey('calendar-filter-${keys.first}')));
    for (final key in keys) {
      final filter = find.byKey(ValueKey('calendar-filter-$key'));
      final rect = tester.getRect(filter);
      expect(rect.top, first.top);
      expect(rect.width, closeTo(first.width, 0.1));
      expect(rect.height, greaterThanOrEqualTo(48));
      if (key != 'all') {
        final logo = find.descendant(
            of: filter, matching: find.byType(SocialPlatformLogo));
        final label = find.descendant(of: filter, matching: find.byType(Text));
        expect(tester.getRect(logo).bottom,
            lessThanOrEqualTo(tester.getRect(label).top));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing owner during cancellation confirmation does not call API',
      (tester) async {
    final session = PostDeeAuthSessionStore.instance;
    final original = session.session;
    addTearDown(() => session.signIn(original));
    session.signIn(const AuthSession(userId: 'owner-a', idToken: 'a'));
    var cancellations = 0;
    final now = DateTime(2026, 10, 11, 15, 45);
    CalendarScreen screen(String owner) => CalendarScreen(
          ownerUserId: owner,
          now: () => now,
          loadScheduledPosts: () async =>
              [_compactPost('$owner clip', now, owner: owner)],
          cancelPost: (_) async => cancellations++,
        );
    await tester.pumpWidget(_calendarApp(screen('owner-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('owner-a clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์'));
    await tester.pumpAndSettle();
    session.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    await tester.pumpWidget(_calendarApp(screen('owner-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pumpAndSettle();
    expect(cancellations, 0);
    expect(find.text('owner-b clip'), findsOneWidget);
    expect(find.text('owner-a clip'), findsNothing);
    expect(find.text('ยกเลิกโพสต์แล้ว'), findsNothing);
  });

  testWidgets('month selection handles leap day and week crossing a year',
      (tester) async {
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => DateTime(2028, 2, 29),
      loadScheduledPosts: () async => const [],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('calendar-day-2028-02-29')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-2028-02-30')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(find.text('1 มี.ค. 2028'), findsOneWidget);
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      key: const ValueKey('year-boundary'),
      now: () => DateTime(2026, 12, 31),
      loadScheduledPosts: () async => const [],
    )));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('calendar-day-2027-01-03')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(find.text('7 ม.ค. 2027'), findsOneWidget);
    expect(find.text('มกราคม 2027'), findsOneWidget);
  });

  testWidgets('defaults to a compact week and keeps period selection in sync',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CalendarScreen(
          now: () => DateTime(2026, 10, 11, 15, 45),
          loadScheduledPosts: () async => const [],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('สัปดาห์'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('calendar-day-2026-10-05')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-2026-10-12')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(find.text('18 ต.ค. 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('calendar-day-2026-10-01')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(find.text('1 พ.ย. 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(find.text('11 ต.ค. 2026'), findsOneWidget);
  });

  testWidgets('counts posts once and shows every channel in the compact row',
      (tester) async {
    final now = DateTime(2026, 10, 11, 15, 45);
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadScheduledPosts: () async => [
        _compactPost('Four channels', now, platforms: const [
          'TIKTOK',
          'YOUTUBE_SHORTS',
          'INSTAGRAM_REELS',
          'FACEBOOK_REELS'
        ]),
        _compactPost('Needs review', now,
            status: 'PARTIAL_PUBLISHED', platforms: const ['INSTAGRAM_REELS']),
        _compactPost('Failed clip', now, status: 'FAILED'),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.text('สัปดาห์นี้ 3 โพสต์ · รอส่ง 1 · ต้องตรวจสอบ 2'),
        findsOneWidget);
    final channels =
        find.byKey(const ValueKey('calendar-channels-Four channels'));
    expect(
        find.descendant(
            of: channels, matching: find.byType(SocialPlatformLogo)),
        findsNWidgets(4));
    await tester
        .tap(find.byKey(const ValueKey('calendar-filter-INSTAGRAM_REELS')));
    await tester.pumpAndSettle();
    expect(find.text('สัปดาห์นี้ 2 โพสต์ · รอส่ง 1 · ต้องตรวจสอบ 1'),
        findsOneWidget);
    expect(find.text('Four channels'), findsOneWidget);
    expect(find.text('Failed clip'), findsNothing);
  });

  testWidgets(
      'creates for the selected local day and retains the legacy callback',
      (tester) async {
    DateTime? selected;
    var legacy = 0;
    final now = DateTime(2026, 10, 11, 15, 45);
    CalendarScreen screen({bool dated = true}) => CalendarScreen(
          now: () => now,
          loadScheduledPosts: () async => const [],
          onAddPost: () => legacy++,
          onAddPostForDate: dated ? (date) => selected = date : null,
        );
    await tester.pumpWidget(_calendarApp(screen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-add-post')));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 10, 12));
    expect(selected!.isUtc, isFalse);
    expect(legacy, 0);
    await tester.pumpWidget(_calendarApp(screen(dated: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-add-post')));
    await tester.pumpAndSettle();
    expect(legacy, 1);
  });

  testWidgets('past empty dates offer Today without creating a past schedule',
      (tester) async {
    var creates = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => DateTime(2026, 10, 11, 15, 45),
      loadScheduledPosts: () async => const [],
      onAddPostForDate: (_) => creates++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-10')));
    await tester.pumpAndSettle();
    expect(find.text('วันที่เลือกยังไม่มีโพสต์'), findsOneWidget);
    await tester.ensureVisible(find.text('กลับไปวันนี้'));
    await tester.tap(find.text('กลับไปวันนี้'));
    await tester.pumpAndSettle();
    expect(creates, 0);
    expect(find.text('11 ต.ค. 2026'), findsOneWidget);
  });

  testWidgets(
      'pull refresh keeps rows and reports stale data until retry succeeds',
      (tester) async {
    var now = DateTime(2026, 10, 11, 15, 45);
    var loads = 0;
    final gate = Completer<List<ScheduledPostResult>>();
    final post = _compactPost('Cached clip', now);
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadScheduledPosts: () =>
          ++loads == 2 ? gate.future : Future.value([post]),
    )));
    await tester.pumpAndSettle();
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(find.text('Cached clip'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-loading')), findsNothing);
    now = now.add(const Duration(minutes: 1));
    gate.completeError(StateError('offline'));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Cached clip'), findsOneWidget);
    expect(find.textContaining('ข้อมูลเดิม'), findsWidgets);
    expect(find.text('อัปเดตล่าสุด 15:45'), findsOneWidget);
    await tester.ensureVisible(find.text('ลองใหม่'));
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('อัปเดตล่าสุด 15:46'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-error')), findsNothing);
  });

  testWidgets(
      'owner change clears cached posts and rejects late or foreign results',
      (tester) async {
    final session = PostDeeAuthSessionStore.instance;
    final original = session.session;
    addTearDown(() => session.signIn(original));
    session.signIn(const AuthSession(userId: 'owner-a', idToken: 'a'));
    final gate = Completer<List<ScheduledPostResult>>();
    final now = DateTime(2026, 10, 11, 15, 45);
    var loads = 0;
    CalendarScreen screen(String owner) => CalendarScreen(
          ownerUserId: owner,
          now: () => now,
          loadScheduledPosts: () => ++loads == 1
              ? gate.future
              : Future.value([
                  _compactPost('Current owner', now, owner: 'owner-b'),
                  _compactPost('Foreign owner', now, owner: 'owner-a'),
                ]),
        );
    await tester.pumpWidget(_calendarApp(screen('owner-a')));
    await tester.pump();
    session.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    await tester.pumpWidget(_calendarApp(screen('owner-b')));
    await tester.pumpAndSettle();
    expect(find.text('Current owner'), findsOneWidget);
    expect(find.text('Foreign owner'), findsNothing);
    gate.complete([_compactPost('Late owner', now, owner: 'owner-a')]);
    await tester.pumpAndSettle();
    expect(find.text('Late owner'), findsNothing);
    expect(find.text('Current owner'), findsOneWidget);
  });

  testWidgets(
      'calendar accessibility actions fire once and expose selected days',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var creates = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => DateTime(2026, 10, 11, 15, 45),
      loadScheduledPosts: () async => const [],
      onAddPostForDate: (_) => creates++,
    )));
    await tester.pumpAndSettle();
    final add =
        tester.getSemantics(find.byKey(const ValueKey('calendar-add-post')));
    expect(add.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    add.owner!.performAction(add.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(creates, 1);
    final next =
        tester.getSemantics(find.byKey(const ValueKey('calendar-next-period')));
    next.owner!.performAction(next.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.text('18 ต.ค. 2026'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('calendar-day-2026-10-18'))),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the current month when older scheduled history exists',
      (tester) async {
    final now = DateTime(2026, 10, 9);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadScheduledPosts: () async => [
        ScheduledPostResult(
            id: 'history',
            caption: 'Old post',
            videoS3Key: 'uploads/history.mp4',
            platforms: const ['TIKTOK'],
            status: 'PUBLISHED',
            createdAt: DateTime(2026, 1, 1),
            scheduledAt: DateTime(2026, 1, 2))
      ],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('ตุลาคม 2026'), findsOneWidget);
    expect(find.text('9 ต.ค. 2026'), findsOneWidget);
    expect(find.text('Old post'), findsNothing);
  });
  testWidgets(
      'rechecks a downgrade before PATCH without changing the old queue',
      (tester) async {
    final now = DateTime(2026, 10, 8, 12);
    var plan = 'PRO';
    var checks = 0;
    var calls = 0;
    final post = _queuedFixture(now);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadSubscription: () async {
        checks++;
        return _scheduleSubscription(plan);
      },
      loadScheduledPosts: () async => [post],
      reschedulePost: (_, __) async {
        calls++;
        return post;
      },
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    plan = 'STARTER';
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(calls, 0);
    expect(post.scheduledAt, now.add(const Duration(days: 20)));
    expect(find.text('คิวเดิม'), findsOneWidget);
    expect(find.text('เลื่อนเวลาได้ล่วงหน้าสูงสุด 14 วัน กรุณาเลือกเวลาใหม่'),
        findsOneWidget);
  });

  testWidgets('does not apply a pending plan from a previous signed-in owner',
      (tester) async {
    final session = PostDeeAuthSessionStore.instance;
    final original = session.session;
    session.signIn(AuthSession.authenticated(
        userId: 'calendar-owner-a', idToken: 'test-a'));
    addTearDown(() => session.signIn(original));
    final pending = Completer<SubscriptionStatusResult>();
    final now = DateTime(2026, 10, 8, 12);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadSubscription: () => pending.future,
      loadScheduledPosts: () async => [_queuedFixture(now)],
      reschedulePost: (_, __) async {
        calls++;
        return _queuedFixture(now);
      },
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('คิวเดิม'));
    await tester.tap(find.text('คิวเดิม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pump();
    session.signIn(AuthSession.authenticated(
        userId: 'calendar-owner-b', idToken: 'test-b'));
    pending.complete(_scheduleSubscription('PRO'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(calls, 0);
  });

  testWidgets('cancelling the reschedule wheel keeps the queue without PATCH',
      (tester) async {
    final now = DateTime(2026, 10, 8, 12);
    final post = _queuedFixture(now);
    var calls = 0;
    var planChecks = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadScheduledPosts: () async => [post],
      loadSubscription: () async {
        planChecks++;
        return _scheduleSubscription('PRO');
      },
      reschedulePost: (_, __) async {
        calls++;
        return post;
      },
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);
    final summary = find.byKey(const ValueKey('postdee-time-summary'));
    Finder summaryText() => find.descendant(of: summary, matching: find.byType(Text));
    final previousSummary = tester.widgetList<Text>(summaryText())
        .map((text) => text.data).toList();
    await tester.drag(find.byKey(const ValueKey('postdee-time-minute-picker')),
        const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.widgetList<Text>(summaryText()).map((text) => text.data).toList(),
        isNot(previousSummary));
    await tester.ensureVisible(find.byKey(const ValueKey('postdee-time-cancel')));
    await tester.tap(find.byKey(const ValueKey('postdee-time-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('postdee-time-picker')), findsNothing);
    expect(calls, 0);
    expect(planChecks, 1);
    expect(post.scheduledAt, now.add(const Duration(days: 20)));
    expect(find.text(post.caption), findsOneWidget);
    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    expect(find.text('เลื่อนเวลา'), findsOneWidget,
        reason: 'Cancelling the wheel must release the queued-post action lock');
  });

  testWidgets('an old reschedule wheel cannot PATCH after owner A to B to A',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(AuthSession.authenticated(
        userId: 'wheel-owner-a', idToken: 'test-a'));
    addTearDown(() => sessions.signIn(previous));
    final now = DateTime(2026, 10, 8, 12);
    final post = _queuedFixture(now);
    var calls = 0;
    var planChecks = 0;
    await tester.pumpWidget(_calendarApp(CalendarScreen(
      now: () => now,
      loadScheduledPosts: () async =>
          sessions.session.stableUserId == 'wheel-owner-a' ? [post] : [],
      loadSubscription: () async {
        planChecks++;
        return _scheduleSubscription('PRO');
      },
      reschedulePost: (_, __) async {
        calls++;
        return post;
      },
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('postdee-time-picker')), findsOneWidget);

    sessions.signIn(AuthSession.authenticated(
        userId: 'wheel-owner-b', idToken: 'test-b'));
    await tester.pumpAndSettle();
    sessions.signIn(AuthSession.authenticated(
        userId: 'wheel-owner-a', idToken: 'test-a-new'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(planChecks, 1,
        reason: 'A stale wheel must stop before fresh-plan or PATCH requests');
    expect(post.scheduledAt, now.add(const Duration(days: 20)));
    expect(tester.takeException(), isNull);
  });

  for (final plan in ['STARTER', 'PRO']) {
    testWidgets('$plan bounds rescheduling using the latest plan',
        (tester) async {
      final now = DateTime(2026, 10, 8, 12);
      var checks = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CalendarScreen(
        now: () => now,
        loadSubscription: () async {
          checks++;
          return _scheduleSubscription(plan);
        },
        loadScheduledPosts: () async => [_queuedFixture(now)],
      ))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('คิวเดิม'));
      await tester.tap(find.text('คิวเดิม'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลื่อนเวลา'));
      await tester.pumpAndSettle();
      final picker =
          tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      expect(
          picker.lastDate,
          DateTime(2026, 10, 8)
              .add(Duration(days: plan == 'STARTER' ? 14 : 30)));
      expect(checks, 1);
    });
  }

  for (final unavailable in [false, true]) {
    testWidgets(
        'keeps existing queues but blocks rescheduling when '
        '${unavailable ? 'the plan cannot be loaded' : 'the plan is Basic'}',
        (tester) async {
      final now = DateTime(2026, 10, 8, 12);
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CalendarScreen(
        now: () => now,
        loadSubscription: () async {
          if (unavailable) {
            throw const ApiException('Request failed', statusCode: 503);
          }
          return _scheduleSubscription('BASIC');
        },
        loadScheduledPosts: () async => [_queuedFixture(now)],
        reschedulePost: (_, __) async {
          calls++;
          return _queuedFixture(now);
        },
      ))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('คิวเดิม'));
      await tester.tap(find.text('คิวเดิม'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลื่อนเวลา'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(calls, 0);
      expect(find.text('คิวเดิม'), findsOneWidget);
      expect(
          find.text(unavailable
              ? 'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่ก่อนตั้งเวลา'
              : 'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299'),
          findsOneWidget);
    });
  }

  testWidgets('shows Thai gateway failure and keeps retry available',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      loadScheduledPosts: () async =>
          throw const ApiException('Request failed', statusCode: 503),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('ระบบ PostDee ไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่ภายหลัง'),
        findsOneWidget);
    expect(find.text('Request failed'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });

  testWidgets('loads scheduled posts into the calendar', (tester) async {
    final scheduledPosts = Completer<List<ScheduledPostResult>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: () => scheduledPosts.future,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('calendar-loading')), findsOneWidget);

    scheduledPosts.complete([
      ScheduledPostResult(
        id: 'post-1',
        caption: 'Launch clip',
        videoS3Key: 'uploads/launch.mp4',
        platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
        scheduledAt: DateTime(2026, 6, 7, 18, 30),
        status: 'QUEUED',
        createdAt: DateTime(2026, 6, 1),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-loading')), findsNothing);
    // The first scheduled day is auto-selected, so its posts show below the
    // grid with time and delivery status shown independently.
    expect(find.text('Launch clip'), findsOneWidget);
    expect(find.text('7 มิ.ย. 2026'), findsOneWidget);
    expect(find.text('รอส่งตามเวลา'), findsOneWidget);
    expect(find.text('18:30'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-empty')), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-platform-filters')),
      findsOneWidget,
    );
    for (final platform in const [
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS',
      'FACEBOOK_REELS'
    ]) {
      expect(find.byKey(ValueKey('calendar-filter-$platform')), findsOneWidget);
    }
    expect(find.text('Shopee'), findsNothing);
    expect(find.text('Lazada'), findsNothing);
  });

  testWidgets('reloads scheduled posts when the refresh token changes',
      (tester) async {
    var loadCount = 0;
    var posts = <ScheduledPostResult>[];

    Future<List<ScheduledPostResult>> loadScheduledPosts() async {
      loadCount += 1;
      return posts;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            refreshToken: 0,
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: loadScheduledPosts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.byKey(const ValueKey('calendar-empty')), findsOneWidget);

    posts = [
      ScheduledPostResult(
        id: 'post-2',
        caption: 'Fresh scheduled clip',
        videoS3Key: 'uploads/fresh.mp4',
        platforms: const ['INSTAGRAM_REELS'],
        scheduledAt: DateTime(2026, 6, 8, 11),
        status: 'QUEUED',
        createdAt: DateTime(2026, 6, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            refreshToken: 1,
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: loadScheduledPosts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(find.text('Fresh scheduled clip'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-empty')), findsNothing);
  });

  testWidgets('only shows actions supported by the scheduled-post API',
      (tester) async {
    var addPostCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'post-actions',
                caption: 'Scheduled actions clip',
                videoS3Key: 'uploads/actions.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: DateTime(2026, 6, 9, 19),
                status: 'QUEUED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
            onAddPost: () => addPostCalls += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Scheduled actions clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scheduled actions clip'));
    await tester.pumpAndSettle();

    expect(find.text('เลื่อนเวลา'), findsOneWidget);
    expect(find.text('ยกเลิกโพสต์'), findsOneWidget);
    expect(find.text('แก้ไขโพสต์'), findsNothing);
    expect(addPostCalls, 0);
  });

  testWidgets('shows busy feedback while a reschedule is being saved',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final pendingReschedule = Completer<ScheduledPostResult>();
    final post = ScheduledPostResult(
      id: 'busy-reschedule',
      caption: 'โพสต์ที่กำลังเลื่อนเวลา',
      videoS3Key: 'uploads/busy-reschedule.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [post],
            loadSubscription: () async => _scheduleSubscription('PRO'),
            reschedulePost: (_, __) => pendingReschedule.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsOneWidget,
    );
    expect(find.text('กำลังเลื่อนเวลา...'), findsOneWidget);

    pendingReschedule.complete(post);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsNothing,
    );
  });

  testWidgets('shows busy feedback while a cancellation is being saved',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final pendingCancel = Completer<void>();
    final post = ScheduledPostResult(
      id: 'busy-cancel',
      caption: 'โพสต์ที่กำลังยกเลิก',
      videoS3Key: 'uploads/busy-cancel.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2)),
      status: 'QUEUED',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [post],
            cancelPost: (_) => pendingCancel.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsOneWidget,
    );
    expect(find.text('กำลังยกเลิก...'), findsOneWidget);

    pendingCancel.complete();
    await tester.pumpAndSettle();
    expect(find.text(post.caption), findsNothing);
  });

  testWidgets('queues a fresh load after rescheduling during a stale refresh',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    late ScheduledPostResult updatedPost;
    final originalPost = ScheduledPostResult(
      id: 'reschedule-during-refresh',
      caption: 'โพสต์ก่อนเลื่อนเวลา',
      videoS3Key: 'uploads/reschedule-during-refresh.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return switch (loadCalls) {
        1 => Future.value([originalPost]),
        2 => staleRefresh.future,
        _ => Future.value([updatedPost]),
      };
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              loadSubscription: () async => _scheduleSubscription('PRO'),
              reschedulePost: (postId, next) async {
                updatedPost = ScheduledPostResult(
                  id: postId,
                  caption: 'โพสต์หลังเลื่อนเวลา',
                  videoS3Key: originalPost.videoS3Key,
                  platforms: originalPost.platforms,
                  scheduledAt: next,
                  status: 'QUEUED',
                  createdAt: originalPost.createdAt,
                );
                return updatedPost;
              },
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(originalPost.caption));
    await tester.tap(find.text(originalPost.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pump();

    staleRefresh.complete([originalPost]);
    await tester.pumpAndSettle();

    expect(loadCalls, 3);
    expect(find.text('โพสต์หลังเลื่อนเวลา'), findsOneWidget);
    expect(find.text(originalPost.caption), findsNothing);
  });

  testWidgets('keeps the local reschedule when the queued reload fails',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    final originalPost = ScheduledPostResult(
      id: 'reschedule-reload-failure',
      caption: 'โพสต์ก่อนเลื่อนและรีโหลดล้มเหลว',
      videoS3Key: 'uploads/reschedule-reload-failure.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return switch (loadCalls) {
        1 => Future.value([originalPost]),
        2 => staleRefresh.future,
        _ => Future.error(StateError('queued reload failed')),
      };
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              loadSubscription: () async => _scheduleSubscription('PRO'),
              reschedulePost: (postId, next) async => ScheduledPostResult(
                id: postId,
                caption: 'โพสต์หลังเลื่อนจากผลตอบกลับ',
                videoS3Key: originalPost.videoS3Key,
                platforms: originalPost.platforms,
                scheduledAt: next,
                status: 'QUEUED',
                createdAt: originalPost.createdAt,
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(originalPost.caption));
    await tester.tap(find.text(originalPost.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pump();

    staleRefresh.complete([originalPost]);
    await tester.pumpAndSettle();

    expect(loadCalls, 3);
    expect(find.text('โพสต์หลังเลื่อนจากผลตอบกลับ'), findsOneWidget);
    expect(find.text(originalPost.caption), findsNothing);
  });

  testWidgets('a stale refresh cannot restore a canceled post', (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    final post = ScheduledPostResult(
      id: 'cancel-during-refresh',
      caption: 'โพสต์ที่ยกเลิกระหว่างรีเฟรช',
      videoS3Key: 'uploads/cancel-during-refresh.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return loadCalls == 1 ? Future.value([post]) : staleRefresh.future;
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              cancelPost: (_) async {},
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pumpAndSettle();
    expect(find.text(post.caption), findsNothing);

    staleRefresh.complete([post]);
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.text(post.caption), findsNothing);
  });

  testWidgets(
      'month grid stays compact and ignores the POCO bottom system inset',
      (tester) async {
    tester.view.physicalSize = const Size(393, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<double> pumpCalendar({required double bottomInset}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              padding: EdgeInsets.only(bottom: bottomInset),
              textScaler: const TextScaler.linear(1.45),
            ),
            child: Scaffold(
              body: CalendarScreen(
                now: () => DateTime(2026, 2, 14),
                loadScheduledPosts: () async => const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(GridView)).height;
    }

    final heightWithoutInset = await pumpCalendar(bottomInset: 0);
    final heightWithPocoInset = await pumpCalendar(bottomInset: 47);

    expect(heightWithPocoInset, heightWithoutInset);
    expect(heightWithPocoInset, lessThanOrEqualTo(251));
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets('calendar controls fit ${width}dp with ${textScale}x text',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: MediaQueryData.fromView(tester.view).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: CalendarScreen(
                  now: () => DateTime(2026, 2, 14),
                  loadScheduledPosts: () async => const [],
                  onAddPost: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final monthButton = find.ancestor(
          of: find.byIcon(Icons.chevron_left),
          matching: find.byType(InkWell),
        );
        final filter = find.ancestor(
          of: find.text('ทั้งหมด'),
          matching: find.byType(InkWell),
        );
        final addButton = find.ancestor(
          of: find.byIcon(Icons.add_rounded),
          matching: find.byType(InkWell),
        );
        final selectedDay = find.ancestor(
          of: find.text('14'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(monthButton).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(filter).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(addButton).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(selectedDay).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(selectedDay).height, greaterThanOrEqualTo(48));
      });
    }
  }

  testWidgets('explains when rescheduling is blocked by publishing config',
      (tester) async {
    final now = DateTime(2026, 10, 14, 12);
    final scheduledAt = now.add(const Duration(days: 2));
    var rescheduleCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'disabled-reschedule',
                caption: 'โพสต์ที่ต้องการเลื่อนเวลา',
                videoS3Key: 'uploads/reschedule.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: scheduledAt,
                status: 'QUEUED',
                createdAt: now,
              ),
            ],
            loadSubscription: () async => _scheduleSubscription('PRO'),
            reschedulePost: (postId, next) async {
              rescheduleCalls += 1;
              throw const ApiException(
                'Social publishing is temporarily unavailable. Please try again later.',
                statusCode: 503,
                code: socialPublishingUnavailableCode,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ที่ต้องการเลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ที่ต้องการเลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();

    expect(rescheduleCalls, 1);
    expect(
      find.text('ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง'),
      findsOneWidget,
    );
  });

  testWidgets('limits the reschedule date picker to the shared 30-day window',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadSubscription: () async => _scheduleSubscription('PRO'),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'bounded-reschedule',
                caption: 'โพสต์ภายในกรอบเวลา',
                videoS3Key: 'uploads/bounded.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: now.add(const Duration(days: 2)),
                status: 'QUEUED',
                createdAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ภายในกรอบเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ภายในกรอบเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();

    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, DateTime(2026, 8, 11));
    expect(picker.lastDate, DateTime(2026, 9, 10));
  });

  testWidgets('blocks a past reschedule before it reaches the API',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    var rescheduleCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'past-reschedule',
                caption: 'โพสต์ที่ห้ามเลื่อนไปอดีต',
                videoS3Key: 'uploads/past.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: now.subtract(const Duration(hours: 1)),
                status: 'QUEUED',
                createdAt: now.subtract(const Duration(days: 1)),
              ),
            ],
            loadSubscription: () async => _scheduleSubscription('PRO'),
            reschedulePost: (postId, next) async {
              rescheduleCalls += 1;
              return ScheduledPostResult(
                id: postId,
                caption: 'ไม่ควรถูกเรียก',
                videoS3Key: 'uploads/past.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: next,
                status: 'QUEUED',
                createdAt: now,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ที่ห้ามเลื่อนไปอดีต'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ที่ห้ามเลื่อนไปอดีต'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();

    expect(rescheduleCalls, 0);
    expect(find.text('เวลาที่เลื่อนต้องเป็นเวลาในอนาคต'), findsOneWidget);
  });

  testWidgets(
      'uses the real published time in Bangkok across a UTC day and month',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 2, 1),
            toLocalTime: (value) => value.toUtc().add(const Duration(hours: 7)),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'published-next-month',
                caption: 'Published after midnight',
                videoS3Key: 'uploads/published.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: DateTime.utc(2026, 1, 31, 16),
                publishedAt: DateTime.utc(2026, 1, 31, 18, 30),
                status: 'PUBLISHED',
                createdAt: DateTime.utc(2026, 1, 30),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 31 Jan 18:30 UTC is 1 Feb 01:30 in Asia/Bangkok.
    expect(find.text('1 ก.พ. 2026'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('Published after midnight'), findsOneWidget);
  });

  testWidgets('translates partial publish and hides queue-only actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'partial-post',
                caption: 'Published on one channel',
                videoS3Key: 'uploads/partial.mp4',
                platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
                scheduledAt: DateTime(2026, 6, 10, 9),
                publishedAt: DateTime(2026, 6, 10, 9, 5),
                status: 'PARTIAL_PUBLISHED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ส่งสำเร็จบางช่องทาง'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    // Only the month-navigation chevron remains; terminal post rows do not
    // show the queue-action chevron.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.ensureVisible(find.text('Published on one channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Published on one channel'));
    await tester.pumpAndSettle();

    expect(find.text('เลื่อนเวลา'), findsNothing);
    expect(find.text('ยกเลิกโพสต์'), findsNothing);
  });

  testWidgets('shows an unknown provider outcome as unconfirmed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'unknown-outcome',
                caption: 'Future provider result',
                videoS3Key: 'uploads/future.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: DateTime(2026, 6, 10, 9),
                publishedAt: DateTime(2026, 6, 10, 9, 5),
                status: 'PUBLISHED',
                createdAt: DateTime(2026, 6, 1),
                platformResults: const [
                  PostPlatformResult(
                    postId: 'unknown-outcome',
                    platform: 'TIKTOK',
                    status: 'PUBLISHED',
                    deliveryOutcome: 'FUTURE_OUTCOME',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ'), findsNothing);
  });

  for (final status in const [
    'PUBLISHED',
    'PARTIAL_PUBLISHED',
    'FAILED',
  ]) {
    testWidgets('$status opens post detail through the terminal-post callback',
        (tester) async {
      final post = ScheduledPostResult(
        id: 'terminal-$status',
        caption: 'Terminal $status clip',
        videoS3Key: 'uploads/terminal.mp4',
        platforms: const ['YOUTUBE_SHORTS'],
        scheduledAt: DateTime(2026, 6, 12, 10),
        publishedAt: status == 'FAILED' ? null : DateTime(2026, 6, 12, 10, 1),
        status: status,
        createdAt: DateTime(2026, 6, 1),
      );
      ScheduledPostResult? openedPost;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              now: () => DateTime(2026, 6, 1),
              loadScheduledPosts: () async => [post],
              onOpenPostDetail: (value) => openedPost = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(post.caption));
      await tester.tap(find.text(post.caption));
      await tester.pumpAndSettle();

      expect(openedPost, same(post));
      expect(find.text('เลื่อนเวลา'), findsNothing);
      expect(find.text('ยกเลิกโพสต์'), findsNothing);
    });
  }

  testWidgets('publishing post remains non-interactive', (tester) async {
    var detailCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => DateTime(2026, 6, 1),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'publishing-post',
                caption: 'Publishing clip',
                videoS3Key: 'uploads/publishing.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: DateTime(2026, 6, 12, 10),
                status: 'PUBLISHING',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
            onOpenPostDetail: (_) => detailCalls += 1,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.ensureVisible(find.text('Publishing clip'));
    await tester.tap(find.text('Publishing clip'));
    await tester.pump();

    expect(detailCalls, 0);
    expect(find.text('เลื่อนเวลา'), findsNothing);
    expect(find.text('ยกเลิกโพสต์'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('refreshes queued and publishing posts every 30 seconds',
      (tester) async {
    var loadCount = 0;

    Future<List<ScheduledPostResult>> loadScheduledPosts() async {
      loadCount += 1;
      return [
        ScheduledPostResult(
          id: 'polling-post',
          caption: 'Polling clip',
          videoS3Key: 'uploads/polling.mp4',
          platforms: const ['YOUTUBE_SHORTS'],
          scheduledAt: DateTime(2026, 6, 11, 10),
          publishedAt: loadCount < 3 ? null : DateTime(2026, 6, 11, 10, 1),
          status: switch (loadCount) {
            1 => 'QUEUED',
            2 => 'PUBLISHING',
            _ => 'PUBLISHED',
          },
          createdAt: DateTime(2026, 6, 1),
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
              now: () => DateTime(2026, 6, 1),
              loadScheduledPosts: loadScheduledPosts),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('กำลังส่ง'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 3);
    expect(find.text('ส่งสำเร็จ'), findsOneWidget);
    expect(find.text('10:01'), findsOneWidget);
  });

  testWidgets('refreshes after the app resumes', (tester) async {
    var loadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async {
              loadCount += 1;
              return const [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(loadCount, 2);
  });

  testWidgets('refreshes when returning to the calendar tab', (tester) async {
    var loadCount = 0;
    var selectedIndex = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return Scaffold(
              body: IndexedStack(
                index: selectedIndex,
                children: [
                  CalendarScreen(
                    isActive: selectedIndex == 0,
                    loadScheduledPosts: () async {
                      loadCount += 1;
                      return const [];
                    },
                  ),
                  const SizedBox(key: ValueKey('another-tab')),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => selectedIndex = 1);
    await tester.pump();
    await tester.pump();
    expect(loadCount, 1);

    setHostState(() => selectedIndex = 0);
    await tester.pump();
    await tester.pump();

    expect(loadCount, 2);
  });
}
