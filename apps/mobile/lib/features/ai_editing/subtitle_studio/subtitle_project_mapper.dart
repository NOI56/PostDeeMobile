import 'dart:convert';

import '../../../core/network/postdee_api_client.dart';
import '../style_options.dart';
import '../subtitle_burn_video_processor.dart';
import '../subtitle_word_timing_safety.dart';
import 'subtitle_project.dart';

SubtitleProject mapAiEditRecipeToSubtitleProject({
  required AiEditRecipeResult recipe,
  required String projectId,
  required String sourceFingerprint,
  required DateTime now,
  List<AiEditCut>? effectiveCutRanges,
  int maxCharsPerCue = 18,
}) {
  final sourceDurationMs = _secondsToMilliseconds(
    recipe.transcript.durationSeconds,
    'Source duration',
  );
  if (sourceDurationMs <= 0) {
    throw const SubtitleProjectValidationException(
      'Source duration must be positive.',
    );
  }

  final usesValidatedCueWordContract =
      recipe.subtitles.segments.any((segment) => segment.words != null);
  final sourceSubtitleSegments = recipe.subtitles.segments
      .where((segment) => segment.text.trim().isNotEmpty)
      .toList(growable: false);
  final sourceSegments = sourceSubtitleSegments
      .where((segment) => segment.text.trim().isNotEmpty)
      .map(
        (segment) => SubtitleSegment(
          text: segment.text.trim(),
          start: segment.start,
          end: segment.end,
        ),
      )
      .toList(growable: false);
  // Keep server-validated cue/word boundaries intact while creating the
  // editable project. The renderer can re-chunk display text later, after its
  // cleanup safety pass has used these source-timeline word timings.
  final preparedSegments = (usesValidatedCueWordContract
          ? sourceSegments
          : prepareSubtitleSegmentsForLocalRender(
              sourceSegments,
              language: recipe.transcript.language,
              maximumCharacters: maxCharsPerCue,
            ))
      .map(
        (segment) => _MappedRange(
          text: segment.text,
          startMs: _secondsToMilliseconds(segment.start, 'Subtitle segment'),
          endMs: _secondsToMilliseconds(segment.end, 'Subtitle segment'),
          validatedWords: usesValidatedCueWordContract
              ? _readValidatedWordsForPreparedSegment(
                  sourceSubtitleSegments,
                  segment,
                )
              : null,
        ),
      )
      .toList()
    ..sort(_compareRanges);

  final legacyTranscriptWords = usesValidatedCueWordContract
      ? null
      : _prepareTranscriptWords(
          recipe.transcript.words,
          language: recipe.transcript.language,
          sourceDurationMs: sourceDurationMs,
        );
  final cues = <SubtitleCue>[];
  for (var index = 0; index < preparedSegments.length; index += 1) {
    final segment = preparedSegments[index];
    final cueId = 'cue-${index + 1}-${segment.startMs}-${segment.endMs}';
    final preferredWords = segment.validatedWords == null
        ? legacyTranscriptWords
        : _prepareTranscriptWords(
            segment.validatedWords!,
            language: recipe.transcript.language,
            sourceDurationMs: sourceDurationMs,
          );
    final words = preferredWords == null
        ? const <SubtitleWord>[]
        : _mapWordsToCue(
            preferredWords,
            cueId: cueId,
            cueText: segment.text!,
            cueStartMs: segment.startMs,
            cueEndMs: segment.endMs,
          );
    cues.add(
      SubtitleCue(
        cueId: cueId,
        sourceStartMs: segment.startMs,
        sourceEndMs: segment.endMs,
        text: segment.text!,
        words: words,
        timingMode: words.isEmpty
            ? SubtitleTimingMode.segment
            : SubtitleTimingMode.word,
      ),
    );
  }

  final cutRanges = _mapCutRanges(
    ranges: effectiveCutRanges ?? recipe.cutRanges,
    readStart: (range) => range.start,
    readEnd: (range) => range.end,
    sourceDurationMs: sourceDurationMs,
  );
  final defaultStyle = _mapStyle(recipe.subtitles.style);
  final recipeFingerprint = _buildRecipeFingerprint(
    sourceDurationMs: sourceDurationMs,
    language: recipe.transcript.language,
    cues: cues,
    defaultStyle: defaultStyle,
    cutRanges: cutRanges,
  );

  final project = SubtitleProject(
    schemaVersion: 1,
    projectId: projectId,
    sourceFingerprint: sourceFingerprint,
    recipeFingerprint: recipeFingerprint,
    sourceDurationMs: sourceDurationMs,
    language: recipe.transcript.language,
    cues: cues,
    defaultStyle: defaultStyle,
    cutRanges: cutRanges,
    revision: 0,
    createdAt: now,
    updatedAt: now,
  );
  validateSubtitleProject(project);
  return project;
}

