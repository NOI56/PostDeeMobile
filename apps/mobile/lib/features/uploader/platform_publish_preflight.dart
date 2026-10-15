import 'dart:convert';

import '../platforms/social_platform.dart';

/// Metadata read from the file that is actually sent, including rendered files.
/// A missing value remains unknown and never implies provider compatibility.
class PublishMediaMetadata {
  const PublishMediaMetadata({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.hasVideo = true,
    this.hasAudio = false,
    this.videoCodec,
    this.audioCodec,
    this.fps,
    this.sampleRate,
    this.channels,
    this.container,
  });

  final double? durationSeconds;
  final int? width;
  final int? height;
  final int sizeBytes;
  final bool hasVideo;
  final bool hasAudio;
  final String? videoCodec;
  final String? audioCodec;
  final double? fps;
  final int? sampleRate;
  final int? channels;
  final String? container;

  Map<String, Object?> toJson() => {
        'durationSeconds': durationSeconds,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
        'hasVideo': hasVideo,
        'hasAudio': hasAudio,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'fps': fps,
        'sampleRate': sampleRate,
        'channels': channels,
        'container': container,
      };

  factory PublishMediaMetadata.fromJson(Map<String, Object?> json) {
    const keys = {
      'durationSeconds',
      'width',
      'height',
      'sizeBytes',
      'hasVideo',
      'hasAudio',
      'videoCodec',
      'audioCodec',
      'fps',
      'sampleRate',
      'channels',
      'container',
    };
    if (json.keys.any((key) => !keys.contains(key)) ||
        json['sizeBytes'] is! int ||
        (json['sizeBytes'] as int) <= 0 ||
        json['hasVideo'] is! bool ||
        json['hasAudio'] is! bool) {
      throw const FormatException('Invalid publish media metadata');
    }
    double? positiveDouble(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is num && value.isFinite && value > 0) return value.toDouble();
      throw const FormatException('Invalid publish media metadata');
    }

    int? positiveInt(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is int && value > 0) return value;
      throw const FormatException('Invalid publish media metadata');
    }

    String? boundedString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String && value.isNotEmpty && value.length <= 128) {
        return value;
      }
      throw const FormatException('Invalid publish media metadata');
    }

    return PublishMediaMetadata(
      durationSeconds: positiveDouble('durationSeconds'),
      width: positiveInt('width'),
      height: positiveInt('height'),
      sizeBytes: json['sizeBytes'] as int,
      hasVideo: json['hasVideo'] as bool,
      hasAudio: json['hasAudio'] as bool,
      videoCodec: boundedString('videoCodec'),
      audioCodec: boundedString('audioCodec'),
      fps: positiveDouble('fps'),
      sampleRate: positiveInt('sampleRate'),
      channels: positiveInt('channels'),
      container: boundedString('container'),
    );
  }
}

class PublishPreflightProblem {
  const PublishPreflightProblem({
    required this.code,
    required this.message,
    this.platform,
  });

  final String code;
  final String message;
  final SocialPlatform? platform;
}

