import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/shared/postdee_publishing_motion.dart';
import 'package:postdee_mobile/features/uploader/post_video_preview_screen.dart';
// Replaces the native interface already used by url_launcher.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// Replaces the native interface already used by video_player.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _id = 'english-detail-post';
final _created = DateTime(2026, 10, 27, 18, 5);

PostSummaryResult _post({
  String status = 'PUBLISHED',
  String caption = 'Product video',
  DateTime? createdAt,
  DateTime? scheduledAt,
  DateTime? publishedAt,
  List<String> platforms = const ['YOUTUBE_SHORTS'],
  List<PostPlatformResult> results = const [],
  Uri? videoUrl,
}) =>
    PostSummaryResult(
      id: _id,
      caption: caption,
      videoS3Key: '',
      platforms: platforms,
      status: status,
      createdAt: createdAt ?? _created,
      scheduledAt: scheduledAt,
      publishedAt: publishedAt,
      platformResults: results,
      videoUrl: videoUrl,
    );

class _Client extends PostDeeApiClient {
  _Client(this.latest);
  PostSummaryResult? latest;
  Object? readError;
  Object? publishError;
  Object? cancelError;
  Future<PostSummaryResult?>? readGate;
  Future<void>? writeGate;
  final reads = <bool>[];
  final published = <String>[];
  final canceled = <String>[];

  @override
  Future<PostSummaryResult?> getPostById(String postId,
      {bool includeMedia = false}) async {
    reads.add(includeMedia);
    if (readError != null) throw readError!;
    return readGate != null ? await readGate! : latest;
  }

  @override
  Future<void> publishPostNow(String postId) async {
    published.add(postId);
    await writeGate;
    if (publishError != null) throw publishError!;
  }

  @override
  Future<void> cancelPost(String postId) async {
    canceled.add(postId);
    await writeGate;
    if (cancelError != null) throw cancelError!;
  }
}

class _VideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length + 1;
    sources.add(options.dataSource);
    events[id] = StreamController<VideoEvent>(onListen: () {
      events[id]!.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(1080, 1920)));
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => events[playerId]?.close();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blue);
}

class _LinkPlatform extends UrlLauncherPlatform {
  final launched = <String>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return false;
  }
}

PostDetailScreen _detail(PostSummaryResult post,
        {_Client? api, bool refresh = false}) =>
    PostDetailScreen(
        key: const ValueKey('english-detail'),
        post: post,
        apiClient: api ?? _Client(post),
        refreshOnOpen: refresh);

