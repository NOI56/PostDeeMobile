import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

void main() {
  test('builds safe defaults only for selected platforms', () {
    const settings = PlatformPublishSettings(
      youtubeTitle: 'คลิปสินค้าใหม่',
      youtubeMadeForKids: false,
      youtubeContainsSyntheticMedia: true,
      youtubeCommunityGuidelinesCertified: true,
      facebookPublishMode: FacebookPublishMode.pageDraft,
    );

    expect(
      settings.toApiJson(
        selectedPlatforms: const {
          SocialPlatform.tiktok,
          SocialPlatform.youtubeShorts,
          SocialPlatform.instagramReels,
          SocialPlatform.facebookReels,
        },
      ),
      {
        'TIKTOK': {'publishMode': 'INBOX_DRAFT'},
        'YOUTUBE_SHORTS': {
          'title': 'คลิปสินค้าใหม่',
          'visibility': 'private',
          'madeForKids': false,
          'containsSyntheticMedia': true,
          'communityGuidelinesCertified': true,
        },
        'INSTAGRAM_REELS': {'shareToFeed': true},
        'FACEBOOK_REELS': {'publishMode': 'PAGE_DRAFT'},
      },
    );

    expect(
      settings.toApiJson(
        selectedPlatforms: const {SocialPlatform.youtubeShorts},
      ),
      {
        'YOUTUBE_SHORTS': {
          'title': 'คลิปสินค้าใหม่',
          'visibility': 'private',
          'madeForKids': false,
          'containsSyntheticMedia': true,
          'communityGuidelinesCertified': true,
        },
      },
    );
  });

  test('round-trips user choices through local draft json', () {
    const settings = PlatformPublishSettings(
      youtubeTitle: 'Summer collection',
      youtubeVisibility: YouTubeVisibility.unlisted,
      youtubeMadeForKids: true,
      youtubeContainsSyntheticMedia: false,
      youtubeCommunityGuidelinesCertified: true,
      instagramShareToFeed: false,
      facebookPublishMode: FacebookPublishMode.publish,
    );

    expect(
      PlatformPublishSettings.fromDraftJson(settings.toDraftJson()),
      settings,
    );
  });

  test('legacy drafts without platform settings receive safe defaults', () {
    final settings = PlatformPublishSettings.fromDraftJson(null);

    expect(settings, const PlatformPublishSettings());
    expect(settings.canSubmit(SocialPlatform.facebookReels), isFalse);
  });

  test('YouTube requires explicit safe publishing answers', () {
    const incomplete = PlatformPublishSettings();
    const complete = PlatformPublishSettings(
      youtubeTitle: 'รีวิวสินค้า',
      youtubeMadeForKids: false,
      youtubeContainsSyntheticMedia: false,
      youtubeCommunityGuidelinesCertified: true,
    );

    expect(incomplete.canSubmit(SocialPlatform.youtubeShorts), isFalse);
    expect(complete.canSubmit(SocialPlatform.youtubeShorts), isTrue);
    expect(
      const PlatformPublishSettings(
        youtubeTitle: 'bad <title>',
        youtubeMadeForKids: false,
        youtubeContainsSyntheticMedia: false,
        youtubeCommunityGuidelinesCertified: true,
      ).canSubmit(SocialPlatform.youtubeShorts),
      isFalse,
    );
  });

  test('direct TikTok posting remains fail-closed without creator info', () {
    const settings = PlatformPublishSettings(
      tiktokPublishMode: TikTokPublishMode.directPost,
    );

    expect(settings.canSubmit(SocialPlatform.tiktok), isFalse);
    expect(
      () => settings.toApiJson(
        selectedPlatforms: const {SocialPlatform.tiktok},
      ),
      throwsStateError,
    );
  });

  test('copyWith can explicitly clear nullable answers', () {
    const settings = PlatformPublishSettings(
      youtubeMadeForKids: true,
      youtubeContainsSyntheticMedia: false,
      facebookPublishMode: FacebookPublishMode.publish,
    );
    final cleared = settings.copyWith(
      youtubeMadeForKids: null,
      youtubeContainsSyntheticMedia: null,
      facebookPublishMode: null,
    );

    expect(cleared.youtubeMadeForKids, isNull);
    expect(cleared.youtubeContainsSyntheticMedia, isNull);
    expect(cleared.facebookPublishMode, isNull);
  });

  test('PostDee watermark is disabled whenever TikTok is selected', () {
    expect(
      shouldApplyPostDeeWatermark(
        requested: true,
        selectedPlatforms: const {SocialPlatform.tiktok},
      ),
      isFalse,
    );
    expect(
      shouldApplyPostDeeWatermark(
        requested: true,
        selectedPlatforms: const {SocialPlatform.youtubeShorts},
      ),
      isTrue,
    );
  });
}
