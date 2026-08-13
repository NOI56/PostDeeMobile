import '../platforms/social_platform.dart';

enum TikTokPublishMode {
  inboxDraft,
  directPost,
}

enum YouTubeVisibility {
  private,
  unlisted,
  public,
}

enum FacebookPublishMode {
  pageDraft,
  publish,
}

/// User-visible publishing choices that differ between social platforms.
///
/// TikTok direct publishing intentionally remains modeled but unavailable.
/// PostDee does not yet receive TikTok creator-info capabilities, so it cannot
/// safely offer the account's current privacy and interaction choices.
class PlatformPublishSettings {
  const PlatformPublishSettings({
    this.tiktokPublishMode = TikTokPublishMode.inboxDraft,
    this.youtubeTitle = '',
    this.youtubeVisibility = YouTubeVisibility.private,
    this.youtubeMadeForKids,
    this.youtubeContainsSyntheticMedia,
    this.youtubeCommunityGuidelinesCertified = false,
    this.instagramShareToFeed = true,
    this.facebookPublishMode,
  });

  final TikTokPublishMode tiktokPublishMode;
  final String youtubeTitle;
  final YouTubeVisibility youtubeVisibility;
  final bool? youtubeMadeForKids;
  final bool? youtubeContainsSyntheticMedia;
  final bool youtubeCommunityGuidelinesCertified;
  final bool instagramShareToFeed;
  final FacebookPublishMode? facebookPublishMode;

  PlatformPublishSettings copyWith({
    TikTokPublishMode? tiktokPublishMode,
    String? youtubeTitle,
    YouTubeVisibility? youtubeVisibility,
    Object? youtubeMadeForKids = _keepSetting,
    Object? youtubeContainsSyntheticMedia = _keepSetting,
    bool? youtubeCommunityGuidelinesCertified,
    bool? instagramShareToFeed,
    Object? facebookPublishMode = _keepSetting,
  }) =>
      PlatformPublishSettings(
        tiktokPublishMode: tiktokPublishMode ?? this.tiktokPublishMode,
        youtubeTitle: youtubeTitle ?? this.youtubeTitle,
        youtubeVisibility: youtubeVisibility ?? this.youtubeVisibility,
        youtubeMadeForKids: identical(youtubeMadeForKids, _keepSetting)
            ? this.youtubeMadeForKids
            : youtubeMadeForKids as bool?,
        youtubeContainsSyntheticMedia:
            identical(youtubeContainsSyntheticMedia, _keepSetting)
                ? this.youtubeContainsSyntheticMedia
                : youtubeContainsSyntheticMedia as bool?,
        youtubeCommunityGuidelinesCertified:
            youtubeCommunityGuidelinesCertified ??
                this.youtubeCommunityGuidelinesCertified,
        instagramShareToFeed: instagramShareToFeed ?? this.instagramShareToFeed,
        facebookPublishMode: identical(facebookPublishMode, _keepSetting)
            ? this.facebookPublishMode
            : facebookPublishMode as FacebookPublishMode?,
      );

