import 'dart:convert';
import 'dart:io';

import '../auth/auth_session.dart';
import '../config/app_config.dart';

const socialPublishingUnavailableCode = 'SOCIAL_PUBLISHING_UNAVAILABLE';
const platformSettingsUnsupportedCode = 'PLATFORM_SETTINGS_UNSUPPORTED';
const scheduledPostNotFoundCode = 'SCHEDULED_POST_NOT_FOUND';
const publishQueueUnavailableCode = 'PUBLISH_QUEUE_UNAVAILABLE';
const idempotentPostFailedCode = 'IDEMPOTENT_POST_FAILED';
const idempotencyKeyReusedCode = 'IDEMPOTENCY_KEY_REUSED';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code, this.postId});

  final String message;
  final int? statusCode;
  final String? code;
  final String? postId;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

typedef AuthTokenProvider = Future<String?> Function();

class ClipTranscriptSegment {
  const ClipTranscriptSegment({
    required this.text,
    required this.start,
    required this.end,
    this.words,
    this.avgLogprob,
    this.noSpeechProbability,
    this.compressionRatio,
  });

  final String text;
  final double start;
  final double end;
  final List<AiEditTranscriptWordResult>? words;
  final double? avgLogprob;
  final double? noSpeechProbability;
  final double? compressionRatio;