Widget _app(
  Widget detail, {
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
    home: detail,
  );
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _dispose(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(WidgetTester tester, {bool cancel = false}) =>
    _tap(
        tester,
        cancel
            ? find.byIcon(Icons.delete_outline)
            : find.byKey(const ValueKey('post-detail-publish-now')));

Finder _dialogText(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void _expectReadable(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'english-detail-owner', idToken: 'fixture-token')));
  tearDown(PostDeeAuthSessionStore.instance.clear);
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets('English detail translates its title and empty content',
      (tester) async {
    await tester
        .pumpWidget(_app(_detail(_post(caption: '', platforms: const []))));
    await tester.pumpAndSettle();
    for (final label in [
      'Post details',
      'Caption',
      'No caption',
      'Posting channels',
      'No channel information',
      'Preview unavailable',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byTooltip('Refresh status'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets('English publish confirmation can decline without sending',
      (tester) async {
    final post = _post(status: 'QUEUED', scheduledAt: _created);
    final api = _Client(post);
    await tester.pumpWidget(_app(_detail(post, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-detail-publish-now')));
    await tester.pumpAndSettle();
    expect(find.text('Publish now?'), findsOneWidget);
    expect(
        find.text(
            'This post will be sent to all selected channels immediately.'),
        findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
    await _dispose(tester);
  });

  testWidgets('stored detail read error changes language without another read',
      (tester) async {
    final post = _post();
    final api = _Client(post)..readError = StateError('private diagnostic');
    final detail = _detail(post, api: api, refresh: true);
    await tester.pumpWidget(_app(detail, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('อัปเดตไม่สำเร็จ กำลังแสดงข้อมูลเดิม'), findsOneWidget);
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    expect(find.text('Could not refresh. Showing previous information.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(api.reads, [true]);
    _expectEnglish(tester);
    await tester.pumpWidget(_app(detail, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('อัปเดตไม่สำเร็จ กำลังแสดงข้อมูลเดิม'), findsOneWidget);
    expect(api.reads, [true]);
  });

  for (final item in const {
    'PUBLISHED': 'Delivered',
    'QUEUED': 'Queued',
    'PUBLISHING': 'Sending',
    'PARTIAL_PUBLISHED': 'Partially delivered',
    'FAILED': 'Failed',
  }.entries) {
    testWidgets('English detail keeps ${item.key} aggregate status honest',
        (tester) async {
      await tester.pumpWidget(_app(_detail(_post(status: item.key))));
      await tester.pumpAndSettle();
      expect(find.text(item.value), findsWidgets);
      expect(
          tester
              .widget<PostDeePublishingMotion>(
                  find.byType(PostDeePublishingMotion))
              .sending,
          item.key == 'PUBLISHING');
      expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
          item.key == 'PUBLISHING' ? findsOneWidget : findsNothing);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  for (final item in const {
    'DRAFT': 'Sent as draft',
    'PRIVATE': 'Private',
    'UNLISTED': 'Unlisted',
    'LIVE': 'Published',
    'FUTURE_PROVIDER_OUTCOME': 'Delivery unconfirmed',
  }.entries) {
    testWidgets(
        'English detail preserves ${item.key} outcomes and safe actions',
        (tester) async {
      const reference = 'https://fixture.invalid/provider-post';
      await tester.pumpWidget(_app(_detail(_post(results: [
        PostPlatformResult(
            postId: _id,
            platform: 'YOUTUBE_SHORTS',
            status: 'PUBLISHED',
            deliveryOutcome: item.key,
            externalPostId: reference),
      ]))));
      await tester.pumpAndSettle();
      expect(find.text(item.value), findsWidgets);
      final confirmedPublicType =
          const {'PRIVATE', 'UNLISTED', 'LIVE'}.contains(item.key);
      expect(find.byKey(const ValueKey('post-detail-open-analytics')),
          confirmedPublicType ? findsOneWidget : findsNothing);
      if (item.key == 'FUTURE_PROVIDER_OUTCOME') {
        expect(find.textContaining(reference), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsNothing);
      } else {
        final referenceText = find.text(
            '${item.key == 'DRAFT' ? 'Post ID' : 'Post link'}: $reference');
        expect(referenceText, findsOneWidget);
        final link = tester.widget<InkWell>(find
            .ancestor(of: referenceText, matching: find.byType(InkWell))
            .first);
        expect(link.onTap != null, confirmedPublicType);
      }
      if (item.key != 'LIVE') expect(find.text('Published'), findsNothing);
      _expectEnglish(tester);
    });
  }

  testWidgets('English sending badges use channel state after a locale change',
      (tester) async {
    final detail = _detail(_post(status: 'PUBLISHING', platforms: const [
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'FACEBOOK_REELS'
    ], results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT'),
      PostPlatformResult(
          postId: _id, platform: 'YOUTUBE_SHORTS', status: 'PUBLISHING'),
    ]));
    await tester.pumpWidget(_app(detail, locale: const Locale('th')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    final badges = tester.widgetList<PostDeePublishingBadge>(
        find.byType(PostDeePublishingBadge));
    expect(badges.where((badge) => badge.sending && badge.label == 'Sending'),
        hasLength(2));
    expect(find.text('Sent as draft'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Facebook Reels'), 160,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Awaiting result'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    _expectEnglish(tester);
    await _dispose(tester);
  });

  testWidgets('unknown delivery stops sending motion without inventing success',
      (tester) async {
    await tester
        .pumpWidget(_app(_detail(_post(status: 'PUBLISHING', results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          deliveryOutcome: 'FUTURE_PROVIDER_OUTCOME'),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Delivery unconfirmed'), findsWidgets);
    expect(
        tester
            .widget<PostDeePublishingMotion>(
                find.byType(PostDeePublishingMotion))
            .sending,
        isFalse);
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-open-analytics')), findsNothing);
    _expectEnglish(tester);
    await _dispose(tester);
  });

  testWidgets(
      'missing channel results never inherit another channels draft success',
      (tester) async {
    await tester.pumpWidget(_app(_detail(_post(platforms: const [
      'TIKTOK',
      'YOUTUBE_SHORTS'
    ], results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'DRAFT'),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting result'), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Delivered'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-open-analytics')), findsNothing);
    expect(
        find.byKey(const ValueKey('tiktok-draft-next-step')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tiktok-draft-next-step')), 160,
        scrollable: find.byType(Scrollable).first);
    _expectEnglish(tester);
  });

  testWidgets('failed receipts take priority over stale delivery visibility',
      (tester) async {
    await tester
        .pumpWidget(_app(_detail(_post(status: 'FAILED', results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'YOUTUBE_SHORTS',
          status: 'FAILED',
          deliveryOutcome: 'PRIVATE'),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsNWidgets(2));
    expect(find.text('Private'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-open-analytics')), findsNothing);
    _expectEnglish(tester);
  });

  testWidgets(
      'partial delivery keeps successful and failed channel results separate',
      (tester) async {
    await tester.pumpWidget(
        _app(_detail(_post(status: 'PARTIAL_PUBLISHED', platforms: const [
      'TIKTOK',
      'YOUTUBE_SHORTS'
    ], results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'TIKTOK',
          status: 'PUBLISHED',
          deliveryOutcome: 'PRIVATE'),
      PostPlatformResult(
          postId: _id,
          platform: 'YOUTUBE_SHORTS',
          status: 'FAILED',
          errorMessage:
              'Publishing to this platform failed. Please try again later.'),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Partially delivered'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(
        find.text(
            'Reason: Publishing to this platform failed. Please try again later.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('post-detail-open-analytics')),
        findsOneWidget);
    _expectEnglish(tester);
  });

  for (final dateCase in ['created', 'scheduled', 'delivered']) {
    testWidgets('English $dateCase date stays Gregorian and local 24-hour',
        (tester) async {
      final post = _post(
          status: dateCase == 'scheduled' ? 'QUEUED' : 'PUBLISHED',
          createdAt: _created.toUtc(),
          scheduledAt: dateCase == 'scheduled' ? _created.toUtc() : null,
          publishedAt: dateCase == 'delivered' ? _created.toUtc() : null);
      await tester.pumpWidget(_app(_detail(post)));
      await tester.pumpAndSettle();
      final prefix = switch (dateCase) {
        'scheduled' => 'Scheduled',
        'delivered' => 'Delivered',
        _ => 'Created'
      };
      expect(find.text('$prefix 27 Oct 2026 · 18:05'), findsOneWidget);
      expect(find.textContaining('2569'), findsNothing);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  testWidgets('English refresh retry updates the owned rows and checked date',
      (tester) async {
    final post = _post();
    final api = _Client(post)..readError = StateError('private diagnostic');
    await tester.pumpWidget(_app(_detail(post, api: api, refresh: true)));
    await tester.pumpAndSettle();
    api.readError = null;
    api.latest = _post(caption: 'Updated owned caption');
    await _tap(tester, find.text('Try again'));
    expect(api.reads, [true, true]);
    expect(find.text('Updated owned caption'), findsOneWidget);
    expect(find.text('Could not refresh. Showing previous information.'),
        findsNothing);
    expect(find.textContaining('Last checked '), findsOneWidget);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
  });

  testWidgets('English unavailable post can be checked again without mutation',
      (tester) async {
    final post = _post();
    final api = _Client(null);
    await tester.pumpWidget(_app(_detail(post, api: api, refresh: true)));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This post is not available in your account. It may have been canceled or removed.'),
        findsOneWidget);
    expect(find.text('Product video'), findsNothing);
    api.latest = post;
    await _tap(tester, find.text('Check again'));
    expect(find.text('Product video'), findsOneWidget);
    expect(api.reads, [true, true]);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'English owner switch rejects pending ${fails ? 'error' : 'data'}',
        (tester) async {
      final gate = Completer<PostSummaryResult?>();
      final post = _post();
      final api = _Client(post)..readGate = gate.future;
      final detail = _detail(post, api: api, refresh: true);
      await tester.pumpWidget(_app(detail));
      await tester.pump();
      PostDeeAuthSessionStore.instance.signIn(const AuthSession(
          userId: 'another-detail-owner', idToken: 'other-token'));
      if (fails) {
        gate.completeError(StateError('previous owner failure'));
      } else {
        gate.complete(_post(caption: 'Previous owner private update'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Your account has changed. Reopen Post details.'),
          findsOneWidget);
      expect(find.text('Product video'), findsNothing);
      expect(find.text('Previous owner private update'), findsNothing);
      expect(find.byKey(const ValueKey('post-detail-refresh')), findsNothing);
      _expectEnglish(tester);
      await tester.pumpWidget(_app(detail, locale: const Locale('th')));
      await tester.pumpAndSettle();
      expect(
          find.text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายละเอียดโพสต์ใหม่'),
          findsOneWidget);
      expect(api.reads, [true]);
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
    });
  }

  testWidgets('user Thai caption survives English and Thai locale changes',
      (tester) async {
    const caption = 'สินค้าใหม่พร้อมส่งวันนี้';
    final post = _post(caption: caption);
    final api = _Client(post);
    final detail = _detail(post, api: api);
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    expect(find.text(caption), findsOneWidget);
    await tester.pumpWidget(_app(detail, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text(caption), findsOneWidget);
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    expect(find.text('Post details'), findsOneWidget);
    expect(find.text(caption), findsOneWidget);
    expect(api.reads, isEmpty);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English cancel confirmation declines without changing the queue',
      (tester) async {
    final post = _post(status: 'QUEUED', scheduledAt: _created);
    final api = _Client(post);
    await tester.pumpWidget(_app(_detail(post, api: api)));
    await tester.pumpAndSettle();
    await _openConfirmation(tester, cancel: true);
    expect(find.text('Cancel this post?'), findsOneWidget);
    expect(find.text('The scheduled post will be removed from the queue.'),
        findsOneWidget);
    expect(_dialogText('Cancel post'), findsOneWidget);
    await _tap(tester, _dialogText('No'));
    expect(
        find.byKey(const ValueKey('post-detail-publish-now')), findsOneWidget);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
    await _dispose(tester);
  });

  for (final cancel in [false, true]) {
    testWidgets(
        '${cancel ? 'Cancel' : 'Publish'} dialog follows language changes without a write',
        (tester) async {
      final post = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(post);
      final detail = _detail(post, api: api);
      await tester.pumpWidget(_app(detail));
      await tester.pumpAndSettle();
      await _openConfirmation(tester, cancel: cancel);
      final readsBefore = api.reads.length;
      await tester.pumpWidget(_app(detail, locale: const Locale('th')));
      await tester.pumpAndSettle();
      expect(find.text(cancel ? 'ยกเลิกโพสต์นี้?' : 'โพสต์เลยตอนนี้?'),
          findsOneWidget);
      expect(_dialogText('ไม่'), findsOneWidget);
      expect(api.reads.length, readsBefore);
      await tester.pumpWidget(_app(detail));
      await tester.pumpAndSettle();
      expect(find.text(cancel ? 'Cancel this post?' : 'Publish now?'),
          findsOneWidget);
      expect(api.reads.length, readsBefore);
      await _tap(tester, _dialogText('No'));
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
        'English confirmed ${cancel ? 'cancel' : 'publish'} sends exactly one command and returns changed',
        (tester) async {
      final post = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(post);
      bool? changed;
      await tester.pumpWidget(_app(Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => _detail(post, api: api)));
                  },
                  child: const Text('Open detail'),
                ),
              ))));
      await _tap(tester, find.text('Open detail'));
      await _openConfirmation(tester, cancel: cancel);
      await _tap(tester, _dialogText(cancel ? 'Cancel post' : 'Publish now'));
      expect(changed, isTrue);
      expect(cancel ? api.canceled : api.published, [_id]);
      expect(cancel ? api.published : api.canceled, isEmpty);
      expect(find.text('Open detail'), findsOneWidget);
    });
  }

  testWidgets('English pending command disables repeat actions and refresh',
      (tester) async {
    final post = _post(status: 'QUEUED', scheduledAt: _created);
    final gate = Completer<void>();
    final api = _Client(post)
      ..writeGate = gate.future
      ..publishError = StateError('response failed');
    await tester.pumpWidget(_app(_detail(post, api: api)));
    await tester.pumpAndSettle();
    await _openConfirmation(tester);
    await _tap(tester, _dialogText('Publish now'));
    expect(find.text('Sending...'), findsOneWidget);
    final button = find.descendant(
        of: find.byKey(const ValueKey('post-detail-publish-now')),
        matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('post-detail-refresh')))
            .onPressed,
        isNull);
    expect(api.published, [_id]);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
        find.text('Could not publish now. Please try again.'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(api.published, [_id]);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
    await _dispose(tester);
  });

  for (final cancel in [false, true]) {
    testWidgets(
        'account change during ${cancel ? 'cancel' : 'publish'} confirmation prevents the command',
        (tester) async {
      final post = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(post);
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      await _openConfirmation(tester, cancel: cancel);
      PostDeeAuthSessionStore.instance.signIn(
          const AuthSession(userId: 'new-confirm-owner', idToken: 'new-token'));
      await tester.pumpAndSettle();
      await _tap(tester, _dialogText(cancel ? 'Cancel post' : 'Publish now'));
      expect(find.text('Your account has changed. Reopen Post details.'),
          findsOneWidget);
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  for (final errorCase in [
    (
      label: 'missing schedule',
      error: const ApiException('provider diagnostic',
          code: scheduledPostNotFoundCode),
      message: 'Scheduled post not found. Return to All posts to check.'
    ),
    (
      label: 'unavailable queue',
      error: const ApiException('provider diagnostic',
          code: publishQueueUnavailableCode),
      message:
          'The posting queue is temporarily unavailable. Please try again later.'
    ),
    (
      label: 'unavailable publishing',
      error: const ApiException('provider diagnostic',
          code: socialPublishingUnavailableCode),
      message: 'Publishing is temporarily unavailable. Please try again later.'
    ),
    (
      label: 'other API failure',
      error: const ApiException('provider diagnostic'),
      message: 'Could not publish now. Please try again.'
    ),
    (
      label: 'unexpected failure',
      error: StateError('provider diagnostic'),
      message: 'Could not publish now. Please try again.'
    ),
  ]) {
    testWidgets(
        'English publish error explains ${errorCase.label} without retrying',
        (tester) async {
      final post = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(post)..publishError = errorCase.error;
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      await _openConfirmation(tester);
      await _tap(tester, _dialogText('Publish now'));
      expect(find.text(errorCase.message), findsOneWidget);
      expect(find.textContaining('provider diagnostic'), findsNothing);
      expect(api.published, [_id]);
      expect(api.canceled, isEmpty);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  for (final outcome in [
    'PUBLISHING',
    'REMOVED',
    'FAILED',
    'QUEUED',
    'READ_ERROR'
  ]) {
    testWidgets(
        'English ambiguous cancellation reconciles $outcome with one mutation',
        (tester) async {
      final queued = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(queued)
        ..cancelError = TimeoutException('lost response');
      await tester.pumpWidget(_app(_detail(queued, api: api, refresh: true)));
      await tester.pumpAndSettle();
      expect(api.reads, [true]);
      await _openConfirmation(tester, cancel: true);
      api.latest = switch (outcome) {
        'REMOVED' => null,
        'QUEUED' || 'READ_ERROR' => queued,
        _ => _post(status: outcome),
      };
      if (outcome == 'READ_ERROR') api.readError = StateError('offline');
      await _tap(tester, _dialogText('Cancel post'));
      final message = switch (outcome) {
        'PUBLISHING' =>
          'This post has started sending and cannot be removed from the queue. Check its latest status.',
        'REMOVED' =>
          'This post is no longer in the list. It may have been canceled or removed.',
        'FAILED' =>
          'The post status has changed. Showing the latest information.',
        'QUEUED' =>
          'This post is still scheduled. Cancellation is not confirmed.',
        _ =>
          'Cancellation is not confirmed. Check the status again when you are connected.',
      };
      expect(find.text(message), findsOneWidget);
      expect(api.canceled, [_id]);
      expect(api.published, isEmpty);
      expect(api.reads, [true, false]);
      expect(
          find.byKey(const ValueKey('post-detail-publish-now')),
          const {'QUEUED', 'READ_ERROR'}.contains(outcome)
              ? findsOneWidget
              : findsNothing);
      _expectEnglish(tester);
      await _dispose(tester);
    });
  }

  for (final message in const [
    'Publishing to this platform failed. Please try again later.',
    'TikTok rejected this video because its frame rate validation failed. Export the video again before retrying.',
    'TikTok publishing options changed. Review the account and publishing settings before trying again.',
    'TikTok publishing options could not be checked. No video was sent to TikTok. Review the settings before trying again.',
    'Publishing result could not be confirmed. Check the platform before trying again.',
  ]) {
    testWidgets('English preserves the safe provider reason: $message',
        (tester) async {
      final post = _post(status: 'FAILED', platforms: const [
        'TIKTOK'
      ], results: [
        PostPlatformResult(
            postId: _id,
            platform: 'TIKTOK',
            status: 'FAILED',
            errorMessage: message),
      ]);
      final api = _Client(post);
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Reason: $message'), findsOneWidget);
      expect(find.text('Review this channel'), findsOneWidget);
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'English paid-plan failure explains the plan without channel review',
      (tester) async {
    await tester
        .pumpWidget(_app(_detail(_post(status: 'FAILED', results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'YOUTUBE_SHORTS',
          status: 'FAILED',
          errorMessage: 'PAID_PLAN_REQUIRED'),
    ]))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Reason: Your paid plan expired before the scheduled time, so this post was not sent. Renew Starter or Pro and create a new post.'),
        findsOneWidget);
    expect(find.textContaining('PAID_PLAN_REQUIRED'), findsNothing);
    expect(find.text('Review this channel'), findsNothing);
    _expectEnglish(tester);
  });

  testWidgets(
      'English channel review explains checks without resending any channel',
      (tester) async {
    final post = _post(status: 'FAILED', platforms: const ['TIKTOK']);
    final api = _Client(post);
    final detail = _detail(post, api: api);
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('post-detail-review-TIKTOK')));
    expect(find.text('Review TikTok'), findsOneWidget);
    expect(
        find.textContaining('Check this channel before creating a new post.'),
        findsOneWidget);
    expect(
        find.textContaining(
            'This review does not send your video. Successful channels will not be sent again.'),
        findsOneWidget);
    expect(find.text('Check connections'), findsOneWidget);
    final before = api.reads.length;
    await tester.pumpWidget(_app(detail, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('ทบทวน TikTok'), findsOneWidget);
    expect(api.reads.length, before);
    await tester.pumpWidget(_app(detail));
    await tester.pumpAndSettle();
    expect(find.text('Review TikTok'), findsOneWidget);
    await _tap(tester, find.text('Got it'));
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
  });

  for (final uri in [
    'javascript:alert(1)',
    'file:///private/video.mp4',
    'https://user:password@fixture.invalid/video.mp4',
    '/relative/video.mp4',
    'http:video.mp4',
  ]) {
    testWidgets('English unsafe preview URL has no play action: $uri',
        (tester) async {
      final post = _post(videoUrl: Uri.parse(uri));
      final api = _Client(post);
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Preview unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('post-detail-preview')), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
      expect(api.reads, isEmpty);
      _expectEnglish(tester);
    });
  }

  testWidgets('English preview re-signs before opening the submitted video',
      (tester) async {
    final oldPlatform = VideoPlayerPlatform.instance;
    final player = _VideoPlatform();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = oldPlatform);
    final cached = Uri.parse('https://fixture.invalid/expired.mp4');
    final fresh = Uri.parse('https://fixture.invalid/fresh.mp4');
    final post = _post(videoUrl: cached);
    final api = _Client(_post(videoUrl: fresh));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'\bView submitted video\b')),
          findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('post-detail-preview')));
      expect(api.reads, [true]);
      expect(find.byType(PostVideoPreviewScreen), findsOneWidget);
      expect(
          tester
              .widget<PostVideoPreviewScreen>(
                  find.byType(PostVideoPreviewScreen))
              .videoUrl,
          fresh);
      expect(player.sources.map((source) => source.uri), [fresh.toString()]);
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    } finally {
      semantics.dispose();
    }
  });

  for (final fails in [false, true]) {
    testWidgets(
        'English preview refuses a ${fails ? 'failed read' : 'new unsafe URL'} after re-signing',
        (tester) async {
      final post =
          _post(videoUrl: Uri.parse('https://fixture.invalid/cached.mp4'));
      final api =
          _Client(_post(videoUrl: Uri.parse('file:///private/video.mp4')));
      if (fails) api.readError = StateError('media unavailable');
      await tester.pumpWidget(_app(_detail(post, api: api)));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('post-detail-preview')));
      expect(
          find.text(
              'The video preview is not ready. Please refresh the status and try again.'),
          findsOneWidget);
      expect(find.byType(PostVideoPreviewScreen), findsNothing);
      expect(api.reads, [true]);
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      _expectEnglish(tester);
    });
  }

  testWidgets(
      'owner change during preview re-signing does not open old-account media',
      (tester) async {
    final gate = Completer<PostSummaryResult?>();
    final post =
        _post(videoUrl: Uri.parse('https://fixture.invalid/cached.mp4'));
    final api = _Client(post)..readGate = gate.future;
    await tester.pumpWidget(_app(_detail(post, api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-detail-preview')));
    await tester.pump();
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: 'preview-new-owner', idToken: 'new-token'));
    gate.complete(_post(
        videoUrl: Uri.parse('https://fixture.invalid/old-owner-fresh.mp4')));
    await tester.pumpAndSettle();
    expect(find.byType(PostVideoPreviewScreen), findsNothing);
    expect(find.text('Your account has changed. Reopen Post details.'),
        findsOneWidget);
    expect(api.reads, [true]);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
  });

  testWidgets('bare MaterialApp keeps existing Thai detail fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _detail(_post(caption: ''))));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text('(ไม่มีแคปชั่น)'), findsOneWidget);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(find.text('สร้างเมื่อ 27 ต.ค. 2026 · 18:05 น.'), findsOneWidget);
    expect(find.text('Post details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English failed post-link opening reports a local action error',
      (tester) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _LinkPlatform();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    const link = 'https://fixture.invalid/published-video';
    final post = _post(results: const [
      PostPlatformResult(
          postId: _id,
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          deliveryOutcome: 'LIVE',
          externalPostId: link),
    ]);
    final api = _Client(post);
    await tester.pumpWidget(_app(_detail(post, api: api)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Post link: $link'));
    expect(launcher.launched, [link]);
    expect(find.text('Could not open the post link.'), findsOneWidget);
    expect(api.published, isEmpty);
    expect(api.canceled, isEmpty);
    _expectEnglish(tester);
  });

  for (final dark in [false, true]) {
    for (final status in ['PARTIAL_PUBLISHED', 'UNCONFIRMED']) {
      testWidgets(
          'English $status badge is readable at 320dp 2x ${dark ? 'dark' : 'light'} mode',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_app(
            _detail(_post(
                status: status == 'UNCONFIRMED' ? 'PUBLISHED' : status,
                platforms: const [],
                results: status == 'UNCONFIRMED'
                    ? const [
                        PostPlatformResult(
                            postId: _id,
                            platform: 'YOUTUBE_SHORTS',
                            status: 'PUBLISHED',
                            deliveryOutcome: 'FUTURE_PROVIDER_OUTCOME')
                      ]
                    : const [])),
            dark: dark,
            scale: 2));
        await tester.pumpAndSettle();
        _expectReadable(
            tester,
            find.text(status == 'UNCONFIRMED'
                ? 'Delivery unconfirmed'
                : 'Partially delivered'));
        _expectEnglish(tester);
      });
    }

    testWidgets(
        'English scheduled detail and dialogs fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final post = _post(status: 'QUEUED', scheduledAt: _created);
      final api = _Client(post);
      await tester
          .pumpWidget(_app(_detail(post, api: api), dark: dark, scale: 2));
      await tester.pumpAndSettle();
      _expectReadable(tester, find.text('Scheduled 27 Oct 2026 · 18:05'));
      _expectReadable(tester, find.text('Publish now'));
      _expectEnglish(tester);
      for (final cancel in [false, true]) {
        await _openConfirmation(tester, cancel: cancel);
        expect(find.text(cancel ? 'Cancel this post?' : 'Publish now?'),
            findsOneWidget);
        _expectReadable(
            tester, _dialogText(cancel ? 'Cancel post' : 'Publish now'));
        _expectReadable(tester, _dialogText('No'));
        _expectEnglish(tester);
        await _tap(tester, _dialogText('No'));
      }
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      await _dispose(tester);
    });

    testWidgets(
        'English failed-channel review fits 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final post = _post(status: 'FAILED', platforms: const [
        'TIKTOK'
      ], results: const [
        PostPlatformResult(
            postId: _id,
            platform: 'TIKTOK',
            status: 'FAILED',
            errorMessage:
                'Publishing to this platform failed. Please try again later.'),
      ]);
      final api = _Client(post);
      await tester
          .pumpWidget(_app(_detail(post, api: api), dark: dark, scale: 2));
      await tester.pumpAndSettle();
      await _tap(
          tester, find.byKey(const ValueKey('post-detail-review-TIKTOK')));
      expect(find.text('Review TikTok'), findsOneWidget);
      _expectReadable(tester, find.text('Review TikTok'));
      _expectReadable(tester, find.text('Check connections'));
      _expectReadable(tester, find.text('Got it'));
      _expectEnglish(tester);
      await _tap(tester, find.text('Got it'));
      expect(api.published, isEmpty);
      expect(api.canceled, isEmpty);
      await _dispose(tester);
    });

    for (final missing in [false, true]) {
      testWidgets(
          'English ${missing ? 'unavailable' : 'read-error'} notice works at 320dp 2x ${dark ? 'dark' : 'light'} mode',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final post = _post();
        final api = _Client(missing ? null : post);
        if (!missing) api.readError = StateError('offline');
        await tester.pumpWidget(
            _app(_detail(post, api: api, refresh: true), dark: dark, scale: 2));
        await tester.pumpAndSettle();
        final message = missing
            ? 'This post is not available in your account. It may have been canceled or removed.'
            : 'Could not refresh. Showing previous information.';
        _expectReadable(tester, find.text(message));
        final action = find.text(missing ? 'Check again' : 'Try again');
        _expectReadable(tester, action);
        _expectEnglish(tester);
        api.readError = null;
        api.latest = _post(caption: 'Recovered narrow detail');
        await _tap(tester, action);
        expect(find.text('Recovered narrow detail'), findsOneWidget);
        expect(api.reads, [true, true]);
        expect(api.published, isEmpty);
        expect(api.canceled, isEmpty);
        _expectEnglish(tester);
      });
    }
  }
}
