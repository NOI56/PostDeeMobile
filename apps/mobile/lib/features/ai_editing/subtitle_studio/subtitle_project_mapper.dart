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
  final preparedSegments = rechunkSubtitleByMaxChars(
    sourceSegments,
    maxCharsPerCue,
  )
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

  final mappedCutRanges = recipe.cutRanges
      .map(
        (range) => SubtitleCutRange(
          sourceStartMs: _secondsToMilliseconds(range.start, 'Cut range'),
          sourceEndMs: _secondsToMilliseconds(range.end, 'Cut range'),
        ),
      )
      .toList()
    ..sort(
      (left, right) => left.sourceStartMs != right.sourceStartMs
          ? left.sourceStartMs.compareTo(right.sourceStartMs)
          : left.sourceEndMs.compareTo(right.sourceEndMs),
    );
  for (final range in mappedCutRanges) {
    if (range.sourceStartMs < 0 ||
        range.sourceEndMs <= range.sourceStartMs ||
        range.sourceEndMs > sourceDurationMs) {
      throw const SubtitleProjectValidationException(
        'Cut range has invalid timing.',
      );
    }
  }
  final cutRanges = _mergeCutRanges(mappedCutRanges);

  final project = SubtitleProject(
    schemaVersion: 1,
    projectId: projectId,
    sourceFingerprint: sourceFingerprint,
    sourceDurationMs: sourceDurationMs,
    language: recipe.transcript.language,
    cues: cues,
    defaultStyle: _mapStyle(recipe.subtitles.style),
    cutRanges: cutRanges,
    revision: 0,
    createdAt: now,
    updatedAt: now,
  );
  validateSubtitleProject(project);
  return project;
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

SubtitleStyle _mapStyle(AiEditSubtitleStyleResult style) {
  final defaults = SubtitleStyle.defaults;
  final color = RegExp(r'^#[0-9A-F]{6}$').hasMatch(style.color)
      ? style.color
      : defaults.textColor;
  final alignment = switch (style.position) {
    'top' => SubtitleAlignment.top,
    'bottom' => SubtitleAlignment.bottom,
    _ => defaults.alignment,
  };

  return SubtitleStyle(
    fontId: defaults.fontId,
    fontWeight: defaults.fontWeight,
    fontSize: defaults.fontSize,
    textColor: color,
    activeWordColor: defaults.activeWordColor,
    outlineColor: defaults.outlineColor,
    outlineWidth: defaults.outlineWidth,
    shadowColor: defaults.shadowColor,
    shadowDepth: defaults.shadowDepth,
    alignment: alignment,
    normalizedX: defaults.normalizedX,
    normalizedY: defaults.normalizedY,
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
