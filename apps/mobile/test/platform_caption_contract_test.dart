import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_defaults_store.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';

void main() {
  const captions = {
    SocialPlatform.tiktok: 'แคปชัน TikTok',
    SocialPlatform.youtubeShorts: 'ชื่อ Shorts! รายละเอียด',
    SocialPlatform.instagramReels: 'แคปชัน Instagram',
    SocialPlatform.facebookReels: 'แคปชัน Facebook',
  };
  const settings = PlatformPublishSettings(
    usePlatformCaptions: true,
    platformCaptions: captions,
    aiCaptionPlatforms: {
      SocialPlatform.tiktok,
      SocialPlatform.instagramReels,
    },
    youtubeMadeForKids: false,
    youtubeContainsSyntheticMedia: false,
    youtubeCommunityGuidelinesCertified: true,
    facebookPublishMode: FacebookPublishMode.publish,
  );

  test('shared mode ignores retained overrides without losing their drafts',
      () {
    final shared = settings.copyWith(usePlatformCaptions: false);
    expect(shared.effectiveCaption(SocialPlatform.tiktok, 'หลัก'), 'หลัก');
    expect(shared.platformCaptions, captions);
    expect(shared.aiCaptionPlatforms, settings.aiCaptionPlatforms);
    final json = shared.resolvedForCaption('หลัก').toApiJson(
          selectedPlatforms: captions.keys.toSet(),
        );
    for (final entry in json.values.cast<Map<String, Object?>>()) {
      expect(entry.containsKey('caption'), isFalse);
    }
    final restored = PlatformPublishSettings.fromDraftJson(
      jsonDecode(jsonEncode(shared.toDraftJson())),
      strict: true,
    );
    expect(restored, shared);
    expect(restored.copyWith(usePlatformCaptions: true), settings);
  });

  test('submission and recovery serialize only selected caption overrides', () {
    final resolved = settings.resolvedForCaption('หลัก');
    final selected = {SocialPlatform.youtubeShorts, SocialPlatform.tiktok};
    final json = resolved.toApiJson(selectedPlatforms: selected);
    expect(json.keys.toSet(), {'TIKTOK', 'YOUTUBE_SHORTS'});
    expect((json['TIKTOK'] as Map)['caption'], captions[SocialPlatform.tiktok]);
    expect((json['YOUTUBE_SHORTS'] as Map)['caption'],
        captions[SocialPlatform.youtubeShorts]);
    expect(resolved.toRecoveryApiJson(selectedPlatforms: selected), json);
    expect(jsonEncode(json), isNot(contains('aiCaptionPlatforms')));
    expect(resolved.youtubeTitle, 'ชื่อ Shorts!');
    expect(resolved.platformCaptions, captions);
    expect(resolved.effectiveCaption(SocialPlatform.facebookReels, 'หลัก'),
        captions[SocialPlatform.facebookReels]);
  });

  test('missing override falls back to shared caption and omits API field', () {
    const partial = PlatformPublishSettings(
      usePlatformCaptions: true,
      platformCaptions: {SocialPlatform.tiktok: 'TikTok'},
    );
    expect(partial.effectiveCaption(SocialPlatform.instagramReels, 'หลัก'),
        'หลัก');
    final json = partial.toApiJson(
      selectedPlatforms: {SocialPlatform.instagramReels},
    );
    expect((json['INSTAGRAM_REELS'] as Map).containsKey('caption'), isFalse);
  });

  test('all four submission payloads retain their exact independent captions',
      () {
    final json = settings.resolvedForCaption('หลัก').toApiJson(
          selectedPlatforms: captions.keys.toSet(),
        );
    for (final entry in captions.entries) {
      expect((json[entry.key.apiValue] as Map)['caption'], entry.value);
    }
  });

  test('reusable account preferences never capture per-post caption drafts',
      () {
    for (final platform in captions.keys) {
      final preferences =
          PlatformPublishDefaults.fromSettings(platform, settings);
      final savedJson = preferences.toJson();
      expect(jsonEncode(savedJson), isNot(contains('platformCaptions')));
      expect(jsonEncode(savedJson), isNot(contains('usePlatformCaptions')));
      expect(jsonEncode(savedJson), isNot(contains('aiCaptionPlatforms')));
      final applied = PlatformPublishDefaults.fromJson(savedJson)!
          .applyTo(const PlatformPublishSettings());
      expect(applied.platformCaptions, isEmpty);
      expect(applied.usePlatformCaptions, isFalse);
      expect(applied.aiCaptionPlatforms, isEmpty);
      final samePost = preferences.applyTo(settings);
      expect(samePost.platformCaptions, captions);
      expect(samePost.usePlatformCaptions, isTrue);
      expect(samePost.aiCaptionPlatforms, settings.aiCaptionPlatforms);
    }
  });

  test('caption settings use value equality independent of map insertion order',
      () {
    final reordered = settings.copyWith(platformCaptions: {
      for (final key in captions.keys.toList().reversed) key: captions[key]!,
    });
    expect(reordered, settings);
    expect(reordered.hashCode, settings.hashCode);
    expect(settings.copyWith(platformCaptions: const {}), isNot(settings));
    expect(settings.copyWith(usePlatformCaptions: false), isNot(settings));
  });

  test('AI target selection round trips in stable order independently of mode',
      () {
    final reordered = settings.copyWith(aiCaptionPlatforms: {
      SocialPlatform.instagramReels,
      SocialPlatform.tiktok,
    });
    expect(reordered, settings);
    expect(reordered.hashCode, settings.hashCode);
    expect(reordered.toDraftJson()['aiCaptionPlatforms'],
        ['TIKTOK', 'INSTAGRAM_REELS']);
    for (final active in [true, false]) {
      final draft = reordered.copyWith(usePlatformCaptions: active);
      final restored = PlatformPublishSettings.fromDraftJson(
        jsonDecode(jsonEncode(draft.toDraftJson())),
        strict: true,
      );
      expect(restored, draft);
      expect(restored.aiCaptionPlatforms, settings.aiCaptionPlatforms);
    }
    expect(settings.copyWith(aiCaptionPlatforms: const {}), isNot(settings));
    expect(settings.copyWith(aiCaptionPlatforms: const {}).aiCaptionPlatforms,
        isEmpty);
  });

  test('AI target draft serialization only includes supported destinations',
      () {
    final unsupported = settings.copyWith(aiCaptionPlatforms: {
      SocialPlatform.shopeeVideo,
      SocialPlatform.instagramReels,
      SocialPlatform.lazadaVideo,
    });
    expect(
        unsupported.toDraftJson()['aiCaptionPlatforms'], ['INSTAGRAM_REELS']);
  });

  test('historical draft shape defaults to shared mode', () {
    final historical = const PlatformPublishSettings().toDraftJson()
      ..remove('usePlatformCaptions')
      ..remove('platformCaptions')
      ..remove('aiCaptionPlatforms');
    final restored =
        PlatformPublishSettings.fromDraftJson(historical, strict: true);
    expect(restored.usePlatformCaptions, isFalse);
    expect(restored.platformCaptions, isEmpty);
    expect(restored.aiCaptionPlatforms, isEmpty);
    expect(restored.toDraftJson(), isNot(contains('aiCaptionPlatforms')));
  });

  test('draft parser rejects malformed or unsupported AI target selections',
      () {
    for (final invalid in <Object?>[
      null,
      'TIKTOK',
      {'TIKTOK': true},
      [1],
      ['TIKTOK', null],
      ['SHOPEE_VIDEO'],
      ['LAZADA_VIDEO'],
      ['UNKNOWN'],
    ]) {
      expect(
        () => PlatformPublishSettings.fromDraftJson({
          ...settings.toDraftJson(),
          'aiCaptionPlatforms': invalid,
        }),
        throwsFormatException,
      );
    }
  });

  test('draft parser rejects malformed caption mode or platform entries', () {
    for (final invalid in <Object?>[null, 'true', 1]) {
      expect(
        () => PlatformPublishSettings.fromDraftJson({
          ...settings.toDraftJson(),
          'usePlatformCaptions': invalid,
        }),
        throwsFormatException,
      );
    }
    for (final invalid in <Object?>[
      null,
      [],
      {'TIKTOK': 3},
      {'SHOPEE_VIDEO': 'not supported'},
      {'INVALID': 'not supported'},
    ]) {
      expect(
        () => PlatformPublishSettings.fromDraftJson({
          ...settings.toDraftJson(),
          'platformCaptions': invalid,
        }),
        throwsFormatException,
      );
    }
  });

  test('AI request platform list is optional for historical shared generation',
      () {
    expect(
      const GenerateRealClipCaptionRequest(videoS3Key: 'video.mp4').toJson(),
      {'videoS3Key': 'video.mp4'},
    );
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'video.mp4',
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
      ).toJson(),
      {
        'videoS3Key': 'video.mp4',
        'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
      },
    );
  });

  test('AI request explicitly confirms the selected caption credit cost', () {
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'video.mp4',
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        expectedCredits: 2,
      ).toJson(),
      {
        'videoS3Key': 'video.mp4',
        'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
        'expectedCredits': 2,
      },
    );
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'video.mp4',
        expectedCredits: 1,
      ).toJson()['expectedCredits'],
      1,
    );
  });

  Map<String, Object?> aiResponse() => {
        'caption': 'Shared',
        'captionOptions': ['Shared'],
        'hooks': [],
        'hashtags': [],
        'seoKeywords': [],
        'searchTitle': 'Title',
        'source': {
          'videoS3Key': 'video.mp4',
          'mode': 'AUDIO_WITH_FRAMES',
          'selectedFrameCount': 1,
        },
        'quota': {'limit': 50, 'usedThisMonth': 1, 'remainingThisMonth': 49},
      };

  test('AI response retains all platform captions and their own hashtags', () {
    final result = RealClipCaptionResult.fromJson({
      ...aiResponse(),
      'platformCaptions': {
        for (final entry in captions.entries)
          entry.key.apiValue: {
            'caption': entry.value,
            'hashtags': ['#${entry.key.apiValue}'],
          },
      },
    });
    expect(result.platformCaptions.keys.toSet(),
        captions.keys.map((value) => value.apiValue).toSet());
    expect(result.platformCaptions['TIKTOK']!.caption,
        captions[SocialPlatform.tiktok]);
    expect(result.platformCaptions['TIKTOK']!.hashtags, ['#TIKTOK']);
    expect(
        RealClipCaptionResult.fromJson(aiResponse()).platformCaptions, isEmpty);
  });

  test(
      'AI response rejects malformed platform captions rather than mixing text',
      () {
    for (final invalid in <Object?>[
      null,
      [],
      {'TIKTOK': 'wrong shape'},
      {
        'TIKTOK': {'caption': 1, 'hashtags': []}
      },
      {
        'TIKTOK': {'caption': 'TikTok', 'hashtags': 'not a list'}
      },
    ]) {
      expect(
        () => RealClipCaptionResult.fromJson({
          ...aiResponse(),
          'platformCaptions': invalid,
        }),
        throwsA(isA<ApiException>()),
      );
    }
  });
}