PublishPreflightProblem? validatePlatformPublishPreflight({
  required Set<SocialPlatform> selectedPlatforms,
  required String caption,
  PublishMediaMetadata? media,
  bool requireMedia = false,
}) {
  final text = caption.trim();
  PublishPreflightProblem problem(
          SocialPlatform platform, String code, String message) =>
      PublishPreflightProblem(code: code, message: message, platform: platform);

  // Apply limits to the exact trimmed caption that is serialized to the API.
  for (final platform
      in SocialPlatform.values.where(selectedPlatforms.contains)) {
    if (platform == SocialPlatform.youtubeShorts) {
      if (utf8.encode(text).length > 5000) {
        return problem(platform, 'YOUTUBE_DESCRIPTION_TOO_LONG',
            'คำอธิบาย YouTube ต้องไม่เกิน 5,000 ไบต์ กรุณาย่อแคปชั่นก่อนโพสต์');
      }
      if (text.contains('<') || text.contains('>')) {
        return problem(platform, 'YOUTUBE_DESCRIPTION_INVALID',
            'คำอธิบาย YouTube ห้ามมี < หรือ > กรุณาแก้แคปชั่นก่อนโพสต์');
      }
    } else if (platform == SocialPlatform.instagramReels &&
        text.length > 2200) {
      return problem(platform, 'INSTAGRAM_CAPTION_TOO_LONG',
          'แคปชั่น Instagram ต้องไม่เกิน 2,200 ตัวอักษร');
    } else if (platform == SocialPlatform.facebookReels &&
        text.length > 63206) {
      return problem(platform, 'FACEBOOK_CAPTION_TOO_LONG',
          'แคปชั่น Facebook ต้องไม่เกิน 63,206 ตัวอักษร');
    }
  }
  if (!requireMedia) return null;

  for (final platform
      in SocialPlatform.values.where(selectedPlatforms.contains)) {
    if (platform != SocialPlatform.youtubeShorts &&
        platform != SocialPlatform.instagramReels &&
        platform != SocialPlatform.facebookReels) {
      continue;
    }
    final duration = media?.durationSeconds;
    if (media == null ||
        !media.hasVideo ||
        media.sizeBytes <= 0 ||
        duration == null ||
        !duration.isFinite ||
        duration <= 0 ||
        media.width == null ||
        media.width! <= 0 ||
        media.height == null ||
        media.height! <= 0) {
      return problem(platform, 'PUBLISH_MEDIA_UNVERIFIED',
          'ยังตรวจสอบข้อมูลคลิปสำหรับ ${platform.label} ไม่สำเร็จ กรุณาลองอีกครั้งหรือเลือกคลิปใหม่');
    }
    if (platform == SocialPlatform.youtubeShorts && duration > 180) {
      return problem(platform, 'YOUTUBE_SHORTS_DURATION_INVALID',
          'YouTube Shorts ต้องใช้คลิปยาวไม่เกิน 3 นาที');
    }
    if (platform == SocialPlatform.instagramReels) {
      final containerNames =
          media.container?.split(',').map((name) => name.trim().toLowerCase());
      if (containerNames == null ||
          !containerNames.any((name) => name == 'mov' || name == 'mp4')) {
        return problem(platform, 'INSTAGRAM_CONTAINER_INVALID',
            'Instagram ต้องใช้คลิป MOV หรือ MP4 ที่ตรวจสอบรูปแบบไฟล์ได้');
      }
      if (duration < 3 || duration > 900) {
        return problem(platform, 'INSTAGRAM_DURATION_INVALID',
            'Instagram Reels ต้องใช้คลิปยาวตั้งแต่ 3 วินาทีถึง 15 นาที');
      }
      if (media.sizeBytes > 300000000) {
        return problem(platform, 'INSTAGRAM_SIZE_INVALID',
            'คลิป Instagram ต้องมีขนาดไม่เกิน 300 MB');
      }
      if (media.width! > 1920) {
        return problem(platform, 'INSTAGRAM_WIDTH_INVALID',
            'คลิป Instagram ต้องมีความกว้างไม่เกิน 1,920 พิกเซล');
      }
      final fps = media.fps;
      if (fps == null || !fps.isFinite || fps < 23 || fps > 60) {
        return problem(platform, 'INSTAGRAM_FRAME_RATE_INVALID',
            'คลิป Instagram ต้องมีเฟรมเรต 23–60 FPS กรุณาเลือกคลิปที่รองรับ');
      }
      if (media.videoCodec != 'h264' && media.videoCodec != 'hevc') {
        return problem(platform, 'INSTAGRAM_VIDEO_CODEC_INVALID',
            'คลิป Instagram ต้องเข้ารหัสวิดีโอแบบ H.264 หรือ HEVC');
      }
      if (media.hasAudio &&
          (media.audioCodec != 'aac' ||
              media.sampleRate == null ||
              media.sampleRate! <= 0 ||
              media.sampleRate! > 48000 ||
              (media.channels != 1 && media.channels != 2))) {
        return problem(platform, 'INSTAGRAM_AUDIO_INVALID',
            'เสียง Instagram ต้องเป็น AAC แบบโมโนหรือสเตอริโอ และไม่เกิน 48 kHz');
      }
    }
    if (platform == SocialPlatform.facebookReels) {
      if (duration > 14400) {
        return problem(platform, 'FACEBOOK_DURATION_INVALID',
            'วิดีโอบนเพจ Facebook ต้องยาวไม่เกิน 240 นาที');
      }
      if (media.width! > 4000) {
        return problem(platform, 'FACEBOOK_WIDTH_INVALID',
            'วิดีโอบนเพจ Facebook ต้องกว้างไม่เกิน 4,000 พิกเซล');
      }
    }
  }
  return null;
}