SubtitleProject replaceSubtitleProjectCutRanges({
  required SubtitleProject project,
  required List<SilenceCutRange> effectiveCutRanges,
  required DateTime now,
}) {
  validateSubtitleProject(project);
  final cutRanges = _mapCutRanges(
    ranges: effectiveCutRanges,
    readStart: (range) => range.start,
    readEnd: (range) => range.end,
    sourceDurationMs: project.sourceDurationMs,
  );
  final recipeFingerprint = _buildRecipeFingerprint(
    sourceDurationMs: project.sourceDurationMs,
    language: project.language,
    cues: project.cues,
    defaultStyle: project.defaultStyle,
    cutRanges: cutRanges,
  );
  final updated = project.copyWith(
    recipeFingerprint: recipeFingerprint,
    cutRanges: cutRanges,
    revision: project.revision + 1,
    updatedAt: now.toUtc(),
  );
  validateSubtitleProject(updated);
  return updated;
}

SubtitleProject applySubtitleSetupStyle(
  SubtitleProject project,
  SubtitleStyle style,
) {
  final styledProject = project.copyWith(defaultStyle: style);
  final recipeFingerprint = _buildRecipeFingerprint(
    sourceDurationMs: styledProject.sourceDurationMs,
    language: styledProject.language,
    cues: styledProject.cues,
    defaultStyle: styledProject.defaultStyle,
    cutRanges: styledProject.cutRanges,
  );
  return styledProject.copyWith(recipeFingerprint: recipeFingerprint);
}

String _buildRecipeFingerprint({
  required int sourceDurationMs,
  required String language,
  required List<SubtitleCue> cues,
  required SubtitleStyle defaultStyle,
  required List<SubtitleCutRange> cutRanges,
}) {
  final baseline = jsonEncode({
    'sourceDurationMs': sourceDurationMs,
    'language': language,
    'cues': cues.map((cue) => cue.toJson()).toList(growable: false),
    'defaultStyle': defaultStyle.toJson(),
    'cutRanges':
        cutRanges.map((range) => range.toJson()).toList(growable: false),
  });
  return 'recipe-${_fnv1a64Hex(baseline)}';
}

String _fnv1a64Hex(String value) {
  final offsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  var hash = offsetBasis;
  for (final byte in utf8.encode(value)) {
    hash ^= BigInt.from(byte);
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

List<SubtitleCutRange> _mergeCutRanges(List<SubtitleCutRange> ranges) {
  final merged = <SubtitleCutRange>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.sourceStartMs > merged.last.sourceEndMs) {
      merged.add(range);
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      SubtitleCutRange(
        sourceStartMs: previous.sourceStartMs,
        sourceEndMs: range.sourceEndMs > previous.sourceEndMs
            ? range.sourceEndMs
            : previous.sourceEndMs,
      ),
    );
  }
  return merged;
}

List<SubtitleCutRange> _mapCutRanges<T>({
  required Iterable<T> ranges,
  required double Function(T range) readStart,
  required double Function(T range) readEnd,
  required int sourceDurationMs,
}) {
  final mapped = <SubtitleCutRange>[];
  final sourceDurationSeconds = sourceDurationMs / 1000;
  for (final range in ranges) {
    final start = readStart(range);
    final end = readEnd(range);
    if (!start.isFinite || !end.isFinite) {
      throw const SubtitleProjectValidationException(
        'Cut range must be finite.',
      );
    }
    if (start < 0 || end <= start || end > sourceDurationSeconds) {
      throw const SubtitleProjectValidationException(
        'Cut range has invalid timing.',
      );
    }

    final mappedRange = SubtitleCutRange(
      sourceStartMs: _secondsToMilliseconds(start, 'Cut range'),
      sourceEndMs: _secondsToMilliseconds(end, 'Cut range'),
    );
    if (mappedRange.sourceStartMs < 0 ||
        mappedRange.sourceEndMs <= mappedRange.sourceStartMs ||
        mappedRange.sourceEndMs > sourceDurationMs) {
      throw const SubtitleProjectValidationException(
        'Cut range has invalid timing.',
      );
    }
    mapped.add(mappedRange);
  }

  mapped.sort(
    (left, right) => left.sourceStartMs != right.sourceStartMs
        ? left.sourceStartMs.compareTo(right.sourceStartMs)
        : left.sourceEndMs.compareTo(right.sourceEndMs),
  );
  return _mergeCutRanges(mapped);
}

