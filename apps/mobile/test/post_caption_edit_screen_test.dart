import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/posts/post_caption_edit_screen.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

final captionTestNow = DateTime.utc(2030, 11, 3, 10);

PostSummaryResult captionTestPost({
  String caption = 'แคปชั่นเดิม',
  String status = 'QUEUED',
  DateTime? scheduledAt,
  List<String> platforms = const ['TIKTOK'],
  Map<String, Object?> settings = const {},
}) =>
    PostSummaryResult(
      id: 'caption-post',
      caption: caption,
      videoS3Key: 'clip.mp4',
      platforms: platforms,
      status: status,
      createdAt: captionTestNow,
      scheduledAt: scheduledAt ?? captionTestNow.add(const Duration(hours: 1)),
      updatedAt: captionTestNow,
      platformSettings: settings,
    );

class CaptionTestClient extends PostDeeApiClient {
  CaptionTestClient(this.latest);
  PostSummaryResult? latest;
  Object? readError;
  Object? writeError;
  Completer<PostSummaryResult?>? readGate;
  Completer<PostSummaryResult>? writeGate;
  int writes = 0;
  String? sentCaption;
  Map<String, String?>? sentPlatforms;
  String? sentTitle;
  DateTime? sentUpdatedAt;

  @override
  Future<PostSummaryResult?> getPostById(String postId,
      {bool includeMedia = false}) async {
    if (readError != null) throw readError!;
    return readGate == null ? latest : await readGate!.future;
  }

  @override
  Future<PostSummaryResult> updatePostCaption(
    String postId, {
    required String caption,
    Map<String, String?>? platformCaptions,
    String? youtubeTitle,
    DateTime? expectedUpdatedAt,
  }) async {
    writes++;
    sentCaption = caption;
    sentPlatforms = platformCaptions;
    sentTitle = youtubeTitle;
    sentUpdatedAt = expectedUpdatedAt;
    if (writeError != null) throw writeError!;
    if (writeGate != null) return writeGate!.future;
    return latest = captionTestPost(
        caption: caption,
        platforms: latest!.platforms,
        settings: {
          ...latest!.platformSettings,
          if (platformCaptions != null)
            for (final entry in platformCaptions.entries)
              entry.key: {'caption': entry.value},
        });
  }
}

Widget captionTestApp(Widget child,
        {String language = 'th', bool dark = false, double textScale = 1}) =>
    MaterialApp(
      locale: Locale(language),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: child,
    );

