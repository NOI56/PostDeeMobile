import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

void main() {
  group('safe YouTube title suggestion', () {
    test('uses the first usable caption line without forbidden characters', () {
      expect(
          safeYouTubeTitleSuggestion(
              '\n <> \n  รีวิว\t <สินค้า>   ใหม่  \n#รีวิว'),
          'รีวิว สินค้า ใหม่');
    });

    test('returns no invented title for an empty caption', () {
      expect(safeYouTubeTitleSuggestion(' \n\t<>\r\n '), isEmpty);
    });

    test('limits titles to 100 Unicode code points without splitting emoji',
        () {
      final title = safeYouTubeTitleSuggestion('${'😀' * 99}กขค');
      expect(title, '${'😀' * 99}ก');
      expect(title.runes.length, 100);
    });

    test('keeps a complete title at the exact Unicode boundary', () {
      final title = '🎬${'ก' * 99}';
      expect(safeYouTubeTitleSuggestion(title), title);
    });
  });

  group('read-only submission recovery settings', () {
    test('preserves every completed current publishing choice', () {
      const settings = PlatformPublishSettings(
        youtubeTitle: 'ชื่อที่ยืนยันไว้',
        youtubeVisibility: YouTubeVisibility.unlisted,
        youtubeMadeForKids: true,
        youtubeContainsSyntheticMedia: false,
        youtubeCommunityGuidelinesCertified: true,
        instagramShareToFeed: false,
        facebookPublishMode: FacebookPublishMode.pageDraft,
      );
      const platforms = {
        SocialPlatform.tiktok,
        SocialPlatform.youtubeShorts,
        SocialPlatform.instagramReels,
        SocialPlatform.facebookReels,
      };
      expect(settings.toRecoveryApiJson(selectedPlatforms: platforms),
          settings.toApiJson(selectedPlatforms: platforms));
    });

    test('old YouTube answers serialize only the persisted visibility', () {
      for (final settings in [
        const PlatformPublishSettings(),
        const PlatformPublishSettings(youtubeTitle: 'ชื่อเดิม'),
        const PlatformPublishSettings(
          youtubeMadeForKids: false,
          youtubeContainsSyntheticMedia: false,
        ),
      ]) {
        expect(
            settings.toRecoveryApiJson(
                selectedPlatforms: {SocialPlatform.youtubeShorts}),
            {
              'YOUTUBE_SHORTS': {'visibility': 'private'},
            });
        expect(settings.youtubeCommunityGuidelinesCertified, isFalse);
        expect(
            () => settings
                .toApiJson(selectedPlatforms: {SocialPlatform.youtubeShorts}),
            throwsStateError);
      }
    });

    test('does not invent private visibility for an incomplete saved choice',
        () {
      const settings =
          PlatformPublishSettings(youtubeVisibility: YouTubeVisibility.public);
      expect(
          settings.toRecoveryApiJson(
              selectedPlatforms: {SocialPlatform.youtubeShorts}),
          {
            'YOUTUBE_SHORTS': {'visibility': 'public'},
          });
    });

    test('omits an unrecorded legacy Facebook mode instead of inventing one',
        () {
      const settings = PlatformPublishSettings();
      expect(
          settings.toRecoveryApiJson(selectedPlatforms: {
            SocialPlatform.instagramReels,
            SocialPlatform.facebookReels,
          }),
          {
            'INSTAGRAM_REELS': {'shareToFeed': true},
          });
      expect(
          () => settings
              .toApiJson(selectedPlatforms: {SocialPlatform.facebookReels}),
          throwsStateError);
    });

    test(
        'preserves a Direct snapshot without asserting current publishing readiness',
        () {
      const settings = PlatformPublishSettings(
        tiktokPublishMode: TikTokPublishMode.directPost,
        tiktokPrivacyLevel: TikTokPrivacyLevel.selfOnly,
        tiktokAllowComment: true,
      );
      final snapshot = settings
          .toRecoveryApiJson(selectedPlatforms: {SocialPlatform.tiktok});
      expect(snapshot, {
        'TIKTOK': {
          'publishMode': 'DIRECT_POST',
          'privacyLevel': 'SELF_ONLY',
          'creatorInfoRevision': null,
          'disableComment': false,
          'disableDuet': true,
          'disableStitch': true,
          'brandContentToggle': false,
          'brandOrganicToggle': false,
          'isAigc': false,
          'videoDurationSeconds': null,
          'musicUsageConfirmed': false,
          'brandedContentPolicyConfirmed': false,
        },
      });
      expect(
          () => settings.toApiJson(selectedPlatforms: {SocialPlatform.tiktok}),
          throwsStateError);
    });

    test('does not invent an unrecorded TikTok privacy choice', () {
      const settings = PlatformPublishSettings(
          tiktokPublishMode: TikTokPublishMode.directPost);
      final snapshot = settings
          .toRecoveryApiJson(selectedPlatforms: {SocialPlatform.tiktok});
      expect((snapshot['TIKTOK'] as Map)['privacyLevel'], isNull);
      expect((snapshot['TIKTOK'] as Map)['musicUsageConfirmed'], isFalse);
    });

    test('serializes no platforms that were not in the original selection', () {
      expect(
          const PlatformPublishSettings()
              .toRecoveryApiJson(selectedPlatforms: {}),
          isEmpty);
    });
  });

  group('optional Meta AI-generated declarations', () {
    const platforms = {
      SocialPlatform.instagramReels,
      SocialPlatform.facebookReels,
    };

    test('legacy unanswered declarations retain their exact API shape', () {
      const settings = PlatformPublishSettings(
        facebookPublishMode: FacebookPublishMode.publish,
      );
      final legacyDraft = settings.toDraftJson();
      expect(legacyDraft, isNot(contains('instagramIsAiGenerated')));
      expect(legacyDraft, isNot(contains('facebookIsAiGenerated')));
      final restored =
          PlatformPublishSettings.fromDraftJson(legacyDraft, strict: true);
      expect(restored.instagramIsAiGenerated, isNull);
      expect(restored.facebookIsAiGenerated, isNull);
      expect(restored.canSubmit(SocialPlatform.instagramReels), isTrue);
      expect(restored.canSubmit(SocialPlatform.facebookReels), isTrue);
      const expected = {
        'INSTAGRAM_REELS': {'shareToFeed': true},
        'FACEBOOK_REELS': {'publishMode': 'PUBLISH'},
      };
      expect(restored.toApiJson(selectedPlatforms: platforms), expected);
      expect(
          restored.toRecoveryApiJson(selectedPlatforms: platforms), expected);
    });

    test('round-trips every explicit boolean through drafts and recovery', () {
      for (final instagramAnswer in [true, false]) {
        for (final facebookAnswer in [true, false]) {
          final settings = PlatformPublishSettings(
            instagramShareToFeed: false,
            instagramIsAiGenerated: instagramAnswer,
            facebookPublishMode: FacebookPublishMode.pageDraft,
            facebookIsAiGenerated: facebookAnswer,
          );
          final restored = PlatformPublishSettings.fromDraftJson(
              settings.toDraftJson(),
              strict: true);
          expect(restored, settings);
          expect(restored.hashCode, settings.hashCode);
          final expected = {
            'INSTAGRAM_REELS': {
              'shareToFeed': false,
              'isAiGenerated': instagramAnswer,
            },
            'FACEBOOK_REELS': {
              'publishMode': 'PAGE_DRAFT',
              'isAiGenerated': facebookAnswer,
            },
          };
          expect(restored.toApiJson(selectedPlatforms: platforms), expected);
          expect(restored.toRecoveryApiJson(selectedPlatforms: platforms),
              expected);
          expect(restored.toApiJson(selectedPlatforms: {}), isEmpty);
        }
      }
    });

    test('copying preserves, updates and clears each nullable declaration', () {
      const settings = PlatformPublishSettings(
        instagramIsAiGenerated: true,
        facebookIsAiGenerated: false,
      );
      expect(settings.copyWith(), settings);
      final instagramCleared = settings.copyWith(instagramIsAiGenerated: null);
      expect(instagramCleared.instagramIsAiGenerated, isNull);
      expect(instagramCleared.facebookIsAiGenerated, isFalse);
      final facebookCleared = settings.copyWith(facebookIsAiGenerated: null);
      expect(facebookCleared.instagramIsAiGenerated, isTrue);
      expect(facebookCleared.facebookIsAiGenerated, isNull);
      expect({settings, instagramCleared, facebookCleared}, hasLength(3));
      expect(settings.copyWith(instagramIsAiGenerated: false), isNot(settings));
      expect(settings.copyWith(facebookIsAiGenerated: true), isNot(settings));
      final cleared = settings.copyWith(
          instagramIsAiGenerated: null, facebookIsAiGenerated: null);
      expect(cleared, const PlatformPublishSettings());
      expect(cleared.toDraftJson(), isNot(contains('instagramIsAiGenerated')));
      expect(cleared.toDraftJson(), isNot(contains('facebookIsAiGenerated')));
    });

    test('rejects malformed optional declarations in otherwise valid drafts',
        () {
      for (final key in ['instagramIsAiGenerated', 'facebookIsAiGenerated']) {
        for (final invalid in <Object?>['true', 0, null, [], {}]) {
          for (final strict in [false, true]) {
            expect(
              () => PlatformPublishSettings.fromDraftJson({
                ...const PlatformPublishSettings().toDraftJson(),
                key: invalid
              }, strict: strict),
              throwsFormatException,
              reason: '$key must preserve an explicit boolean',
            );
          }
        }
      }
    });
  });

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
