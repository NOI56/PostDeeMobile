import 'package:flutter/foundation.dart';

import '../../core/network/postdee_api_client.dart';
import '../platforms/social_platform.dart';

export '../../core/network/postdee_api_client.dart'
    show TikTokCreatorInfo, TikTokPrivacyLevel;

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

/// Uses the caption's first sentence; a blank saved title means automatic mode.
String safeYouTubeTitleSuggestion(String caption) {
  for (final line in caption.split(RegExp(r'\r\n?|\n'))) {
    final title = line
        .replaceAll(RegExp(r'[<>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isNotEmpty) {
      final sentenceEnd = RegExp(r'[.!?。！？](?:\s|$)').firstMatch(title);
      final sentence = sentenceEnd == null
          ? title
          : title.substring(0, sentenceEnd.start + 1);
      return String.fromCharCodes(sentence.runes.take(100)).trim();
    }
  }
  return '';
}

/// User-visible publishing choices that differ between social platforms.
///
/// Direct Post requires fresh creator capabilities in the caller and verified
/// prepared-video duration before serialization. Inbox retains its old shape.
class PlatformPublishSettings {
  const PlatformPublishSettings({
    this.usePlatformCaptions = false,
    this.platformCaptions = const {},
    this.tiktokPublishMode = TikTokPublishMode.inboxDraft,
    this.tiktokPrivacyLevel,
    this.tiktokCreatorInfoRevision,
    this.tiktokAllowComment = false,
    this.tiktokAllowDuet = false,
    this.tiktokAllowStitch = false,
    this.tiktokBrandContentToggle = false,
    this.tiktokBrandOrganicToggle = false,
    this.tiktokIsAigc = false,
    this.tiktokMusicUsageConfirmed = false,
    this.tiktokBrandedContentPolicyConfirmed = false,
    this.tiktokVideoDurationSeconds,
    this.youtubeTitle = '',
    this.youtubeVisibility = YouTubeVisibility.private,
    this.youtubeMadeForKids,
    this.youtubeContainsSyntheticMedia,
    this.youtubeCommunityGuidelinesCertified = false,
    this.instagramShareToFeed = true,
    this.instagramIsAiGenerated,
    this.facebookPublishMode,
    this.facebookIsAiGenerated,
  });

  /// Per-post caption drafts stay available when the shared editor is active.
  final bool usePlatformCaptions;
  final Map<SocialPlatform, String> platformCaptions;
  final TikTokPublishMode tiktokPublishMode;
  final TikTokPrivacyLevel? tiktokPrivacyLevel;
  final String? tiktokCreatorInfoRevision;
  final bool tiktokAllowComment;
  final bool tiktokAllowDuet;
  final bool tiktokAllowStitch;
  final bool tiktokBrandContentToggle;
  final bool tiktokBrandOrganicToggle;
  final bool tiktokIsAigc;
  final bool tiktokMusicUsageConfirmed;
  final bool tiktokBrandedContentPolicyConfirmed;
  final double? tiktokVideoDurationSeconds;
  final String youtubeTitle;
  final YouTubeVisibility youtubeVisibility;
  final bool? youtubeMadeForKids;
  final bool? youtubeContainsSyntheticMedia;
  final bool youtubeCommunityGuidelinesCertified;
  final bool instagramShareToFeed;
  final bool? instagramIsAiGenerated;
  final FacebookPublishMode? facebookPublishMode;
  final bool? facebookIsAiGenerated;

  String effectiveCaption(SocialPlatform platform, String sharedCaption) =>
      usePlatformCaptions
          ? platformCaptions[platform] ?? sharedCaption
          : sharedCaption;

  /// Resolve only for validation/review/submission. Drafts retain the override
  /// so automatic titles continue to follow edits to their saved caption.
  PlatformPublishSettings resolvedForCaption(String caption) =>
      youtubeTitle.trim().isNotEmpty
          ? this
          : copyWith(
              youtubeTitle: safeYouTubeTitleSuggestion(
                effectiveCaption(SocialPlatform.youtubeShorts, caption),
              ),
            );

  PlatformPublishSettings copyWith({
    bool? usePlatformCaptions,
    Map<SocialPlatform, String>? platformCaptions,
    TikTokPublishMode? tiktokPublishMode,
    Object? tiktokPrivacyLevel = _keepSetting,
    Object? tiktokCreatorInfoRevision = _keepSetting,
    bool? tiktokAllowComment,
    bool? tiktokAllowDuet,
    bool? tiktokAllowStitch,
    bool? tiktokBrandContentToggle,
    bool? tiktokBrandOrganicToggle,
    bool? tiktokIsAigc,
    bool? tiktokMusicUsageConfirmed,
    bool? tiktokBrandedContentPolicyConfirmed,
    Object? tiktokVideoDurationSeconds = _keepSetting,
    String? youtubeTitle,
    YouTubeVisibility? youtubeVisibility,
    Object? youtubeMadeForKids = _keepSetting,
    Object? youtubeContainsSyntheticMedia = _keepSetting,
    bool? youtubeCommunityGuidelinesCertified,
    bool? instagramShareToFeed,
    Object? instagramIsAiGenerated = _keepSetting,
    Object? facebookPublishMode = _keepSetting,
    Object? facebookIsAiGenerated = _keepSetting,
  }) =>
      PlatformPublishSettings(
        usePlatformCaptions: usePlatformCaptions ?? this.usePlatformCaptions,
        platformCaptions: platformCaptions ?? this.platformCaptions,
        tiktokPublishMode: tiktokPublishMode ?? this.tiktokPublishMode,
        tiktokPrivacyLevel: identical(tiktokPrivacyLevel, _keepSetting)
            ? this.tiktokPrivacyLevel
            : tiktokPrivacyLevel as TikTokPrivacyLevel?,
        tiktokCreatorInfoRevision:
            identical(tiktokCreatorInfoRevision, _keepSetting)
                ? this.tiktokCreatorInfoRevision
                : tiktokCreatorInfoRevision as String?,
        tiktokAllowComment: tiktokAllowComment ?? this.tiktokAllowComment,
        tiktokAllowDuet: tiktokAllowDuet ?? this.tiktokAllowDuet,
        tiktokAllowStitch: tiktokAllowStitch ?? this.tiktokAllowStitch,
        tiktokBrandContentToggle:
            tiktokBrandContentToggle ?? this.tiktokBrandContentToggle,
        tiktokBrandOrganicToggle:
            tiktokBrandOrganicToggle ?? this.tiktokBrandOrganicToggle,
        tiktokIsAigc: tiktokIsAigc ?? this.tiktokIsAigc,
        tiktokMusicUsageConfirmed:
            tiktokMusicUsageConfirmed ?? this.tiktokMusicUsageConfirmed,
        tiktokBrandedContentPolicyConfirmed:
            tiktokBrandedContentPolicyConfirmed ??
                this.tiktokBrandedContentPolicyConfirmed,
        tiktokVideoDurationSeconds:
            identical(tiktokVideoDurationSeconds, _keepSetting)
                ? this.tiktokVideoDurationSeconds
                : (tiktokVideoDurationSeconds as num?)?.toDouble(),
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
        instagramIsAiGenerated: identical(instagramIsAiGenerated, _keepSetting)
            ? this.instagramIsAiGenerated
            : instagramIsAiGenerated as bool?,
        facebookPublishMode: identical(facebookPublishMode, _keepSetting)
            ? this.facebookPublishMode
            : facebookPublishMode as FacebookPublishMode?,
        facebookIsAiGenerated: identical(facebookIsAiGenerated, _keepSetting)
            ? this.facebookIsAiGenerated
            : facebookIsAiGenerated as bool?,
      );

  bool canSubmit(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.tiktok:
        return tiktokValidationMessage == null;
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

  String? get tiktokValidationMessage {
    if (tiktokPublishMode == TikTokPublishMode.inboxDraft) return null;
    if (tiktokPrivacyLevel == null) return 'เลือกผู้ที่สามารถดูวิดีโอ TikTok';
    if (!_tikTokRevisionPattern.hasMatch(tiktokCreatorInfoRevision ?? '')) {
      return 'ตรวจสอบบัญชี TikTok และตัวเลือกการโพสต์อีกครั้ง';
    }
    if (!tiktokMusicUsageConfirmed) return 'ยืนยันข้อกำหนดการใช้เพลง TikTok';
    if (tiktokBrandContentToggle &&
        tiktokPrivacyLevel == TikTokPrivacyLevel.selfOnly) {
      return 'เนื้อหาที่มีผู้สนับสนุนไม่สามารถตั้งเป็นเฉพาะฉันได้';
    }
    if (tiktokBrandContentToggle && !tiktokBrandedContentPolicyConfirmed) {
      return 'ยืนยันนโยบายเนื้อหาที่มีผู้สนับสนุน TikTok';
    }
    return null;
  }

  String? validateTikTokCreatorInfo(TikTokCreatorInfo creatorInfo,
      {bool validateDuration = true}) {
    if (tiktokPublishMode == TikTokPublishMode.inboxDraft) return null;
    final configurationError = tiktokValidationMessage;
    if (configurationError != null) return configurationError;
    if (!creatorInfo.privacyLevelOptions.contains(tiktokPrivacyLevel)) {
      return 'บัญชี TikTok ไม่รองรับผู้ชมที่เลือก กรุณาเลือกใหม่';
    }
    if ((tiktokAllowComment && creatorInfo.commentDisabled) ||
        (tiktokAllowDuet && creatorInfo.duetDisabled) ||
        (tiktokAllowStitch && creatorInfo.stitchDisabled)) {
      return 'บัญชี TikTok ปิดการโต้ตอบที่เลือก กรุณาตรวจสอบใหม่';
    }
    if (validateDuration) {
      final duration = tiktokVideoDurationSeconds;
      final maximum = creatorInfo.maxVideoPostDurationSec < 600
          ? creatorInfo.maxVideoPostDurationSec
          : 600;
      if (duration == null ||
          !duration.isFinite ||
          duration <= 0 ||
          duration > maximum) {
        return 'ตรวจสอบความยาววิดีโอให้ตรงกับข้อจำกัดบัญชี TikTok';
      }
    }
    return null;
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
    if (selectedPlatforms.contains(SocialPlatform.tiktok) &&
        tiktokPublishMode == TikTokPublishMode.directPost) {
      final duration = tiktokVideoDurationSeconds;
      if (duration == null ||
          !duration.isFinite ||
          duration <= 0 ||
          duration > 600) {
        throw StateError(
            'TikTok Direct Post requires verified video duration.');
      }
    }

    return {
      if (selectedPlatforms.contains(SocialPlatform.tiktok))
        'TIKTOK': <String, Object?>{
          ..._captionApiJson(SocialPlatform.tiktok),
          'publishMode': switch (tiktokPublishMode) {
            TikTokPublishMode.inboxDraft => 'INBOX_DRAFT',
            TikTokPublishMode.directPost => 'DIRECT_POST',
          },
          if (tiktokPublishMode == TikTokPublishMode.directPost) ...{
            'privacyLevel': tiktokPrivacyLevel!.apiValue,
            'creatorInfoRevision': tiktokCreatorInfoRevision,
            'disableComment': !tiktokAllowComment,
            'disableDuet': !tiktokAllowDuet,
            'disableStitch': !tiktokAllowStitch,
            'brandContentToggle': tiktokBrandContentToggle,
            'brandOrganicToggle': tiktokBrandOrganicToggle,
            'isAigc': tiktokIsAigc,
            'videoDurationSeconds': tiktokVideoDurationSeconds,
            'musicUsageConfirmed': tiktokMusicUsageConfirmed,
            'brandedContentPolicyConfirmed':
                tiktokBrandedContentPolicyConfirmed,
          },
        },
      if (selectedPlatforms.contains(SocialPlatform.youtubeShorts))
        'YOUTUBE_SHORTS': <String, Object?>{
          ..._captionApiJson(SocialPlatform.youtubeShorts),
          'title': youtubeTitle.trim(),
          'visibility': youtubeVisibility.name,
          'madeForKids': youtubeMadeForKids,
          'containsSyntheticMedia': youtubeContainsSyntheticMedia,
          'communityGuidelinesCertified': youtubeCommunityGuidelinesCertified,
        },
      if (selectedPlatforms.contains(SocialPlatform.instagramReels))
        'INSTAGRAM_REELS': <String, Object?>{
          ..._captionApiJson(SocialPlatform.instagramReels),
          'shareToFeed': instagramShareToFeed,
          if (instagramIsAiGenerated != null)
            'isAiGenerated': instagramIsAiGenerated,
        },
      if (selectedPlatforms.contains(SocialPlatform.facebookReels))
        'FACEBOOK_REELS': <String, Object?>{
          ..._captionApiJson(SocialPlatform.facebookReels),
          'publishMode': switch (facebookPublishMode) {
            FacebookPublishMode.publish => 'PUBLISH',
            FacebookPublishMode.pageDraft => 'PAGE_DRAFT',
            null => throw StateError('Facebook publish mode is required.'),
          },
          if (facebookIsAiGenerated != null)
            'isAiGenerated': facebookIsAiGenerated,
        },
    };
  }

  /// Serializes a saved intent only for the read-only submission recovery route.
  /// Missing historical answers stay missing. New publishing must use [toApiJson].
  Map<String, Object?> toRecoveryApiJson({
    required Set<SocialPlatform> selectedPlatforms,
  }) =>
      {
        if (selectedPlatforms.contains(SocialPlatform.tiktok))
          'TIKTOK': <String, Object?>{
            ..._captionApiJson(SocialPlatform.tiktok),
            'publishMode': switch (tiktokPublishMode) {
              TikTokPublishMode.inboxDraft => 'INBOX_DRAFT',
              TikTokPublishMode.directPost => 'DIRECT_POST',
            },
            if (tiktokPublishMode == TikTokPublishMode.directPost) ...{
              'privacyLevel': tiktokPrivacyLevel?.apiValue,
              'creatorInfoRevision': tiktokCreatorInfoRevision,
              'disableComment': !tiktokAllowComment,
              'disableDuet': !tiktokAllowDuet,
              'disableStitch': !tiktokAllowStitch,
              'brandContentToggle': tiktokBrandContentToggle,
              'brandOrganicToggle': tiktokBrandOrganicToggle,
              'isAigc': tiktokIsAigc,
              'videoDurationSeconds': tiktokVideoDurationSeconds,
              'musicUsageConfirmed': tiktokMusicUsageConfirmed,
              'brandedContentPolicyConfirmed':
                  tiktokBrandedContentPolicyConfirmed,
            },
          },
        if (selectedPlatforms.contains(SocialPlatform.youtubeShorts))
          'YOUTUBE_SHORTS': <String, Object?>{
            ..._captionApiJson(SocialPlatform.youtubeShorts),
            'visibility': youtubeVisibility.name,
            if (youtubeTitle.trim().isNotEmpty &&
                youtubeMadeForKids != null &&
                youtubeContainsSyntheticMedia != null &&
                youtubeCommunityGuidelinesCertified) ...{
              'title': youtubeTitle.trim(),
              'madeForKids': youtubeMadeForKids,
              'containsSyntheticMedia': youtubeContainsSyntheticMedia,
              'communityGuidelinesCertified':
                  youtubeCommunityGuidelinesCertified,
            },
          },
        if (selectedPlatforms.contains(SocialPlatform.instagramReels))
          'INSTAGRAM_REELS': <String, Object?>{
            ..._captionApiJson(SocialPlatform.instagramReels),
            'shareToFeed': instagramShareToFeed,
            if (instagramIsAiGenerated != null)
              'isAiGenerated': instagramIsAiGenerated,
          },
        if (selectedPlatforms.contains(SocialPlatform.facebookReels) &&
            facebookPublishMode != null)
          'FACEBOOK_REELS': <String, Object?>{
            ..._captionApiJson(SocialPlatform.facebookReels),
            'publishMode': switch (facebookPublishMode!) {
              FacebookPublishMode.publish => 'PUBLISH',
              FacebookPublishMode.pageDraft => 'PAGE_DRAFT',
            },
            if (facebookIsAiGenerated != null)
              'isAiGenerated': facebookIsAiGenerated,
          },
      };

  Map<String, Object?> _captionApiJson(SocialPlatform platform) => {
        if (usePlatformCaptions && platformCaptions.containsKey(platform))
          'caption': platformCaptions[platform],
      };

  Map<String, Object?> toDraftJson() => {
        if (usePlatformCaptions) 'usePlatformCaptions': true,
        if (platformCaptions.isNotEmpty)
          'platformCaptions': {
            for (final platform in _captionPlatforms)
              if (platformCaptions.containsKey(platform))
                platform.apiValue: platformCaptions[platform],
          },
        'tiktokPublishMode': tiktokPublishMode.name,
        'tiktokPrivacyLevel': tiktokPrivacyLevel?.name,
        'tiktokCreatorInfoRevision': tiktokCreatorInfoRevision,
        'tiktokAllowComment': tiktokAllowComment,
        'tiktokAllowDuet': tiktokAllowDuet,
        'tiktokAllowStitch': tiktokAllowStitch,
        'tiktokBrandContentToggle': tiktokBrandContentToggle,
        'tiktokBrandOrganicToggle': tiktokBrandOrganicToggle,
        'tiktokIsAigc': tiktokIsAigc,
        'tiktokMusicUsageConfirmed': tiktokMusicUsageConfirmed,
        'tiktokBrandedContentPolicyConfirmed':
            tiktokBrandedContentPolicyConfirmed,
        'tiktokVideoDurationSeconds': tiktokVideoDurationSeconds,
        'youtubeTitle': youtubeTitle,
        'youtubeVisibility': youtubeVisibility.name,
        'youtubeMadeForKids': youtubeMadeForKids,
        'youtubeContainsSyntheticMedia': youtubeContainsSyntheticMedia,
        'youtubeCommunityGuidelinesCertified':
            youtubeCommunityGuidelinesCertified,
        'instagramShareToFeed': instagramShareToFeed,
        if (instagramIsAiGenerated != null)
          'instagramIsAiGenerated': instagramIsAiGenerated,
        'facebookPublishMode': facebookPublishMode?.name,
        if (facebookIsAiGenerated != null)
          'facebookIsAiGenerated': facebookIsAiGenerated,
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
      usePlatformCaptions: json.containsKey('usePlatformCaptions')
          ? _requiredCaptionMode(json['usePlatformCaptions'])
          : false,
      platformCaptions: json.containsKey('platformCaptions')
          ? _readPlatformCaptionDrafts(json['platformCaptions'])
          : const {},
      tiktokPublishMode: _enumByName(
        TikTokPublishMode.values,
        json['tiktokPublishMode'],
        'tiktokPublishMode',
      ),
      tiktokPrivacyLevel: _nullableEnumByName(TikTokPrivacyLevel.values,
          json['tiktokPrivacyLevel'], 'tiktokPrivacyLevel'),
      tiktokCreatorInfoRevision:
          _nullableTikTokRevision(json['tiktokCreatorInfoRevision']),
      tiktokAllowComment: _optionalTikTokBool(json, 'tiktokAllowComment'),
      tiktokAllowDuet: _optionalTikTokBool(json, 'tiktokAllowDuet'),
      tiktokAllowStitch: _optionalTikTokBool(json, 'tiktokAllowStitch'),
      tiktokBrandContentToggle:
          _optionalTikTokBool(json, 'tiktokBrandContentToggle'),
      tiktokBrandOrganicToggle:
          _optionalTikTokBool(json, 'tiktokBrandOrganicToggle'),
      tiktokIsAigc: _optionalTikTokBool(json, 'tiktokIsAigc'),
      tiktokMusicUsageConfirmed:
          _optionalTikTokBool(json, 'tiktokMusicUsageConfirmed'),
      tiktokBrandedContentPolicyConfirmed:
          _optionalTikTokBool(json, 'tiktokBrandedContentPolicyConfirmed'),
      tiktokVideoDurationSeconds:
          _nullableTikTokDuration(json['tiktokVideoDurationSeconds']),
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
      instagramIsAiGenerated:
          _optionalDeclarationBool(json, 'instagramIsAiGenerated'),
      facebookPublishMode: _nullableEnumByName(
        FacebookPublishMode.values,
        json['facebookPublishMode'],
        'facebookPublishMode',
      ),
      facebookIsAiGenerated:
          _optionalDeclarationBool(json, 'facebookIsAiGenerated'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlatformPublishSettings &&
          other.usePlatformCaptions == usePlatformCaptions &&
          mapEquals(other.platformCaptions, platformCaptions) &&
          other.tiktokPublishMode == tiktokPublishMode &&
          other.tiktokPrivacyLevel == tiktokPrivacyLevel &&
          other.tiktokCreatorInfoRevision == tiktokCreatorInfoRevision &&
          other.tiktokAllowComment == tiktokAllowComment &&
          other.tiktokAllowDuet == tiktokAllowDuet &&
          other.tiktokAllowStitch == tiktokAllowStitch &&
          other.tiktokBrandContentToggle == tiktokBrandContentToggle &&
          other.tiktokBrandOrganicToggle == tiktokBrandOrganicToggle &&
          other.tiktokIsAigc == tiktokIsAigc &&
          other.tiktokMusicUsageConfirmed == tiktokMusicUsageConfirmed &&
          other.tiktokBrandedContentPolicyConfirmed ==
              tiktokBrandedContentPolicyConfirmed &&
          other.tiktokVideoDurationSeconds == tiktokVideoDurationSeconds &&
          other.youtubeTitle == youtubeTitle &&
          other.youtubeVisibility == youtubeVisibility &&
          other.youtubeMadeForKids == youtubeMadeForKids &&
          other.youtubeContainsSyntheticMedia ==
              youtubeContainsSyntheticMedia &&
          other.youtubeCommunityGuidelinesCertified ==
              youtubeCommunityGuidelinesCertified &&
          other.instagramShareToFeed == instagramShareToFeed &&
          other.instagramIsAiGenerated == instagramIsAiGenerated &&
          other.facebookPublishMode == facebookPublishMode &&
          other.facebookIsAiGenerated == facebookIsAiGenerated;

  @override
  int get hashCode => Object.hashAll([
        usePlatformCaptions,
        Object.hashAll([
          for (final platform in _captionPlatforms)
            if (platformCaptions.containsKey(platform))
              Object.hash(platform, platformCaptions[platform]),
        ]),
        tiktokPublishMode,
        tiktokPrivacyLevel,
        tiktokCreatorInfoRevision,
        tiktokAllowComment,
        tiktokAllowDuet,
        tiktokAllowStitch,
        tiktokBrandContentToggle,
        tiktokBrandOrganicToggle,
        tiktokIsAigc,
        tiktokMusicUsageConfirmed,
        tiktokBrandedContentPolicyConfirmed,
        tiktokVideoDurationSeconds,
        youtubeTitle,
        youtubeVisibility,
        youtubeMadeForKids,
        youtubeContainsSyntheticMedia,
        youtubeCommunityGuidelinesCertified,
        instagramShareToFeed,
        instagramIsAiGenerated,
        facebookPublishMode,
        facebookIsAiGenerated,
      ]);
}

const _captionPlatforms = {
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
};

bool _requiredCaptionMode(Object? value) {
  if (value is bool) return value;
  throw const FormatException('usePlatformCaptions must be a boolean');
}

Map<SocialPlatform, String> _readPlatformCaptionDrafts(Object? value) {
  if (value is! Map) {
    throw const FormatException('platformCaptions must be an object');
  }
  final captions = <SocialPlatform, String>{};
  for (final entry in value.entries) {
    final platform = _captionPlatforms
        .where((platform) => platform.apiValue == entry.key)
        .firstOrNull;
    if (platform == null || entry.value is! String) {
      throw const FormatException('Invalid platform caption');
    }
    captions[platform] = entry.value as String;
  }
  return Map.unmodifiable(captions);
}

final _tikTokRevisionPattern = RegExp(r'^[0-9a-f]{64}$');

String? _nullableTikTokRevision(Object? value) {
  if (value == null) return null;
  if (value is String && _tikTokRevisionPattern.hasMatch(value)) return value;
  throw const FormatException('Invalid TikTok creator revision');
}

double? _nullableTikTokDuration(Object? value) {
  if (value == null) return null;
  if (value is num && value.isFinite && value > 0) return value.toDouble();
  throw const FormatException('Invalid TikTok video duration');
}

bool _optionalTikTokBool(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return false;
  if (json[key] is bool) return json[key] as bool;
  throw const FormatException('Expected a TikTok boolean');
}

bool? _optionalDeclarationBool(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  if (json[key] is bool) return json[key] as bool;
  throw FormatException('$key must be a boolean when present');
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