void runCaptionEditorTests({String language = 'th'}) {
  final english = language == 'en';
  String text(String th, String en) => english ? en : th;
  Future<void> open(WidgetTester tester, CaptionTestClient client,
      {bool dark = false, double textScale = 1}) async {
    await tester.pumpWidget(captionTestApp(
        PostCaptionEditScreen(
            post: client.latest!, apiClient: client, now: () => captionTestNow),
        language: language,
        dark: dark,
        textScale: textScale));
    await tester.pumpAndSettle();
  }

  String composerTitle(String caption,
          {Map<SocialPlatform, String> platformCaptions = const {}}) =>
      PlatformPublishSettings(
              usePlatformCaptions: platformCaptions.isNotEmpty,
              platformCaptions: platformCaptions)
          .resolvedForCaption(caption)
          .youtubeTitle;

  final automaticCaptionCases = {
    'shared price': 'สินค้า 199 บาท! รายละเอียดสินค้าเดิม',
    'whitespace and server trim':
        ' \n\t สินค้า   ราคา 199   บาท! รายละเอียดเดิม \r\n ',
    'unicode limit and removed brackets': '<${'😀' * 105}> รายละเอียดเดิม',
    'final trim at unicode limit': '${'😀' * 99} ${'ก' * 20}',
  };
  for (final entry in automaticCaptionCases.entries) {
    testWidgets(
        'persisted composer automatic title follows shared edits: ${entry.key}',
        (tester) async {
      final savedTitle = composerTitle(entry.value).trim();
      final editedCaption = entry.key.contains('unicode')
          ? '${'ก😀' * 60} ราคา 159 บาท'
          : '  สินค้า 159 บาท! รายละเอียดสินค้าใหม่  ';
      final expectedTitle = composerTitle(editedCaption);
      final client = CaptionTestClient(
          captionTestPost(caption: entry.value.trim(), platforms: [
        'TIKTOK',
        'YOUTUBE_SHORTS'
      ], settings: {
        'YOUTUBE_SHORTS': {'title': savedTitle}
      }));
      await open(tester, client);
      expect(find.text(text('ชื่อจากแคปชัน', 'Title from caption')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('post-caption-youtube-title')),
          findsNothing);
      expect(find.text(savedTitle), findsOneWidget);
      if (entry.key == 'unicode limit and removed brackets') {
        expect(savedTitle.runes.length, 100);
        expect(savedTitle.contains('<') || savedTitle.contains('>'), isFalse);
      }
      if (entry.key == 'final trim at unicode limit') {
        expect(savedTitle.runes.length, 99);
      }
      await tester.enterText(
          find.byKey(const ValueKey('post-caption-shared')), editedCaption);
      await tester.pump();
      expect(find.text(expectedTitle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-caption-save')));
      await tester.pumpAndSettle();
      expect(client.sentCaption, editedCaption.trim());
      expect(client.sentTitle, expectedTitle);
    });
  }

  testWidgets('persisted automatic title follows only the YouTube override',
      (tester) async {
    const shared = 'Shared summary without the YouTube title';
    const tikTokCaption = 'TikTok caption for the original product';
    const youtubeCaption = ' \n YouTube ราคา 199 บาท! รายละเอียด YouTube \n ';
    final savedTitle = composerTitle(shared, platformCaptions: {
      SocialPlatform.tiktok: tikTokCaption,
      SocialPlatform.youtubeShorts: youtubeCaption,
    }).trim();
    final client =
        CaptionTestClient(captionTestPost(caption: shared, platforms: [
      'TIKTOK',
      'YOUTUBE_SHORTS'
    ], settings: {
      'TIKTOK': {'caption': tikTokCaption},
      'YOUTUBE_SHORTS': {'caption': youtubeCaption.trim(), 'title': savedTitle},
    }));
    await open(tester, client);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-TIKTOK')),
        'TikTok changes must not become a YouTube title');
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(text('ชื่อจากแคปชัน', 'Title from caption')), 220,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(savedTitle), findsOneWidget);
    const editedYoutube = '  YouTube ราคา 159 บาท! รายละเอียดใหม่  ';
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('uploader-caption-YOUTUBE_SHORTS')), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-YOUTUBE_SHORTS')),
        editedYoutube);
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(text('ชื่อจากแคปชัน', 'Title from caption')), 220,
        scrollable: find.byType(Scrollable).first);
    final expectedTitle = composerTitle(shared,
        platformCaptions: {SocialPlatform.youtubeShorts: editedYoutube});
    expect(find.text(expectedTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentCaption, shared);
    expect(client.sentPlatforms!['YOUTUBE_SHORTS'], editedYoutube.trim());
    expect(client.sentTitle, expectedTitle);
  });

  testWidgets(
      'a distinct custom title keeps its internal spaces across caption edits',
      (tester) async {
    const caption = 'Original caption! Description';
    final customTitle = '${composerTitle(caption)}  custom';
    final client =
        CaptionTestClient(captionTestPost(caption: caption, platforms: [
      'TIKTOK',
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'title': customTitle}
    }));
    await open(tester, client);
    expect(find.widgetWithText(TextField, customTitle), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        'New caption with a different automatic title! Description');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentTitle, customTitle);
  });

  for (final separate in [false, true]) {
    testWidgets(
        'untouched persisted automatic title leaves without discard dialog: separate=$separate',
        (tester) async {
      const shared = 'Shared caption! Details';
      const youtube = 'YouTube override! Details';
      final savedTitle = composerTitle(shared,
          platformCaptions:
              separate ? {SocialPlatform.youtubeShorts: youtube} : const {});
      final client =
          CaptionTestClient(captionTestPost(caption: shared, platforms: [
        'TIKTOK',
        'YOUTUBE_SHORTS'
      ], settings: {
        'YOUTUBE_SHORTS': {
          'title': savedTitle,
          if (separate) 'caption': youtube
        },
      }));
      await tester.pumpWidget(captionTestApp(
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('open automatic editor'),
                      onPressed: () => Navigator.of(context)
                          .push<PostSummaryResult>(MaterialPageRoute(
                              builder: (_) => PostCaptionEditScreen(
                                  post: client.latest!,
                                  apiClient: client,
                                  now: () => captionTestNow)))))),
          language: language));
      await tester.tap(find.text('open automatic editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
          find.text(text('ทิ้งการแก้ไข?', 'Discard changes?')), findsNothing);
      expect(find.byType(PostCaptionEditScreen), findsNothing);
      expect(find.text('open automatic editor'), findsOneWidget);
      expect(client.writes, 0);
    });
  }

  testWidgets(
      'persisted automatic title still supports customizing and resetting',
      (tester) async {
    const caption = 'Automatic title! Description';
    final savedTitle = composerTitle(caption);
    final client =
        CaptionTestClient(captionTestPost(caption: caption, platforms: [
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'title': savedTitle}
    }));
    await open(tester, client);
    await tester.tap(
        find.text(text('ปรับชื่อเฉพาะ YouTube', 'Customize YouTube title')));
    await tester.pump();
    expect(find.widgetWithText(TextField, savedTitle), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-youtube-title')),
        '$savedTitle custom');
    await tester
        .tap(find.text(text('ใช้ชื่อจากแคปชัน', 'Use title from caption')));
    await tester.pump();
    const editedCaption = 'Changed automatic title! More details';
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), editedCaption);
    await tester.pump();
    final expectedTitle = composerTitle(editedCaption);
    expect(find.text(expectedTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentTitle, expectedTitle);
  });

  testWidgets('legacy TikTok settings still enforce direct caption limit',
      (tester) async {
    final client = CaptionTestClient(captionTestPost());
    await open(tester, client);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        List.filled(2201, 'a').join());
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    expect(client.writes, 0);
    expect(find.textContaining('2,200'), findsWidgets);
  });

  testWidgets('calendar refresh shows edited per-channel preview',
      (tester) async {
    var caption = 'ก่อนแก้';
    Widget calendar(int token) => captionTestApp(
        Scaffold(
            body: CalendarScreen(
          refreshToken: token,
          now: () => DateTime(2030, 11, 3, 12),
          loadCalendarPosts: () async => [
            CalendarPostResult(
                id: 'calendar-caption',
                caption: 'shared preserved',
                videoS3Key: '',
                platforms: const ['TIKTOK'],
                status: 'QUEUED',
                createdAt: DateTime(2030, 11, 3, 10),
                scheduledAt: DateTime(2030, 11, 3, 14),
                platformSettings: {
                  'TIKTOK': {'caption': caption}
                })
          ],
        )),
        language: language);
    await tester.pumpWidget(calendar(0));
    await tester.pumpAndSettle();
    expect(find.text('ก่อนแก้'), findsOneWidget);
    caption = 'หลังแก้';
    await tester.pumpWidget(calendar(1));
    await tester.pumpAndSettle();
    expect(find.text('หลังแก้'), findsOneWidget);
    expect(find.text('ก่อนแก้'), findsNothing);
  });

  testWidgets('window locks exactly when remaining time reaches sixty seconds',
      (tester) async {
    var now = captionTestNow;
    final client = CaptionTestClient(
        captionTestPost(scheduledAt: now.add(const Duration(seconds: 61))));
    await tester.pumpWidget(captionTestApp(
        PostCaptionEditScreen(
            post: client.latest!, apiClient: client, now: () => now),
        language: language));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('post-caption-save')))
            .onPressed,
        isNotNull);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('post-caption-save')))
            .onPressed,
        isNull);
    expect(
        find.text(text('ใกล้เวลาโพสต์แล้ว แก้แคปชั่นไม่ได้',
            'It is too close to the scheduled time to edit the caption.')),
        findsOneWidget);
  });

  testWidgets('loading hides form and an account switch drops a late read',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(
        AuthSession.authenticated(userId: 'read-owner-a', idToken: 'a'));
    final client = CaptionTestClient(captionTestPost())
      ..readGate = Completer<PostSummaryResult?>();
    await tester.pumpWidget(captionTestApp(
        PostCaptionEditScreen(
            post: client.latest!, apiClient: client, now: () => captionTestNow),
        language: language));
    await tester.pump();
    expect(find.byKey(const ValueKey('post-caption-shared')), findsNothing);
    sessions.signIn(
        AuthSession.authenticated(userId: 'read-owner-b', idToken: 'b'));
    client.readGate!.complete(captionTestPost(caption: 'private late load'));
    await tester.pumpAndSettle();
    expect(find.text('private late load'), findsNothing);
    expect(find.byKey(const ValueKey('post-caption-save')), findsNothing);
  });

  testWidgets('account switch during pending save can leave editor immediately',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(
        AuthSession.authenticated(userId: 'leave-owner-a', idToken: 'a'));
    final client = CaptionTestClient(captionTestPost())
      ..writeGate = Completer<PostSummaryResult>();
    await tester.pumpWidget(captionTestApp(
        Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  child: const Text('open editor'),
                  onPressed: () => Navigator.of(context)
                      .push<PostSummaryResult>(MaterialPageRoute(
                          builder: (_) => PostCaptionEditScreen(
                              post: client.latest!,
                              apiClient: client,
                              now: () => captionTestNow))))),
        ),
        language: language));
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'pending text');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    sessions.signIn(
        AuthSession.authenticated(userId: 'leave-owner-b', idToken: 'b'));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open editor'), findsOneWidget);
    expect(find.byType(PostCaptionEditScreen), findsNothing);
    client.writeGate!
        .complete(captionTestPost(caption: 'old private response'));
    await tester.pumpAndSettle();
    expect(find.text('old private response'), findsNothing);
  });

  testWidgets('invalid YouTube title blocks save without changing the caption',
      (tester) async {
    final client = CaptionTestClient(captionTestPost(platforms: [
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'title': 'Saved title'}
    }));
    await open(tester, client);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-youtube-title')), '<invalid>');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    expect(client.writes, 0);
    expect(find.textContaining('100'), findsWidgets);
  });

  testWidgets('empty per-channel caption validation is localized', (tester) async {
    final client = CaptionTestClient(captionTestPost(platforms: ['INSTAGRAM_REELS'],
      settings: {'INSTAGRAM_REELS': {'caption': 'Existing caption'}}));
    await open(tester, client);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-INSTAGRAM_REELS')), '');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    expect(find.text(text('เพิ่มแคปชั่นสำหรับช่องทางนี้', 'Add a caption for this channel.')), findsOneWidget);
    expect(client.writes, 0);
  });

  testWidgets(
      'conflict reload asks before discarding local text and shows newest form',
      (tester) async {
    final client = CaptionTestClient(captionTestPost())
      ..writeError = const ApiException('',
          code: 'POST_CAPTION_CONFLICT', statusCode: 409);
    await open(tester, client);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'local unsaved');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    client.latest = captionTestPost(caption: 'updated on another device');
    await tester.tap(find.text(text('โหลดข้อมูลล่าสุด', 'Load latest')));
    await tester.pumpAndSettle();
    expect(
        find.text(text('ทิ้งการแก้ไข?', 'Discard changes?')), findsOneWidget);
    await tester.tap(find.text(text('ทิ้งการแก้ไข', 'Discard changes')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'updated on another device'),
        findsOneWidget);
    expect(client.writes, 1);
  });

  testWidgets(
      'distinct saved YouTube title stays explicit until user selects automatic title',
      (tester) async {
    const caption = 'Original caption! Description';
    final customTitle = '${composerTitle(caption)} custom';
    final client =
        CaptionTestClient(captionTestPost(caption: caption, platforms: [
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'title': customTitle}
    }));
    await open(tester, client);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        'Changed caption. Details');
    expect(find.widgetWithText(TextField, customTitle), findsOneWidget);
    await tester.ensureVisible(
        find.text(text('ใช้ชื่อจากแคปชัน', 'Use title from caption')));
    await tester
        .tap(find.text(text('ใช้ชื่อจากแคปชัน', 'Use title from caption')));
    await tester.pump();
    expect(find.text('Changed caption.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentTitle, 'Changed caption.');
  });

  testWidgets('clearing a custom YouTube title falls back to the caption', (tester) async {
    final client = CaptionTestClient(captionTestPost(caption: 'First sentence. More details',
      platforms: ['YOUTUBE_SHORTS'], settings: {'YOUTUBE_SHORTS': {'title': 'Custom title'}}));
    await open(tester, client);
    await tester.enterText(find.byKey(const ValueKey('post-caption-youtube-title')), '');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentTitle, 'First sentence.');
    expect(client.sentCaption, 'First sentence. More details');
  });

  testWidgets('shared form loads latest caption and saves with version',
      (tester) async {
    final client = CaptionTestClient(captionTestPost(caption: 'ข้อมูลล่าสุด'));
    await open(tester, client);
    expect(find.widgetWithText(TextField, 'ข้อมูลล่าสุด'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-caption-TIKTOK')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'แก้ใหม่');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentCaption, 'แก้ใหม่');
    expect(client.sentPlatforms, isNull);
    expect(client.sentUpdatedAt, captionTestNow);
  });

  testWidgets(
      'per-channel editor preserves shared caption and edits only selected fields',
      (tester) async {
    final client = CaptionTestClient(captionTestPost(platforms: [
      'TIKTOK',
      'YOUTUBE_SHORTS'
    ], settings: {
      'TIKTOK': {'caption': 'TikTok เดิม'},
      'YOUTUBE_SHORTS': {'caption': 'คำอธิบายเดิม', 'title': 'ชื่อเดิม'}
    }));
    await open(tester, client);
    expect(find.byKey(const ValueKey('post-caption-shared')), findsNothing);
    expect(find.byKey(const ValueKey('uploader-caption-INSTAGRAM_REELS')),
        findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('uploader-caption-TIKTOK')), 'TikTok ใหม่');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post-caption-youtube-title')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-youtube-title')), 'ชื่อใหม่');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentCaption, 'แคปชั่นเดิม');
    expect(client.sentPlatforms,
        {'TIKTOK': 'TikTok ใหม่', 'YOUTUBE_SHORTS': 'คำอธิบายเดิม'});
    expect(client.sentTitle, 'ชื่อใหม่');
  });

  testWidgets(
      'YouTube automatic title uses existing caption suggestion and supports legacy settings',
      (tester) async {
    final client = CaptionTestClient(
        captionTestPost(caption: 'First sentence. More detail', platforms: [
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'visibility': 'private'}
    }));
    await open(tester, client);
    expect(find.text('First sentence.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        'New sentence! More');
    await tester.pump();
    expect(find.text('New sentence!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(client.sentTitle, 'New sentence!');
  });

  testWidgets('TikTok UTF-16 and YouTube byte/title validation block save',
      (tester) async {
    final client = CaptionTestClient(captionTestPost(settings: {
      'TIKTOK': {'publishMode': 'DIRECT_POST'}
    }));
    await open(tester, client);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        List.filled(1101, '😀').join());
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    expect(
        find.text(text('แคปชั่น TikTok ต้องไม่เกิน 2,200 ตัวอักษร',
            'The TikTok caption must be no longer than 2,200 characters.')),
        findsWidgets);
    expect(client.writes, 0);
    await tester.pumpWidget(const SizedBox());
    final youtube = CaptionTestClient(captionTestPost(platforms: [
      'YOUTUBE_SHORTS'
    ], settings: {
      'YOUTUBE_SHORTS': {'title': 'Title'}
    }));
    await open(tester, youtube);
    await tester.enterText(find.byKey(const ValueKey('post-caption-shared')),
        List.filled(1667, 'ก').join());
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    expect(youtube.writes, 0);
    expect(find.textContaining('5,000'), findsWidgets);
  });

  for (final status in ['PUBLISHING', 'PUBLISHED', 'FAILED', 'CANCELLED']) {
    testWidgets('$status post is read-only', (tester) async {
      final client = CaptionTestClient(captionTestPost(status: status));
      await open(tester, client);
      expect(
          find.text(text('โพสต์นี้เริ่มส่งหรือถูกยกเลิกแล้ว แก้แคปชั่นไม่ได้',
              'This post has started sending or was canceled. Its caption cannot be edited.')),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('post-caption-save')))
              .onPressed,
          isNull);
    });
  }

  for (final seconds in [60, 0, -1]) {
    testWidgets('window closed at $seconds seconds', (tester) async {
      final client = CaptionTestClient(captionTestPost(
          scheduledAt: captionTestNow.add(Duration(seconds: seconds))));
      await open(tester, client);
      expect(
          find.text(text('ใกล้เวลาโพสต์แล้ว แก้แคปชั่นไม่ได้',
              'It is too close to the scheduled time to edit the caption.')),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('post-caption-save')))
              .onPressed,
          isNull);
    });
  }

  testWidgets('load failure offers retry without showing stale editable form',
      (tester) async {
    final client = CaptionTestClient(captionTestPost())
      ..readError = Exception('offline');
    await open(tester, client);
    expect(find.byKey(const ValueKey('post-caption-shared')), findsNothing);
    client.readError = null;
    await tester.tap(find.text(text('ลองใหม่', 'Try again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-caption-shared')), findsOneWidget);
  });

  for (final code in [
    'POST_NOT_EDITABLE',
    'POST_CAPTION_EDIT_WINDOW_CLOSED',
    'POST_CAPTION_CONFLICT',
    'POST_NOT_FOUND',
    'POST_CAPTION_EDIT_UNAVAILABLE',
    'TIKTOK_CAPTION_TOO_LONG',
    'PLATFORM_CAPTION_INVALID',
    'INVALID_YOUTUBE_TITLE'
  ]) {
    testWidgets('save error $code keeps input and shows localized action',
        (tester) async {
      final client = CaptionTestClient(captionTestPost())
        ..writeError = ApiException('raw provider error',
            code: code, statusCode: code == 'POST_NOT_FOUND' ? 404 : 409);
      await open(tester, client);
      await tester.enterText(
          find.byKey(const ValueKey('post-caption-shared')), 'เก็บข้อความนี้');
      await tester.tap(find.byKey(const ValueKey('post-caption-save')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'เก็บข้อความนี้'), findsOneWidget);
      expect(find.text('raw provider error'), findsNothing);
      expect(find.byKey(const ValueKey('post-caption-error')), findsOneWidget);
    });
  }

  testWidgets('back asks before discarding unsaved edits', (tester) async {
    final client = CaptionTestClient(captionTestPost());
    await tester.pumpWidget(captionTestApp(
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<PostSummaryResult>(
                            builder: (_) => PostCaptionEditScreen(
                                post: client.latest!,
                                apiClient: client,
                                now: () => captionTestNow))),
                    child: const Text('open')))),
        language: language));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'ยังไม่บันทึก');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
        find.text(text('ทิ้งการแก้ไข?', 'Discard changes?')), findsOneWidget);
    await tester.tap(find.text(text('แก้ไขต่อ', 'Keep editing')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'ยังไม่บันทึก'), findsOneWidget);
  });

  testWidgets(
      'account change hides private text and ignores pending save result',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(
        AuthSession.authenticated(userId: 'caption-owner-a', idToken: 'a'));
    final client = CaptionTestClient(captionTestPost())
      ..writeGate = Completer<PostSummaryResult>();
    await open(tester, client);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'private changed');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pump();
    sessions.signIn(
        AuthSession.authenticated(userId: 'caption-owner-b', idToken: 'b'));
    await tester.pump();
    expect(find.text('private changed'), findsNothing);
    client.writeGate!
        .complete(captionTestPost(caption: 'old account response'));
    await tester.pumpAndSettle();
    expect(find.text('old account response'), findsNothing);
    expect(
        find.text(text('บัญชีเปลี่ยนแล้ว กรุณากลับไปเปิดโพสต์จากบัญชีปัจจุบัน',
            'Your account changed. Open the post again from your current account.')),
        findsOneWidget);
  });

  testWidgets('narrow dark screen and long text wrap without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = CaptionTestClient(captionTestPost(
        caption: List.filled(20, 'ข้อความภาษาไทยยาวมาก ').join(),
        platforms: [
          'YOUTUBE_SHORTS'
        ],
        settings: {
          'YOUTUBE_SHORTS': {'title': 'ชื่อคลิปยาว'}
        }));
    await open(tester, client, dark: true, textScale: 1.6);
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), '<invalid>');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            english ? 'YouTube descriptions cannot' : 'คำอธิบาย YouTube ห้าม'),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detail edit button requires queued future schedule and successful save updates detail',
      (tester) async {
    final client = CaptionTestClient(captionTestPost(
        scheduledAt: DateTime.now().add(const Duration(hours: 2))));
    await tester.pumpWidget(captionTestApp(
        PostDetailScreen(
            post: client.latest!, apiClient: client, refreshOnOpen: false),
        language: language));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-detail-edit-caption')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('post-caption-shared')), 'รายละเอียดใหม่');
    await tester.tap(find.byKey(const ValueKey('post-caption-save')));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดใหม่'), findsOneWidget);
    for (final status in ['PUBLISHED', 'PUBLISHING', 'CANCELLED']) {
      await tester.pumpWidget(captionTestApp(
          PostDetailScreen(
              key: ValueKey(status),
              post: captionTestPost(status: status),
              refreshOnOpen: false),
          language: language));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('post-detail-edit-caption')), findsNothing);
    }
    await tester.pumpWidget(captionTestApp(
        PostDetailScreen(
            key: const ValueKey('past'),
            post: captionTestPost(scheduledAt: DateTime(2020)),
            refreshOnOpen: false),
        language: language));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('post-detail-edit-caption')), findsNothing);
  });
}

void main() => runCaptionEditorTests();
