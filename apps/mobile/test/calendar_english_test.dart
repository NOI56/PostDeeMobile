import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_publishing_motion.dart';

final _now = DateTime(2026, 10, 27, 10);
const _owner = 'english-calendar-owner';
const _subscription = SubscriptionStatusResult(
  userId: _owner,
  plan: 'PRO',
  status: 'ACTIVE',
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: true,
);

CalendarPostResult _post({
  String status = 'PUBLISHED',
  String caption = 'Product launch',
  DateTime? scheduledAt,
  List<String> platforms = const ['YOUTUBE_SHORTS'],
  List<PostPlatformResult> results = const [],
}) =>
    CalendarPostResult(
      id: 'english-calendar-post',
      userId: _owner,
      caption: caption,
      videoS3Key: '',
      platforms: platforms,
      status: status,
      createdAt: _now,
      scheduledAt: scheduledAt,
      platformResults: results,
    );

CalendarScreen _calendar({
  CalendarPostsLoader? load,
  ScheduledPostCanceller? cancel,
  Future<PostSummaryResult?> Function(String)? loadPost,
  CalendarSubscriptionLoader? subscription,
  ScheduledPostRescheduler? reschedule,
  ValueChanged<DateTime>? onAdd,
}) =>
    CalendarScreen(
      key: const ValueKey('english-calendar'),
      ownerUserId: _owner,
      now: () => _now,
      loadCalendarPosts: load ?? () async => [],
      loadCoverPost: (_) async => null,
      cancelPost: cancel,
      loadPost: loadPost,
      loadSubscription: subscription ?? () async => _subscription,
      reschedulePost: reschedule,
      onAddPostForDate: onAdd ?? (_) {},
    );

