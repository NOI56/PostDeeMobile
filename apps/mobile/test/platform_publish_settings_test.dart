import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

void main() {
  const revision =
      'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
  const creator = TikTokCreatorInfo(
    creatorAvatarUrl: 'https://example.test/avatar.png',
    creatorUsername: 'fixture_creator',
    creatorNickname: 'Fixture creator',
    privacyLevelOptions: TikTokPrivacyLevel.values,
    commentDisabled: false,
    duetDisabled: true,
    stitchDisabled: false,
    maxVideoPostDurationSec: 3600,
  );
  const direct = PlatformPublishSettings(
    tiktokPublishMode: TikTokPublishMode.directPost,
    tiktokPrivacyLevel: TikTokPrivacyLevel.selfOnly,
    tiktokCreatorInfoRevision: revision,
    tiktokMusicUsageConfirmed: true,
    tiktokVideoDurationSeconds: 5.5,
  );

  test(
      'Direct has no selected privacy or implicit consent/interaction defaults',
      () {
    const settings = PlatformPublishSettings();
    expect(settings.tiktokPrivacyLevel, isNull);
    expect(settings.tiktokCreatorInfoRevision, isNull);
    expect(settings.tiktokAllowComment, isFalse);
    expect(settings.tiktokAllowDuet, isFalse);
    expect(settings.tiktokAllowStitch, isFalse);
    expect(settings.tiktokBrandContentToggle, isFalse);
    expect(settings.tiktokBrandOrganicToggle, isFalse);
    expect(settings.tiktokIsAigc, isFalse);
    expect(settings.tiktokMusicUsageConfirmed, isFalse);
    expect(settings.tiktokBrandedContentPolicyConfirmed, isFalse);
    expect(settings.tiktokVideoDurationSeconds, isNull);
  });

  test('Direct serializes exact choices with inverse interaction flags', () {
    final settings = direct.copyWith(
      tiktokPrivacyLevel: TikTokPrivacyLevel.mutualFollowFriends,
      tiktokAllowComment: true,
      tiktokAllowStitch: true,
      tiktokBrandContentToggle: true,
      tiktokBrandOrganicToggle: true,
      tiktokIsAigc: true,
      tiktokBrandedContentPolicyConfirmed: true,
    );
    expect(settings.canSubmit(SocialPlatform.tiktok), isTrue);
    expect(settings.validateTikTokCreatorInfo(creator), isNull);
    expect(settings.toApiJson(selectedPlatforms: {SocialPlatform.tiktok}), {
      'TIKTOK': {
        'publishMode': 'DIRECT_POST',
        'privacyLevel': 'MUTUAL_FOLLOW_FRIENDS',
        'creatorInfoRevision': revision,
        'disableComment': false,
        'disableDuet': true,
        'disableStitch': false,
        'brandContentToggle': true,
        'brandOrganicToggle': true,
        'isAigc': true,
        'videoDurationSeconds': 5.5,
        'musicUsageConfirmed': true,
        'brandedContentPolicyConfirmed': true,
      },
    });
  });

  test(
      'Direct configuration can be ready before actual prepared duration exists',
      () {
    final settings = direct.copyWith(tiktokVideoDurationSeconds: null);
    expect(settings.canSubmit(SocialPlatform.tiktok), isTrue);
    expect(settings.validateTikTokCreatorInfo(creator, validateDuration: false),
        isNull);
    expect(settings.validateTikTokCreatorInfo(creator), isNotNull);
    expect(() => settings.toApiJson(selectedPlatforms: {SocialPlatform.tiktok}),
        throwsStateError);
  });

  test('Direct requires privacy, music and third-party policy consent', () {
    expect(
        direct
            .copyWith(tiktokPrivacyLevel: null)
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(tiktokCreatorInfoRevision: null)
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(tiktokCreatorInfoRevision: 'outdated')
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(tiktokMusicUsageConfirmed: false)
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(tiktokBrandContentToggle: true)
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(
                tiktokBrandContentToggle: true,
                tiktokBrandedContentPolicyConfirmed: true)
            .canSubmit(SocialPlatform.tiktok),
        isFalse);
    expect(
        direct
            .copyWith(
                tiktokPrivacyLevel: TikTokPrivacyLevel.publicToEveryone,
                tiktokBrandContentToggle: true,
                tiktokBrandedContentPolicyConfirmed: true)
            .canSubmit(SocialPlatform.tiktok),
        isTrue);
  });

  test('Direct validates current creator privacy and disabled interactions',
      () {
    expect(
        direct
            .copyWith(tiktokAllowDuet: true)
            .validateTikTokCreatorInfo(creator),
        isNotNull);
    const restricted = TikTokCreatorInfo(
      creatorAvatarUrl: '',
      creatorUsername: 'fixture',
      creatorNickname: 'Fixture',
      privacyLevelOptions: [TikTokPrivacyLevel.selfOnly],
      commentDisabled: true,
      duetDisabled: true,
      stitchDisabled: true,
      maxVideoPostDurationSec: 5,
    );
    for (final settings in [
      direct.copyWith(tiktokPrivacyLevel: TikTokPrivacyLevel.publicToEveryone),
      direct.copyWith(tiktokAllowComment: true),
      direct.copyWith(tiktokAllowStitch: true),
      direct,
    ]) {
      expect(settings.validateTikTokCreatorInfo(restricted), isNotNull);
    }
    expect(
        direct
            .copyWith(tiktokVideoDurationSeconds: 5)
            .validateTikTokCreatorInfo(restricted),
        isNull);
  });

  test('Direct caps creator duration at 600 seconds and rejects unusable proof',
      () {
    expect(
        direct
            .copyWith(tiktokVideoDurationSeconds: 600)
            .validateTikTokCreatorInfo(creator),
        isNull);
    for (final duration in [0.0, -1.0, 600.001, double.nan, double.infinity]) {
      final settings = direct.copyWith(tiktokVideoDurationSeconds: duration);
      expect(settings.validateTikTokCreatorInfo(creator), isNotNull);
      expect(
          () => settings.toApiJson(selectedPlatforms: {SocialPlatform.tiktok}),
          throwsStateError);
    }
  });

  test('Direct draft choices round-trip without changing old strict v3 fields',
      () {
    final settings = direct.copyWith(
        tiktokPrivacyLevel: TikTokPrivacyLevel.followerOfCreator,
        tiktokAllowComment: true);
    expect(
        PlatformPublishSettings.fromDraftJson(settings.toDraftJson(),
            strict: true),
        settings);
    final legacy = const PlatformPublishSettings().toDraftJson()
      ..removeWhere(
          (key, _) => key.startsWith('tiktok') && key != 'tiktokPublishMode');
    expect(PlatformPublishSettings.fromDraftJson(legacy, strict: true),
        const PlatformPublishSettings());
    expect(
        settings
            .copyWith(
                tiktokPrivacyLevel: null, tiktokVideoDurationSeconds: null)
            .tiktokPrivacyLevel,
        isNull);
    expect(
        settings
            .copyWith(tiktokVideoDurationSeconds: null)
            .tiktokVideoDurationSeconds,
        isNull);
    expect(
        settings, isNot(settings.copyWith(tiktokMusicUsageConfirmed: false)));
    expect({settings, settings.copyWith(tiktokMusicUsageConfirmed: false)},
        hasLength(2));
  });

  test('malformed optional Direct draft fields fail closed', () {
    for (final field in <Map<String, Object?>>[
      {'tiktokPrivacyLevel': 'everyone'},
      {'tiktokAllowComment': 'true'},
      {'tiktokMusicUsageConfirmed': 1},
      {'tiktokVideoDurationSeconds': -1},
      {'tiktokCreatorInfoRevision': 'invalid'},
      {'tiktokVideoDurationSeconds': '5'},
      {'tiktokBrandContentToggle': null},
    ]) {
      expect(
          () => PlatformPublishSettings.fromDraftJson(
              {...direct.toDraftJson(), ...field}),
          throwsFormatException);
    }
  });

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