SubtitleStyle _mapStyle(AiEditSubtitleStyleResult style) {
  final defaults = SubtitleStyle.defaults;
  final color = RegExp(r'^#[0-9A-F]{6}$').hasMatch(style.color)
      ? style.color
      : defaults.textColor;
  final outlineColor = RegExp(r'^#[0-9A-F]{6}$').hasMatch(style.outlineColor)
      ? style.outlineColor
      : defaults.outlineColor;
  final hasNormalizedPosition =
      style.normalizedX != null && style.normalizedY != null;
  final alignment = hasNormalizedPosition
      ? switch (style.normalizedY!) {
          < 0.34 => SubtitleAlignment.top,
          < 0.67 => SubtitleAlignment.middle,
          _ => SubtitleAlignment.bottom,
        }
      : switch (style.position) {
          'top' => SubtitleAlignment.top,
          'middle' => SubtitleAlignment.middle,
          'bottom' => SubtitleAlignment.bottom,
          _ => defaults.alignment,
        };
  final legacyY = switch (alignment) {
    SubtitleAlignment.top => 0.12,
    SubtitleAlignment.middle => 0.5,
    SubtitleAlignment.bottom => 0.88,
  };

  return SubtitleStyle(
    fontId: defaults.fontId,
    fontWeight: defaults.fontWeight,
    fontSize: defaults.fontSize,
    textColor: color,
    activeWordColor: defaults.activeWordColor,
    outlineColor: outlineColor,
    outlineWidth: defaults.outlineWidth,
    shadowColor: defaults.shadowColor,
    shadowDepth: defaults.shadowDepth,
    alignment: alignment,
    normalizedX:
        hasNormalizedPosition ? style.normalizedX! : defaults.normalizedX,
    normalizedY: hasNormalizedPosition ? style.normalizedY! : legacyY,
    maxLines: defaults.maxLines,
    animation: defaults.animation,
  );
}

int _secondsToMilliseconds(double seconds, String label) {
  if (!seconds.isFinite) {
    throw SubtitleProjectValidationException('$label must be finite.');
  }
  final milliseconds = seconds * 1000;
  if (!milliseconds.isFinite) {
    throw SubtitleProjectValidationException('$label must be finite.');
  }
  return milliseconds.round();
}

int _compareRanges(_MappedRange left, _MappedRange right) {
  if (left.startMs != right.startMs) {
    return left.startMs.compareTo(right.startMs);
  }
  return left.endMs.compareTo(right.endMs);
}

List<AiEditTranscriptWordResult> _readValidatedWordsForPreparedSegment(
  List<ClipTranscriptSegment> sourceSegments,
  SubtitleSegment preparedSegment,
) {
  final overlappingSources = sourceSegments.where(
    (source) =>
        source.start < preparedSegment.end &&
        source.end > preparedSegment.start,
  );
  final words = <AiEditTranscriptWordResult>[];
  for (final source in overlappingSources) {
    final validatedWords = source.words;
    if (validatedWords == null) {
      return const <AiEditTranscriptWordResult>[];
    }
    words.addAll(validatedWords);
  }
  return words;
}

List<_MappedWord>? _prepareTranscriptWords(
  List<AiEditTranscriptWordResult> words, {
  required String language,
  required int sourceDurationMs,
}) {
  final prepared = <_MappedWord>[];
  var previousEndMs = 0;
  var previousEndSeconds = 0.0;

  for (final word in words) {
    final text = word.word.trim();
    final startMs = _trySecondsToMilliseconds(word.start);
    final endMs = _trySecondsToMilliseconds(word.end);
    if (text.isEmpty ||
        startMs == null ||
        endMs == null ||
        word.start < 0 ||
        word.end <= word.start ||
        startMs < 0 ||
        endMs <= startMs ||
        endMs > sourceDurationMs ||
        word.start < previousEndSeconds ||
        startMs < previousEndMs) {
      return null;
    }
    prepared.add(
      _MappedWord(text: text, startMs: startMs, endMs: endMs),
    );
    previousEndMs = endMs;
    previousEndSeconds = word.end;
  }

  if (_isThaiLanguage(language) &&
      prepared.any((word) => _isStandaloneThaiMark(word.text))) {
    return null;
  }
  if (_hasFragmentedThaiTiming(prepared, language)) {
    return null;
  }
  return prepared;
}