  bool canSubmit(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.tiktok:
        return tiktokPublishMode == TikTokPublishMode.inboxDraft;
      case SocialPlatform.youtubeShorts:
        return youtubeValidationMessage == null;
      case SocialPlatform.instagramReels:
        return true;
      case SocialPlatform.facebookReels:
        return facebookPublishMode != null;
      case SocialPlatform.shopeeVideo:
      case SocialPlatform.lazadaVideo:
        return false;
    }
  }

  String? get youtubeValidationMessage {
    final title = youtubeTitle.trim();
    if (title.isEmpty) return 'เพิ่มชื่อวิดีโอ YouTube';
    if (title.runes.length > 100 ||
        title.contains('<') ||
        title.contains('>')) {
      return 'ชื่อ YouTube ต้องไม่เกิน 100 ตัวอักษร และห้ามมี < หรือ >';
    }
    if (youtubeMadeForKids == null) {
      return 'ระบุว่าวิดีโอ YouTube ทำมาเพื่อเด็กหรือไม่';
    }
    if (youtubeContainsSyntheticMedia == null) {
      return 'ระบุว่าวิดีโอมีสื่อสังเคราะห์ที่ดูเหมือนจริงหรือไม่';
    }
    if (!youtubeCommunityGuidelinesCertified) {
      return 'ยืนยันกฎชุมชน YouTube ก่อนโพสต์';
    }
    return null;
  }

  Map<String, Object?> toApiJson({
    required Set<SocialPlatform> selectedPlatforms,
  }) {
    if (selectedPlatforms.any((platform) => !canSubmit(platform))) {
      throw StateError(
        'TikTok direct publishing requires current creator info.',
      );
    }

    return {
      if (selectedPlatforms.contains(SocialPlatform.tiktok))
        'TIKTOK': <String, Object?>{
          'publishMode': switch (tiktokPublishMode) {
            TikTokPublishMode.inboxDraft => 'INBOX_DRAFT',
            TikTokPublishMode.directPost => 'DIRECT_POST',
          },
        },
      if (selectedPlatforms.contains(SocialPlatform.youtubeShorts))
        'YOUTUBE_SHORTS': <String, Object?>{
          'title': youtubeTitle.trim(),
          'visibility': youtubeVisibility.name,
          'madeForKids': youtubeMadeForKids,
          'containsSyntheticMedia': youtubeContainsSyntheticMedia,
          'communityGuidelinesCertified': youtubeCommunityGuidelinesCertified,
        },
      if (selectedPlatforms.contains(SocialPlatform.instagramReels))
        'INSTAGRAM_REELS': <String, Object?>{
          'shareToFeed': instagramShareToFeed,
        },
      if (selectedPlatforms.contains(SocialPlatform.facebookReels))
        'FACEBOOK_REELS': <String, Object?>{
          'publishMode': switch (facebookPublishMode) {
            FacebookPublishMode.publish => 'PUBLISH',
            FacebookPublishMode.pageDraft => 'PAGE_DRAFT',
            null => throw StateError('Facebook publish mode is required.'),
          },
        },
    };
  }

  Map<String, Object?> toDraftJson() => {
        'tiktokPublishMode': tiktokPublishMode.name,
        'youtubeTitle': youtubeTitle,
        'youtubeVisibility': youtubeVisibility.name,
        'youtubeMadeForKids': youtubeMadeForKids,
        'youtubeContainsSyntheticMedia': youtubeContainsSyntheticMedia,
        'youtubeCommunityGuidelinesCertified':
            youtubeCommunityGuidelinesCertified,
        'instagramShareToFeed': instagramShareToFeed,
        'facebookPublishMode': facebookPublishMode?.name,
      };

  factory PlatformPublishSettings.fromDraftJson(
    Object? value, {
    bool strict = false,
  }) {
    if (value == null) {
      if (strict) {
        throw const FormatException('platformSettings is required');
      }
      return const PlatformPublishSettings();
    }
    if (value is! Map) {
      throw const FormatException('platformSettings must be an object');
    }
    final json = Map<String, Object?>.from(value);
    if (strict) {
      const requiredKeys = {
        'tiktokPublishMode',
        'youtubeTitle',
        'youtubeVisibility',
        'youtubeMadeForKids',
        'youtubeContainsSyntheticMedia',
        'youtubeCommunityGuidelinesCertified',
        'instagramShareToFeed',
        'facebookPublishMode',
      };
      if (!json.keys.toSet().containsAll(requiredKeys)) {
        throw const FormatException('platformSettings is incomplete');
      }
    }
    return PlatformPublishSettings(
      tiktokPublishMode: _enumByName(
        TikTokPublishMode.values,
        json['tiktokPublishMode'],
        'tiktokPublishMode',
      ),
      youtubeTitle: _stringOrDefault(json['youtubeTitle']),
      youtubeVisibility: _enumByName(
        YouTubeVisibility.values,
        json['youtubeVisibility'],
        'youtubeVisibility',
      ),
      youtubeMadeForKids: _nullableBool(json['youtubeMadeForKids']),
      youtubeContainsSyntheticMedia:
          _nullableBool(json['youtubeContainsSyntheticMedia']),
      youtubeCommunityGuidelinesCertified:
          _boolOrDefault(json['youtubeCommunityGuidelinesCertified']),
      instagramShareToFeed:
          _boolOrDefault(json['instagramShareToFeed'], defaultValue: true),
      facebookPublishMode: _nullableEnumByName(
        FacebookPublishMode.values,
        json['facebookPublishMode'],
        'facebookPublishMode',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlatformPublishSettings &&
          other.tiktokPublishMode == tiktokPublishMode &&
          other.youtubeTitle == youtubeTitle &&
          other.youtubeVisibility == youtubeVisibility &&
          other.youtubeMadeForKids == youtubeMadeForKids &&
          other.youtubeContainsSyntheticMedia ==
              youtubeContainsSyntheticMedia &&
          other.youtubeCommunityGuidelinesCertified ==
              youtubeCommunityGuidelinesCertified &&
          other.instagramShareToFeed == instagramShareToFeed &&
          other.facebookPublishMode == facebookPublishMode;

  @override
  int get hashCode => Object.hash(
        tiktokPublishMode,
        youtubeTitle,
        youtubeVisibility,
        youtubeMadeForKids,
        youtubeContainsSyntheticMedia,
        youtubeCommunityGuidelinesCertified,
        instagramShareToFeed,
        facebookPublishMode,
      );
}

String _stringOrDefault(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  throw const FormatException('Expected a string');
}

bool? _nullableBool(Object? value) {
  if (value == null || value is bool) return value as bool?;
  throw const FormatException('Expected a boolean');
}

bool _boolOrDefault(Object? value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  throw const FormatException('Expected a boolean');
}

T _enumByName<T extends Enum>(
  List<T> values,
  Object? value,
  String fieldName,
) {
  if (value is! String) {
    throw FormatException('$fieldName must be a string');
  }
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$fieldName is unsupported');
}

T? _nullableEnumByName<T extends Enum>(
  List<T> values,
  Object? value,
  String fieldName,
) {
  if (value == null) return null;
  return _enumByName(values, value, fieldName);
}

bool shouldApplyPostDeeWatermark({
  required bool requested,
  required Set<SocialPlatform> selectedPlatforms,
}) =>
    requested && !selectedPlatforms.contains(SocialPlatform.tiktok);

const _keepSetting = Object();