  factory ClipTranscriptSegment.fromJson(Map<String, Object?> json) {
    final hasValidatedWords = json.containsKey('words');
    return ClipTranscriptSegment(
      text: json['text'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
      words:
          hasValidatedWords ? _readValidatedSubtitleWords(json['words']) : null,
      avgLogprob: (json['avgLogprob'] as num?)?.toDouble(),
      noSpeechProbability: (json['noSpeechProbability'] as num?)?.toDouble(),
      compressionRatio: (json['compressionRatio'] as num?)?.toDouble(),
    );
  }
}

List<AiEditTranscriptWordResult> _readValidatedSubtitleWords(Object? rawWords) {
  if (rawWords is! List<dynamic>) {
    return const <AiEditTranscriptWordResult>[];
  }

  final words = <AiEditTranscriptWordResult>[];
  for (final rawWord in rawWords) {
    if (rawWord is! Map<String, Object?>) {
      return const <AiEditTranscriptWordResult>[];
    }
    final word = rawWord['word'];
    final rawStart = rawWord['start'];
    final rawEnd = rawWord['end'];
    if (word is! String || rawStart is! num || rawEnd is! num) {
      return const <AiEditTranscriptWordResult>[];
    }
    final start = rawStart.toDouble();
    final end = rawEnd.toDouble();
    if (!start.isFinite || !end.isFinite) {
      return const <AiEditTranscriptWordResult>[];
    }
    words.add(
      AiEditTranscriptWordResult(word: word, start: start, end: end),
    );
  }
  return List<AiEditTranscriptWordResult>.unmodifiable(words);
}

List<ClipTranscriptSegment> _readStrictBoundarySegments(
  Object? rawSegments, {
  required double durationSeconds,
}) {
  if (rawSegments is! List<dynamic> ||
      !durationSeconds.isFinite ||
      durationSeconds <= 0) {
    return const <ClipTranscriptSegment>[];
  }

  final segments = <ClipTranscriptSegment>[];
  for (final rawSegment in rawSegments) {
    if (rawSegment is! Map<String, Object?>) {
      return const <ClipTranscriptSegment>[];
    }
    final text = rawSegment['text'];
    final rawStart = rawSegment['start'];
    final rawEnd = rawSegment['end'];
    if (text is! String ||
        text.trim().isEmpty ||
        rawStart is! num ||
        rawEnd is! num) {
      return const <ClipTranscriptSegment>[];
    }
    final start = rawStart.toDouble();
    final end = rawEnd.toDouble();
    if (!start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start ||
        end > durationSeconds) {
      return const <ClipTranscriptSegment>[];
    }

    final metrics = <String, double?>{};
    for (final key in const [
      'avgLogprob',
      'noSpeechProbability',
      'compressionRatio',
    ]) {
      final rawMetric = rawSegment[key];
      if (rawMetric != null && rawMetric is! num) {
        return const <ClipTranscriptSegment>[];
      }
      final metric = rawMetric is num ? rawMetric.toDouble() : null;
      if (metric != null && !metric.isFinite) {
        return const <ClipTranscriptSegment>[];
      }
      metrics[key] = metric;
    }

    List<AiEditTranscriptWordResult>? words;
    if (rawSegment.containsKey('words')) {
      final rawWords = rawSegment['words'];
      if (rawWords is! List<dynamic>) {
        return const <ClipTranscriptSegment>[];
      }
      words = _readValidatedSubtitleWords(rawWords);
      if (words.length != rawWords.length ||
          words.any((word) =>
              word.word.trim().isEmpty ||
              word.start < start ||
              word.end <= word.start ||
              word.end > end)) {
        return const <ClipTranscriptSegment>[];
      }
    }

    segments.add(
      ClipTranscriptSegment(
        text: text,
        start: start,
        end: end,
        words: words,
        avgLogprob: metrics['avgLogprob'],
        noSpeechProbability: metrics['noSpeechProbability'],
        compressionRatio: metrics['compressionRatio'],
      ),
    );
  }
  return List<ClipTranscriptSegment>.unmodifiable(segments);
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

class AiEditSpeechReductionGroupResult {
  const AiEditSpeechReductionGroupResult({
    required this.id,
    required this.text,
    required this.normalizedText,
    required this.totalOccurrences,
    required this.occurrenceIds,
  });

  final String id;
  final String text;
  final String normalizedText;
  final int totalOccurrences;
  final List<String> occurrenceIds;

  factory AiEditSpeechReductionGroupResult.fromJson(
    Map<String, Object?> json,
  ) {
    final rawOccurrenceIds = json['occurrenceIds'];
    final parsedTotal = (json['totalOccurrences'] as num?)?.round() ?? 0;
    return AiEditSpeechReductionGroupResult(
      id: (json['id'] as String? ?? '').trim(),
      text: (json['text'] as String? ?? '').trim(),
      normalizedText: (json['normalizedText'] as String? ?? '').trim(),
      totalOccurrences: parsedTotal < 0 ? 0 : parsedTotal,
      occurrenceIds: rawOccurrenceIds is List<dynamic>
          ? rawOccurrenceIds
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }
}

class AiEditSpeechReductionOccurrenceResult {
  const AiEditSpeechReductionOccurrenceResult({
    required this.id,
    required this.groupId,
    required this.text,
    required this.normalizedText,
    required this.start,
    required this.end,
    required this.occurrenceIndex,
    required this.occurrenceCount,
    required this.kind,
    required this.recommendation,
    required this.selectedByDefault,
    required this.confidence,
    required this.contextBefore,
    required this.contextAfter,
    required this.canAutoRemove,
  });

  final String id;
  final String groupId;
  final String text;
  final String normalizedText;
  final double start;
  final double end;
  final int occurrenceIndex;
  final int occurrenceCount;
  final String kind;
  final String recommendation;
  final bool selectedByDefault;
  final double confidence;
  final String contextBefore;
  final String contextAfter;
  final bool canAutoRemove;

  factory AiEditSpeechReductionOccurrenceResult.fromJson(
    Map<String, Object?> json,
  ) {
    const supportedKinds = {
      'adjacent-word',
      'adjacent-phrase',
      'frequent-only',
    };
    final rawKind = json['kind'] as String? ?? '';
    final hasSupportedKind = supportedKinds.contains(rawKind);
    final kind = hasSupportedKind ? rawKind : 'frequent-only';
    final canAutoRemove = hasSupportedKind &&
        kind != 'frequent-only' &&
        (json['canAutoRemove'] as bool? ?? false);
    final rawConfidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    final confidence =
        rawConfidence.isFinite ? rawConfidence.clamp(0.0, 1.0).toDouble() : 0.0;
    final rawOccurrenceIndex = (json['occurrenceIndex'] as num?)?.round() ?? 0;
    final rawOccurrenceCount = (json['occurrenceCount'] as num?)?.round() ?? 0;

    return AiEditSpeechReductionOccurrenceResult(
      id: (json['id'] as String? ?? '').trim(),
      groupId: (json['groupId'] as String? ?? '').trim(),
      text: (json['text'] as String? ?? '').trim(),
      normalizedText: (json['normalizedText'] as String? ?? '').trim(),
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
      occurrenceIndex: rawOccurrenceIndex < 0 ? 0 : rawOccurrenceIndex,
      occurrenceCount: rawOccurrenceCount < 0 ? 0 : rawOccurrenceCount,
      kind: kind,
      recommendation:
          canAutoRemove && json['recommendation'] == 'cut' ? 'cut' : 'keep',
      selectedByDefault:
          canAutoRemove && (json['selectedByDefault'] as bool? ?? false),
      confidence: confidence,
      contextBefore: json['contextBefore'] as String? ?? '',
      contextAfter: json['contextAfter'] as String? ?? '',
      canAutoRemove: canAutoRemove,
    );
  }
}

class AiEditSpeechReductionCutResult {
  const AiEditSpeechReductionCutResult({
    required this.occurrenceId,
    required this.start,
    required this.end,
  });

  final String occurrenceId;
  final double start;
  final double end;

  factory AiEditSpeechReductionCutResult.fromJson(
    Map<String, Object?> json,
  ) {
    return AiEditSpeechReductionCutResult(
      occurrenceId: (json['occurrenceId'] as String? ?? '').trim(),
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiEditSpeechReductionResult {
  const AiEditSpeechReductionResult({
    required this.version,
    required this.status,
    required this.groups,
    required this.occurrences,
    required this.defaultCutRanges,
    this.unavailableReason,
  });

  const AiEditSpeechReductionResult.unavailable({
    this.unavailableReason,
  })  : version = 1,
        status = 'unavailable',
        groups = const <AiEditSpeechReductionGroupResult>[],
        occurrences = const <AiEditSpeechReductionOccurrenceResult>[],
        defaultCutRanges = const <AiEditSpeechReductionCutResult>[];

  final int version;
  final String status;
  final String? unavailableReason;
  final List<AiEditSpeechReductionGroupResult> groups;
  final List<AiEditSpeechReductionOccurrenceResult> occurrences;
  final List<AiEditSpeechReductionCutResult> defaultCutRanges;

  bool get isReady => status == 'ready';

  factory AiEditSpeechReductionResult.fromJson(Map<String, Object?> json) {
    final status = json['status'] as String?;
    final unavailableReason = json['unavailableReason'] as String?;
    if (status != 'ready') {
      return AiEditSpeechReductionResult.unavailable(
        unavailableReason: unavailableReason,
      );
    }

    final rawGroups = json['groups'];
    final rawOccurrences = json['occurrences'];
    final rawDefaultCutRanges = json['defaultCutRanges'];
    final parsedVersion = (json['version'] as num?)?.round() ?? 1;

    return AiEditSpeechReductionResult(
      version: parsedVersion < 1 ? 1 : parsedVersion,
      status: 'ready',
      unavailableReason: unavailableReason,
      groups: rawGroups is List<dynamic>
          ? rawGroups
              .whereType<Map<String, Object?>>()
              .map(AiEditSpeechReductionGroupResult.fromJson)
              .toList(growable: false)
          : const <AiEditSpeechReductionGroupResult>[],
      occurrences: rawOccurrences is List<dynamic>
          ? rawOccurrences
              .whereType<Map<String, Object?>>()
              .map(AiEditSpeechReductionOccurrenceResult.fromJson)
              .toList(growable: false)
          : const <AiEditSpeechReductionOccurrenceResult>[],
      defaultCutRanges: rawDefaultCutRanges is List<dynamic>
          ? rawDefaultCutRanges
              .whereType<Map<String, Object?>>()
              .map(AiEditSpeechReductionCutResult.fromJson)
              .toList(growable: false)
          : const <AiEditSpeechReductionCutResult>[],
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
    this.targetDurationSeconds,
    this.styleId,
    this.prompt,
    this.visualProxyS3Key,
  });

  final List<ClipTranscriptSegment> segments;
  final double durationSeconds;
  final double? targetDurationSeconds;
  final String? styleId;
  final String? prompt;
  final String? visualProxyS3Key;

  Map<String, Object?> toJson() => {
        'durationSeconds': durationSeconds,
        if (targetDurationSeconds != null)
          'targetDurationSeconds': targetDurationSeconds,
        if (styleId != null) 'styleId': styleId,
        if (prompt != null) 'prompt': prompt,
        if (visualProxyS3Key != null) 'visualProxyS3Key': visualProxyS3Key,
        'segments': [
          for (final segment in segments)
            {
              'text': segment.text,
              'start': segment.start,
              'end': segment.end,
              if (segment.avgLogprob != null) 'avgLogprob': segment.avgLogprob,
              if (segment.noSpeechProbability != null)
                'noSpeechProbability': segment.noSpeechProbability,
              if (segment.compressionRatio != null)
                'compressionRatio': segment.compressionRatio,
            },
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
    this.subtitleOutlineColor,
    this.subtitleWordsPerLine,
    this.subtitlePosition,
    this.subtitleNormalizedX,
    this.subtitleNormalizedY,
    this.ctaText,
    this.ctaDesign,
    this.priceText,
    this.watermarkText,
    this.toneFilter,
    this.zoomLevel,
    this.silencePreset,
    this.fillerWords,
    this.speechReductionMode,
    this.music,
  });

  final String? subtitleStyle;
  final String? subtitleColor;
  final String? subtitleOutlineColor;
  final int? subtitleWordsPerLine;
  final String? subtitlePosition;
  final double? subtitleNormalizedX;
  final double? subtitleNormalizedY;
  final String? ctaText;
  final String? ctaDesign;
  final String? priceText;
  final String? watermarkText;
  final String? toneFilter;
  final String? zoomLevel;
  final String? silencePreset;
  final List<String>? fillerWords;
  final String? speechReductionMode;
  final AiEditMusicSettings? music;

  Map<String, Object?> toJson() => {
        if (subtitleStyle != null) 'subtitleStyle': subtitleStyle,
        if (subtitleColor != null) 'subtitleColor': subtitleColor,
        if (subtitleOutlineColor != null)
          'subtitleOutlineColor': subtitleOutlineColor,
        if (subtitleWordsPerLine != null)
          'subtitleWordsPerLine': subtitleWordsPerLine,
        if (subtitlePosition != null) 'subtitlePosition': subtitlePosition,
        if (subtitleNormalizedX != null)
          'subtitleNormalizedX': subtitleNormalizedX,
        if (subtitleNormalizedY != null)
          'subtitleNormalizedY': subtitleNormalizedY,
        if (ctaText != null) 'ctaText': ctaText,
        if (ctaDesign != null) 'ctaDesign': ctaDesign,
        if (priceText != null) 'priceText': priceText,
        if (watermarkText != null) 'watermarkText': watermarkText,
        if (toneFilter != null) 'toneFilter': toneFilter,
        if (zoomLevel != null) 'zoomLevel': zoomLevel,
        if (silencePreset != null) 'silencePreset': silencePreset,
        if (fillerWords != null) 'fillerWords': fillerWords,
        if (speechReductionMode != null)
          'speechReductionMode': speechReductionMode,
        if (music != null) 'music': music!.toJson(),
      };
}

class AiEditAudioChunkRequest {
  const AiEditAudioChunkRequest({
    required this.audioS3Key,
    required this.startSeconds,
  });

  final String audioS3Key;
  final double startSeconds;

  Map<String, Object?> toJson() => {
        'audioS3Key': audioS3Key,
        'startSeconds': startSeconds,
      };
}

class AiEditPrepareRequest {
  const AiEditPrepareRequest({
    this.audioS3Key,
    this.audioChunks,
    this.videoS3Key,
    required this.durationSeconds,
    this.targetDurationSeconds,
    this.styleId,
    this.prompt,
    this.capabilities = const <String, bool>{},
    this.settings = const AiEditPrepareSettings(),
  }) : assert(
          (audioS3Key != null && audioChunks == null && videoS3Key == null) ||
              (audioS3Key == null &&
                  audioChunks != null &&
                  videoS3Key == null) ||
              (audioS3Key == null && audioChunks == null && videoS3Key != null),
          'Provide exactly one of audioS3Key, audioChunks, or videoS3Key',
        );

  final String? audioS3Key;
  final List<AiEditAudioChunkRequest>? audioChunks;
  final String? videoS3Key;
  final double durationSeconds;
  final double? targetDurationSeconds;
  final String? styleId;
  final String? prompt;
  final Map<String, bool> capabilities;
  final AiEditPrepareSettings settings;

  Map<String, Object?> toJson() => {
        if (audioS3Key != null) 'audioS3Key': audioS3Key,
        if (audioChunks != null)
          'audioChunks': audioChunks!
              .map((chunk) => chunk.toJson())
              .toList(growable: false),
        if (videoS3Key != null) 'videoS3Key': videoS3Key,
        'durationSeconds': durationSeconds,
        if (targetDurationSeconds != null)
          'targetDurationSeconds': targetDurationSeconds,
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
    this.boundarySegments = const [],
    required this.words,
    required this.model,
  });

  final String text;
  final String language;
  final double durationSeconds;
  final List<ClipTranscriptSegment> segments;
  final List<ClipTranscriptSegment> boundarySegments;
  final List<AiEditTranscriptWordResult> words;
  final String model;

  factory AiEditTranscriptResult.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'];
    final rawBoundarySegments = json['boundarySegments'];
    final rawWords = json['words'];
    final durationSeconds = (json['durationSeconds'] as num?)?.toDouble() ?? 0;

    return AiEditTranscriptResult(
      text: json['text'] as String? ?? '',
      language: json['language'] as String? ?? '',
      durationSeconds: durationSeconds,
      segments: rawSegments is List<dynamic>
          ? rawSegments
              .whereType<Map<String, Object?>>()
              .map(ClipTranscriptSegment.fromJson)
              .toList()
          : <ClipTranscriptSegment>[],
      boundarySegments: _readStrictBoundarySegments(
        rawBoundarySegments,
        durationSeconds: durationSeconds,
      ),
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
    this.outlineColor = '#000000',
    this.normalizedX,
    this.normalizedY,
  });

  final String mode;
  final String color;
  final int wordsPerLine;
  final String position;
  final String outlineColor;
  final double? normalizedX;
  final double? normalizedY;

  AiEditSubtitleStyleResult withWordsPerLine(int updatedWordsPerLine) =>
      AiEditSubtitleStyleResult(
        mode: mode,
        color: color,
        wordsPerLine: updatedWordsPerLine,
        position: position,
        outlineColor: outlineColor,
        normalizedX: normalizedX,
        normalizedY: normalizedY,
      );

  factory AiEditSubtitleStyleResult.fromJson(Map<String, Object?> json) {
    final position = json['position'] as String? ?? 'bottom';
    double? readNormalized(String key) {
      final rawValue = json[key];
      if (rawValue is! num) {
        return null;
      }
      final value = rawValue.toDouble();
      return value.isFinite && value >= 0 && value <= 1 ? value : null;
    }

    final rawOutlineColor = json['outlineColor'];
    final outlineColor = rawOutlineColor is String &&
            RegExp(r'^#[0-9A-F]{6}$').hasMatch(rawOutlineColor)
        ? rawOutlineColor
        : '#000000';

    return AiEditSubtitleStyleResult(
      mode: json['mode'] as String? ?? 'bold',
      color: json['color'] as String? ?? '#FFFFFF',
      wordsPerLine: (json['wordsPerLine'] as num?)?.round() ?? 2,
      position: position,
      outlineColor: outlineColor,
      normalizedX: readNormalized('normalizedX'),
      normalizedY: readNormalized('normalizedY'),
    );
  }
}

class AiEditSubtitlesResult {
  const AiEditSubtitlesResult({
    required this.enabled,
    required this.segments,
    required this.style,
    this.variants = const <int, List<ClipTranscriptSegment>>{},
  });

  final bool enabled;
  final List<ClipTranscriptSegment> segments;
  final AiEditSubtitleStyleResult style;
  final Map<int, List<ClipTranscriptSegment>> variants;

  AiEditSubtitlesResult? withWordsPerLine(int wordsPerLine) {
    if (!enabled || style.wordsPerLine == wordsPerLine) return this;
    final variant = variants[wordsPerLine];
    if (variant == null) return null;

    return AiEditSubtitlesResult(
      enabled: enabled,
      segments: variant,
      style: style.withWordsPerLine(wordsPerLine),
      variants: variants,
    );
  }

  factory AiEditSubtitlesResult.fromJson(Map<String, Object?> json) {
    final rawSegments = json['segments'];
    final rawStyle = json['style'];
    final rawVariants = json['variants'];
    final variants = <int, List<ClipTranscriptSegment>>{};
    if (rawVariants is Map<String, Object?>) {
      for (final entry in rawVariants.entries) {
        final wordsPerLine = int.tryParse(entry.key);
        final rawVariantSegments = entry.value;
        if (wordsPerLine == null || rawVariantSegments is! List<dynamic>) {
          continue;
        }
        variants[wordsPerLine] = rawVariantSegments
            .whereType<Map<String, Object?>>()
            .map(ClipTranscriptSegment.fromJson)
            .toList(growable: false);
      }
    }

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
      variants: variants,
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

const maxAiEditRecipeSoundEffectsPerVideo = 8;

/// IDs the mobile renderer can resolve to bundled, rights-safe WAV assets.
///
/// Keep this allowlist in lockstep with the catalog in
/// `features/ai_editing/ai_edit_sound_effects.dart`. A focused asset test
/// protects against either side drifting independently.
const aiEditRecipeKnownSoundEffectIds = <String>{
  'soft_pop',
  'clean_tap',
  'short_whoosh',
  'medium_whoosh',
  'sparkle',
  'success_ding',
  'coin_ping',
  'soft_impact',
  'short_riser',
  'attention_boop',
};

class AiEditSoundEffectSuggestionResult {
  const AiEditSoundEffectSuggestionResult({
    required this.soundId,
    required this.sourceSeconds,
  });

  final String soundId;

  /// Anchor on the original source timeline. Mobile maps this through the
  /// final accepted cuts before handing it to the local renderer.
  final double sourceSeconds;
}

List<AiEditSoundEffectSuggestionResult> _readAiEditSoundEffects(
  Object? value, {
  required double sourceDurationSeconds,
}) {
  if (value == null) {
    return const <AiEditSoundEffectSuggestionResult>[];
  }
  if (value is! List<dynamic> ||
      value.length > maxAiEditRecipeSoundEffectsPerVideo ||
      !sourceDurationSeconds.isFinite ||
      sourceDurationSeconds <= 0) {
    return const <AiEditSoundEffectSuggestionResult>[];
  }

  final suggestions = <AiEditSoundEffectSuggestionResult>[];
  final seenSourceAnchors = <double>{};
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      return const <AiEditSoundEffectSuggestionResult>[];
    }
    if (item.length != 2 ||
        !item.containsKey('soundId') ||
        !item.containsKey('sourceSeconds')) {
      return const <AiEditSoundEffectSuggestionResult>[];
    }
    final soundId = item['soundId'];
    final rawSourceSeconds = item['sourceSeconds'];
    final sourceSeconds =
        rawSourceSeconds is num ? rawSourceSeconds.toDouble() : null;
    if (soundId is! String ||
        !aiEditRecipeKnownSoundEffectIds.contains(soundId) ||
        sourceSeconds == null ||
        !sourceSeconds.isFinite ||
        sourceSeconds < 0 ||
        sourceSeconds >= sourceDurationSeconds) {
      // Sound effects are an executable recipe. Never keep a seemingly safe
      // subset when one item proves that the server contract is malformed.
      return const <AiEditSoundEffectSuggestionResult>[];
    }
    if (!seenSourceAnchors.add(sourceSeconds)) {
      return const <AiEditSoundEffectSuggestionResult>[];
    }
    suggestions.add(
      AiEditSoundEffectSuggestionResult(
        soundId: soundId,
        sourceSeconds: sourceSeconds,
      ),
    );
  }
  return List<AiEditSoundEffectSuggestionResult>.unmodifiable(suggestions);
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
    this.plan = const AiEditPlanResult(
      cuts: [],
      summary: '',
      model: 'none',
    ),
    this.music = const AiEditMusicResult(
      source: 'original',
      beatIntensity: 'balanced',
      volume: 0.25,
      ducking: AiEditMusicDuckingResult(
        enabled: true,
        musicVolumeDuringSpeech: 0.12,
      ),
    ),
    this.speechReduction = const AiEditSpeechReductionResult.unavailable(),
    this.soundEffects = const <AiEditSoundEffectSuggestionResult>[],
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
  final AiEditPlanResult plan;
  final AiEditMusicResult music;
  final AiEditSpeechReductionResult speechReduction;
  final List<AiEditSoundEffectSuggestionResult> soundEffects;
  final Map<String, AiEditCapabilityStatusResult> capabilities;

  AiEditRecipeResult? withSubtitleWordsPerLine(int wordsPerLine) {
    final updatedSubtitles = subtitles.withWordsPerLine(wordsPerLine);
    if (updatedSubtitles == null) return null;
    if (identical(updatedSubtitles, subtitles)) return this;

    return AiEditRecipeResult(
      version: version,
      status: status,
      renderMode: renderMode,
      styleId: styleId,
      prompt: prompt,
      transcript: transcript,
      subtitles: updatedSubtitles,
      cutRanges: cutRanges,
      silenceRanges: silenceRanges,
      fillerRanges: fillerRanges,
      plan: plan,
      music: music,
      speechReduction: speechReduction,
      soundEffects: soundEffects,
      capabilities: capabilities,
    );
  }

  AiEditRecipeResult withPlan(AiEditPlanResult updatedPlan) {
    return AiEditRecipeResult(
      version: version,
      status: status,
      renderMode: renderMode,
      styleId: styleId,
      prompt: prompt,
      transcript: transcript,
      subtitles: subtitles,
      cutRanges: [
        ...updatedPlan.cuts,
        ...fillerRanges,
      ],
      silenceRanges: silenceRanges,
      fillerRanges: fillerRanges,
      plan: updatedPlan,
      music: music,
      speechReduction: speechReduction,
      soundEffects: soundEffects,
      capabilities: capabilities,
    );
  }

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
    final rawPlan = json['plan'];
    final rawMusic = json['music'];
    final rawSpeechReduction = json['speechReduction'];
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

    final transcript = AiEditTranscriptResult.fromJson(
      rawTranscript is Map<String, Object?>
          ? rawTranscript
          : const <String, Object?>{},
    );
    return AiEditRecipeResult(
      version: (json['version'] as num?)?.round() ?? 1,
      status: json['status'] as String? ?? '',
      renderMode: json['renderMode'] as String? ?? '',
      styleId: json['styleId'] as String?,
      prompt: json['prompt'] as String?,
      transcript: transcript,
      subtitles: AiEditSubtitlesResult.fromJson(
        rawSubtitles is Map<String, Object?>
            ? rawSubtitles
            : const <String, Object?>{},
      ),
      cutRanges: parseRanges(json['cutRanges']),
      silenceRanges: parseRanges(json['silenceRanges']),
      fillerRanges: parseRanges(json['fillerRanges']),
      plan: AiEditPlanResult.fromJson(
        rawPlan is Map<String, Object?> ? rawPlan : const <String, Object?>{},
      ),
      music: AiEditMusicResult.fromJson(
        rawMusic is Map<String, Object?> ? rawMusic : const <String, Object?>{},
      ),
      speechReduction: rawSpeechReduction is Map<String, Object?>
          ? AiEditSpeechReductionResult.fromJson(rawSpeechReduction)
          : const AiEditSpeechReductionResult.unavailable(),
      soundEffects: _readAiEditSoundEffects(
        json['soundEffects'],
        sourceDurationSeconds: transcript.durationSeconds,
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
    PostDeeAuthSessionStore? sessionStore,
    this.mockUserId = AppConfig.mockUserId,
    this.mockSubscriptionPlan = AppConfig.mockSubscriptionPlan,
  }) : authTokenProvider = authTokenProvider ??
            (sessionStore ?? PostDeeAuthSessionStore.instance).currentIdToken;

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
    this.purpose,
    this.width,
    this.height,
  });

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String? purpose;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'uploadProtocol': _multipartUploadProtocol,
        if (purpose != null) 'purpose': purpose,
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
    this.uploadProtocol,
    this.partSizeBytes,
    this.partCount,
    this.sessionExpiresAt,
  });

