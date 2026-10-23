import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';
import 'package:postdee_mobile/features/uploader/uploader_screen.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/publish_preflight_fixtures.dart';
import 'support/test_publish_draft_store.dart';
import 'support/uploader_wizard_test_navigation.dart';

const _captions = {
  SocialPlatform.tiktok: 'ข้อความ TikTok ของฉัน',
  SocialPlatform.youtubeShorts: 'ข้อความ Shorts ของฉัน',
  SocialPlatform.instagramReels: 'ข้อความ Instagram ของฉัน',
  SocialPlatform.facebookReels: 'ข้อความ Facebook ของฉัน',
};
const _revision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// The file manifest sorts selected API values. Keep the same ordering boundary
/// here while letting widget tests run without native asynchronous file I/O.
class _SortedDraftStore extends TestPublishDraftStore {
  _SortedDraftStore() : super(ownerUserId: 'owner-a');

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) {
    final platforms = request.platformApiValues.toList()..sort();
    return super.saveDraft(PublishDraftSaveRequest(
      id: request.id,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      videoFile: request.videoFile,
      videoName: request.videoName,
      videoSizeBytes: request.videoSizeBytes,
      videoWidth: request.videoWidth,
      videoHeight: request.videoHeight,
      caption: request.caption,
      captionNeedsReview: request.captionNeedsReview,
      aiGuidance: request.aiGuidance,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: platforms.toSet(),
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
      coverImageFile: request.coverImageFile,
      coverDesign: request.coverDesign,
      coverDurationMs: request.coverDurationMs,
      coverSourceKind: request.coverSourceKind,
      coverSourceImageFile: request.coverSourceImageFile,
      coverSourceImageName: request.coverSourceImageName,
      uploadedMedia: request.uploadedMedia,
    ));
  }
}

class _Fixture {
  _Fixture() {
    directory = Directory.systemTemp.createTempSync('platform-caption-submit-');
    video = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync(List.filled(512, 1));
    replacement = File('${directory.path}/replacement.mp4')
      ..writeAsBytesSync(List.filled(512, 2));
    store = _SortedDraftStore();
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  }

  late final Directory directory;
  late final File video;
  late final File replacement;
  late final _SortedDraftStore store;
  final posts = <CreatePostRequest>[];
  final recovered = <CreatePostRequest>[];

  Future<PublishDraft> seed({
    Set<String> platforms = const {'TIKTOK', 'FACEBOOK_REELS'},
    PlatformPublishSettings settings = const PlatformPublishSettings(
      usePlatformCaptions: true,
      platformCaptions: _captions,
      facebookPublishMode: FacebookPublishMode.publish,
    ),
  }) =>
      store.saveDraft(PublishDraftSaveRequest(
        id: 'advanced-draft',
        createdAt: DateTime.utc(2026, 10, 23),
        updatedAt: DateTime.utc(2026, 10, 23),
        videoFile: video,
        videoName: 'clip.mp4',
        videoSizeBytes: 512,
        videoWidth: 1080,
        videoHeight: 1920,
        caption: 'แคปชั่นหลักที่ซ่อนไว้',
        aiGuidance: '',
        watermarkEnabled: false,
        platformApiValues: platforms,
        platformSettings: settings,
      ));

