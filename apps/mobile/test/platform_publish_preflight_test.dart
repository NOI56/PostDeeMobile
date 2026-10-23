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
      expect(check(SocialPlatform.youtubeShorts, media: media)?.code,
          'PUBLISH_MEDIA_UNVERIFIED');
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

  test('Facebook uses actual hard limits without enforcing recommendations',
      () {
    expect(
        check(SocialPlatform.facebookReels,
            media: _media(duration: 14400, width: 4000, fps: 29.97)),
        isNull);
    expect(
        check(SocialPlatform.facebookReels, media: _media(duration: 14400.01))
            ?.code,
        'FACEBOOK_DURATION_INVALID');
    expect(
        check(SocialPlatform.facebookReels, media: _media(width: 4001))?.code,
        'FACEBOOK_WIDTH_INVALID');
    expect(
        check(SocialPlatform.facebookReels,
            media: _media(width: 1079, fps: 25)),
        isNull);
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