  final String id;
  final String videoS3Key;
  final String storageProvider;
  final String? uploadUrl;
  final String? uploadMethod;
  final Map<String, String> uploadHeaders;
  final DateTime? uploadExpiresAt;
  final String? uploadProtocol;
  final int? partSizeBytes;
  final int? partCount;
  final DateTime? sessionExpiresAt;

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
      uploadProtocol: json['uploadProtocol'] as String?,
      partSizeBytes: (json['partSizeBytes'] as num?)?.toInt(),
      partCount: (json['partCount'] as num?)?.toInt(),
      sessionExpiresAt: json['sessionExpiresAt'] is String
          ? DateTime.tryParse(json['sessionExpiresAt'] as String)
          : null,
    );
  }
}

const _uploadUrlExpirySafetyMargin = Duration(seconds: 30);
const _uploadUrlExpiredCode = 'UPLOAD_URL_EXPIRED';
const _uploadCompletionInProgressCode = 'UPLOAD_COMPLETION_IN_PROGRESS';
const _multipartUploadProtocol = 'multipart-v1';
const _multipartPartMaxAttempts = 3;
const _multipartCompletionPollDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

enum _MultipartCompletionResolution {
  completed,
  stillCompleting,
  notCompleted,
}

class _MultipartCompletionStillInProgress implements Exception {
  const _MultipartCompletionStillInProgress({
    required this.originalError,
    required this.originalStackTrace,
  });

