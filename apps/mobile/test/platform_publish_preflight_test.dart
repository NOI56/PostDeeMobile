import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';

PublishMediaMetadata _media({
  double? duration = 10,
  int? width = 1080,
  int? height = 1920,
  int size = 1000000,
  bool hasVideo = true,
  bool hasAudio = true,
  String? videoCodec = 'h264',
  String? audioCodec = 'aac',
  double? fps = 30,
  int? sampleRate = 48000,
  int? channels = 2,
  String? container = 'mov,mp4,m4a,3gp,3g2,mj2',
}) =>
    PublishMediaMetadata(
      durationSeconds: duration,
      width: width,
      height: height,
      sizeBytes: size,
      hasVideo: hasVideo,
      hasAudio: hasAudio,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      fps: fps,
      sampleRate: sampleRate,
      channels: channels,
      container: container,
    );

void main() {
  test('validates destination text instead of an unused shared caption', () {
    expect(validatePlatformPublishPreflight(
      selectedPlatforms: {SocialPlatform.youtubeShorts, SocialPlatform.instagramReels},
      caption: '<unused shared caption>',
      platformCaptions: const {
        SocialPlatform.youtubeShorts: 'YouTube description',
        SocialPlatform.instagramReels: 'Instagram caption',
      },
      media: _media(),
      requireMedia: true,
    ), isNull);
    expect(validatePlatformPublishPreflight(
      selectedPlatforms: {SocialPlatform.youtubeShorts},
      caption: 'shared caption',
      platformCaptions: const {SocialPlatform.youtubeShorts: '<invalid>'},
    )?.code, 'YOUTUBE_DESCRIPTION_INVALID');
  });

  test('unselected captions do not block media or selected descriptions', () {
    expect(validatePlatformPublishPreflight(
      selectedPlatforms: {SocialPlatform.youtubeShorts},
      caption: 'shared',
      platformCaptions: {
        SocialPlatform.youtubeShorts: '',
        SocialPlatform.instagramReels: 'x' * 2201,
      },
      media: _media(),
      requireMedia: true,
    ), isNull);
    expect(validatePlatformPublishPreflight(
      selectedPlatforms: {SocialPlatform.youtubeShorts},
      caption: 'shared',
      platformCaptions: const {SocialPlatform.youtubeShorts: ''},
      requireMedia: true,
    )?.code, 'PUBLISH_MEDIA_UNVERIFIED');
  });

  PublishPreflightProblem? check(SocialPlatform platform,
          {String caption = 'caption', PublishMediaMetadata? media}) =>
      validatePlatformPublishPreflight(
        selectedPlatforms: {platform},
        caption: caption,
        media: media,
        requireMedia: true,
      );

  test('duration hints wait for a finite positive duration', () {
    for (final platform in SocialPlatform.values) {
      for (final duration in [
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.0,
        -1.0,
      ]) {
        expect(
          validatePlatformVideoDuration(
            platform: platform,
            durationSeconds: duration,
            tikTokMaxDurationSeconds: 300,
          ),
          isNull,
          reason: '$platform duration $duration has not been verified',
        );
      }
    }
  });

  test('duration hints keep exact non-TikTok boundaries and destination errors',
      () {
    final accepted = <SocialPlatform, List<double>>{
      SocialPlatform.youtubeShorts: [0.001, 180],
      SocialPlatform.instagramReels: [3, 900],
      SocialPlatform.facebookReels: [3, 90],
    };
    for (final entry in accepted.entries) {
      for (final duration in entry.value) {
        expect(
          validatePlatformVideoDuration(
            platform: entry.key,
            durationSeconds: duration,
          ),
          isNull,
          reason: '${entry.key} accepts $duration seconds',
        );
      }
    }
    final rejected = <SocialPlatform, List<double>>{
      SocialPlatform.youtubeShorts: [180.001],
      SocialPlatform.instagramReels: [2.999, 900.001],
      SocialPlatform.facebookReels: [2.999, 90.001],
    };
    const codes = {
      SocialPlatform.youtubeShorts: 'YOUTUBE_SHORTS_DURATION_INVALID',
      SocialPlatform.instagramReels: 'INSTAGRAM_DURATION_INVALID',
      SocialPlatform.facebookReels: 'FACEBOOK_DURATION_INVALID',
    };
    for (final entry in rejected.entries) {
      for (final duration in entry.value) {
        final problem = validatePlatformVideoDuration(
          platform: entry.key,
          durationSeconds: duration,
        );
        expect(problem?.code, codes[entry.key]);
        expect(problem?.platform, entry.key);
      }
    }
    expect(
      validatePlatformVideoDuration(
        platform: SocialPlatform.youtubeShorts,
        durationSeconds: 180.001,
      )?.message,
      'YouTube Shorts ต้องใช้คลิปยาวไม่เกิน 3 นาที',
    );
    expect(
      validatePlatformVideoDuration(
        platform: SocialPlatform.instagramReels,
        durationSeconds: 900.001,
      )?.message,
      'Instagram Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 15 นาที',
    );
  });

  test('TikTok duration hints retain the 600 second API upload ceiling', () {
    for (final creatorLimit in <int?>[null, 0, -1, 600, 601, 3600]) {
      expect(
        validatePlatformVideoDuration(
          platform: SocialPlatform.tiktok,
          durationSeconds: 600,
          tikTokMaxDurationSeconds: creatorLimit,
        ),
        isNull,
      );
      final problem = validatePlatformVideoDuration(
        platform: SocialPlatform.tiktok,
        durationSeconds: 600.001,
        tikTokMaxDurationSeconds: creatorLimit,
      );
      expect(problem?.code, 'TIKTOK_DURATION_INVALID');
      expect(problem?.platform, SocialPlatform.tiktok);
      expect(problem?.message, contains('TikTok'));
    }
  });

  test('TikTok duration hints respect a smaller positive creator limit', () {
    for (final creatorLimit in [1, 59, 90, 300, 599]) {
      expect(
        validatePlatformVideoDuration(
          platform: SocialPlatform.tiktok,
          durationSeconds: creatorLimit.toDouble(),
          tikTokMaxDurationSeconds: creatorLimit,
        ),
        isNull,
      );
      final problem = validatePlatformVideoDuration(
        platform: SocialPlatform.tiktok,
        durationSeconds: creatorLimit + 0.001,
        tikTokMaxDurationSeconds: creatorLimit,
      );
      expect(problem?.code, 'TIKTOK_DURATION_INVALID');
      expect(problem?.platform, SocialPlatform.tiktok);
    }
  });

  test('valid original media passes each non-TikTok destination', () {
    for (final platform in [
      SocialPlatform.youtubeShorts,
      SocialPlatform.instagramReels,
      SocialPlatform.facebookReels,
    ]) {
      expect(check(platform, media: _media()), isNull);
    }
    expect(
        check(SocialPlatform.youtubeShorts,
            media: _media(width: 180, height: 320)),
        isNull);
  });

  test('YouTube description limit counts UTF8 bytes and rejects angle brackets',
      () {
    expect(
        check(SocialPlatform.youtubeShorts,
            caption: 'ก' * 1666, media: _media()),
        isNull);
    expect(
        check(SocialPlatform.youtubeShorts,
                caption: 'ก' * 1667, media: _media())
            ?.code,
        'YOUTUBE_DESCRIPTION_TOO_LONG');
    expect(
        check(SocialPlatform.youtubeShorts,
                caption: 'look <here>', media: _media())
            ?.code,
        'YOUTUBE_DESCRIPTION_INVALID');
  });

  test('caption-only validation works before native metadata is loaded', () {
    expect(
        validatePlatformPublishPreflight(
          selectedPlatforms: {SocialPlatform.instagramReels},
          caption: '😀' * 1100,
        ),
        isNull);
    expect(
        validatePlatformPublishPreflight(
          selectedPlatforms: {SocialPlatform.instagramReels},
          caption: '😀' * 1101,
        )?.code,
        'INSTAGRAM_CAPTION_TOO_LONG');
    expect(
        validatePlatformPublishPreflight(
          selectedPlatforms: {SocialPlatform.facebookReels},
          caption: 'a' * 63206,
        ),
        isNull);
    expect(
        validatePlatformPublishPreflight(
          selectedPlatforms: {SocialPlatform.facebookReels},
          caption: 'a' * 63207,
        )?.code,
        'FACEBOOK_CAPTION_TOO_LONG');
  });

  test('unknown metadata cannot pass a required non-TikTok media check', () {
    for (final media in [
      null,
      _media(duration: null),
      _media(duration: double.nan),
      _media(duration: double.infinity),
      _media(duration: 0),
      _media(width: null),
      _media(height: 0),
      _media(size: 0),
      _media(hasVideo: false),
    ]) {
      for (final platform in [
        SocialPlatform.youtubeShorts,
        SocialPlatform.instagramReels,
        SocialPlatform.facebookReels,
      ]) {
        expect(check(platform, media: media)?.code, 'PUBLISH_MEDIA_UNVERIFIED');
      }
    }
    expect(
        validatePlatformPublishPreflight(
          selectedPlatforms: {SocialPlatform.tiktok},
          caption: 'caption',
          requireMedia: true,
        ),
        isNull,
        reason: 'TikTok retains its separate preparation flow');
  });

  test('YouTube Shorts allows 180 seconds and rejects a longer clip', () {
    expect(check(SocialPlatform.youtubeShorts, media: _media(duration: 180)),
        isNull);
    expect(
        check(SocialPlatform.youtubeShorts, media: _media(duration: 180.01))
            ?.code,
        'YOUTUBE_SHORTS_DURATION_INVALID');
  });

  test('Instagram hard media limits are checked before upload', () {
    for (final duration in [3.0, 900.0]) {
      expect(
          check(SocialPlatform.instagramReels,
              media: _media(duration: duration)),
          isNull);
    }
    for (final duration in [2.99, 900.01]) {
      expect(
          check(SocialPlatform.instagramReels,
                  media: _media(duration: duration))
              ?.code,
          'INSTAGRAM_DURATION_INVALID');
    }
    final failures = <PublishMediaMetadata>[
      _media(size: 300000001),
      _media(width: 1921),
      _media(fps: null),
      _media(fps: 22.9),
      _media(fps: 60.01),
      _media(videoCodec: null),
      _media(videoCodec: 'vp9'),
      _media(audioCodec: 'mp3'),
      _media(sampleRate: null),
      _media(sampleRate: 48001),
      _media(channels: null),
      _media(channels: 6),
    ];
    for (final media in failures) {
      expect(check(SocialPlatform.instagramReels, media: media), isNotNull);
    }
    expect(
        check(SocialPlatform.instagramReels,
            media: _media(videoCodec: 'hevc', fps: 23)),
        isNull);
    expect(
        check(SocialPlatform.instagramReels,
            media: _media(
                hasAudio: false,
                audioCodec: null,
                sampleRate: null,
                channels: null)),
        isNull);
  });

  test('Facebook Reels allows 3 to 90 seconds without rounding', () {
    for (final duration in [3.0, 90.0]) {
      expect(check(SocialPlatform.facebookReels, media: _media(duration: duration)),
          isNull);
    }
    for (final duration in [2.999, 90.001]) {
      final problem = check(SocialPlatform.facebookReels,
          media: _media(duration: duration));
      expect(problem?.code, 'FACEBOOK_DURATION_INVALID');
      expect(problem?.platform, SocialPlatform.facebookReels);
      expect(problem?.message, contains('1 นาที 30 วินาที'));
    }
  });

  test('Facebook Reels does not reuse Facebook Feed Video width ceilings', () {
    // Passing local preflight does not guarantee provider acceptance.
    expect(check(SocialPlatform.facebookReels, media: _media(width: 4001)), isNull);
    expect(
        check(SocialPlatform.facebookReels,
            media: _media(width: 1079, fps: 25)),
        isNull);
  });

  test('Facebook Reels still requires verified media metadata', () {
    for (final media in [
      null,
      _media(duration: null),
      _media(duration: 0),
      _media(width: null),
      _media(height: 0),
      _media(size: 0),
      _media(hasVideo: false),
    ]) {
      expect(check(SocialPlatform.facebookReels, media: media)?.code,
          'PUBLISH_MEDIA_UNVERIFIED');
    }
  });

  test('Instagram requires a probed MOV or MP4 container token', () {
    for (final container in [null, 'matroska,webm', 'not-mp4', 'mp4-invalid']) {
      expect(
          check(SocialPlatform.instagramReels,
                  media: _media(container: container))
              ?.code,
          'INSTAGRAM_CONTAINER_INVALID');
    }
    for (final container in ['mov', 'mp4', 'mov,mp4,m4a,3gp,3g2,mj2']) {
      expect(
          check(SocialPlatform.instagramReels,
              media: _media(container: container)),
          isNull);
    }
    expect(check(SocialPlatform.youtubeShorts, media: _media(container: null)),
        isNull);
  });

  test('required Instagram container validation keeps its existing priority', () {
    expect(
      check(SocialPlatform.instagramReels,
          media: _media(container: null, duration: 900.001))?.code,
      'INSTAGRAM_CONTAINER_INVALID',
    );
  });

  test('full TikTok preflight keeps duration checks in its preparation flow', () {
    expect(check(SocialPlatform.tiktok, media: _media(duration: 600.001)), isNull);
  });

  test('an overlong Reel only blocks when Facebook is selected', () {
    final result = validatePlatformPublishPreflight(
      selectedPlatforms: {
        SocialPlatform.youtubeShorts,
        SocialPlatform.instagramReels,
        SocialPlatform.facebookReels,
      },
      caption: 'caption',
      media: _media(duration: 120),
      requireMedia: true,
    );
    expect(result?.code, 'FACEBOOK_DURATION_INVALID');
    expect(result?.platform, SocialPlatform.facebookReels);
    expect(
      validatePlatformPublishPreflight(
        selectedPlatforms: {
          SocialPlatform.youtubeShorts,
          SocialPlatform.instagramReels,
        },
        caption: 'caption',
        media: _media(duration: 120),
        requireMedia: true,
      ),
      isNull,
    );
  });

  test('multi-destination preflight identifies the platform that blocks upload',
      () {
    final result = validatePlatformPublishPreflight(
      selectedPlatforms: {
        SocialPlatform.youtubeShorts,
        SocialPlatform.instagramReels,
      },
      caption: 'a' * 2201,
      media: _media(),
      requireMedia: true,
    );
    expect(result?.platform, SocialPlatform.instagramReels);
    expect(result?.message, contains('Instagram'));
  });
}