Widget _app(
  CalendarScreen calendar, {
  Locale locale = const Locale('en'),
  double scale = 1,
  bool dark = false,
}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: locale,
    theme: dark ? AppTheme.dark : AppTheme.light,
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: calendar),
  );
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _openPostActions(WidgetTester tester) async {
  final post =
      find.byKey(const ValueKey('calendar-post-english-calendar-post'));
  await tester.ensureVisible(post);
  await tester.tap(post);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance
      .signIn(const AuthSession(userId: _owner, idToken: 'local-fixture')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets(
      'English calendar translates navigation, weekdays and Gregorian dates',
      (tester) async {
    await tester.pumpWidget(_app(_calendar()));
    await tester.pumpAndSettle();
    expect(find.text('Post calendar'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('27 Oct 2026'), findsOneWidget);
    for (final weekday in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(weekday), findsOneWidget);
    }
    _expectEnglish(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.textContaining('2569'), findsNothing);
    _expectEnglish(tester);
  });

  testWidgets('English calendar localizes empty states and filters',
      (tester) async {
    await tester.pumpWidget(_app(_calendar()));
    await tester.pumpAndSettle();
    expect(find.text('No posts on this day'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('calendar-filter-YOUTUBE_SHORTS')));
    await tester.pumpAndSettle();
    expect(find.text('No posts for this channel'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'changing calendar language translates a stored load error without reloading',
      (tester) async {
    var reads = 0;
    final calendar = _calendar(load: () async {
      reads++;
      throw const ApiException('opaque gateway response', statusCode: 503);
    });
    await tester.pumpWidget(_app(calendar, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
    expect(find.textContaining('opaque gateway response'), findsNothing);
    _expectEnglish(tester);
  });

  for (final error in <Object>[
    const SocketException('offline'),
    TimeoutException('slow response'),
    const ApiException('expired token', statusCode: 401),
    const ApiException('too many requests', statusCode: 429),
    const ApiException('ข้อความผิดพลาดจากเซิร์ฟเวอร์', statusCode: 400),
  ]) {
    testWidgets(
        'English calendar keeps ${error.runtimeType} errors safe and localizable',
        (tester) async {
      await tester.pumpWidget(_app(_calendar(load: () async => throw error)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-error')), findsOneWidget);
      expect(find.textContaining('expired token'), findsNothing);
      _expectEnglish(tester);
    });
  }

  for (final entry in const {
    'DRAFT': 'Sent as draft',
    'PRIVATE': 'Private',
    'UNLISTED': 'Unlisted',
    'LIVE': 'Published',
    'FUTURE_PROVIDER_OUTCOME': 'Delivery unconfirmed',
  }.entries) {
    testWidgets('English calendar keeps ${entry.key} delivery distinct',
        (tester) async {
      await tester.pumpWidget(_app(_calendar(
          load: () async => [
                _post(results: [
                  PostPlatformResult(
                      postId: 'english-calendar-post',
                      platform: 'YOUTUBE_SHORTS',
                      status: 'PUBLISHED',
                      deliveryOutcome: entry.key),
                ])
              ])));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'English calendar sends per-channel results without inventing public delivery',
      (tester) async {
    await tester.pumpWidget(_app(_calendar(
        load: () async => [
              _post(
                status: 'PUBLISHING',
                platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS'],
                results: const [
                  PostPlatformResult(
                      postId: 'english-calendar-post',
                      platform: 'TIKTOK',
                      status: 'PUBLISHED',
                      deliveryOutcome: 'DRAFT'),
                  PostPlatformResult(
                      postId: 'english-calendar-post',
                      platform: 'YOUTUBE_SHORTS',
                      status: 'PUBLISHING'),
                ],
              )
            ])));
    await tester.pumpAndSettle();
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('TikTok · Sent as draft'), findsOneWidget);
    expect(find.text('Shorts · Sending'), findsOneWidget);
    expect(find.textContaining('Awaiting result'), findsOneWidget);
    expect(
        find.byKey(
            const ValueKey('calendar-publishing-rail-english-calendar-post')),
        findsOneWidget);
    _expectEnglish(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unconfirmed delivery in English does not become a sending animation',
      (tester) async {
    await tester.pumpWidget(_app(_calendar(
        load: () async => [
              _post(
                status: 'PUBLISHING',
                results: const [
                  PostPlatformResult(
                      postId: 'english-calendar-post',
                      platform: 'YOUTUBE_SHORTS',
                      status: 'PUBLISHED',
                      deliveryOutcome: 'UNKNOWN'),
                ],
              )
            ])));
    await tester.pumpAndSettle();
    expect(find.text('Delivery unconfirmed'), findsOneWidget);
    final motion = find
        .ancestor(
          of: find.byKey(const ValueKey('calendar-post-english-calendar-post')),
          matching: find.byType(PostDeePublishingMotion),
        )
        .first;
    expect(tester.widget<PostDeePublishingMotion>(motion).sending, isFalse);
    expect(
        find.byKey(
            const ValueKey('calendar-publishing-rail-english-calendar-post')),
        findsNothing);
    _expectEnglish(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('English calendar keeps user-written Thai captions unchanged',
      (tester) async {
    const caption = 'แคปชันที่ผู้ใช้เขียนเอง';
    await tester.pumpWidget(
        _app(_calendar(load: () async => [_post(caption: caption)])));
    await tester.pumpAndSettle();
    expect(find.text(caption), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English day accessibility keeps Gregorian dates and invokes creation once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var creates = 0;
      await tester.pumpWidget(_app(_calendar(onAdd: (_) => creates++)));
      await tester.pumpAndSettle();
      final day = tester
          .getSemantics(find.byKey(const ValueKey('calendar-day-2026-10-27')));
      expect(day.getSemanticsData().label, contains('27 Oct 2026'));
      expect(day.getSemanticsData().label,
          isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
      expect(day.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
          isTrue);
      final add =
          tester.getSemantics(find.byKey(const ValueKey('calendar-add-post')));
      expect(add.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      add.owner!.performAction(add.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(creates, 1);
      _expectEnglish(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'English cancel dialog can keep the queued post without a mutation',
      (tester) async {
    final post = _post(
        status: 'QUEUED', scheduledAt: _now.add(const Duration(hours: 2)));
    var cancels = 0;
    await tester.pumpWidget(_app(
        _calendar(load: () async => [post], cancel: (_) async => cancels++)));
    await tester.pumpAndSettle();
    await _openPostActions(tester);
    expect(find.text('Reschedule'), findsOneWidget);
    await tester.tap(find.text('Cancel post'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this post?'), findsOneWidget);
    _expectEnglish(tester);
    await tester.tap(find.text('Keep post'));
    await tester.pumpAndSettle();
    expect(cancels, 0);
    expect(find.text(post.caption), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending cancellation changes language without a second request',
      (tester) async {
    final post = _post(
        status: 'QUEUED', scheduledAt: _now.add(const Duration(hours: 2)));
    final pending = Completer<void>();
    var cancels = 0;
    final calendar = _calendar(
        load: () async => [post],
        cancel: (_) {
          cancels++;
          return pending.future;
        });
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await _openPostActions(tester);
    await tester.tap(find.text('Cancel post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel post').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Canceling...'), findsOneWidget);
    await tester.pumpWidget(_app(calendar, locale: const Locale('th')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('กำลังยกเลิก...'), findsOneWidget);
    expect(cancels, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.text(post.caption), findsNothing);
  });

  for (final state in ['PUBLISHING', 'REMOVED']) {
    testWidgets(
        'English calendar reconciles $state after cancellation loses its response',
        (tester) async {
      final post = _post(
          status: 'QUEUED', scheduledAt: _now.add(const Duration(hours: 2)));
      var cancels = 0;
      var reads = 0;
      await tester.pumpWidget(_app(_calendar(
          load: () async => [post],
          cancel: (_) async {
            cancels++;
            throw TimeoutException('response lost');
          },
          loadPost: (_) async {
            reads++;
            return state == 'REMOVED'
                ? null
                : PostSummaryResult(
                    id: post.id,
                    caption: post.caption,
                    videoS3Key: '',
                    platforms: post.platforms,
                    status: 'PUBLISHING',
                    scheduledAt: post.scheduledAt,
                    createdAt: _now,
                  );
          })));
      await tester.pumpAndSettle();
      await _openPostActions(tester);
      await tester.tap(find.text('Cancel post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel post').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(cancels, 1);
      expect(reads, 1);
      if (state == 'REMOVED') {
        expect(find.text(post.caption), findsNothing);
      } else {
        expect(find.text('Sending'), findsOneWidget);
        expect(find.text(post.caption), findsOneWidget);
      }
      _expectEnglish(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'canceling the English reschedule time wheel never PATCHes the queue',
      (tester) async {
    final post = _post(
        status: 'QUEUED', scheduledAt: _now.add(const Duration(hours: 2)));
    var mutations = 0;
    await tester.pumpWidget(_app(_calendar(
        load: () async => [post],
        reschedule: (_, __) async {
          mutations++;
          throw StateError('No mutation is allowed after Cancel');
        })));
    await tester.pumpAndSettle();
    await _openPostActions(tester);
    await tester.tap(find.text('Reschedule'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('postdee-time-confirm')), findsOneWidget);
    _expectEnglish(tester);
    await tester.tap(find.byKey(const ValueKey('postdee-time-cancel')));
    await tester.pumpAndSettle();
    expect(mutations, 0);
    expect(find.text(post.caption), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'English rescheduling rechecks the plan and preserves local time for one update',
      (tester) async {
    final post = _post(
        status: 'QUEUED', scheduledAt: _now.add(const Duration(hours: 2)));
    var planReads = 0;
    final changes = <DateTime>[];
    await tester.pumpWidget(_app(_calendar(
      load: () async => [post],
      subscription: () async {
        planReads++;
        return _subscription;
      },
      reschedule: (id, next) async {
        expect(id, post.id);
        changes.add(next);
        return ScheduledPostResult(
          id: id,
          userId: _owner,
          caption: post.caption,
          videoS3Key: '',
          platforms: post.platforms,
          status: 'QUEUED',
          createdAt: _now,
          scheduledAt: next,
        );
      },
    )));
    await tester.pumpAndSettle();
    await _openPostActions(tester);
    await tester.tap(find.text('Reschedule'));
    await tester.pumpAndSettle();
    expect(planReads, 1);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();
    expect(planReads, 2);
    expect(changes, hasLength(1));
    expect(changes.single.toUtc(), post.scheduledAt!.toUtc());
    expect(changes.single.hour, post.scheduledAt!.hour);
    expect(changes.single.minute, post.scheduledAt!.minute);
    expect(find.textContaining('Rescheduled'), findsOneWidget);
    _expectEnglish(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    for (final scale in [1.6, 2.0]) {
      testWidgets('English calendar fits 320dp at ${scale}x text, dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FlutterErrorDetails? renderingError;
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          renderingError = details;
          previousErrorHandler?.call(details);
        };
        try {
          await tester.pumpWidget(_app(_calendar(load: () async => [_post()]),
              dark: dark, scale: scale));
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousErrorHandler;
        }
        if (renderingError != null) debugPrint(renderingError.toString());
        expect(find.text('Post calendar'), findsOneWidget);
        _expectEnglish(tester);
      });
    }
  }
}
