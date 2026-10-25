import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/post_video_preview_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_review_screen.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Replaces the native interface already used by video_player.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

const _sharedCaption = 'แคปชันหลักของคลิปสินค้า';
const _platformCaptions = {
  SocialPlatform.tiktok: 'ข้อความเฉพาะ TikTok',
  SocialPlatform.youtubeShorts: 'คำอธิบายเฉพาะ YouTube',
  SocialPlatform.instagramReels: 'ข้อความ Instagram ที่ไม่ได้เลือกส่ง',
  SocialPlatform.facebookReels: 'ข้อความ Facebook ที่ไม่ได้เลือกส่ง',
};

class _PreviewVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final played = <int>[];

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
        size: const Size(1080, 1920),
      ));
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
  Future<void> play(int playerId) async => played.add(playerId);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(
        color: Colors.blue,
      );
}

class _Fixture {
  _Fixture() {
    final directory = Directory.systemTemp.createTempSync('postdee-preview-');
    addTearDown(() => directory.deleteSync(recursive: true));
    video = File('${directory.path}${Platform.pathSeparator}seller.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
  }

  late final File video;
  final drafts = TestPublishDraftStore(ownerUserId: 'preview-owner');
  var uploads = 0;
  var fileUploads = 0;
  var readiness = 0;
  var posts = 0;
  var aiRequests = 0;
  var mediaProcessing = 0;

  Future<PublishDraft> seed({
    Set<String> platforms = const {'TIKTOK', 'YOUTUBE_SHORTS'},
    PlatformPublishSettings settings = const PlatformPublishSettings(
      usePlatformCaptions: true,
      platformCaptions: _platformCaptions,
      aiCaptionPlatforms: {
        SocialPlatform.instagramReels,
        SocialPlatform.facebookReels,
      },
      youtubeTitle: 'ชื่อ YouTube ที่ตั้งไว้เอง',
      youtubeMadeForKids: false,
      youtubeContainsSyntheticMedia: false,
      youtubeCommunityGuidelinesCertified: true,
    ),
  }) async {
    final cover = File('assets/images/brand/postdee_mark.png').absolute;
    final draft = await drafts.saveDraft(PublishDraftSaveRequest(
      id: 'preview-draft',
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 20),
      videoFile: video,
      videoName: 'seller.mp4',
      videoSizeBytes: video.lengthSync(),
      videoWidth: 1080,
      videoHeight: 1920,
      caption: _sharedCaption,
      aiGuidance: 'คำแนะนำที่ยังไม่เรียก AI',
      watermarkEnabled: true,
      platformApiValues: platforms,
      platformSettings: settings,
      scheduledAt: DateTime(2026, 10, 22, 14, 35).toUtc(),
      coverImageFile: cover,
      coverDesign: const CoverDesign(coverFrameTimeMs: 4200, text: 'ปกสินค้า'),
    ));
    // Seeding is setup; opening/closing a preview must add no draft writes.
    drafts.savedRequests.clear();
    return draft;
  }

  Widget app({String? draftId}) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UploaderScreen(
            fullScreen: true,
            draftStore: drafts,
            initialDraftId: draftId,
            enableRevenueCatBilling: false,
            now: () => DateTime(2026, 10, 20, 9),
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'preview-owner',
              plan: 'PRO',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            loadSocialConnections: () async => const [
              SocialConnectionResult(
                platform: 'TIKTOK',
                connected: true,
                externalAccountId: 'tiktok-preview-owner',
                displayName: 'ร้าน TikTok ของฉัน',
              ),
              SocialConnectionResult(
                platform: 'YOUTUBE_SHORTS',
                connected: true,
                externalAccountId: 'youtube-preview-owner',
                displayName: 'ช่อง YouTube ของฉัน',
              ),
              SocialConnectionResult(
                platform: 'INSTAGRAM_REELS',
                connected: true,
                externalAccountId: 'instagram-preview-owner',
                displayName: 'ร้าน Instagram ของฉัน',
              ),
              SocialConnectionResult(
                platform: 'FACEBOOK_REELS',
                connected: true,
                externalAccountId: 'facebook-preview-owner',
                displayName: 'เพจ Facebook ของฉัน',
              ),
            ],
            loadSocialPublishingReadiness: connectedPublishingReadinessForTests,
            probePublishMedia: probeValidPublishMedia,
            pickVideo: () async => PickedVideoFile(
              path: video.path,
              name: 'seller.mp4',
              sizeBytes: video.lengthSync(),
              width: 1080,
              height: 1920,
            ),
            createUpload: (_) async {
              uploads++;
              throw StateError('A preview must not create an upload');
            },
            uploadVideoFile: (_, __) async {
              fileUploads++;
              throw StateError('A preview must not upload a file');
            },
            generateCaption: (_) async {
              aiRequests++;
              throw StateError('A preview must not generate a caption');
            },
            generateRealClipCaption: (_) async {
              aiRequests++;
              throw StateError('A preview must not spend AI credits');
            },
            checkPublishingReadiness: () async {
              readiness++;
              throw StateError('A preview must not prepare publishing');
            },
            createPost: (_) async {
              posts++;
              throw StateError('A preview must not publish');
            },
            prepareTikTokVideo: (_) async {
              mediaProcessing++;
              throw StateError('A preview must not prepare a new video');
            },
            watermarkVideo: (_) async {
              mediaProcessing++;
              throw StateError('A preview must not transcode a watermark');
            },
            extractFrames: (_, {int maxFrames = 6}) async {
              mediaProcessing++;
              throw StateError('A preview must not extract AI frames');
            },
          ),
        ),
      );

  void expectNoSideEffects() {
    expect(uploads, 0);
    expect(fileUploads, 0);
    expect(readiness, 0);
    expect(posts, 0);
    expect(aiRequests, 0);
    expect(mediaProcessing, 0);
    expect(drafts.savedRequests, isEmpty);
  }
}