  Widget app(String draftId) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UploaderScreen(
            draftStore: store,
            initialDraftId: draftId,
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'owner-a',
              plan: 'PRO',
              status: 'ACTIVE',
              phoneVerified: true,
              requiresPhoneVerification: false,
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true,
            ),
            loadSocialConnections: () async => const [
              SocialConnectionResult(
                platform: 'TIKTOK',
                connected: true,
                connectionId: 'local-tiktok',
                connectionRevision: _revision,
                externalAccountId: 'tiktok-owner-a',
                displayName: 'ร้าน TikTok',
              ),
              SocialConnectionResult(
                platform: 'FACEBOOK_REELS',
                connected: true,
                externalAccountId: 'facebook-owner-a',
                displayName: 'เพจร้าน',
              ),
              SocialConnectionResult(
                platform: 'YOUTUBE_SHORTS',
                connected: true,
                externalAccountId: 'youtube-owner-a',
                displayName: 'ช่อง YouTube',
              ),
            ],
            loadSocialPublishingReadiness: () async => const [
              SocialPublishingConnectionReadiness(
                platform: 'TIKTOK',
                state: SocialPublishingState.connected,
                connectionId: 'local-tiktok',
                connectionRevision: _revision,
              ),
              SocialPublishingConnectionReadiness(
                platform: 'FACEBOOK_REELS',
                state: SocialPublishingState.connected,
              ),
              SocialPublishingConnectionReadiness(
                platform: 'YOUTUBE_SHORTS',
                state: SocialPublishingState.connected,
              ),
            ],
            loadTikTokPublishingOptions: () async =>
                const TikTokPublishingOptionsResult(
              connectionId: 'local-tiktok',
              creatorInfoRevision: _revision,
              creatorInfo: TikTokCreatorInfo(
                creatorAvatarUrl: '',
                creatorUsername: 'seller',
                creatorNickname: 'ร้าน TikTok',
                privacyLevelOptions: [TikTokPrivacyLevel.selfOnly],
                commentDisabled: false,
                duetDisabled: false,
                stitchDisabled: false,
                maxVideoPostDurationSec: 600,
              ),
            ),
            probePublishMedia: probeValidPublishMedia,
            prepareTikTokVideo: (request) async => TikTokPreparedVideoResult(
              file: request.inputFile,
              fileName: request.fileName,
              sizeBytes: request.inputFile.lengthSync(),
              width: 1080,
              height: 1920,
              durationSeconds: 10,
            ),
            checkPublishingReadiness: () async {},
            pickVideo: () async => PickedVideoFile(
              path: replacement.path,
              name: 'replacement.mp4',
              sizeBytes: 512,
              width: 1080,
              height: 1920,
            ),
            createUpload: (_) async => const UploadResult(
                id: 'upload',
                videoS3Key: 'uploads/owner-a/clip.mp4',
                storageProvider: 'mock'),
            uploadVideoFile: (_, __) async {},
            createPost: (request) async {
              posts.add(request);
              throw const SocketException('response lost after commit');
            },
            recoverPostSubmission: (request) async {
              recovered.add(request);
              return QueuedPostResult(
                  id: 'accepted-post',
                  videoS3Key: request.videoS3Key,
                  platforms: request.platforms,
                  status: 'QUEUED',
                  idempotentReplay: true);
            },
          ),
        ),
      );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250, scrollable: uploaderMainScroll);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
  });

  testWidgets(
      'advanced create and restored recovery retain the same exact payload',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    final draft = await fixture.seed();
    expect(draft.platformApiValues.toList(), ['FACEBOOK_REELS', 'TIKTOK']);
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);

    // Re-select Facebook last so the composer's selection order is TikTok,
    // Facebook while the real file store serializes Facebook before TikTok.
    final facebook =
        find.byKey(const ValueKey('uploader-platform-FACEBOOK_REELS'));
    await _tap(tester, facebook);
    await _tap(tester, facebook);
    await goToUploaderStep(tester, 3);
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(fixture.posts, hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>()
            .join(' | '));
    expect((await fixture.store.loadDraft(draft.id))!.uploadedMedia, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await _tap(
        tester, find.byKey(const ValueKey('uploader-recover-submission')));
    expect(fixture.recovered, hasLength(1));
    final submitted = fixture.posts.single;
    final recovered = fixture.recovered.single;
    expect(submitted.caption, _captions[SocialPlatform.tiktok]);
    expect(recovered.caption, submitted.caption);
    expect(recovered.clientRequestId, submitted.clientRequestId);
    expect(recovered.videoS3Key, submitted.videoS3Key);
    expect(
        recovered.mediaContentFingerprint, submitted.mediaContentFingerprint);
    expect(recovered.platforms.toSet(), submitted.platforms.toSet());
    expect(recovered.platformSettings, submitted.platformSettings);
    expect((recovered.platformSettings['TIKTOK'] as Map)['caption'],
        _captions[SocialPlatform.tiktok]);
    expect((recovered.platformSettings['FACEBOOK_REELS'] as Map)['caption'],
        _captions[SocialPlatform.facebookReels]);
    expect(fixture.posts, hasLength(1));
  });

  testWidgets('replacement clip retains four restored captions for review',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    final draft = await fixture.seed();
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 0);
    await _tap(
        tester, find.byKey(const ValueKey('uploader-video-preview-picker')));
    await goToUploaderStep(tester, 1);
    expect(find.byKey(const ValueKey('uploader-caption-field')), findsNothing);
    for (final entry in _captions.entries) {
      final field =
          find.byKey(ValueKey('uploader-caption-${entry.key.apiValue}'));
      await tester.scrollUntilVisible(field, 250,
          scrollable: uploaderMainScroll);
      expect(tester.widget<TextField>(field).controller!.text, entry.value);
    }
    expect(find.byKey(const ValueKey('uploader-caption-review-notice')),
        findsOneWidget);
    final save = find.byKey(const ValueKey('uploader-save-draft-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = (await fixture.store.loadDraft(draft.id))!;
    expect(saved.platformSettings.usePlatformCaptions, isTrue);
    expect(saved.platformSettings.platformCaptions, _captions);
    expect(saved.captionNeedsReview, isTrue);
    expect(saved.caption, 'แคปชั่นหลักที่ซ่อนไว้');
    expect(saved.videoName, 'replacement.mp4');
    expect(fixture.posts, isEmpty);
  });

  testWidgets('advanced YouTube title-only keeps the hidden shared caption out',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    final draft = await fixture.seed(
      platforms: const {'YOUTUBE_SHORTS'},
      settings: const PlatformPublishSettings(
        usePlatformCaptions: true,
        platformCaptions: {SocialPlatform.youtubeShorts: ''},
        youtubeTitle: 'ชื่อวิดีโอที่ตั้งเอง',
        youtubeMadeForKids: false,
        youtubeContainsSyntheticMedia: false,
      ),
    );
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await _tap(
        tester,
        find.byKey(
            const ValueKey('uploader-platform-settings-YOUTUBE_SHORTS')));
    final guidelines =
        find.byKey(const ValueKey('uploader-youtube-guidelines-certified'));
    await tester.ensureVisible(guidelines);
    await tester.tap(guidelines);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('uploader-platform-settings-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 3);
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(fixture.posts, hasLength(1));
    final submitted = fixture.posts.single;
    expect(submitted.caption, isEmpty,
        reason: 'An intentionally empty description must not expose old text');
    expect(
        (submitted.platformSettings['YOUTUBE_SHORTS'] as Map)['caption'], '');
    expect((submitted.platformSettings['YOUTUBE_SHORTS'] as Map)['title'],
        'ชื่อวิดีโอที่ตั้งเอง');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await _tap(
        tester, find.byKey(const ValueKey('uploader-recover-submission')));
    expect(fixture.recovered.single.caption, isEmpty);
    expect(
        fixture.recovered.single.platformSettings, submitted.platformSettings);
  });

  testWidgets('editing Facebook preserves TikTok consent until TikTok changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    final draft = await fixture.seed();
    await tester.pumpWidget(fixture.app(draft.id));
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 2);
    await _tap(tester,
        find.byKey(const ValueKey('uploader-platform-settings-TIKTOK')));
    final direct = find.byKey(const ValueKey('uploader-tiktok-mode-direct'));
    await tester.ensureVisible(direct);
    await tester.tap(direct);
    await tester.pumpAndSettle();
    final privacy = find.byKey(const ValueKey('uploader-tiktok-privacy'));
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เฉพาะฉัน').last);
    await tester.pumpAndSettle();
    final music = find.byKey(const ValueKey('uploader-tiktok-music-consent'));
    await tester.ensureVisible(music);
    await tester.tap(music);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('uploader-platform-settings-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await goToUploaderStep(tester, 1);
    final facebook =
        find.byKey(const ValueKey('uploader-caption-FACEBOOK_REELS'));
    await tester.scrollUntilVisible(facebook, 250,
        scrollable: uploaderMainScroll);
    await tester.enterText(facebook, 'แก้ข้อความเฉพาะ Facebook');
    await goToUploaderStep(tester, 3);
    final confirm = find.byKey(const ValueKey('publish-review-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull,
        reason: 'Facebook text does not change TikTok publishing intent');
    await goToUploaderStep(tester, 1);
    final tiktok = find.byKey(const ValueKey('uploader-caption-TIKTOK'));
    await tester.scrollUntilVisible(tiktok, -250,
        scrollable: uploaderMainScroll);
    await tester.enterText(tiktok, 'แก้ข้อความ TikTok ต้องยืนยันใหม่');
    await goToUploaderStep(tester, 3);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull,
        reason: 'Changing TikTok text requires fresh TikTok consent');
    expect(fixture.posts, isEmpty);
  });
}