List<SubtitleWord> _mapWordsToCue(
  List<_MappedWord> words, {
  required String cueId,
  required String cueText,
  required int cueStartMs,
  required int cueEndMs,
}) {
  final candidates = <_MappedWord>[];
  for (final word in words) {
    if (word.startMs >= cueEndMs || word.endMs <= cueStartMs) {
      continue;
    }
    if (word.startMs < cueStartMs || word.endMs > cueEndMs) {
      return const <SubtitleWord>[];
    }
    candidates.add(word);
  }
  if (candidates.isEmpty) {
    return const <SubtitleWord>[];
  }

  final starts = <int>[];
  final ends = <int>[];
  var cursor = 0;
  for (final word in candidates) {
    final start = cueText.indexOf(word.text, cursor);
    if (start < 0) {
      return const <SubtitleWord>[];
    }
    final separatorBefore = cueText.substring(cursor, start);
    if ((starts.isEmpty && start != 0) ||
        !containsOnlyUntimedSubtitleSeparators(separatorBefore)) {
      return const <SubtitleWord>[];
    }
    final end = start + word.text.length;
    starts.add(start);
    ends.add(end);
    cursor = end;
  }
  final trailingSeparator = cueText.substring(cursor);
  if (!containsOnlyUntimedSubtitleSeparators(trailingSeparator)) {
    return const <SubtitleWord>[];
  }

  return [
    for (var index = 0; index < candidates.length; index += 1)
      SubtitleWord(
        wordId: '$cueId-word-${index + 1}',
        text: candidates[index].text,
        sourceStartMs: candidates[index].startMs,
        sourceEndMs: candidates[index].endMs,
        separatorAfter: index + 1 < candidates.length
            ? cueText.substring(ends[index], starts[index + 1])
            : trailingSeparator,
      ),
  ];
}

bool _hasFragmentedThaiTiming(
  List<_MappedWord> words,
  String language,
) {
  if (!_isThaiLanguage(language) || words.length < 4) {
    return false;
  }
  final thaiTokenCount = words.where((word) => _containsThai(word.text)).length;
  final singleRuneCount =
      words.where((word) => word.text.runes.length == 1).length;
  final tightPairCount = [
    for (var index = 1; index < words.length; index += 1)
      if (words[index].startMs - words[index - 1].endMs <= 80) index,
  ].length;

  return thaiTokenCount / words.length >= 0.5 &&
      tightPairCount / (words.length - 1) >= 0.5 &&
      singleRuneCount / words.length >= 0.75;
}

bool _isThaiLanguage(String language) {
  final normalized = language.trim().toLowerCase().replaceAll('_', '-');
  return normalized == 'th' ||
      normalized == 'tha' ||
      normalized == 'thai' ||
      normalized.startsWith('th-');
}

bool _containsThai(String text) =>
    text.runes.any((rune) => rune >= 0x0E00 && rune <= 0x0E7F);

bool _isStandaloneThaiMark(String text) {
  final runes = text.runes.toList(growable: false);
  return runes.isNotEmpty &&
      runes.every(
        (rune) =>
            rune == 0x0E31 ||
            (rune >= 0x0E34 && rune <= 0x0E3A) ||
            (rune >= 0x0E47 && rune <= 0x0E4E),
      );
}

int? _trySecondsToMilliseconds(double seconds) {
  if (!seconds.isFinite) {
    return null;
  }
  final milliseconds = seconds * 1000;
  if (!milliseconds.isFinite) {
    return null;
  }
  return milliseconds.round();
}

class _MappedRange {
  const _MappedRange({
    this.text,
    required this.startMs,
    required this.endMs,
    this.validatedWords,
  });

  final String? text;
  final int startMs;
  final int endMs;
  final List<AiEditTranscriptWordResult>? validatedWords;
}

class _MappedWord {
  const _MappedWord({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;
}
