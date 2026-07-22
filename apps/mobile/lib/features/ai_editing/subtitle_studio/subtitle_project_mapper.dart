import '../../../core/network/postdee_api_client.dart';
import '../style_options.dart';
import '../subtitle_burn_video_processor.dart';
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

  final sourceSegments = recipe.subtitles.segments
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
        ),
      )
      .toList()
    ..sort(_compareRanges);

  final cues = <SubtitleCue>[
    for (var index = 0; index < preparedSegments.length; index += 1)
      SubtitleCue(
        cueId: 'cue-${index + 1}-${preparedSegments[index].startMs}-'
            '${preparedSegments[index].endMs}',
        sourceStartMs: preparedSegments[index].startMs,
        sourceEndMs: preparedSegments[index].endMs,
        text: preparedSegments[index].text!,
        timingMode: SubtitleTimingMode.segment,
      ),
  ];

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

class _MappedRange {
  const _MappedRange({this.text, required this.startMs, required this.endMs});

  final String? text;
  final int startMs;
  final int endMs;
}