Future<void> _mount(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: uploaderMainScroll);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<PostVideoPreviewScreen> _openPreview(WidgetTester tester) async {
  await goToUploaderStep(tester, 3);
  await _tap(tester, _key('publish-review-preview'));
  expect(find.byType(PostVideoPreviewScreen), findsOneWidget);
  return tester
      .widget<PostVideoPreviewScreen>(find.byType(PostVideoPreviewScreen));
}

Future<void> _closePreview(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  expect(find.byType(PostVideoPreviewScreen), findsNothing);
  expect(find.byType(PublishReviewSummary), findsOneWidget);
  expect(_key('publish-review-confirm'), findsOneWidget);
}

void main() {
  late _PreviewVideoPlatform player;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previousSession = sessions.session;
    addTearDown(() => previousSession.isSignedIn
        ? sessions.signIn(previousSession)
        : sessions.clear());
    sessions.signIn(const AuthSession(
        userId: 'preview-owner', idToken: 'test-preview-token'));
    final previousPlatform = VideoPlayerPlatform.instance;
    player = _PreviewVideoPlatform();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
  });

  testWidgets(
      'review without a clip disables preview and keeps channel editing',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture.app());
    await goToUploaderStep(tester, 3);
    final summary =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(summary.onPreview, isNull);
    expect(_key('publish-review-preview'), findsOneWidget);
    expect(_key('publish-review-edit-video'), findsNothing);
    expect(_key('publish-review-edit-caption'), findsNothing);
    expect(_key('publish-review-edit-platforms'), findsOneWidget);
    await _tap(tester, _key('publish-review-preview'));
    expect(find.byType(PostVideoPreviewScreen), findsNothing);
    expect(player.sources, isEmpty);
    fixture.expectNoSideEffects();
  });

  testWidgets('picked clip previews only selected channels without submitting',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture.app());
    await _tap(tester, _key('uploader-video-preview-picker'));
    await goToUploaderStep(tester, 1);
    await _tap(tester, _key('uploader-caption-field'));
    await tester.enterText(_key('uploader-caption-field'), _sharedCaption);
    await goToUploaderStep(tester, 2);
    // Select in reverse order: preview order follows platform order, not taps.
    await _tap(tester, _key('uploader-platform-FACEBOOK_REELS'));
    await _tap(tester, _key('uploader-platform-TIKTOK'));
    final screen = await _openPreview(tester);
    final data = screen.postPreview!;
    expect(screen.videoFile!.path, fixture.video.path);
    expect(screen.videoUrl, isNull);
    expect(data.caption, _sharedCaption);
    expect(data.channels.map((channel) => channel.platform),
        [SocialPlatform.tiktok, SocialPlatform.facebookReels]);
    expect(data.channels.map((channel) => channel.caption),
        [_sharedCaption, _sharedCaption]);
    expect(data.channels.map((channel) => channel.displayName),
        ['ร้าน TikTok ของฉัน', 'เพจ Facebook ของฉัน']);
    expect(_key('preview-platform-TIKTOK'), findsOneWidget);
    expect(_key('preview-platform-FACEBOOK_REELS'), findsOneWidget);
    expect(_key('preview-platform-YOUTUBE_SHORTS'), findsNothing);
    expect(_key('preview-platform-INSTAGRAM_REELS'), findsNothing);
    expect(find.text('ร้าน TikTok ของฉัน'), findsOneWidget);
    expect(find.text(_sharedCaption), findsOneWidget);
    expect(player.sources.single.sourceType, DataSourceType.file);
    expect(player.played, isEmpty);
    fixture.expectNoSideEffects();

    await _closePreview(tester);
    final summary =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(summary.videoName, 'seller.mp4');
    expect(summary.caption, _sharedCaption);
    expect(summary.platforms,
        [SocialPlatform.tiktok, SocialPlatform.facebookReels]);
    final reopened = await _openPreview(tester);
    expect(reopened.videoFile!.path, fixture.video.path);
    expect(reopened.postPreview!.channels.map((channel) => channel.caption),
        [_sharedCaption, _sharedCaption]);
    await _closePreview(tester);
    await _tap(tester, _key('publish-review-edit-platforms'));
    expect(_key('uploader-step-platforms'), findsOneWidget);
    await goToUploaderStep(tester, 1);
    expect(
        tester
            .widget<TextField>(_key('uploader-caption-field'))
            .controller!
            .text,
        _sharedCaption);
    fixture.expectNoSideEffects();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'advanced preview retains per-channel captions title cover and time',
      (tester) async {
    final fixture = _Fixture();
    final draft = await fixture.seed();
    await _mount(tester, fixture.app(draftId: draft.id));
    final screen = await _openPreview(tester);
    final data = screen.postPreview!;
    expect(data.channels.map((channel) => channel.platform),
        [SocialPlatform.tiktok, SocialPlatform.youtubeShorts]);
    expect(data.channels.map((channel) => channel.caption), [
      _platformCaptions[SocialPlatform.tiktok],
      _platformCaptions[SocialPlatform.youtubeShorts],
    ]);
    expect(data.channels.last.title, 'ชื่อ YouTube ที่ตั้งไว้เอง');
    expect(data.channels.last.displayName, 'ช่อง YouTube ของฉัน');
    expect(data.coverImagePath, draft.cover!.imagePath);
    expect(data.watermarkEnabled, isFalse,
        reason:
            'A shared clip sent to TikTok does not use the PostDee watermark');
    expect(_key('preview-platform-INSTAGRAM_REELS'), findsNothing);
    expect(_key('preview-platform-FACEBOOK_REELS'), findsNothing);
    await tester.tap(_key('preview-platform-YOUTUBE_SHORTS'));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อ YouTube ที่ตั้งไว้เอง'), findsOneWidget);
    expect(find.text(_platformCaptions[SocialPlatform.youtubeShorts]!),
        findsOneWidget);
    expect(find.text(_sharedCaption), findsNothing);
    expect(player.sources, hasLength(1));
    fixture.expectNoSideEffects();

    await _closePreview(tester);
    final summary =
        tester.widget<PublishReviewSummary>(find.byType(PublishReviewSummary));
    expect(summary.caption, draft.caption);
    expect(summary.scheduledAt, draft.scheduledAt);
    expect(summary.coverResult!.localImagePath, draft.cover!.imagePath);
    expect(summary.coverResult!.coverFrameTimeMs, 4200);
    expect(summary.platformSettings.platformCaptions, _platformCaptions);
    expect(summary.platformSettings.youtubeTitle, 'ชื่อ YouTube ที่ตั้งไว้เอง');
    await goToUploaderStep(tester, 1);
    expect(_key('uploader-caption-field'), findsNothing);
    final youtube = _key('uploader-caption-YOUTUBE_SHORTS');
    await tester.scrollUntilVisible(youtube, 200,
        scrollable: uploaderMainScroll);
    expect(tester.widget<TextField>(youtube).controller!.text,
        _platformCaptions[SocialPlatform.youtubeShorts]);
    fixture.expectNoSideEffects();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an explicit empty YouTube description stays separate from its title',
      (tester) async {
    final fixture = _Fixture();
    final draft = await fixture.seed(
      platforms: const {'YOUTUBE_SHORTS'},
      settings: const PlatformPublishSettings(
        usePlatformCaptions: true,
        platformCaptions: {SocialPlatform.youtubeShorts: ''},
        youtubeTitle: 'ชื่อที่มีคำอธิบายว่างได้',
      ),
    );
    await _mount(tester, fixture.app(draftId: draft.id));
    final screen = await _openPreview(tester);
    final channel = screen.postPreview!.channels.single;
    expect(channel.platform, SocialPlatform.youtubeShorts);
    expect(channel.caption, isEmpty);
    expect(channel.title, 'ชื่อที่มีคำอธิบายว่างได้');
    expect(find.text(_sharedCaption), findsNothing);
    expect(find.text('ชื่อที่มีคำอธิบายว่างได้'), findsOneWidget);
    fixture.expectNoSideEffects();
    await _closePreview(tester);
    fixture.expectNoSideEffects();
    expect(tester.takeException(), isNull);
  });
}
