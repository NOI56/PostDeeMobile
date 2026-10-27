import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/posts/posts_screen.dart';

const _owner = 'english-posts-owner';
final _created = DateTime(2026, 10, 27, 18, 5);

PostSummaryResult _post({
  String id = 'english-post',
  String caption = 'Product video',
  String status = 'PUBLISHED',
  DateTime? createdAt,
  DateTime? scheduledAt,
  List<String> platforms = const ['YOUTUBE_SHORTS'],
  List<PostPlatformResult> results = const [],
}) =>
    PostSummaryResult(
      id: id,
      caption: caption,
      videoS3Key: '',
      platforms: platforms,
      status: status,
      createdAt: createdAt ?? _created,
      scheduledAt: scheduledAt,
      platformResults: results,
    );

PostsScreen _posts(PostsLoader load) =>
    PostsScreen(key: const ValueKey('english-posts'), loadPosts: load);

Widget _app(
  PostsScreen posts, {
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
          disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: posts,
  );
}

void _expectEnglishInterface(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _selectFilter(
    WidgetTester tester, String key, String label) async {
  final control = find.byKey(ValueKey(key));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  final item = find.text(label).last;
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('all-post-$id'));

void _expectLabelFits(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance
      .signIn(const AuthSession(userId: _owner, idToken: 'fixture-token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English All posts translates title and filter controls',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [_post()])));
    await tester.pumpAndSettle();
    for (final label in [
      'All posts',
      'Search caption or post ID',
      'Status',
      'All statuses',
      'Channel',
      'All channels',
      'Created date',
      'All dates',
      '1 post',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    _expectEnglishInterface(tester);
  });

  testWidgets('English All posts has a translated empty state', (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [])));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('No posts match your filters'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets('existing All posts error changes language without another read',
      (tester) async {
    var reads = 0;
    final posts = _posts(() async {
      reads++;
      throw StateError('opaque-provider-message');
    });
    await tester.pumpWidget(_app(posts, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โหลดรายการโพสต์ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(reads, 1);
    await tester.pumpWidget(_app(posts));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your posts. Please try again.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('opaque-provider-message'), findsNothing);
    expect(reads, 1);
    _expectEnglishInterface(tester);
    await tester.pumpWidget(_app(posts, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โหลดรายการโพสต์ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(reads, 1);
  });

  testWidgets('English caption and post ID search keeps case folding and clear',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'summer-10', caption: 'Summer Sale'),
          _post(id: 'reference-42', caption: 'Winter launch'),
        ])));
    await tester.pumpAndSettle();
    expect(find.text('2 posts'), findsOneWidget);
    final search = find.byKey(const ValueKey('posts-search'));
    await tester.enterText(search, '  sUmMeR  ');
    await tester.pump();
    expect(find.text('1 post'), findsOneWidget);
    expect(_row('summer-10'), findsOneWidget);
    expect(_row('reference-42'), findsNothing);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.enterText(search, 'REFERENCE-42');
    await tester.pump();
    expect(_row('reference-42'), findsOneWidget);
    expect(_row('summer-10'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('2 posts'), findsOneWidget);
    _expectEnglishInterface(tester);
  });

  testWidgets('English no-match state is distinct from an empty account',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [_post()])));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('posts-search')), 'not found');
    await tester.pump();
    expect(find.text('No posts match your filters'), findsOneWidget);
    expect(find.text('No posts yet'), findsNothing);
    expect(_row('english-post'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('1 post'), findsOneWidget);
    _expectEnglishInterface(tester);
  });

  testWidgets(
      'English status, channel and date filters retain their intersection',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'youtube-today', status: 'FAILED', createdAt: now),
          _post(
              id: 'tiktok-today',
              status: 'FAILED',
              platforms: const ['TIKTOK'],
              createdAt: now),
          _post(id: 'youtube-old', status: 'FAILED', createdAt: DateTime(2020)),
          _post(id: 'youtube-done', createdAt: now),
        ])));
    await tester.pumpAndSettle();
    expect(find.text('4 posts'), findsOneWidget);
    await _selectFilter(tester, 'posts-status-filter', 'Failed');
    expect(find.text('3 posts'), findsOneWidget);
    expect(_row('youtube-done'), findsNothing);
    await _selectFilter(tester, 'posts-platform-filter', 'YouTube Shorts');
    expect(find.text('2 posts'), findsOneWidget);
    expect(_row('tiktok-today'), findsNothing);
    await _selectFilter(tester, 'posts-date-filter', 'Today');
    expect(find.text('1 post'), findsOneWidget);
    expect(_row('youtube-today'), findsOneWidget);
    expect(_row('youtube-old'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets('English date ranges keep inclusive local-day boundaries',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'today', createdAt: today),
          _post(
              id: 'six-days',
              createdAt: today.subtract(const Duration(days: 6))),
          _post(
              id: 'seven-days',
              createdAt: today.subtract(const Duration(days: 7))),
          _post(
              id: '29-days',
              createdAt: today.subtract(const Duration(days: 29))),
          _post(
              id: '30-days',
              createdAt: today.subtract(const Duration(days: 30))),
          _post(id: 'tomorrow', createdAt: today.add(const Duration(days: 1))),
        ])));
    await tester.pumpAndSettle();
    await _selectFilter(tester, 'posts-date-filter', 'Last 7 days');
    expect(find.text('2 posts'), findsOneWidget);
    await _selectFilter(tester, 'posts-date-filter', 'Last 30 days');
    expect(find.text('4 posts'), findsOneWidget);
    await _selectFilter(tester, 'posts-date-filter', 'Today');
    expect(find.text('1 post'), findsOneWidget);
    expect(_row('today'), findsOneWidget);
    await _selectFilter(tester, 'posts-date-filter', 'All dates');
    expect(find.text('6 posts'), findsOneWidget);
    _expectEnglishInterface(tester);
  });

  testWidgets('English pending filter includes queued and sending posts',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'queued', status: 'QUEUED'),
          _post(id: 'sending', status: 'PUBLISHING'),
          _post(id: 'failed', status: 'FAILED'),
        ])));
    await tester.pumpAndSettle();
    await _selectFilter(tester, 'posts-status-filter', 'Queued / Sending');
    expect(find.text('2 posts'), findsOneWidget);
    expect(_row('queued'), findsOneWidget);
    expect(_row('sending'), findsOneWidget);
    expect(_row('failed'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets('English channel menu offers only currently supported targets',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posts-platform-filter')));
    await tester.pumpAndSettle();
    for (final channel in [
      'TikTok',
      'YouTube Shorts',
      'Instagram Reels',
      'Facebook Reels',
    ]) {
      expect(find.text(channel), findsOneWidget);
    }
    expect(find.text('Shopee Video'), findsNothing);
    expect(find.text('Lazada Video'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets('English loading does not flash the no-post message',
      (tester) async {
    final result = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(_app(_posts(() => result.future)));
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    expect(find.text('No posts yet'), findsNothing);
    expect(find.text('1 post'), findsNothing);
    _expectEnglishInterface(tester);
    result.complete([_post()]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.hourglass_empty), findsNothing);
    expect(find.text('1 post'), findsOneWidget);
  });

  testWidgets('English error retries once and recovers the owned rows',
      (tester) async {
    var reads = 0;
    final retry = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(_app(_posts(() {
      reads++;
      return reads == 1
          ? Future.error(StateError('private upstream diagnostic'))
          : retry.future;
    })));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your posts. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('private upstream diagnostic'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(reads, 2);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    retry.complete([_post()]);
    await tester.pumpAndSettle();
    expect(find.text('Product video'), findsOneWidget);
    expect(find.text('Could not load your posts. Please try again.'),
        findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(reads, 2);
    _expectEnglishInterface(tester);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'English account switch rejects stale ${fails ? 'error' : 'data'}',
        (tester) async {
      var reads = 0;
      final pending = Completer<List<PostSummaryResult>>();
      final posts = _posts(() {
        reads++;
        return pending.future;
      });
      await tester.pumpWidget(_app(posts));
      await tester.pump();
      PostDeeAuthSessionStore.instance.signIn(const AuthSession(
          userId: 'different-posts-owner', idToken: 'other-fixture-token'));
      await tester.pump();
      expect(find.text('Your account has changed. Reopen All posts.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('posts-search')), findsNothing);
      expect(find.text('Try again'), findsNothing);
      if (fails) {
        pending.completeError(StateError('prior owner failure'));
      } else {
        pending.complete([_post(caption: 'Prior owner private caption')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Prior owner private caption'), findsNothing);
      expect(find.text('Could not load your posts. Please try again.'),
          findsNothing);
      expect(find.text('Your account has changed. Reopen All posts.'),
          findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.pumpWidget(_app(posts, locale: const Locale('th')));
      await tester.pumpAndSettle();
      expect(find.text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการโพสต์ใหม่'),
          findsOneWidget);
      expect(reads, 1);
    });
  }

  testWidgets('English refresh ignores an older same-owner request',
      (tester) async {
    var reads = 0;
    final old = Completer<List<PostSummaryResult>>();
    final fresh = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(
        _app(_posts(() => ++reads == 1 ? old.future : fresh.future)));
    await tester.pump();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(reads, 2);
    fresh.complete([_post(id: 'fresh', caption: 'Fresh result')]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh result'), findsOneWidget);
    old.complete([_post(id: 'old', caption: 'Stale result')]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
    expect(reads, 2);
    _expectEnglishInterface(tester);
  });

  for (final entry in const {
    'PUBLISHED': 'Delivered',
    'PARTIAL_PUBLISHED': 'Partially delivered',
    'PUBLISHING': 'Sending',
    'FAILED': 'Failed',
    'QUEUED': 'Queued',
  }.entries) {
    testWidgets('English All posts keeps ${entry.key} status distinct',
        (tester) async {
      await tester
          .pumpWidget(_app(_posts(() async => [_post(status: entry.key)])));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: _row('english-post'), matching: find.text(entry.value)),
          findsOneWidget);
      _expectEnglishInterface(tester);
    });
  }

  testWidgets('English scheduled row is distinct from an immediate queued row',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'later', status: 'QUEUED', scheduledAt: _created),
          _post(id: 'immediate', status: 'QUEUED'),
        ])));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _row('later'), matching: find.text('Scheduled')),
        findsOneWidget);
    expect(
        find.descendant(of: _row('immediate'), matching: find.text('Queued')),
        findsOneWidget);
    _expectEnglishInterface(tester);
  });

  for (final entry in const {
    'DRAFT': 'Sent as draft',
    'PRIVATE': 'Private',
    'UNLISTED': 'Unlisted',
    'LIVE': 'Published',
    'FUTURE_PROVIDER_OUTCOME': 'Delivery unconfirmed',
  }.entries) {
    testWidgets('English All posts preserves ${entry.key} delivery meaning',
        (tester) async {
      await tester.pumpWidget(_app(_posts(() async => [
            _post(results: [
              PostPlatformResult(
                  postId: 'english-post',
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHED',
                  deliveryOutcome: entry.key),
            ])
          ])));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: _row('english-post'), matching: find.text(entry.value)),
          findsOneWidget);
      if (entry.key != 'LIVE') {
        expect(
            find.descendant(
                of: _row('english-post'), matching: find.text('Published')),
            findsNothing);
      }
      _expectEnglishInterface(tester);
    });
  }

  testWidgets('English mixed success and failure is only partially delivered',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(status: 'PARTIAL_PUBLISHED', platforms: const [
            'TIKTOK',
            'YOUTUBE_SHORTS'
          ], results: const [
            PostPlatformResult(
                postId: 'english-post',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT'),
            PostPlatformResult(
                postId: 'english-post',
                platform: 'YOUTUBE_SHORTS',
                status: 'FAILED'),
          ])
        ])));
    await tester.pumpAndSettle();
    expect(find.text('Partially delivered'), findsOneWidget);
    expect(find.text('Sent as draft'), findsNothing);
    await _selectFilter(tester, 'posts-status-filter', 'Partially delivered');
    expect(find.text('1 post'), findsOneWidget);
    expect(_row('english-post'), findsOneWidget);
    _expectEnglishInterface(tester);
  });

  testWidgets(
      'English unconfirmed filter does not turn unknown outcomes into success',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'unconfirmed', status: 'PUBLISHING', results: const [
            PostPlatformResult(
                postId: 'unconfirmed',
                platform: 'YOUTUBE_SHORTS',
                status: 'PUBLISHED',
                deliveryOutcome: 'FUTURE_PROVIDER_OUTCOME'),
          ]),
          _post(id: 'ordinary-success'),
          _post(id: 'failed', status: 'FAILED'),
        ])));
    await tester.pumpAndSettle();
    await _selectFilter(tester, 'posts-status-filter', 'Delivery unconfirmed');
    expect(find.text('1 post'), findsOneWidget);
    expect(_row('unconfirmed'), findsOneWidget);
    expect(_row('ordinary-success'), findsNothing);
    expect(_row('failed'), findsNothing);
    expect(
        find.descendant(
            of: _row('unconfirmed'), matching: find.text('Sending')),
        findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets(
      'English delivered filter keeps provider drafts without calling them published',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(id: 'draft', results: const [
            PostPlatformResult(
                postId: 'draft',
                platform: 'YOUTUBE_SHORTS',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT'),
          ]),
          _post(id: 'failed', status: 'FAILED'),
        ])));
    await tester.pumpAndSettle();
    await _selectFilter(tester, 'posts-status-filter', 'Delivered');
    expect(find.text('1 post'), findsOneWidget);
    expect(find.text('Sent as draft'), findsOneWidget);
    expect(_row('draft'), findsOneWidget);
    expect(_row('failed'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets(
      'English empty captions and local Gregorian 24-hour dates are readable',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(caption: '', createdAt: _created.toUtc()),
        ])));
    await tester.pumpAndSettle();
    expect(find.text('Video post'), findsOneWidget);
    expect(find.text('27 Oct 2026 · 18:05'), findsOneWidget);
    expect(find.textContaining('2569'), findsNothing);
    _expectEnglishInterface(tester);
  });

  testWidgets('English rows retain newest-first ordering', (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [
          _post(
              id: 'older',
              caption: 'Older video',
              createdAt: _created.subtract(const Duration(days: 1))),
          _post(id: 'newer', caption: 'Newer video', createdAt: _created),
        ])));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_row('newer')).dy,
        lessThan(tester.getTopLeft(_row('older')).dy));
    expect(find.text('2 posts'), findsOneWidget);
  });

  testWidgets(
      'locale switching preserves user Thai captions, search and selected filters',
      (tester) async {
    var reads = 0;
    const caption = 'เสื้อใหม่พร้อมส่ง needle';
    final posts = _posts(() async {
      reads++;
      return [_post(caption: caption, status: 'QUEUED')];
    });
    await tester.pumpWidget(_app(posts));
    await tester.pumpAndSettle();
    await _selectFilter(tester, 'posts-status-filter', 'Queued / Sending');
    await tester.enterText(
        find.byKey(const ValueKey('posts-search')), 'เสื้อใหม่');
    await tester.pump();
    await tester.pumpWidget(_app(posts, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ทั้งหมด'), findsOneWidget);
    expect(find.text('รอส่ง / กำลังส่ง'), findsOneWidget);
    expect(find.text(caption), findsOneWidget);
    expect(find.text('1 โพสต์'), findsOneWidget);
    await tester.pumpWidget(_app(posts));
    await tester.pumpAndSettle();
    expect(find.text('All posts'), findsOneWidget);
    expect(find.text('Queued / Sending'), findsOneWidget);
    expect(find.text(caption), findsOneWidget);
    expect(find.text('1 post'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('posts-search')))
            .controller!
            .text,
        'เสื้อใหม่');
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit Thai retains caption fallback, status and Gregorian date',
      (tester) async {
    await tester.pumpWidget(_app(_posts(() async => [_post(caption: '')]),
        locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ทั้งหมด'), findsOneWidget);
    expect(find.text('โพสต์วิดีโอ'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ'), findsOneWidget);
    expect(find.text('27 ต.ค. 2026 · 18:05'), findsOneWidget);
    expect(find.text('1 โพสต์'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain MaterialApp retains historical Thai fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _posts(() async => [])));
    await tester.pumpAndSettle();
    expect(find.text('โพสต์ทั้งหมด'), findsOneWidget);
    expect(find.text('ค้นหาแคปชั่นหรือรหัสโพสต์'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์'), findsOneWidget);
    expect(find.text('All posts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English 320dp 2x dropdowns remain usable in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      await tester.pumpWidget(_app(
          _posts(() async => [
                _post(
                    platforms: const ['INSTAGRAM_REELS'],
                    createdAt: now,
                    results: const [
                      PostPlatformResult(
                          postId: 'english-post',
                          platform: 'INSTAGRAM_REELS',
                          status: 'PUBLISHED',
                          deliveryOutcome: 'FUTURE_PROVIDER_OUTCOME'),
                    ])
              ]),
          scale: 2,
          dark: dark));
      await tester.pumpAndSettle();
      for (final option in const {
        'posts-status-filter': 'Delivery unconfirmed',
        'posts-platform-filter': 'Instagram Reels',
        'posts-date-filter': 'Last 30 days',
      }.entries) {
        final control = find.byKey(ValueKey(option.key));
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        final item = find.text(option.value).last;
        await tester.ensureVisible(item);
        _expectLabelFits(tester, item);
        expect(tester.takeException(), isNull);
        await tester.tap(item);
        await tester.pumpAndSettle();
        _expectLabelFits(
            tester,
            find
                .descendant(of: control, matching: find.text(option.value))
                .first);
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(_row('english-post'), 180,
          scrollable: find.byType(Scrollable).first);
      expect(_row('english-post'), findsOneWidget);
      _expectEnglishInterface(tester);
    });
  }
}