  final Object originalError;
  final StackTrace originalStackTrace;
}

class _MultipartUploadPart {
  const _MultipartUploadPart({
    required this.partNumber,
    required this.sizeBytes,
    required this.uploadUrl,
    required this.uploadMethod,
    required this.uploadHeaders,
    this.uploadExpiresAt,
  });

  final int partNumber;
  final int sizeBytes;
  final String uploadUrl;
  final String uploadMethod;
  final Map<String, String> uploadHeaders;
  final DateTime? uploadExpiresAt;

  factory _MultipartUploadPart.fromJson(Map<String, Object?> json) {
    final rawHeaders = json['uploadHeaders'];

    return _MultipartUploadPart(
      partNumber: (json['partNumber'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadUrl: json['uploadUrl'] as String? ?? '',
      uploadMethod: json['uploadMethod'] as String? ?? '',
      uploadHeaders: rawHeaders is Map
          ? rawHeaders.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      uploadExpiresAt: json['uploadExpiresAt'] is String
          ? DateTime.tryParse(json['uploadExpiresAt'] as String)
          : null,
    );
  }
}

class _CompletedMultipartPart {
  const _CompletedMultipartPart({
    required this.partNumber,
    required this.etag,
  });

  final int partNumber;
  final String etag;

  Map<String, Object?> toJson() => {
        'partNumber': partNumber,
        'etag': etag,
      };
}

typedef UploadCreator = Future<UploadResult> Function(
  CreateUploadRequest request,
);
typedef UploadFileSender = Future<void> Function(
  UploadResult upload,
  File file,
);

/// Creates an upload and retries a legacy signed URL once only when R2 says
/// that the first URL expired. Managed multipart uploads refresh and retry each
/// part inside [PostDeeApiClient.uploadVideoFile] instead.
Future<UploadResult> createAndUploadFileWithRetry({
  required CreateUploadRequest request,
  required File file,
  required UploadCreator createUpload,
  required UploadFileSender uploadFile,
  void Function()? onRetry,
}) async {
  for (var attempt = 0; attempt < 2; attempt += 1) {
    final upload = await createUpload(request);

    try {
      await uploadFile(upload, file);
      return upload;
    } on ApiException catch (error) {
      if (upload.uploadProtocol == _multipartUploadProtocol ||
          error.code != _uploadUrlExpiredCode ||
          attempt > 0) {
        rethrow;
      }

      onRetry?.call();
    }
  }

  throw const ApiException(
    'ลิงก์อัปโหลดหมดอายุ กรุณาลองอีกครั้ง',
    code: _uploadUrlExpiredCode,
  );
}

class CreatePostRequest {
  const CreatePostRequest({
    required this.clientRequestId,
    required this.caption,
    required this.videoS3Key,
    required this.platforms,
    this.platformSettings = const {},
    this.scheduledAt,
    this.coverImageS3Key,
    this.coverFrameTimeMs,
  });

  final String clientRequestId;
  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final Map<String, Object?> platformSettings;
  final DateTime? scheduledAt;
  final String? coverImageS3Key;
  final int? coverFrameTimeMs;

  Map<String, Object?> toJson() => {
        'clientRequestId': clientRequestId,
        'caption': caption,
        'videoS3Key': videoS3Key,
        'platforms': platforms,
        if (platformSettings.isNotEmpty) 'platformSettings': platformSettings,
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
        if (coverImageS3Key != null) 'coverImageS3Key': coverImageS3Key,
        if (coverFrameTimeMs != null) 'coverFrameTimeMs': coverFrameTimeMs,
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
    this.idempotentReplay = false,
    this.platformResults = const [],
  });

  final String id;
  final String videoS3Key;
  final List<String> platforms;
  final String status;
  final bool idempotentReplay;
  final List<PostPlatformResult> platformResults;

  factory QueuedPostResult.fromJson(
    Map<String, Object?> json, {
    bool idempotentReplay = false,
  }) =>
      QueuedPostResult(
        id: json['id'] as String,
        videoS3Key: json['videoS3Key'] as String,
        platforms: (json['platforms'] as List<dynamic>)
            .map((value) => '$value')
            .toList(),
        status: json['status'] as String,
        idempotentReplay: idempotentReplay,
        platformResults: (json['platformResults'] as List<dynamic>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(PostPlatformResult.fromJson)
            .toList(),
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
    this.userId,
    this.publishedAt,
    this.platformResults = const [],
  });

  final String id;
  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final DateTime scheduledAt;
  final String status;
  final DateTime createdAt;
  final String? userId;
  final DateTime? publishedAt;
  final List<PostPlatformResult> platformResults;

  factory ScheduledPostResult.fromJson(Map<String, Object?> json) {
    String? optionalString(Object? value) {
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    DateTime? optionalDate(Object? value) {
      final date = optionalString(value);
      return date == null ? null : DateTime.tryParse(date);
    }

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
      userId: optionalString(json['userId']),
      publishedAt: optionalDate(json['publishedAt']),
      platformResults: (json['platformResults'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(PostPlatformResult.fromJson)
          .toList(),
    );
  }
}

/// A post in any state (queued, publishing, published, failed). Unlike
/// [ScheduledPostResult] the schedule and publish times are optional so it also
/// represents post-now items, which the Home dashboard lists as latest posts.
class PostPlatformResult {
  const PostPlatformResult({
    required this.postId,
    required this.platform,
    required this.status,
    this.externalPostId,
    this.errorMessage,
    this.deliveryOutcome,
    this.publishedAt,
    this.views = 0,
    this.likes = 0,
  });

  final String postId;
  final String platform;
  final String status;
  final String? externalPostId;
  final String? errorMessage;
  final String? deliveryOutcome;
  final DateTime? publishedAt;
  final int views;
  final int likes;

  factory PostPlatformResult.fromJson(Map<String, Object?> json) {
    String? optionalString(Object? value) {
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    final rawPublishedAt = optionalString(json['publishedAt']);

    return PostPlatformResult(
      postId: json['postId'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      status: json['status'] as String? ?? '',
      externalPostId: optionalString(json['externalPostId']),
      errorMessage: optionalString(json['errorMessage']),
      deliveryOutcome: optionalString(json['deliveryOutcome']),
      publishedAt:
          rawPublishedAt == null ? null : DateTime.tryParse(rawPublishedAt),
      views: json['views'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
    );
  }
}

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
    this.platformResults = const [],
  });

  final String id;
  final String caption;
  final String videoS3Key;
  final List<String> platforms;
  final String status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;
  final List<PostPlatformResult> platformResults;

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
      platformResults: (json['platformResults'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(PostPlatformResult.fromJson)
          .toList(),
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
    Future<void> Function(Duration)? multipartCompletionPollDelay,
  })  : _customHttpClient = httpClient,
        _baseUri = Uri.parse(baseUrl),
        _authHeaders = authHeaders ??
            PostDeeApiAuthHeaders(
              authTokenProvider: authTokenProvider,
            ),
        _multipartCompletionPollDelay = multipartCompletionPollDelay ??
            ((duration) => Future<void>.delayed(duration));

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
  final Future<void> Function(Duration) _multipartCompletionPollDelay;

  Future<ApiHealthResult> checkHealth() async {
    final response = await _getJson('/health');

    return ApiHealthResult.fromJson(response);
  }

  Future<void> checkPublishingReadiness() async {
    final response = await _getJson('/publishing/readiness');

    if (response['acceptingPosts'] != true) {
      throw const ApiException(
        'Social publishing is temporarily unavailable. Please try again later.',
        statusCode: HttpStatus.serviceUnavailable,
        code: socialPublishingUnavailableCode,
      );
    }

    final platformSettingsVersion = response['platformSettingsVersion'];
    if (platformSettingsVersion is! int || platformSettingsVersion < 1) {
      throw const ApiException(
        'ระบบโพสต์ยังไม่รองรับการตั้งค่าช่องทางรุ่นนี้ กรุณาอัปเดต PostDee API ก่อนลองใหม่',
        code: platformSettingsUnsupportedCode,
      );
    }
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

    return QueuedPostResult.fromJson(
      post,
      idempotentReplay: response['idempotentReplay'] == true,
    );
  }

  Future<void> publishPostNow(String postId) async {
    final response = await _postJson(
      '/posts/${Uri.encodeComponent(postId)}/publish-now',
      const <String, Object?>{},
    );

    if (response['status'] != 'ok') {
      throw const ApiException('Publish-now response is missing ok status');
    }
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

  /// Checks deletion prerequisites and reports whether Firebase identity
  /// deletion already completed during an earlier request.
  Future<bool> checkAccountDeletionReady() async {
    final response = await _getJson('/account/deletion-readiness');

    return response['identityAlreadyDeleted'] == true;
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
        .map((connection) =>
            SocialConnectionResult.fromJson(connection as Map<String, Object?>))
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
        .map((connection) =>
            SocialConnectionResult.fromJson(connection as Map<String, Object?>))
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

  Future<void> cleanupAiEditAudio(String audioS3Key) async {
    await _postJson('/ai-edits/audio/cleanup', {
      'audioS3Key': audioS3Key,
    });
  }

  Future<void> cleanupAiEditVisualProxy(String visualProxyS3Key) async {
    await _postJson('/ai-edits/visual-proxy/cleanup', {
      'visualProxyS3Key': visualProxyS3Key,
    });
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

  Future<String> resyncRevenueCatSubscription() async {
    final response = await _postJson('/billing/revenuecat/resync', const {});
    final plan = response['plan'];

    if (plan is! String || plan.trim().isEmpty) {
      throw const ApiException(
        'RevenueCat resync response is missing the subscription plan',
      );
    }

    return plan.trim().toUpperCase();
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
    if (upload.uploadProtocol == _multipartUploadProtocol) {
      await _uploadMultipartVideoFile(upload, videoFile);
      return;
    }

    await _uploadLegacyVideoFile(upload, videoFile);
  }

  Future<void> _uploadMultipartVideoFile(
    UploadResult upload,
    File videoFile,
  ) async {
    try {
      final partSizeBytes = upload.partSizeBytes;
      final partCount = upload.partCount;
      final fileSizeBytes = await videoFile.length();
      final sessionExpiresAt = upload.sessionExpiresAt?.toUtc();

      if (sessionExpiresAt != null &&
          !sessionExpiresAt.isAfter(
            DateTime.now().toUtc().add(_uploadUrlExpirySafetyMargin),
          )) {
        throw const ApiException(
          'Upload session has expired',
          statusCode: HttpStatus.conflict,
          code: 'UPLOAD_SESSION_EXPIRED',
        );
      }

      if (partSizeBytes == null ||
          partSizeBytes <= 0 ||
          partCount == null ||
          partCount <= 0 ||
          fileSizeBytes <= 0) {
        throw const ApiException('Multipart upload metadata is invalid');
      }

      final expectedPartCount =
          (fileSizeBytes + partSizeBytes - 1) ~/ partSizeBytes;
      if (expectedPartCount != partCount) {
        throw ApiException(
          'Multipart upload expected $partCount parts but the file requires '
          '$expectedPartCount',
        );
      }

      final completedParts = <_CompletedMultipartPart>[];
      for (var partNumber = 1; partNumber <= partCount; partNumber += 1) {
        final start = (partNumber - 1) * partSizeBytes;
        final proposedEnd = start + partSizeBytes;
        final end = proposedEnd < fileSizeBytes ? proposedEnd : fileSizeBytes;

        completedParts.add(
          await _uploadMultipartPartWithRetry(
            upload: upload,
            videoFile: videoFile,
            partNumber: partNumber,
            start: start,
            end: end,
          ),
        );
      }

      await _completeMultipartUpload(upload, completedParts);
    } on _MultipartCompletionStillInProgress catch (pendingCompletion) {
      Error.throwWithStackTrace(
        pendingCompletion.originalError,
        pendingCompletion.originalStackTrace,
      );
    } catch (_) {
      await _abortMultipartUpload(upload.id);
      rethrow;
    }
  }

  Future<_CompletedMultipartPart> _uploadMultipartPartWithRetry({
    required UploadResult upload,
    required File videoFile,
    required int partNumber,
    required int start,
    required int end,
  }) async {
    for (var attempt = 0; attempt < _multipartPartMaxAttempts; attempt += 1) {
      try {
        final part = await _createMultipartPart(upload.id, partNumber);
        final expectedSizeBytes = end - start;

        if (part.partNumber != partNumber ||
            part.sizeBytes != expectedSizeBytes) {
          throw ApiException(
            'Multipart part $partNumber has unexpected metadata',
          );
        }

        final etag = await _putMultipartPart(
          part: part,
          videoFile: videoFile,
          start: start,
          end: end,
        );

        return _CompletedMultipartPart(
          partNumber: partNumber,
          etag: etag,
        );
      } catch (error) {
        final canRetry = _isRetryableMultipartFailure(error);
        final hasAttemptRemaining = attempt + 1 < _multipartPartMaxAttempts;
        if (!canRetry || !hasAttemptRemaining) {
          rethrow;
        }
      }
    }

    throw ApiException('Multipart part $partNumber could not be uploaded');
  }

  Future<_MultipartUploadPart> _createMultipartPart(
    String uploadId,
    int partNumber,
  ) async {
    final response = await _postJson(
      '${_managedUploadPath(uploadId)}/parts/$partNumber',
      const <String, Object?>{},
    );
    final rawPart = response['part'];

    if (rawPart is! Map<String, Object?>) {
      throw const ApiException('Upload part response is missing part data');
    }

    final part = _MultipartUploadPart.fromJson(rawPart);
    final uploadUri = Uri.tryParse(part.uploadUrl);
    if (part.partNumber <= 0 ||
        part.sizeBytes <= 0 ||
        uploadUri == null ||
        !uploadUri.hasScheme ||
        part.uploadMethod.toUpperCase() != 'PUT') {
      throw const ApiException('Upload part response is invalid');
    }

    return part;
  }

  Future<String> _putMultipartPart({
    required _MultipartUploadPart part,
    required File videoFile,
    required int start,
    required int end,
  }) async {
    final expiresAt = part.uploadExpiresAt?.toUtc();
    if (expiresAt != null &&
        !expiresAt.isAfter(
          DateTime.now().toUtc().add(_uploadUrlExpirySafetyMargin),
        )) {
      throw const ApiException(
        'Upload part URL has expired',
        statusCode: HttpStatus.forbidden,
        code: _uploadUrlExpiredCode,
      );
    }

    final request = await _httpClient.openUrl(
      part.uploadMethod.toUpperCase(),
      Uri.parse(part.uploadUrl),
    );
    for (final header in part.uploadHeaders.entries) {
      request.headers.set(header.key, header.value);
    }

    request
      ..contentLength = end - start
      ..bufferOutput = false;
    await request.addStream(videoFile.openRead(start, end));

    final response = await request.close();
    final etag = response.headers.value(HttpHeaders.etagHeader)?.trim();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final isExpired = _isExpiredUploadResponse(
        response.statusCode,
        responseBody,
      );
      throw ApiException(
        isExpired
            ? 'Upload part URL has expired'
            : (responseBody.isEmpty
                ? 'Multipart part upload failed'
                : responseBody),
        statusCode: response.statusCode,
        code: isExpired ? _uploadUrlExpiredCode : null,
      );
    }

    if (etag == null || etag.isEmpty) {
      throw const ApiException('Multipart part response is missing ETag');
    }

    return etag;
  }

  Future<void> _completeMultipartUpload(
    UploadResult upload,
    List<_CompletedMultipartPart> completedParts,
  ) async {
    try {
      final response = await _postJson(
        '${_managedUploadPath(upload.id)}/complete',
        {
          'parts': [
            for (final part in completedParts) part.toJson(),
          ],
        },
      );
      final completedUpload = _readMultipartUploadResponse(
        response,
        'Complete upload response is missing upload data',
      );

      if (completedUpload.id != upload.id) {
        throw const ApiException('Complete upload response has the wrong id');
      }
    } catch (error, stackTrace) {
      if (!_shouldResolveMultipartCompletion(error)) {
        rethrow;
      }

      final resolution = await _resolveMultipartCompletion(
        upload.id,
        completionAlreadyInProgress: _isMultipartCompletionInProgress(error),
      );
      if (resolution == _MultipartCompletionResolution.completed) {
        return;
      }
      if (resolution == _MultipartCompletionResolution.stillCompleting) {
        throw _MultipartCompletionStillInProgress(
          originalError: error,
          originalStackTrace: stackTrace,
        );
      }

      rethrow;
    }
  }

  Future<_MultipartCompletionResolution> _resolveMultipartCompletion(
    String uploadId, {
    required bool completionAlreadyInProgress,
  }) async {
    var lastResolution = completionAlreadyInProgress
        ? _MultipartCompletionResolution.stillCompleting
        : _MultipartCompletionResolution.notCompleted;

    for (var attempt = 0;
        attempt <= _multipartCompletionPollDelays.length;
        attempt += 1) {
      Map<String, Object?>? response;
      try {
        response = await _getJson(_managedUploadPath(uploadId));
      } catch (_) {
        if (lastResolution != _MultipartCompletionResolution.stillCompleting) {
          return _MultipartCompletionResolution.notCompleted;
        }
      }

      if (response != null) {
        final sessionStatus = response['sessionStatus'];
        if (sessionStatus == 'COMPLETED') {
          try {
            final completedUpload = _readMultipartUploadResponse(
              response,
              'Upload status response is missing upload data',
            );
            return completedUpload.id == uploadId
                ? _MultipartCompletionResolution.completed
                : lastResolution;
          } catch (_) {
            return lastResolution;
          }
        }
        if (sessionStatus != 'COMPLETING') {
          return lastResolution;
        }

        lastResolution = _MultipartCompletionResolution.stillCompleting;
      }

      if (attempt < _multipartCompletionPollDelays.length) {
        await _multipartCompletionPollDelay(
          _multipartCompletionPollDelays[attempt],
        );
      }
    }

    return lastResolution;
  }

  UploadResult _readMultipartUploadResponse(
    Map<String, Object?> response,
    String missingMessage,
  ) {
    final rawUpload = response['upload'];
    if (rawUpload is! Map<String, Object?>) {
      throw ApiException(missingMessage);
    }

    return UploadResult.fromJson(rawUpload);
  }

  Future<void> _abortMultipartUpload(String uploadId) async {
    try {
      await _deleteJson(_managedUploadPath(uploadId));
    } catch (_) {
      // Best effort only: preserve the upload error that triggered the abort.
    }
  }

  String _managedUploadPath(String uploadId) =>
      '/uploads/${Uri.encodeComponent(uploadId)}';

  bool _isRetryableMultipartFailure(Object error) {
    if (error is ApiException) {
      final statusCode = error.statusCode;
      return error.code == _uploadUrlExpiredCode ||
          statusCode == HttpStatus.requestTimeout ||
          statusCode == HttpStatus.tooManyRequests ||
          (statusCode != null && statusCode >= 500 && statusCode < 600);
    }

    return error is SocketException ||
        error is HttpException ||
        error is HandshakeException;
  }

  bool _isMultipartCompletionInProgress(Object error) =>
      error is ApiException &&
      error.statusCode == HttpStatus.conflict &&
      error.code == _uploadCompletionInProgressCode;

  bool _shouldResolveMultipartCompletion(Object error) =>
      _isRetryableMultipartFailure(error) ||
      _isMultipartCompletionInProgress(error);

  bool _isExpiredUploadResponse(int statusCode, String responseBody) {
    final normalizedBody = responseBody.toLowerCase();
    return (statusCode == HttpStatus.badRequest ||
            statusCode == HttpStatus.forbidden) &&
        (normalizedBody.contains('expiredrequest') ||
            normalizedBody.contains('requestexpired') ||
            normalizedBody.contains('request has expired') ||
            normalizedBody.contains('expiredtoken'));
  }

  Future<void> _uploadLegacyVideoFile(
    UploadResult upload,
    File videoFile,
  ) async {
    if (upload.uploadUrl == null) {
      return;
    }

    if (upload.uploadMethod != null && upload.uploadMethod != 'PUT') {
      throw ApiException('Unsupported upload method: ${upload.uploadMethod}');
    }

    final expiresAt = upload.uploadExpiresAt?.toUtc();
    if (expiresAt != null &&
        !expiresAt.isAfter(
          DateTime.now().toUtc().add(_uploadUrlExpirySafetyMargin),
        )) {
      throw const ApiException(
        'ลิงก์อัปโหลดหมดอายุ กรุณาลองอีกครั้ง',
        statusCode: HttpStatus.forbidden,
        code: _uploadUrlExpiredCode,
      );
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
      final isExpired = _isExpiredUploadResponse(
        response.statusCode,
        responseBody,
      );

      throw ApiException(
        isExpired
            ? 'ลิงก์อัปโหลดหมดอายุ กรุณาลองอีกครั้ง'
            : (responseBody.isEmpty ? 'Video upload failed' : responseBody),
        statusCode: response.statusCode,
        code: isExpired ? _uploadUrlExpiredCode : null,
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
    Object? decoded;

    try {
      decoded =
          responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
    } on FormatException {
      throw ApiException(
        response.statusCode < 200 || response.statusCode >= 300
            ? 'Request failed'
            : 'Unexpected API response',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw ApiException('Unexpected API response',
          statusCode: response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        decoded['message'] as String? ?? 'Request failed',
        statusCode: response.statusCode,
        code: decoded['code'] as String?,
        postId:
            decoded['postId'] is String ? decoded['postId'] as String : null,
      );
    }

    return decoded;
  }
}
