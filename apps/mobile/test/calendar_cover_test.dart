import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/calendar/calendar_cover_preview_cache.dart';
import 'package:video_player/video_player.dart';

CalendarPostResult _post(
        {Uri? cover,
        String id = 'chosen-cover',
        String? coverKey,
        String? owner,
        int? frame,
        String status = 'PUBLISHED'}) =>
    CalendarPostResult(
      id: id,
      caption: 'เล่นเกมนี้แล้วติดหนึบเลย ลองดูคลิปใหม่ของวันนี้',
      videoS3Key: 'uploads/owner/video.mp4',
      coverImageUrl: cover,
      coverImageS3Key: coverKey,
      userId: owner,
      coverFrameTimeMs: frame,
      videoUrl: Uri.parse('https://media.test/video-must-not-load.mp4'),
      platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
      status: status,
      createdAt: DateTime(2026, 10, 21, 12, 20),
    );

Widget _host(CalendarPostResult post,
        {double scale = 1,
        ValueChanged<CalendarPostResult>? onOpen,
        CalendarLegacyCoverFrameLoader? extractFrame,
        Future<PostSummaryResult?> Function(String)? loadCoverPost}) =>
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: CalendarScreen(
          now: () => DateTime(2026, 10, 21, 15),
          loadCalendarPosts: () async => [post],
          loadCoverPost: loadCoverPost,
          extractLegacyCoverFrame: extractFrame,
          onOpenCalendarPostDetail: onOpen,
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
  });

  testWidgets(
      'selected-cover metadata loads once and is reused across view rebuilds',
      (tester) async {
    var reads = 0;
    final post = _post(coverKey: 'uploads/owner/chosen.jpg');
    await tester.pumpWidget(_host(post, loadCoverPost: (id) async {
      reads++;
      expect(id, post.id);
      return _post(cover: Uri.parse('https://media.test/selected.jpg'));
    }));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byKey(const ValueKey('calendar-post-cover-image-chosen-cover')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.byKey(const ValueKey('calendar-week-view')));
    await tester.pumpAndSettle();
    expect(reads, 1);
  });

  testWidgets('a saved legacy frame is rendered as an image without a player',
      (tester) async {
    final bytes =
        (await rootBundle.load('assets/images/brand/postdee_mark.png'))
            .buffer
            .asUint8List();
    var extracts = 0;
    await tester.pumpWidget(_host(
      _post(frame: 1200),
      loadCoverPost: (_) async => _post(frame: 1200),
      extractFrame: (url, {required frameTimeMs, required isCurrent}) async {
        extracts++;
        expect(frameTimeMs, 1200);
        expect(isCurrent(), isTrue);
        return bytes;
      },
    ));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byKey(
      const ValueKey('calendar-post-cover-image-chosen-cover'),
    ));
    final provider = (image.image as ResizeImage).imageProvider as MemoryImage;
    expect(provider.bytes, same(bytes));
    expect(extracts, 1);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual refresh can renew a failed cover read', (tester) async {
    var reads = 0;
    await tester.pumpWidget(_host(
      _post(coverKey: 'uploads/owner/chosen.jpg'),
      loadCoverPost: (id) async {
        reads++;
        if (reads == 1) throw const ApiException('Offline');
        return _post(cover: Uri.parse('https://media.test/fresh.jpg'));
      },
    ));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(
        find.byKey(
            const ValueKey('calendar-post-cover-placeholder-chosen-cover')),
        findsOneWidget);
    final refresh = tester
        .widget<RefreshIndicator>(
            find.byKey(const ValueKey('calendar-pull-refresh')))
        .onRefresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(reads, 2);
    expect(find.byKey(const ValueKey('calendar-post-cover-image-chosen-cover')),
        findsOneWidget);
  });

  testWidgets('silent sending-status refresh does not sign the cover again',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(_host(
      _post(coverKey: 'uploads/owner/chosen.jpg', status: 'PUBLISHING'),
      loadCoverPost: (id) async {
        reads++;
        return _post(cover: Uri.parse('https://media.test/selected.jpg'));
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a late cover cannot reveal the previous account image',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(const AuthSession(userId: 'owner-a', idToken: 'a'));
    final lateCover = Completer<PostSummaryResult?>();
    var reads = 0;
    await tester.pumpWidget(_host(
      _post(owner: 'owner-a', coverKey: 'uploads/owner-a/chosen.jpg'),
      loadCoverPost: (_) {
        reads++;
        return lateCover.future;
      },
    ));
    await tester.pumpAndSettle();
    sessions.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    lateCover.complete(
        _post(cover: Uri.parse('https://media.test/old-account.jpg')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byKey(const ValueKey('calendar-post-cover-image-chosen-cover')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar uses the chosen cover image without a video player',
      (tester) async {
    final cover =
        Uri.parse('https://media.test/chosen-cover.jpg?signature=test');
    final post = _post(cover: cover);
    CalendarPostResult? opened;
    await tester.pumpWidget(_host(post, onOpen: (value) => opened = value));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byKey(
      const ValueKey('calendar-post-cover-image-chosen-cover'),
    ));
    final resized = image.image as ResizeImage;
    expect((resized.imageProvider as NetworkImage).url, cover.toString());
    expect(image.fit, BoxFit.cover);
    expect(image.excludeFromSemantics, isTrue);
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.ensureVisible(find.byKey(
      const ValueKey('calendar-post-cover-chosen-cover'),
    ));
    await tester.tap(find.byKey(
      const ValueKey('calendar-post-cover-chosen-cover'),
    ));
    await tester.pumpAndSettle();
    expect(opened, same(post));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing cover stays readable without using the video URL',
      (tester) async {
    await tester.pumpWidget(_host(_post()));
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const ValueKey('calendar-post-cover-placeholder-chosen-cover')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-post-cover-image-chosen-cover')),
        findsNothing);
    expect(find.text('12:20'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image error shows a placeholder and keeps the post tappable',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(_host(
      _post(cover: Uri.parse('https://media.test/unavailable.jpg')),
      onOpen: (_) => opens++,
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const ValueKey('calendar-post-cover-placeholder-chosen-cover')),
        findsOneWidget);
    await tester.ensureVisible(find.text('12:20'));
    await tester.tap(find.text('12:20'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  for (final url in [
    'file:///private/cover.jpg',
    'https://user:secret@media.test/cover.jpg'
  ]) {
    testWidgets('calendar rejects an unsafe cover URL $url', (tester) async {
      await tester.pumpWidget(_host(_post(cover: Uri.parse(url))));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('calendar-post-cover-image-chosen-cover')),
          findsNothing);
      expect(
          find.byKey(
              const ValueKey('calendar-post-cover-placeholder-chosen-cover')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('portrait cover and post details fit 320dp at ${scale}x text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final post = _post(cover: Uri.parse('https://media.test/cover.jpg'));
      CalendarPostResult? opened;
      await tester.pumpWidget(_host(
        post,
        scale: scale,
        onOpen: (value) => opened = value,
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(
        const ValueKey('calendar-post-cover-chosen-cover'),
      ));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(
        const ValueKey('calendar-post-cover-chosen-cover'),
      ));
      expect(size.width / size.height, closeTo(9 / 16, .01));
      expect(find.text('12:20'), findsOneWidget);
      final captionFinder = find.text(post.caption);
      final caption = tester.widget<Text>(captionFinder);
      final captionSize = tester.getSize(captionFinder);
      final renderedCaption = tester.widget<RichText>(
        find.descendant(of: captionFinder, matching: find.byType(RichText)),
      );
      final singleLine = TextPainter(
        text: renderedCaption.text,
        textDirection: TextDirection.ltr,
        textScaler: renderedCaption.textScaler,
        strutStyle: renderedCaption.strutStyle,
        textHeightBehavior: renderedCaption.textHeightBehavior,
        maxLines: 1,
        ellipsis: '\u2026',
      )..layout(maxWidth: captionSize.width);
      addTearDown(singleLine.dispose);
      expect(singleLine.didExceedMaxLines, isTrue);
      expect(captionSize.height, closeTo(singleLine.height, .01));
      expect(caption.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSemantics(find.byKey(ValueKey('calendar-post-${post.id}')))
            .label,
        contains(post.caption),
      );
      final channels = find.byKey(
        const ValueKey('calendar-channels-chosen-cover'),
      );
      expect(find.descendant(of: channels, matching: find.text('TikTok')),
          findsOneWidget);
      expect(find.descendant(of: channels, matching: find.text('Shorts')),
          findsOneWidget);
      await tester.tap(captionFinder);
      await tester.pumpAndSettle();
      expect(opened, same(post));
      expect(tester.takeException(), isNull);
    });
  }
}
