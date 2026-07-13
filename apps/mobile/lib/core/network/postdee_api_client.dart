import 'dart:convert';
import 'dart:io';

import '../auth/auth_session.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

typedef AuthTokenProvider = Future<String?> Function();

class ClipTranscriptSegment {
  const ClipTranscriptSegment({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final double start;
  final double end;

  factory ClipTranscriptSegment.fromJson(Map<String, Object?> json) {
    return ClipTranscriptSegment(
      text: json['text'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiEditQuota {
  const AiEditQuota({
    required this.limitMinutes,
    required this.usedMinutes,
    required this.remainingMinutes,
  });

  final int limitMinutes;
  final int usedMinutes;
  final int remainingMinutes;

  factory AiEditQuota.fromJson(Map<String, Object?> json) {
    return AiEditQuota(
      limitMinutes: (json['limitMinutes'] as num?)?.round() ?? 0,
      usedMinutes: (json['usedMinutes'] as num?)?.round() ?? 0,
      remainingMinutes: (json['remainingMinutes'] as num?)?.round() ?? 0,
    );
  }
}

class AiEditCut {
  const AiEditCut({required this.start, required this.end});

  final double start;
  final double end;

  factory AiEditCut.fromJson(Map<String, Object?> json) {
    return AiEditCut(
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiEditPlanResult {
  const AiEditPlanResult({
    required this.cuts,
    required this.summary,
    required this.model,
  });

  final List<AiEditCut> cuts;
  final String summary;
  final String model;

  factory AiEditPlanResult.fromJson(Map<String, Object?> json) {
    final rawCuts = json['cuts'];
    final cuts = rawCuts is List<dynamic>
        ? rawCuts
            .whereType<Map<String, Object?>>()
            .map(AiEditCut.fromJson)
            .toList()
        : <AiEditCut>[];

    return AiEditPlanResult(
      cuts: cuts,
      summary: json['summary'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }
}

class AiEditPlanRequest {
  const AiEditPlanRequest({
    required this.segments,
    required this.durationSeconds,
    this.styleId,
    this.prompt,
  });

  final List<ClipTranscriptSegment> segments;
  final double durationSeconds;
  final String? styleId;
  final String? prompt;

  Map<String, Object?> toJson() => {
        'durationSeconds': durationSeconds,
        if (styleId != null) 'styleId': styleId,
        if (prompt != null) 'prompt': prompt,
        'segments': [
          for (final segment in segments)
            {'text': segment.text, 'start': segment.start, 'end': segment.end},
        ],
      };
}

class AiEditMusicDuckingSettings {
  const AiEditMusicDuckingSettings({
    this.enabled = true,
    this.musicVolumeDuringSpeech = 0.12,
  });

  final bool enabled;
  final double musicVolumeDuringSpeech;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'musicVolumeDuringSpeech': musicVolumeDuringSpeech,
      };
}

class AiEditMusicSettings {
  const AiEditMusicSettings({
    required this.source,
    this.genre,
    this.trackId,
    this.beatIntensity = 'balanced',
    this.volume = 0.25,
    this.ducking = const AiEditMusicDuckingSettings(),
  });

  final String source;
  final String? genre;
  final String? trackId;
  final String beatIntensity;
  final double volume;
  final AiEditMusicDuckingSettings ducking;

  Map<String, Object?> toJson() => {
        'source': source,
        if (genre != null) 'genre': genre,
        if (trackId != null) 'trackId': trackId,
        'beatIntensity': beatIntensity,
        'volume': volume,
        'ducking': ducking.toJson(),
      };
}

class AiEditPrepareSettings {
  const AiEditPrepareSettings({
    this.subtitleStyle,
    this.subtitleColor,
    this.subtitleWordsPerLine,
    this.subtitlePosition,
    this.ctaText,
    this.ctaDesign,
    this.priceText,
    this.watermarkText,
    this.toneFilter,
    this.zoomLevel,
    this.silencePreset,
    this.fillerWords,
    this.music,
  });

  final String? subtitleStyle;
  final String? subtitleColor;
  final int? subtitleWordsPerLine;
  final String? subtitlePosition;
  final String? ctaText;
  final String? ctaDesign;
  final String? priceText;
  final String? watermarkText;
  final String? toneFilter;
  final String? zoomLevel;
  final String? silencePreset;
  final List<String>? fillerWords;
  final AiEditMusicSettings? music;

  Map<String, Object?> toJson() => {
        if (subtitleStyle != null) 'subtitleStyle': subtitleStyle,
        if (subtitleColor != null) 'subtitleColor': subtitleColor,
        if (subtitleWordsPerLine != null)
          'subtitleWordsPerLine': subtitleWordsPerLine,
        if (subtitlePosition != null) 'subtitlePosition': subtitlePosition,
        if (ctaText != null) 'ctaText': ctaText,
        if (ctaDesign != null) 'ctaDesign': ctaDesign,
        if (priceText != null) 'priceText': priceText,
        if (watermarkText != null) 'watermarkText': watermarkText,
        if (toneFilter != null) 'toneFilter': toneFilter,
        if (zoomLevel != null) 'zoomLevel': zoomLevel,
        if (silencePreset != null) 'silencePreset': silencePreset,
        if (fillerWords != null) 'fillerWords': fillerWords,
        if (music != null) 'music': music!.toJson(),
      };
}

class AiEditPrepareRequest {
  const AiEditPrepareRequest({
    required this.videoS3Key,
    required this.durationSeconds,
    this.styleId,
    this.prompt,
    this.capabilities = const <String, bool>{},
    this.settings = const AiEditPrepareSettings(),
  });

  final String videoS3Key;
  final double durationSeconds;
  final String? styleId;
  final String? prompt;
  final Map<String, bool> capabilities;
  final AiEditPrepareSettings settings;

  Map<String, Object?> toJson() => {
        'videoS3Key': videoS3Key,
        'durationSeconds': durationSeconds,
        if (styleId != null) 'styleId': styleId,
        if (prompt != null) 'prompt': prompt,
        'capabilities': capabilities,
        'settings': settings.toJson(),
      };
}

class AiEditTranscriptWordResult {
  const AiEditTranscriptWordResult({
    required this.word,
    required this.start,
    required this.end,
  });

  final String word;
  final double start;
  final double end;

  factory AiEditTranscriptWordResult.fromJson(Map<String, Object?> json) {
    return AiEditTranscriptWordResult(
      word: json['word'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiEditTranscriptResult {
  const AiEditTranscriptResult({
    required this.text,
    required this.language,
    required this.durationSeconds,
    required this.segments,
    required this.words,
    required this.model,
  });

  final String text;
  final String language;
  final double durationSeconds;
  final List<ClipTranscriptSegment> segments;
  final List<AiEditTranscriptWordResult> words;
  final String model;

  factory AiEditTranscriptResult.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'];
    final rawWords = json['words'];

    return AiEditTranscriptResult(
      text: json['text'] as String? ?? '',
      language: json['language'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
      segments: rawSegments is List<dynamic>
          ? rawSegments
              .whereType<Map<String, Object?>>()
              .map(ClipTranscriptSegment.fromJson)
              .toList()
          : <ClipTranscriptSegment>[],
      words: rawWords is List<dynamic>
          ? rawWords
              .whereType<Map<String, Object?>>()
              .map(AiEditTranscriptWordResult.fromJson)
              .toList()
          : <AiEditTranscriptWordResult>[],
      model: json['model'] as String? ?? '',
    );
  }
}

class AiEditSubtitleStyleResult {
  const AiEditSubtitleStyleResult({
    required this.mode,
    required this.color,
    required this.wordsPerLine,
    required this.position,
  });

  final String mode;
  final String color;
  final int wordsPerLine;
  final String position;

  factory AiEditSubtitleStyleResult.fromJson(Map<String, Object?> json) {
    return AiEditSubtitleStyleResult(
      mode: json['mode'] as String? ?? 'bold',
      color: json['color'] as String? ?? '#FFFFFF',
      wordsPerLine: (json['wordsPerLine'] as num?)?.round() ?? 2,
      position: json['position'] as String? ?? 'bottom',
    );
  }
}

class AiEditSubtitlesResult {
  const AiEditSubtitlesResult({
    required this.enabled,
    required this.segments,
    required this.style,
  });

  final bool enabled;
  final List<ClipTranscriptSegment> segments;
  final AiEditSubtitleStyleResult style;

  factory AiEditSubtitlesResult.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'];
    final rawStyle = json['style'];

    return AiEditSubtitlesResult(
      enabled: json['enabled'] as bool? ?? false,
      segments: rawSegments is List<dynamic>
          ? rawSegments
              .whereType<Map<String, Object?>>()
              .map(ClipTranscriptSegment.fromJson)
              .toList()
          : <ClipTranscriptSegment>[],
      style: AiEditSubtitleStyleResult.fromJson(
        rawStyle is Map<String, Object?> ? rawStyle : const <String, Object?>{},
      ),
    );
  }
}

class AiEditCapabilityStatusResult {
  const AiEditCapabilityStatusResult({
    required this.enabled,
    required this.state,
    required this.message,
  });

  final bool enabled;
  final String state;
  final String message;

  bool get isApplied => state == 'applied';

  factory AiEditCapabilityStatusResult.fromJson(Map<String, Object?> json) {
    return AiEditCapabilityStatusResult(
      enabled: json['enabled'] as bool? ?? false,
      state: json['state'] as String? ?? 'skipped',
      message: json['message'] as String? ?? '',
    );
  }
}

class AiEditMusicDuckingResult {
  const AiEditMusicDuckingResult({
    required this.enabled,
    required this.musicVolumeDuringSpeech,
  });

  final bool enabled;
  final double musicVolumeDuringSpeech;

  factory AiEditMusicDuckingResult.fromJson(Map<String, Object?> json) {
    return AiEditMusicDuckingResult(
      enabled: json['enabled'] as bool? ?? true,
      musicVolumeDuringSpeech:
          (json['musicVolumeDuringSpeech'] as num?)?.toDouble() ??
              (json['speechVolume'] as num?)?.toDouble() ??
              0.12,
    );
  }
}

class AiEditMusicResult {
  const AiEditMusicResult({
    required this.source,
    required this.beatIntensity,
    required this.volume,
    required this.ducking,
    this.genre,
    this.trackId,
  });

  final String source;
  final String? genre;
  final String? trackId;
  final String beatIntensity;
  final double volume;
  final AiEditMusicDuckingResult ducking;

  factory AiEditMusicResult.fromJson(Map<String, Object?> json) {
    final rawDucking = json['ducking'];
    return AiEditMusicResult(
      source: json['source'] as String? ?? 'original',
      genre: json['genre'] as String?,
      trackId: json['trackId'] as String?,
      beatIntensity: json['beatIntensity'] as String? ?? 'balanced',
      volume: (json['volume'] as num?)?.toDouble() ?? 0.25,
      ducking: AiEditMusicDuckingResult.fromJson(
        rawDucking is Map<String, Object?>
            ? rawDucking
            : const <String, Object?>{},
      ),
    );
  }
}

class AiEditRecipeResult {
  const AiEditRecipeResult({
    required this.version,
    required this.status,
    required this.renderMode,
    required this.transcript,
    required this.subtitles,
    required this.cutRanges,
    required this.silenceRanges,
    required this.fillerRanges,
    required this.capabilities,
    this.music = const AiEditMusicResult(
      source: 'original',
      beatIntensity: 'balanced',
      volume: 0.25,
      ducking: AiEditMusicDuckingResult(
        enabled: true,
        musicVolumeDuringSpeech: 0.12,
      ),
    ),
    this.styleId,
    this.prompt,
  });

  final int version;
  final String status;
  final String renderMode;
  final String? styleId;
  final String? prompt;
  final AiEditTranscriptResult transcript;
  final AiEditSubtitlesResult subtitles;
  final List<AiEditCut> cutRanges;
  final List<AiEditCut> silenceRanges;
  final List<AiEditCut> fillerRanges;
  final AiEditMusicResult music;
  final Map<String, AiEditCapabilityStatusResult> capabilities;

  factory AiEditRecipeResult.fromJson(Map<String, Object?> json) {
    List<AiEditCut> parseRanges(Object? value) => value is List<dynamic>
        ? value
            .whereType<Map<String, Object?>>()
            .map(AiEditCut.fromJson)
            .toList()
        : <AiEditCut>[];

    final rawTranscript = json['transcript'];
    final rawSubtitles = json['subtitles'];
    final rawCapabilities = json['capabilities'];
    final rawMusic = json['music'];
    final capabilities = <String, AiEditCapabilityStatusResult>{};

    if (rawCapabilities is Map<String, Object?>) {
      for (final entry in rawCapabilities.entries) {
        final status = entry.value;
        if (status is Map<String, Object?>) {
          capabilities[entry.key] =
              AiEditCapabilityStatusResult.fromJson(status);
        }
      }
    }

    return AiEditRecipeResult(
      version: (json['version'] as num?)?.round() ?? 1,
      status: json['status'] as String? ?? '',
      renderMode: json['renderMode'] as String? ?? '',
      styleId: json['styleId'] as String?,
      prompt: json['prompt'] as String?,
      transcript: AiEditTranscriptResult.fromJson(
        rawTranscript is Map<String, Object?>
            ? rawTranscript
            : const <String, Object?>{},
      ),
      subtitles: AiEditSubtitlesResult.fromJson(
        rawSubtitles is Map<String, Object?>
            ? rawSubtitles
            : const <String, Object?>{},
      ),
      cutRanges: parseRanges(json['cutRanges']),
      silenceRanges: parseRanges(json['silenceRanges']),
      fillerRanges: parseRanges(json['fillerRanges']),
      music: AiEditMusicResult.fromJson(
        rawMusic is Map<String, Object?> ? rawMusic : const <String, Object?>{},
      ),
      capabilities: capabilities,
    );
  }
}

class AiEditPrepareResult {
  const AiEditPrepareResult({
    required this.recipe,
    required this.quota,
  });

  final AiEditRecipeResult recipe;
  final AiEditQuota quota;
}

class ClipTranscriptResult {
  const ClipTranscriptResult({
    required this.text,
    required this.segments,
    required this.durationSeconds,
  });

  final String text;
  final List<ClipTranscriptSegment> segments;
  final double durationSeconds;

  factory ClipTranscriptResult.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'];
    final segments = rawSegments is List<dynamic>
        ? rawSegments
            .whereType<Map<String, Object?>>()
            .map(ClipTranscriptSegment.fromJson)
            .toList()
        : <ClipTranscriptSegment>[];

    return ClipTranscriptResult(
      text: json['text'] as String? ?? '',
      segments: segments,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ApiHealthResult {
  const ApiHealthResult({
    required this.status,
    required this.service,
  });

  final String status;
  final String service;

  bool get isOk => status == 'ok';

  factory ApiHealthResult.fromJson(Map<String, Object?> json) =>
      ApiHealthResult(
        status: json['status'] as String,
        service: json['service'] as String,
      );
}

class PostDeeApiAuthHeaders {
  PostDeeApiAuthHeaders({
    AuthTokenProvider? authTokenProvider,
    this.mockUserId = AppConfig.mockUserId,
    this.mockSubscriptionPlan = AppConfig.mockSubscriptionPlan,
  }) : authTokenProvider = authTokenProvider ??
            PostDeeAuthSessionStore.instance.currentIdToken;

  final AuthTokenProvider authTokenProvider;
  final String mockUserId;
  final String mockSubscriptionPlan;

  Future<Map<String, String>> load() async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    // Dev-only subscription plan override. Sent alongside whichever auth method
    // is used so it also applies when signed in with a real token. The API
    // expects an uppercase plan code (e.g. PRO, STARTER). Empty in production.
    if (mockSubscriptionPlan.isNotEmpty) {
      headers['x-postdee-subscription-plan'] =
          mockSubscriptionPlan.trim().toUpperCase();
    }

    final token = (await authTokenProvider())?.trim();

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      return headers;
    }

    if (mockUserId.isNotEmpty) {
      headers['x-postdee-user-id'] = mockUserId;
    }

    return headers;
  }
}

class CreateUploadRequest {
  const CreateUploadRequest({
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class UploadResult {
  const UploadResult({
    required this.id,
    required this.videoS3Key,
    required this.storageProvider,
    this.uploadUrl,
    this.uploadMethod,
    this.uploadHeaders = const {},
    this.uploadExpiresAt,
  });

  final String id;
  final String videoS3Key;
  final String storageProvider;
  final String? uploadUrl;
  final String? uploadMethod;
  final Map<String, String> uploadHeaders;
  final DateTime? uploadExpiresAt;

  factory UploadResult.fromJson(Map<String, Object?> json) {
    final rawHeaders = json['uploadHeaders'];

    return UploadResult(
      id: json['id'] as String,
      videoS3Key: json['videoS3Key'] as String,
      storageProvider: json['storageProvider'] as String? ?? 'private',
      uploadUrl: json['uploadUrl'] as String?,
      uploadMethod: json['uploadMethod'] as String?,
      uploadHeaders: rawHeaders is Map
          ? rawHeaders.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      uploadExpiresAt: json['uploadExpiresAt'] is String
          ? DateTime.tryParse(json['uploadExpiresAt'] as String)
          : null,
    );
  }
}

class CreatePostRequest {
  const CreatePostRequest({
    required this.caption,
    required this.videoS3Key,
    required this.platforms,
    this.scheduledAt,
  });

  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final DateTime? scheduledAt;

  Map<String, Object?> toJson() => {
        'caption': caption,
        'videoS3Key': videoS3Key,
        'platforms': platforms,
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
      };
}

class GenerateCaptionRequest {
  const GenerateCaptionRequest({
    required this.keywords,
  });

  final List<String> keywords;

  Map<String, Object?> toJson() => {
        'keywords': keywords,
      };
}

class CaptionResult {
  const CaptionResult({
    required this.caption,
    required this.hashtags,
  });

  final String caption;
  final List<String> hashtags;

  factory CaptionResult.fromJson(Map<String, Object?> json) => CaptionResult(
        caption: json['caption'] as String,
        hashtags: (json['hashtags'] as List<dynamic>)
            .map((value) => '$value')
            .toList(),
      );
}

class GenerateRealClipCaptionRequest {
  const GenerateRealClipCaptionRequest({
    required this.videoS3Key,
    this.guidance,
    this.selectedFrameKeys = const [],
    this.deleteAfterUse = false,
  });

  final String videoS3Key;
  final String? guidance;
  final List<String> selectedFrameKeys;
  final bool deleteAfterUse;

  Map<String, Object?> toJson() => {
        'videoS3Key': videoS3Key,
        if (guidance != null && guidance!.trim().isNotEmpty)
          'guidance': guidance,
        if (selectedFrameKeys.isNotEmpty)
          'selectedFrameKeys': selectedFrameKeys,
        if (deleteAfterUse) 'deleteAfterUse': true,
      };
}

class RealClipCaptionContext {
  const RealClipCaptionContext({
    required this.selectedCaptionLanguage,
    required this.selectedTargetMarket,
    required this.selectedTone,
    required this.detectedSpokenLanguage,
    required this.suggestedCaptionLanguage,
    required this.suggestedTargetMarket,
  });

  static const fallback = RealClipCaptionContext(
    selectedCaptionLanguage: 'auto',
    selectedTargetMarket: 'auto',
    selectedTone: 'auto',
    detectedSpokenLanguage: 'auto',
    suggestedCaptionLanguage: 'auto',
    suggestedTargetMarket: 'auto',
  );

  final String selectedCaptionLanguage;
  final String selectedTargetMarket;
  final String selectedTone;
  final String detectedSpokenLanguage;
  final String suggestedCaptionLanguage;
  final String suggestedTargetMarket;

  factory RealClipCaptionContext.fromJson(Map<String, Object?> json) =>
      RealClipCaptionContext(
        selectedCaptionLanguage:
            json['selectedCaptionLanguage'] as String? ?? 'auto',
        selectedTargetMarket: json['selectedTargetMarket'] as String? ?? 'auto',
        selectedTone: json['selectedTone'] as String? ?? 'auto',
        detectedSpokenLanguage:
            json['detectedSpokenLanguage'] as String? ?? 'auto',
        suggestedCaptionLanguage:
            json['suggestedCaptionLanguage'] as String? ?? 'auto',
        suggestedTargetMarket:
            json['suggestedTargetMarket'] as String? ?? 'auto',
      );
}

class RealClipCaptionSource {
  const RealClipCaptionSource({
    required this.videoS3Key,
    required this.mode,
    required this.selectedFrameCount,
  });

  final String videoS3Key;
  final String mode;
  final int selectedFrameCount;

  factory RealClipCaptionSource.fromJson(Map<String, Object?> json) =>
      RealClipCaptionSource(
        videoS3Key: json['videoS3Key'] as String,
        mode: json['mode'] as String,
        selectedFrameCount: json['selectedFrameCount'] as int,
      );
}

class RealClipCaptionQuota {
  const RealClipCaptionQuota({
    required this.limit,
    required this.usedThisMonth,
    required this.remainingThisMonth,
  });

  final int limit;
  final int usedThisMonth;
  final int remainingThisMonth;

  factory RealClipCaptionQuota.fromJson(Map<String, Object?> json) =>
      RealClipCaptionQuota(
        limit: json['limit'] as int,
        usedThisMonth: json['usedThisMonth'] as int,
        remainingThisMonth: json['remainingThisMonth'] as int,
      );
}

class RealClipCaptionResult {
  const RealClipCaptionResult({
    required this.caption,
    required this.captionOptions,
    required this.hooks,
    required this.hashtags,
    required this.seoKeywords,
    required this.searchTitle,
    required this.source,
    required this.quota,
    this.context = RealClipCaptionContext.fallback,
  });

  final String caption;
  final List<String> captionOptions;
  final List<String> hooks;
  final List<String> hashtags;
  final List<String> seoKeywords;
  final String searchTitle;
  final RealClipCaptionSource source;
  final RealClipCaptionQuota quota;
  final RealClipCaptionContext context;

  factory RealClipCaptionResult.fromJson(Map<String, Object?> json) {
    final source = json['source'];
    final quota = json['quota'];

    if (source is! Map<String, Object?>) {
      throw const ApiException('Real-clip caption response is missing source');
    }

    if (quota is! Map<String, Object?>) {
      throw const ApiException('Real-clip caption response is missing quota');
    }

    final context = json['context'];

    return RealClipCaptionResult(
      caption: json['caption'] as String,
      captionOptions: _readStringList(json['captionOptions']),
      hooks: _readStringList(json['hooks']),
      hashtags: _readStringList(json['hashtags']),
      seoKeywords: _readStringList(json['seoKeywords']),
      searchTitle: json['searchTitle'] as String,
      source: RealClipCaptionSource.fromJson(source),
      quota: RealClipCaptionQuota.fromJson(quota),
      context: context is Map<String, Object?>
          ? RealClipCaptionContext.fromJson(context)
          : RealClipCaptionContext.fallback,
    );
  }
}

List<String> _readStringList(Object? value) {
  if (value is! List<dynamic>) {
    throw const ApiException('API response is missing a list value');
  }

  return value.map((item) => '$item').toList();
}

class CreateTemplateRequest {
  const CreateTemplateRequest({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  Map<String, Object?> toJson() => {
        'title': title,
        'body': body,
      };
}

class TextTemplateResult {
  const TextTemplateResult({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  factory TextTemplateResult.fromJson(Map<String, Object?> json) =>
      TextTemplateResult(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class PlatformAnalyticsResult {
  const PlatformAnalyticsResult({
    required this.platform,
    required this.label,
    required this.views,
    required this.likes,
  });

  final String platform;
  final String label;
  final int views;
  final int likes;

  factory PlatformAnalyticsResult.fromJson(Map<String, Object?> json) =>
      PlatformAnalyticsResult(
        platform: json['platform'] as String,
        label: json['label'] as String,
        views: json['views'] as int,
        likes: json['likes'] as int,
      );
}

class DailyAnalyticsResult {
  const DailyAnalyticsResult({
    required this.date,
    required this.views,
    required this.likes,
  });

  final DateTime date;
  final int views;
  final int likes;

  factory DailyAnalyticsResult.fromJson(Map<String, Object?> json) =>
      DailyAnalyticsResult(
        date: DateTime.parse(json['date'] as String),
        views: json['views'] as int,
        likes: json['likes'] as int,
      );
}

class AnalyticsSummaryResult {
  const AnalyticsSummaryResult({
    required this.totalViews,
    required this.totalLikes,
    required this.platforms,
    this.range = '30d',
    this.daily = const [],
  });

  final String range;
  final int totalViews;
  final int totalLikes;
  final List<PlatformAnalyticsResult> platforms;
  final List<DailyAnalyticsResult> daily;

  factory AnalyticsSummaryResult.fromJson(Map<String, Object?> json) {
    final platforms = json['platforms'];

    if (platforms is! List<dynamic>) {
      throw const ApiException(
          'Analytics response is missing platform metrics');
    }

    return AnalyticsSummaryResult(
      range: json['range'] as String? ?? '30d',
      totalViews: json['totalViews'] as int,
      totalLikes: json['totalLikes'] as int,
      platforms: platforms
          .map((platform) => PlatformAnalyticsResult.fromJson(
              platform as Map<String, Object?>))
          .toList(),
      daily: (json['daily'] as List<dynamic>? ?? const [])
          .map((metric) =>
              DailyAnalyticsResult.fromJson(metric as Map<String, Object?>))
          .toList(),
    );
  }
}

class SubscriptionStatusResult {
  const SubscriptionStatusResult({
    required this.userId,
    required this.plan,
    required this.status,
    this.monthlyPostLimit,
    this.usedPostsThisMonth,
    this.remainingPostsThisMonth,
    required this.canSchedule,
    required this.canUseAiCaptions,
    required this.canUseAnalytics,
    this.phoneVerified = false,
    this.requiresPhoneVerification = false,
    this.canUseFreePostQuota = false,
    this.canUseAiAudioReview = false,
    this.canUseAiVideoReview = false,
  });

  final String userId;
  final String plan;
  final String status;
  final int? monthlyPostLimit;
  final int? usedPostsThisMonth;
  final int? remainingPostsThisMonth;
  final bool canSchedule;
  final bool canUseAiCaptions;
  final bool canUseAnalytics;
  final bool phoneVerified;
  final bool requiresPhoneVerification;
  final bool canUseFreePostQuota;
  final bool canUseAiAudioReview;
  final bool canUseAiVideoReview;

  bool get isStarter => plan == 'STARTER';
  bool get isPro => plan == 'PRO';

  factory SubscriptionStatusResult.fromJson(Map<String, Object?> json) =>
      SubscriptionStatusResult(
        userId: json['userId'] as String,
        plan: json['plan'] as String,
        status: json['status'] as String,
        monthlyPostLimit: json['monthlyPostLimit'] as int?,
        usedPostsThisMonth: json['usedPostsThisMonth'] as int?,
        remainingPostsThisMonth: json['remainingPostsThisMonth'] as int?,
        phoneVerified: json['phoneVerified'] as bool? ?? false,
        requiresPhoneVerification:
            json['requiresPhoneVerification'] as bool? ?? false,
        canUseFreePostQuota: json['canUseFreePostQuota'] as bool? ?? false,
        canSchedule: json['canSchedule'] as bool,
        canUseAiCaptions: json['canUseAiCaptions'] as bool,
        canUseAnalytics: json['canUseAnalytics'] as bool,
        canUseAiAudioReview: json['canUseAiAudioReview'] as bool? ?? false,
        canUseAiVideoReview: json['canUseAiVideoReview'] as bool? ?? false,
      );
}

class VerifyStorePurchaseRequest {
  const VerifyStorePurchaseRequest({
    required this.platform,
    this.productId = AppConfig.storeProMonthlyProductId,
    this.purchaseToken,
    this.transactionId,
  });

  const VerifyStorePurchaseRequest.android({
    required String purchaseToken,
    String productId = AppConfig.storeProMonthlyProductId,
  }) : this(
          platform: 'ANDROID',
          productId: productId,
          purchaseToken: purchaseToken,
        );

  const VerifyStorePurchaseRequest.ios({
    required String transactionId,
    String productId = AppConfig.storeProMonthlyProductId,
  }) : this(
          platform: 'IOS',
          productId: productId,
          transactionId: transactionId,
        );

  final String platform;
  final String productId;
  final String? purchaseToken;
  final String? transactionId;

  Map<String, Object?> toJson() => {
        'platform': platform,
        'productId': productId,
        if (purchaseToken != null) 'purchaseToken': purchaseToken,
        if (transactionId != null) 'transactionId': transactionId,
      };
}

class StorePurchaseResult {
  const StorePurchaseResult({
    required this.provider,
    required this.platform,
    required this.productId,
    required this.verifiedAt,
    this.purchaseToken,
    this.transactionId,
  });

  final String provider;
  final String platform;
  final String productId;
  final DateTime verifiedAt;
  final String? purchaseToken;
  final String? transactionId;

  factory StorePurchaseResult.fromJson(Map<String, Object?> json) =>
      StorePurchaseResult(
        provider: json['provider'] as String,
        platform: json['platform'] as String,
        productId: json['productId'] as String,
        verifiedAt: DateTime.parse(json['verifiedAt'] as String),
        purchaseToken: json['purchaseToken'] as String?,
        transactionId: json['transactionId'] as String?,
      );
}

class StoreSubscriptionVerificationResult {
  const StoreSubscriptionVerificationResult({
    required this.purchase,
    required this.subscription,
  });

  final StorePurchaseResult purchase;
  final SubscriptionStatusResult subscription;

  factory StoreSubscriptionVerificationResult.fromJson(
    Map<String, Object?> json,
  ) {
    final purchase = json['purchase'];
    final subscription = json['subscription'];

    if (purchase is! Map<String, Object?>) {
      throw const ApiException('Store response is missing purchase data');
    }

    if (subscription is! Map<String, Object?>) {
      throw const ApiException('Store response is missing subscription data');
    }

    return StoreSubscriptionVerificationResult(
      purchase: StorePurchaseResult.fromJson(purchase),
      subscription: SubscriptionStatusResult.fromJson(subscription),
    );
  }
}

class QueuedPostResult {
  const QueuedPostResult({
    required this.id,
    required this.videoS3Key,
    required this.platforms,
    required this.status,
  });

  final String id;
  final String videoS3Key;
  final List<String> platforms;
  final String status;

  factory QueuedPostResult.fromJson(Map<String, Object?> json) =>
      QueuedPostResult(
        id: json['id'] as String,
        videoS3Key: json['videoS3Key'] as String,
        platforms: (json['platforms'] as List<dynamic>)
            .map((value) => '$value')
            .toList(),
        status: json['status'] as String,
      );
}

class ScheduledPostResult {
  const ScheduledPostResult({
    required this.id,
    required this.caption,
    required this.videoS3Key,
    required this.platforms,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final DateTime scheduledAt;
  final String status;
  final DateTime createdAt;

  factory ScheduledPostResult.fromJson(Map<String, Object?> json) {
    final scheduledAt = json['scheduledAt'];
    final createdAt = json['createdAt'];

    if (scheduledAt is! String || scheduledAt.trim().isEmpty) {
      throw const ApiException('Scheduled post is missing scheduledAt');
    }

    if (createdAt is! String || createdAt.trim().isEmpty) {
      throw const ApiException('Scheduled post is missing createdAt');
    }

    return ScheduledPostResult(
      id: json['id'] as String,
      caption: json['caption'] as String,
      videoS3Key: json['videoS3Key'] as String,
      platforms: (json['platforms'] as List<dynamic>)
          .map((value) => '$value')
          .toList(),
      scheduledAt: DateTime.parse(scheduledAt),
      status: json['status'] as String,
      createdAt: DateTime.parse(createdAt),
    );
  }
}

/// A post in any state (queued, publishing, published, failed). Unlike
/// [ScheduledPostResult] the schedule and publish times are optional so it also
/// represents post-now items, which the Home dashboard lists as latest posts.
class PostSummaryResult {
  const PostSummaryResult({
    required this.id,
    required this.caption,
    required this.videoS3Key,
    required this.platforms,
    required this.status,
    required this.createdAt,
    this.scheduledAt,
    this.publishedAt,
  });

  final String id;
  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final String status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;

  factory PostSummaryResult.fromJson(Map<String, Object?> json) {
    DateTime? parseDate(Object? value) =>
        value is String && value.trim().isNotEmpty
            ? DateTime.tryParse(value)
            : null;

    final createdAt = parseDate(json['createdAt']);

    if (createdAt == null) {
      throw const ApiException('Post is missing createdAt');
    }

    return PostSummaryResult(
      id: json['id'] as String,
      caption: json['caption'] as String? ?? '',
      videoS3Key: json['videoS3Key'] as String? ?? '',
      platforms: (json['platforms'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .toList(),
      status: json['status'] as String? ?? '',
      createdAt: createdAt,
      scheduledAt: parseDate(json['scheduledAt']),
      publishedAt: parseDate(json['publishedAt']),
    );
  }
}

class SocialConnectionResult {
  const SocialConnectionResult({
    required this.platform,
    required this.connected,
    this.displayName,
    this.externalAccountId,
    this.connectedAt,
  });

  final String platform;
  final bool connected;
  final String? displayName;
  final String? externalAccountId;
  final DateTime? connectedAt;

  factory SocialConnectionResult.fromJson(Map<String, Object?> json) =>
      SocialConnectionResult(
        platform: json['platform'] as String,
        connected: json['connected'] as bool? ?? false,
        displayName: json['displayName'] as String?,
        externalAccountId: json['externalAccountId'] as String?,
        connectedAt: json['connectedAt'] is String
            ? DateTime.tryParse(json['connectedAt'] as String)
            : null,
      );
}

class SocialConnectLinkResult {
  const SocialConnectLinkResult({
    required this.connectUrl,
    this.expiresAt,
  });

  final Uri connectUrl;
  final DateTime? expiresAt;

  factory SocialConnectLinkResult.fromJson(Map<String, Object?> json) =>
      SocialConnectLinkResult(
        connectUrl: Uri.parse(json['connectUrl'] as String),
        expiresAt: json['expiresAt'] is String
            ? DateTime.tryParse(json['expiresAt'] as String)
            : null,
      );
}

class PostDeeApiClient {
  PostDeeApiClient({
    HttpClient? httpClient,
    String baseUrl = AppConfig.apiBaseUrl,
    AuthTokenProvider? authTokenProvider,
    PostDeeApiAuthHeaders? authHeaders,
  })  : _customHttpClient = httpClient,
        _baseUri = Uri.parse(baseUrl),
        _authHeaders = authHeaders ??
            PostDeeApiAuthHeaders(
              authTokenProvider: authTokenProvider,
            );

  final HttpClient? _customHttpClient;
  HttpClient? _lazyHttpClient;
  HttpClient get _httpClient =>
      _customHttpClient ?? (_lazyHttpClient ??= _createHttpClientSafe());

  static HttpClient _createHttpClientSafe() {
    try {
      return HttpClient();
    } catch (_) {
      throw const ApiException(
          'Network requests are not supported on this platform without a custom client.');
    }
  }

  final Uri _baseUri;
  final PostDeeApiAuthHeaders _authHeaders;

  Future<ApiHealthResult> checkHealth() async {
    final response = await _getJson('/health');

    return ApiHealthResult.fromJson(response);
  }

  Future<UploadResult> createUpload(CreateUploadRequest request) async {
    final response = await _postJson('/uploads', request.toJson());
    final upload = response['upload'];

    if (upload is! Map<String, Object?>) {
      throw const ApiException('Upload response is missing upload data');
    }

    return UploadResult.fromJson(upload);
  }

  Future<QueuedPostResult> createPost(CreatePostRequest request) async {
    final response = await _postJson('/posts', request.toJson());
    final post = response['post'];

    if (post is! Map<String, Object?>) {
      throw const ApiException('Post response is missing post data');
    }

    return QueuedPostResult.fromJson(post);
  }

  Future<ScheduledPostResult> reschedulePost(
      String postId, DateTime scheduledAt) async {
    final response = await _patchJson('/posts/$postId', {
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    });
    final post = response['post'];

    if (post is! Map<String, Object?>) {
      throw const ApiException('Reschedule response is missing post data');
    }

    return ScheduledPostResult.fromJson(post);
  }

  Future<void> cancelPost(String postId) async {
    await _deleteJson('/posts/$postId');
  }

  /// Permanently deletes the signed-in user's account and all of their data.
  /// Backed by `DELETE /account`. Used by the profile account-deletion flow.
  Future<void> deleteAccount() async {
    await _deleteJson('/account');
  }

  /// Registers this device's FCM token so the backend can target it with push
  /// notifications. Backed by `POST /devices`.
  Future<void> registerDeviceToken(String token, {String? platform}) async {
    await _postJson('/devices', {
      'token': token,
      if (platform != null) 'platform': platform,
    });
  }
  Future<List<SocialConnectionResult>> listSocialConnections() async {
    final response = await _getJson('/social-connections');
    final connections = response['connections'];

    if (connections is! List<dynamic>) {
      throw const ApiException(
          'Social connections response is missing connections');
    }

    return connections
        .map((connection) => SocialConnectionResult.fromJson(
            connection as Map<String, Object?>))
        .toList();
  }

  Future<SocialConnectLinkResult> createSocialConnectionLink(
      String platform) async {
    final response =
        await _postJson('/social-connections/$platform/connect', {});

    return SocialConnectLinkResult.fromJson(response);
  }

  Future<void> disconnectSocialConnection(String platform) async {
    await _deleteJson('/social-connections/$platform');
  }

  Future<List<SocialConnectionResult>> refreshSocialConnections() async {
    final response = await _postJson('/social-connections/refresh', {});
    final connections = response['connections'];

    if (connections is! List<dynamic>) {
      throw const ApiException(
          'Social connections response is missing connections');
    }

    return connections
        .map((connection) => SocialConnectionResult.fromJson(
            connection as Map<String, Object?>))
        .toList();
  }

  Future<AiEditQuota> fetchAiEditQuota() async {
    final response = await _getJson('/ai-edits/quota');
    final quota = response['quota'];

    if (quota is! Map<String, Object?>) {
      throw const ApiException('Quota response is missing quota data');
    }

    return AiEditQuota.fromJson(quota);
  }

  Future<ClipTranscriptResult> transcribeClip(String videoS3Key) async {
    final response = await _postJson('/ai-edits/transcribe', {
      'videoS3Key': videoS3Key,
    });
    final transcript = response['transcript'];

    if (transcript is! Map<String, Object?>) {
      throw const ApiException(
          'Transcription response is missing transcript data');
    }

    return ClipTranscriptResult.fromJson(transcript);
  }

  Future<AiEditPrepareResult> prepareAiEdit(
    AiEditPrepareRequest request,
  ) async {
    final response = await _postJson('/ai-edits/prepare', request.toJson());
    final recipe = response['recipe'];
    final quota = response['quota'];

    if (recipe is! Map<String, Object?>) {
      throw const ApiException(
          'AI edit prepare response is missing recipe data');
    }

    if (quota is! Map<String, Object?>) {
      throw const ApiException(
          'AI edit prepare response is missing quota data');
    }

    return AiEditPrepareResult(
      recipe: AiEditRecipeResult.fromJson(recipe),
      quota: AiEditQuota.fromJson(quota),
    );
  }

  Future<AiEditPlanResult> requestAiEditPlan(AiEditPlanRequest request) async {
    final response = await _postJson('/ai-edits/plan', request.toJson());
    final plan = response['plan'];

    if (plan is! Map<String, Object?>) {
      throw const ApiException('AI edit plan response is missing plan data');
    }

    return AiEditPlanResult.fromJson(plan);
  }

  Future<List<ScheduledPostResult>> listScheduledPosts() async {
    final response = await _getJson('/posts?scheduled=true');
    final posts = response['posts'];

    if (posts is! List<dynamic>) {
      throw const ApiException(
          'Scheduled posts response is missing posts data');
    }

    return posts
        .map((post) =>
            ScheduledPostResult.fromJson(post as Map<String, Object?>))
        .toList();
  }

  /// Lists the user's posts (any state), newest first, limited to [limit].
  /// Used by the Home dashboard's latest-post list.
  Future<List<PostSummaryResult>> listRecentPosts({int limit = 3}) async {
    final response = await _getJson('/posts');
    final posts = response['posts'];

    if (posts is! List<dynamic>) {
      throw const ApiException('Posts response is missing posts data');
    }

    final parsed = posts
        .map((post) => PostSummaryResult.fromJson(post as Map<String, Object?>))
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    if (limit > 0 && parsed.length > limit) {
      return parsed.sublist(0, limit);
    }

    return parsed;
  }

  Future<CaptionResult> generateCaption(List<String> keywords) async {
    final response = await _postJson(
      '/captions/generate',
      GenerateCaptionRequest(keywords: keywords).toJson(),
    );

    return CaptionResult.fromJson(response);
  }

  Future<RealClipCaptionResult> generateCaptionFromClip(
    GenerateRealClipCaptionRequest request,
  ) async {
    final response = await _postJson(
      '/captions/generate-from-clip',
      request.toJson(),
    );

    return RealClipCaptionResult.fromJson(response);
  }

  Future<List<TextTemplateResult>> listTemplates() async {
    final response = await _getJson('/templates');
    final templates = response['templates'];

    if (templates is! List<dynamic>) {
      throw const ApiException('Templates response is missing templates data');
    }

    return templates
        .map((template) =>
            TextTemplateResult.fromJson(template as Map<String, Object?>))
        .toList();
  }

  Future<TextTemplateResult> createTemplate({
    required String title,
    required String body,
  }) async {
    final response = await _postJson(
      '/templates',
      CreateTemplateRequest(title: title, body: body).toJson(),
    );
    final template = response['template'];

    if (template is! Map<String, Object?>) {
      throw const ApiException('Template response is missing template data');
    }

    return TextTemplateResult.fromJson(template);
  }

  Future<AnalyticsSummaryResult> loadAnalyticsSummary({
    String range = '30d',
  }) async {
    final response = await _getJson('/analytics/summary?range=$range');
    final summary = response['summary'];

    if (summary is! Map<String, Object?>) {
      throw const ApiException('Analytics response is missing summary data');
    }

    return AnalyticsSummaryResult.fromJson(summary);
  }

  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    final response = await _getJson('/billing/subscription');
    final subscription = response['subscription'];

    if (subscription is! Map<String, Object?>) {
      throw const ApiException(
          'Subscription response is missing subscription data');
    }

    return SubscriptionStatusResult.fromJson(subscription);
  }

  Future<StoreSubscriptionVerificationResult> verifyStoreSubscription(
    VerifyStorePurchaseRequest request,
  ) async {
    final response = await _postJson(
      '/billing/store/verify',
      request.toJson(),
    );

    return StoreSubscriptionVerificationResult.fromJson(response);
  }

  Future<void> uploadVideoFile(UploadResult upload, File videoFile) async {
    if (upload.uploadUrl == null) {
      return;
    }

    if (upload.uploadMethod != null && upload.uploadMethod != 'PUT') {
      throw ApiException('Unsupported upload method: ${upload.uploadMethod}');
    }

    final request = await _httpClient.putUrl(Uri.parse(upload.uploadUrl!));

    for (final header in upload.uploadHeaders.entries) {
      request.headers.set(header.key, header.value);
    }

    request.contentLength = await videoFile.length();
    await request.addStream(videoFile.openRead());

    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.transform(utf8.decoder).join();
      throw ApiException(
        responseBody.isEmpty ? 'Video upload failed' : responseBody,
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, Object?>> _postJson(
      String path, Map<String, Object?> body) async {
    final request = await _httpClient.postUrl(_baseUri.resolve(path));
    request.headers.contentType = ContentType.json;
    await _setDefaultHeaders(request);

    request.write(jsonEncode(body));

    return _readJsonResponse(request);
  }

  Future<Map<String, Object?>> _getJson(String path) async {
    final request = await _httpClient.getUrl(_baseUri.resolve(path));
    await _setDefaultHeaders(request);

    return _readJsonResponse(request);
  }

  Future<Map<String, Object?>> _patchJson(
      String path, Map<String, Object?> body) async {
    final request = await _httpClient.patchUrl(_baseUri.resolve(path));
    request.headers.contentType = ContentType.json;
    await _setDefaultHeaders(request);

    request.write(jsonEncode(body));

    return _readJsonResponse(request);
  }

  Future<Map<String, Object?>> _deleteJson(String path) async {
    final request = await _httpClient.deleteUrl(_baseUri.resolve(path));
    await _setDefaultHeaders(request);

    return _readJsonResponse(request);
  }

  Future<void> _setDefaultHeaders(HttpClientRequest request) async {
    final headers = await _authHeaders.load();

    for (final header in headers.entries) {
      request.headers.set(header.key, header.value);
    }
  }

  Future<Map<String, Object?>> _readJsonResponse(
      HttpClientRequest request) async {
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    final decoded =
        responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);

    if (decoded is! Map<String, Object?>) {
      throw ApiException('Unexpected API response',
          statusCode: response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        decoded['message'] as String? ?? 'Request failed',
        statusCode: response.statusCode,
        code: decoded['code'] as String?,
      );
    }

    return decoded;
  }
}
