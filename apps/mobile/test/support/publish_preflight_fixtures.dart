import 'dart:io';

import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';

/// Explicit stand-in for the native probe in tests whose clip is dummy bytes.
/// Production always uses FFprobe and never imports these fixtures.
Future<PublishMediaMetadata> probeValidPublishMedia(File file) async =>
    PublishMediaMetadata(
      durationSeconds: 10,
      width: 1080,
      height: 1920,
      sizeBytes: file.lengthSync(),
      hasVideo: true,
      hasAudio: true,
      videoCodec: 'h264',
      audioCodec: 'aac',
      fps: 30,
      sampleRate: 48000,
      channels: 2,
      container: 'mov,mp4,m4a,3gp,3g2,mj2',
    );

/// A connected fixture is deliberately not a claim of verified publish rights.
Future<List<SocialPublishingConnectionReadiness>>
    connectedPublishingReadinessForTests() async => const [
          SocialPublishingConnectionReadiness(
              platform: 'TIKTOK', state: SocialPublishingState.connected),
          SocialPublishingConnectionReadiness(
              platform: 'YOUTUBE_SHORTS',
              state: SocialPublishingState.connected),
          SocialPublishingConnectionReadiness(
              platform: 'INSTAGRAM_REELS',
              state: SocialPublishingState.connected),
          SocialPublishingConnectionReadiness(
              platform: 'FACEBOOK_REELS',
              state: SocialPublishingState.connected),
        ];
