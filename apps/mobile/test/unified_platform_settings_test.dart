import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/tiktok_publishing_settings_sheet.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _saveKey = ValueKey('uploader-platform-settings-save');
const _cancelKey = ValueKey('uploader-platform-settings-cancel');
const _inboxKey = ValueKey('uploader-tiktok-mode-inbox');
const _directKey = ValueKey('uploader-tiktok-mode-direct');
const _pro = SubscriptionStatusResult(
  userId: 'test-user',
  plan: 'PRO',
  status: 'ACTIVE',
  phoneVerified: true,
  requiresPhoneVerification: false,
  canSchedule: true,
  canUseAiCaptions: true,
  canUseAnalytics: true,
);

TikTokPublishingOptionsResult _options({String nickname = 'บัญชีล่าสุด'}) =>
    TikTokPublishingOptionsResult(
      connectionId: 'local-tiktok',
      creatorInfoRevision: _revision,
      creatorInfo: TikTokCreatorInfo(
        creatorAvatarUrl: '',
        creatorUsername: 'seller',
        creatorNickname: nickname,
        privacyLevelOptions: const [TikTokPrivacyLevel.selfOnly],
        commentDisabled: false,
        duetDisabled: false,
        stitchDisabled: false,
        maxVideoPostDurationSec: 600,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previewDirectory = Platform.environment['POSTDEE_SETTINGS_PREVIEW_DIR'];
  late Directory directory;
  late File video;
  late TestPublishDraftStore store;
  late AuthSession previous;
  late ThemeMode previousTheme;
  late List<CreatePostRequest> requests;

  setUpAll(() async {
    // Use the app's Thai metrics for layout checks instead of the square test
    // font, whose fixed-width Thai glyphs exaggerate line wrapping.
    final fonts = FontLoader('Anuphan');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts
          .addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousTheme = AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    AppTheme.applyThemeMode(ThemeMode.light);
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'test-user'));
    directory = Directory.systemTemp.createTempSync('unified-settings-');
    video = File('${directory.path}/video.mp4')..writeAsBytesSync([1, 2, 3]);
    store = TestPublishDraftStore();
    requests = [];
  });

  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    AppTheme.applyThemeMode(previousTheme);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Widget uploader({
    String? initialDraftId,
    GlobalKey? boundaryKey,
    double keyboard = 0,
    double textScale = 1,
  }) =>
      RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: UploaderScreen(
                draftStore: store,
                initialDraftId: initialDraftId,
                initialVideoPath: initialDraftId == null ? video.path : null,
                initialVideoName: 'video.mp4',
                initialVideoSizeBytes: 3,
                initialVideoWidth: 720,
                initialVideoHeight: 1280,
                loadSubscription: () async => _pro,
                loadTikTokPublishingOptions: () async => _options(),
                loadSocialConnections: () async => const [
                  SocialConnectionResult(
                    platform: 'TIKTOK',
                    connected: true,
                    connectionId: 'local-tiktok',
                    connectionRevision: _revision,
                    externalAccountId: 'tiktok-seller',
                    displayName: 'ร้าน TikTok ทดสอบ',
                  ),
                  SocialConnectionResult(
                    platform: 'YOUTUBE_SHORTS',
                    connected: true,
                    connectionId: 'local-youtube',
                    externalAccountId: 'youtube-seller',
                    displayName: 'ร้าน YouTube ทดสอบ',
                  ),
                  SocialConnectionResult(
                    platform: 'INSTAGRAM_REELS',
                    connected: true,
                    connectionId: 'local-instagram',
                    externalAccountId: 'instagram-seller',
                    displayName: 'ร้าน Instagram ทดสอบ',
                  ),
                  SocialConnectionResult(
                    platform: 'FACEBOOK_REELS',
                    connected: true,
                    connectionId: 'local-facebook',
                    externalAccountId: 'facebook-page',
                    displayName: 'เพจ Facebook ทดสอบ',
                  ),
                ],
                loadSocialPublishingReadiness: () async => const [
                  SocialPublishingConnectionReadiness(
                      platform: 'TIKTOK',
                      state: SocialPublishingState.connected,
                      connectionId: 'local-tiktok',
                      connectionRevision: _revision),
                  SocialPublishingConnectionReadiness(
                      platform: 'YOUTUBE_SHORTS',
                      state: SocialPublishingState.connected,
                      connectionId: 'local-youtube'),
                  SocialPublishingConnectionReadiness(
                      platform: 'INSTAGRAM_REELS',
                      state: SocialPublishingState.connected,
                      connectionId: 'local-instagram'),
                  SocialPublishingConnectionReadiness(
                      platform: 'FACEBOOK_REELS',
                      state: SocialPublishingState.connected,
                      connectionId: 'local-facebook'),
                ],
                probePublishMedia: probeValidPublishMedia,
                checkPublishingReadiness: () async {},
                createUpload: (_) async => const UploadResult(
                  id: 'upload',
                  videoS3Key: 'uploads/video.mp4',
                  storageProvider: 'mock',
                ),
                uploadVideoFile: (_, __) async {},
                createPost: (request) async {
                  requests.add(request);
                  return QueuedPostResult(
                    id: 'post',
                    videoS3Key: request.videoS3Key,
                    platforms: request.platforms,
                    status: 'QUEUED',
                  );
                },
              ),
            ),
          ));

  Future<void> tapKey(WidgetTester tester, Key key) async {
    final control = find.byKey(key);
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  void usePhoneSize(WidgetTester tester, {Size size = const Size(393, 852)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> selectPlatform(WidgetTester tester, String platform,
      {String caption = 'คลิปสินค้าทดสอบ'}) async {
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tester.enterText(
      find.byKey(const ValueKey('uploader-caption-field')),
      caption,
    );
    await goToUploaderStep(tester, 2);
    await tapKey(tester, ValueKey('uploader-platform-$platform'));
  }

  Future<void> openSettings(WidgetTester tester, String platform) => tapKey(
        tester,
        ValueKey('uploader-platform-settings-$platform'),
      );

  Future<void> submit(WidgetTester tester) async {
    await goToUploaderStep(tester, 3);
    await tapKey(tester, const ValueKey('publish-review-confirm'));
  }

  Future<void> answerYouTube(WidgetTester tester) async {
    for (final key in [
      'uploader-youtube-made-for-kids-no',
      'uploader-youtube-synthetic-no',
      'uploader-youtube-guidelines-certified',
    ]) {
      await tapKey(tester, ValueKey(key));
    }
  }

  Future<void> editYouTubeTitle(WidgetTester tester, String title) async {
    final edit = find.byKey(const ValueKey('uploader-youtube-title-edit'));
    if (edit.evaluate().isNotEmpty) {
      await tapKey(tester, const ValueKey('uploader-youtube-title-edit'));
    }
    final field = find.byKey(const ValueKey('uploader-youtube-title'));
    await tester.ensureVisible(field);
    await tester.enterText(field, title);
    await tester.pumpAndSettle();
  }

  testWidgets('YouTube derives a live title without requiring another entry',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS',
        caption: 'รีวิวสินค้าใหม่! รายละเอียดเพิ่มเติม\n#รีวิว');
    await openSettings(tester, 'YOUTUBE_SHORTS');
    expect(find.text('รีวิวสินค้าใหม่!'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-youtube-title')), findsNothing);
    await answerYouTube(tester);
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'เปลี่ยนแคปชันแล้ว! รายละเอียดใหม่\n#ใหม่');
    await goToUploaderStep(tester, 2);
    await openSettings(tester, 'YOUTUBE_SHORTS');
    expect(find.text('เปลี่ยนแคปชันแล้ว!'), findsOneWidget);
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 3);
    expect(
        find.textContaining('ชื่อวิดีโอ: เปลี่ยนแคปชันแล้ว!'), findsOneWidget);
    await tapKey(tester, const ValueKey('publish-review-confirm'));
    expect(requests.single.caption, 'เปลี่ยนแคปชันแล้ว! รายละเอียดใหม่\n#ใหม่');
    expect((requests.single.platformSettings['YOUTUBE_SHORTS'] as Map)['title'],
        'เปลี่ยนแคปชันแล้ว!');
    expect(store.savedRequests.last.platformSettings.youtubeTitle, isEmpty);
  });

  testWidgets('YouTube custom title persists and reset returns to automatic',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS', caption: 'ชื่อจากแคปชัน');
    await openSettings(tester, 'YOUTUBE_SHORTS');
    await tapKey(tester, const ValueKey('uploader-youtube-title-edit'));
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-youtube-title')))
            .controller!
            .text,
        'ชื่อจากแคปชัน');
    await editYouTubeTitle(tester, 'ชื่อที่ตั้งเอง');
    await answerYouTube(tester);
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('uploader-caption-field')),
        'ชื่อจากแคปชันใหม่! รายละเอียด');
    await goToUploaderStep(tester, 2);
    await openSettings(tester, 'YOUTUBE_SHORTS');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('uploader-youtube-title')))
            .controller!
            .text,
        'ชื่อที่ตั้งเอง');
    await tapKey(tester, const ValueKey('uploader-youtube-title-reset'));
    expect(find.text('ชื่อจากแคปชันใหม่!'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-youtube-title')), findsNothing);
    await tapKey(tester, _saveKey);
    await submit(tester);
    expect((requests.single.platformSettings['YOUTUBE_SHORTS'] as Map)['title'],
        'ชื่อจากแคปชันใหม่!');
  });

  testWidgets('YouTube-only can use an explicit title without a caption',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    await tapKey(tester, const ValueKey('uploader-wizard-next'));
    expect(
        find.byKey(const ValueKey('uploader-step-platforms')), findsOneWidget);
    await tapKey(tester, const ValueKey('uploader-platform-YOUTUBE_SHORTS'));
    await openSettings(tester, 'YOUTUBE_SHORTS');
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await editYouTubeTitle(tester, 'คลิปไม่มีคำอธิบาย');
    await answerYouTube(tester);
    await tapKey(tester, _saveKey);
    await submit(tester);
    expect(requests.single.caption, isEmpty);
    expect(requests.single.platforms, ['YOUTUBE_SHORTS']);
    expect((requests.single.platformSettings['YOUTUBE_SHORTS'] as Map)['title'],
        'คลิปไม่มีคำอธิบาย');
  });

  testWidgets(
      'a blank caption cannot publish YouTube alongside another platform',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS', caption: '');
    await openSettings(tester, 'YOUTUBE_SHORTS');
    await editYouTubeTitle(tester, 'ชื่อสำหรับ YouTube เท่านั้น');
    await answerYouTube(tester);
    await tapKey(tester, _saveKey);
    await tapKey(tester, const ValueKey('uploader-platform-INSTAGRAM_REELS'));
    await tapKey(tester, const ValueKey('uploader-wizard-next'));
    expect(find.byKey(const ValueKey('uploader-step-body-2')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('เพิ่มแคปชั่นก่อนโพสต์'), -300,
        scrollable: uploaderMainScroll);
    expect(find.text('เพิ่มแคปชั่นก่อนโพสต์'), findsOneWidget);
    await goToUploaderStep(tester, 3);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('publish-review-confirm')))
            .onPressed,
        isNull);
    expect(requests, isEmpty);
  });

  testWidgets('YouTube rejects invalid custom titles and clearing uses caption',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'YOUTUBE_SHORTS', caption: 'ชื่ออัตโนมัติ');
    await openSettings(tester, 'YOUTUBE_SHORTS');
    await answerYouTube(tester);
    await editYouTubeTitle(tester, '<ชื่อไม่ถูกต้อง>');
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await editYouTubeTitle(tester, '😀' * 101);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await editYouTubeTitle(tester, '');
    expect(find.text('ชื่ออัตโนมัติ'), findsOneWidget);
    await tapKey(tester, _saveKey);
    await submit(tester);
    expect((requests.single.platformSettings['YOUTUBE_SHORTS'] as Map)['title'],
        'ชื่ออัตโนมัติ');
  });

  testWidgets('Instagram Cancel discards changes and Save sends AI choice',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'INSTAGRAM_REELS');
    await openSettings(tester, 'INSTAGRAM_REELS');
    expect(find.text('ร้าน Instagram ทดสอบ'), findsWidgets);
    await tapKey(tester, const ValueKey('uploader-instagram-share-to-feed'));
    await tapKey(tester, const ValueKey('uploader-instagram-ai-yes'));
    await tapKey(tester, _cancelKey);

    await openSettings(tester, 'INSTAGRAM_REELS');
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const ValueKey('uploader-instagram-share-to-feed')))
          .value,
      isTrue,
      reason: 'Cancel must leave the saved share-to-feed value intact',
    );
    await tapKey(tester, _saveKey);
    await tapKey(tester, const ValueKey('uploader-save-draft-button'));
    expect(
        store.savedRequests.last.platformSettings
            .toDraftJson()['instagramIsAiGenerated'],
        isNull);

    await openSettings(tester, 'INSTAGRAM_REELS');
    await tapKey(tester, const ValueKey('uploader-instagram-share-to-feed'));
    await tapKey(tester, const ValueKey('uploader-instagram-ai-yes'));
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 3);
    expect(find.textContaining('สร้างโดย AI: ใช่'), findsWidgets);
    await tapKey(tester, const ValueKey('publish-review-confirm'));
    expect(requests.single.platformSettings['INSTAGRAM_REELS'], {
      'shareToFeed': false,
      'isAiGenerated': true,
    });
    expect(
        store.savedRequests.last.platformSettings
            .toDraftJson()['instagramIsAiGenerated'],
        isTrue);
  });

  testWidgets('Facebook Cancel keeps mode unset and Save preserves explicit No',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(uploader());
    await selectPlatform(tester, 'FACEBOOK_REELS');
    await openSettings(tester, 'FACEBOOK_REELS');
    expect(find.text('เพจ Facebook ทดสอบ'), findsWidgets);
    await tapKey(tester, const ValueKey('uploader-facebook-page-draft'));
    await tapKey(tester, const ValueKey('uploader-facebook-ai-yes'));
    await tapKey(tester, _cancelKey);

    await openSettings(tester, 'FACEBOOK_REELS');
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await tapKey(tester, const ValueKey('uploader-facebook-page-draft'));
    await tapKey(tester, const ValueKey('uploader-facebook-ai-no'));
    await tapKey(tester, _saveKey);
    await goToUploaderStep(tester, 3);
    expect(find.textContaining('สร้างโดย AI: ไม่ใช่'), findsWidgets);
    expect(find.textContaining('ร่างบนเพจ'), findsWidgets);
    await tapKey(tester, const ValueKey('publish-review-confirm'));
    expect(requests.single.platformSettings['FACEBOOK_REELS'], {
      'publishMode': 'PAGE_DRAFT',
      'isAiGenerated': false,
    });
    expect(
        store.savedRequests.last.platformSettings
            .toDraftJson()['facebookIsAiGenerated'],
        isFalse);
  });

  testWidgets('saving historical Meta settings leaves optional AI unanswered',
      (tester) async {
    usePhoneSize(tester);
    final saved = await store.saveDraft(PublishDraftSaveRequest(
      id: 'historical-meta',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      videoFile: video,
      videoName: 'video.mp4',
      videoSizeBytes: 3,
      videoWidth: 720,
      videoHeight: 1280,
      caption: 'ร่างเดิม',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: {'INSTAGRAM_REELS', 'FACEBOOK_REELS'},
      platformSettings: const PlatformPublishSettings(
        instagramShareToFeed: false,
        facebookPublishMode: FacebookPublishMode.pageDraft,
      ),
    ));
    await tester.pumpWidget(uploader(initialDraftId: saved.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    for (final platform in ['INSTAGRAM_REELS', 'FACEBOOK_REELS']) {
      await openSettings(tester, platform);
      expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNotNull,
          reason: 'Optional AI answers must not invalidate historical drafts');
      await tapKey(tester, _saveKey);
    }
    await submit(tester);
    expect(requests.single.platformSettings, {
      'INSTAGRAM_REELS': {'shareToFeed': false},
      'FACEBOOK_REELS': {'publishMode': 'PAGE_DRAFT'},
    });
  });

  for (final platform in [
    'YOUTUBE_SHORTS',
    'INSTAGRAM_REELS',
    'FACEBOOK_REELS',
  ]) {
    testWidgets('$platform settings remain usable above a short phone keyboard',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(uploader());
      await selectPlatform(tester, platform);
      await openSettings(tester, platform);
      // Apply the smaller available area after opening, as a real keyboard
      // does, so the uploader's own progress controls are outside this check.
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpWidget(uploader(keyboard: 220, textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = find.byKey(_saveKey);
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(420));
      final lastControlKey = switch (platform) {
        'YOUTUBE_SHORTS' => 'uploader-youtube-guidelines-certified',
        'INSTAGRAM_REELS' => 'uploader-instagram-ai-no',
        _ => 'uploader-facebook-ai-no',
      };
      final lastControl = platform == 'YOUTUBE_SHORTS'
          ? find.descendant(
              of: find.byKey(ValueKey(lastControlKey)),
              matching: find.byType(Checkbox))
          : find.byKey(ValueKey(lastControlKey));
      await tester.ensureVisible(lastControl);
      await tester.pumpAndSettle();
      expect(lastControl.hitTestable(), findsOneWidget,
          reason: 'control ${tester.getRect(lastControl)}, '
              'scroll ${tester.getRect(find.byKey(const ValueKey('platform-settings-scroll')))}, '
              'save ${tester.getRect(save)}');
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getRect(lastControl).bottom,
          lessThanOrEqualTo(tester.getRect(save).top));
      expect(tester.takeException(), isNull);
      await tapKey(tester, _cancelKey);
    });
  }

  Future<void> openTikTok(
    WidgetTester tester, {
    required Future<TikTokPublishingOptionsResult> Function() loadOptions,
    PlatformPublishSettings initialSettings = const PlatformPublishSettings(),
    ValueChanged<TikTokSettingsSelection?>? onClosed,
    double keyboard = 0,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result =
                  await showModalBottomSheet<TikTokSettingsSelection>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => TikTokPublishingSettingsSheet(
                  initialSettings: initialSettings,
                  loadOptions: loadOptions,
                  isCurrent: () => true,
                ),
              );
              onClosed?.call(result);
            },
            child: const Text('เปิด TikTok'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('เปิด TikTok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('TikTok Inbox opens compactly without loading Direct options',
      (tester) async {
    var loads = 0;
    TikTokSettingsSelection? selection;
    await openTikTok(tester,
        loadOptions: () async {
          loads++;
          return _options();
        },
        onClosed: (value) => selection = value);
    expect(loads, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('uploader-tiktok-privacy')), findsNothing);
    final sheet = tester.getRect(
        find.byKey(const ValueKey('uploader-platform-settings-sheet')));
    expect(sheet.height, lessThan(tester.view.physicalSize.height * .7));
    expect(
        tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNotNull);
    await tapKey(tester, _saveKey);
    expect(selection!.settings.tiktokPublishMode, TikTokPublishMode.inboxDraft);
    expect(selection!.options, isNull);
  });

  testWidgets('TikTok loading and failures block Direct only', (tester) async {
    var loads = 0;
    final pending = Completer<TikTokPublishingOptionsResult>();
    await openTikTok(tester, loadOptions: () {
      loads++;
      return pending.future;
    });
    expect(loads, 0);
    await tester.tap(find.byKey(_directKey));
    await tester.pump();
    expect(loads, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    pending.completeError(const ApiException('Unavailable', statusCode: 503));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดตัวเลือก TikTok ล่าสุดไม่สำเร็จ'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    await tapKey(tester, _inboxKey);
    expect(find.textContaining('โหลดตัวเลือก TikTok ล่าสุดไม่สำเร็จ'),
        findsNothing);
    expect(find.byKey(const ValueKey('uploader-tiktok-options-retry')),
        findsNothing);
    expect(
        tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNotNull);
    await tapKey(tester, _saveKey);
  });

  testWidgets('returning to TikTok Inbox ignores an obsolete creator response',
      (tester) async {
    var loads = 0;
    final obsolete = Completer<TikTokPublishingOptionsResult>();
    await openTikTok(tester, loadOptions: () {
      loads++;
      return loads == 1 ? obsolete.future : Future.value(_options());
    });
    expect(loads, 0);
    await tester.tap(find.byKey(_directKey));
    await tester.pump();
    expect(loads, 1);
    await tester.tap(find.byKey(_inboxKey));
    await tester.pumpAndSettle();
    obsolete.complete(_options(nickname: 'บัญชีเก่าที่ไม่ควรแสดง'));
    await tester.pumpAndSettle();
    expect(find.text('บัญชีเก่าที่ไม่ควรแสดง'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNotNull);
    await tapKey(tester, _directKey);
    expect(loads, 2, reason: 'Re-entering Direct must fetch current options');
    expect(find.text('บัญชีล่าสุด'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('uploader-tiktok-privacy')), findsOneWidget);
    await tapKey(tester, _cancelKey);
  });

  testWidgets('Direct controls scroll above Save on a short keyboard phone',
      (tester) async {
    usePhoneSize(tester, size: const Size(360, 640));
    await openTikTok(
      tester,
      loadOptions: () async => _options(),
      initialSettings: const PlatformPublishSettings(
        tiktokPublishMode: TikTokPublishMode.directPost,
      ),
      keyboard: 220,
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    final save = find.byKey(_saveKey);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(420));
    final consent = find.descendant(
        of: find.byKey(const ValueKey('uploader-tiktok-music-consent')),
        matching: find.byType(Checkbox));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    expect(consent.hitTestable(), findsOneWidget);
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getRect(consent).bottom,
        lessThanOrEqualTo(tester.getRect(save).top));
    expect(tester.takeException(), isNull);
    await tapKey(tester, _cancelKey);
  });

  testWidgets('captures the five real platform sheets with bundled Thai fonts',
      (tester) async {
    usePhoneSize(tester, size: const Size(390, 844));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(uploader(boundaryKey: boundaryKey));

    Future<void> capture(String name) async {
      final context = tester.element(
          find.byKey(const ValueKey('uploader-platform-settings-sheet')));
      await tester.runAsync(() async {
        for (final name in [
          'tiktok',
          'youtube_shorts',
          'instagram_reels',
          'facebook_reels',
        ]) {
          await precacheImage(
              AssetImage('assets/images/platforms/$name.png'), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(previewDirectory!);
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    for (final platform in [
      'TIKTOK',
      'YOUTUBE_SHORTS',
      'INSTAGRAM_REELS',
      'FACEBOOK_REELS',
    ]) {
      await selectPlatform(tester, platform);
      await openSettings(tester, platform);
      if (platform == 'TIKTOK') {
        await capture('tiktok-inbox');
        await tapKey(tester, _directKey);
        await capture('tiktok-direct');
      } else {
        await capture(platform.toLowerCase());
      }
      await tapKey(tester, _cancelKey);
    }
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: previewDirectory == null || previewDirectory.isEmpty);
}
