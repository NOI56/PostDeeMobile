import '../../core/network/postdee_api_client.dart';

class SpeechReductionReviewGroup {
  const SpeechReductionReviewGroup({
    required this.id,
    required this.text,
    required this.normalizedText,
    required this.occurrences,
  });

  final String id;
  final String text;
  final String normalizedText;
  final List<AiEditSpeechReductionOccurrenceResult> occurrences;
}

class SpeechReductionSelectionSummary {
  const SpeechReductionSelectionSummary({
    required this.totalGroups,
    required this.totalOccurrences,
    required this.removableOccurrences,
    required this.selectedOccurrences,
    required this.keptOccurrences,
    required this.selectedDurationSeconds,
  });

  final int totalGroups;
  final int totalOccurrences;
  final int removableOccurrences;
  final int selectedOccurrences;
  final int keptOccurrences;
  final double selectedDurationSeconds;
}

Set<String> sanitizeSpeechReductionSelection(
  AiEditSpeechReductionResult reduction,
  Set<String>? selectedOccurrenceIds,
) {
  final occurrences = _validOccurrences(reduction);
  final removableIds = <String>{
    for (final occurrence in occurrences)
      if (occurrence.canAutoRemove) occurrence.id,
  };

  final requestedIds = selectedOccurrenceIds ??
      <String>{
        for (final occurrence in occurrences)
          if (occurrence.canAutoRemove && occurrence.selectedByDefault)
            occurrence.id,
        for (final range in reduction.defaultCutRanges)
          if (_isValidCutRange(range.start, range.end) &&
              removableIds.contains(range.occurrenceId))
            range.occurrenceId,
      };

  return Set<String>.unmodifiable({
    for (final occurrence in occurrences)
      if (occurrence.canAutoRemove && requestedIds.contains(occurrence.id))
        occurrence.id,
  });
}

List<AiEditCut> buildSpeechReductionCutRanges(
  AiEditSpeechReductionResult reduction,
  Set<String>? selectedOccurrenceIds,
) {
  final selectedIds = sanitizeSpeechReductionSelection(
    reduction,
    selectedOccurrenceIds,
  );
  if (selectedIds.isEmpty) {
    return const <AiEditCut>[];
  }

  final safeRangesByOccurrenceId = <String, AiEditSpeechReductionCutResult>{};
  for (final range in reduction.defaultCutRanges) {
    if (range.occurrenceId.isEmpty ||
        !_isValidCutRange(range.start, range.end)) {
      continue;
    }
    safeRangesByOccurrenceId.putIfAbsent(range.occurrenceId, () => range);
  }

  final ranges = <AiEditCut>[];
  for (final occurrence in _validOccurrences(reduction)) {
    if (!selectedIds.contains(occurrence.id)) {
      continue;
    }
    final safeRange = safeRangesByOccurrenceId[occurrence.id];
    ranges.add(
      AiEditCut(
        start: safeRange?.start ?? occurrence.start,
        end: safeRange?.end ?? occurrence.end,
      ),
    );
  }
  ranges.sort(_compareCuts);
  return List<AiEditCut>.unmodifiable(ranges);
}

/// Returns only selected occurrences whose complete requested range survived
/// the subtitle-safety pass. Applied ranges may be merged, so containment is
/// used instead of requiring an exact one-to-one range match.
Set<String> resolveAppliedSpeechReductionSelection(
  AiEditSpeechReductionResult reduction,
  Set<String>? selectedOccurrenceIds,
  List<AiEditCut> appliedCutRanges,
) {
  final selectedIds = sanitizeSpeechReductionSelection(
    reduction,
    selectedOccurrenceIds,
  );
  if (selectedIds.isEmpty || appliedCutRanges.isEmpty) {
    return const <String>{};
  }

  final normalizedAppliedRanges = _mergeCuts(appliedCutRanges);
  final safeRangesByOccurrenceId = <String, AiEditSpeechReductionCutResult>{};
  for (final range in reduction.defaultCutRanges) {
    if (range.occurrenceId.isEmpty ||
        !_isValidCutRange(range.start, range.end)) {
      continue;
    }
    safeRangesByOccurrenceId.putIfAbsent(range.occurrenceId, () => range);
  }

  const tolerance = 0.001;
  return Set<String>.unmodifiable({
    for (final occurrence in _validOccurrences(reduction))
      if (selectedIds.contains(occurrence.id) &&
          normalizedAppliedRanges.any((applied) {
            final safeRange = safeRangesByOccurrenceId[occurrence.id];
            final start = safeRange?.start ?? occurrence.start;
            final end = safeRange?.end ?? occurrence.end;
            return applied.start <= start + tolerance &&
                applied.end >= end - tolerance;
          }))
        occurrence.id,
  });
}

List<SpeechReductionReviewGroup> buildSpeechReductionReviewGroups(
  AiEditSpeechReductionResult reduction,
) {
  final occurrences = _validOccurrences(reduction);
  if (occurrences.isEmpty) {
    return const <SpeechReductionReviewGroup>[];
  }

  final metadataById = <String, AiEditSpeechReductionGroupResult>{};
  for (final group in reduction.groups) {
    if (group.id.isNotEmpty) {
      metadataById.putIfAbsent(group.id, () => group);
    }
  }

  final occurrencesByGroupId =
      <String, List<AiEditSpeechReductionOccurrenceResult>>{};
  for (final occurrence in occurrences) {
    final groupId = occurrence.groupId.isNotEmpty
        ? occurrence.groupId
        : 'ungrouped:${occurrence.normalizedText.isNotEmpty ? occurrence.normalizedText : occurrence.id}';
    occurrencesByGroupId
        .putIfAbsent(
          groupId,
          () => <AiEditSpeechReductionOccurrenceResult>[],
        )
        .add(occurrence);
  }

  final groups = <SpeechReductionReviewGroup>[];
  for (final entry in occurrencesByGroupId.entries) {
    final groupOccurrences = entry.value..sort(_compareOccurrences);
    final metadata = metadataById[entry.key];
    final fallback = groupOccurrences.first;
    groups.add(
      SpeechReductionReviewGroup(
        id: entry.key,
        text:
            metadata?.text.isNotEmpty == true ? metadata!.text : fallback.text,
        normalizedText: metadata?.normalizedText.isNotEmpty == true
            ? metadata!.normalizedText
            : fallback.normalizedText,
        occurrences: List<AiEditSpeechReductionOccurrenceResult>.unmodifiable(
          groupOccurrences,
        ),
      ),
    );
  }
  groups.sort((left, right) {
    final byStart = left.occurrences.first.start.compareTo(
      right.occurrences.first.start,
    );
    return byStart != 0 ? byStart : left.id.compareTo(right.id);
  });
  return List<SpeechReductionReviewGroup>.unmodifiable(groups);
}

SpeechReductionSelectionSummary summarizeSpeechReductionSelection(
  AiEditSpeechReductionResult reduction,
  Set<String>? selectedOccurrenceIds,
) {
  final occurrences = _validOccurrences(reduction);
  final selectedIds = sanitizeSpeechReductionSelection(
    reduction,
    selectedOccurrenceIds,
  );
  final ranges = buildSpeechReductionCutRanges(
    reduction,
    selectedOccurrenceIds,
  );

  return SpeechReductionSelectionSummary(
    totalGroups: buildSpeechReductionReviewGroups(reduction).length,
    totalOccurrences: occurrences.length,
    removableOccurrences:
        occurrences.where((occurrence) => occurrence.canAutoRemove).length,
    selectedOccurrences: selectedIds.length,
    keptOccurrences: occurrences.length - selectedIds.length,
    selectedDurationSeconds: _unionDuration(ranges),
  );
}

List<AiEditSpeechReductionOccurrenceResult> _validOccurrences(
  AiEditSpeechReductionResult reduction,
) {
  if (!reduction.isReady) {
    return const <AiEditSpeechReductionOccurrenceResult>[];
  }

  final seenIds = <String>{};
  final occurrences = <AiEditSpeechReductionOccurrenceResult>[];
  for (final occurrence in reduction.occurrences) {
    if (occurrence.id.isEmpty ||
        !seenIds.add(occurrence.id) ||
        !_isValidCutRange(occurrence.start, occurrence.end)) {
      continue;
    }
    occurrences.add(occurrence);
  }
  occurrences.sort(_compareOccurrences);
  return occurrences;
}

bool _isValidCutRange(double start, double end) {
  return start.isFinite && end.isFinite && start >= 0 && end > start;
}

int _compareOccurrences(
  AiEditSpeechReductionOccurrenceResult left,
  AiEditSpeechReductionOccurrenceResult right,
) {
  final byStart = left.start.compareTo(right.start);
  if (byStart != 0) {
    return byStart;
  }
  final byEnd = left.end.compareTo(right.end);
  return byEnd != 0 ? byEnd : left.id.compareTo(right.id);
}

int _compareCuts(AiEditCut left, AiEditCut right) {
  final byStart = left.start.compareTo(right.start);
  return byStart != 0 ? byStart : left.end.compareTo(right.end);
}

double _unionDuration(List<AiEditCut> sortedRanges) {
  if (sortedRanges.isEmpty) {
    return 0;
  }

  var total = 0.0;
  var currentStart = sortedRanges.first.start;
  var currentEnd = sortedRanges.first.end;
  for (final range in sortedRanges.skip(1)) {
    if (range.start <= currentEnd) {
      if (range.end > currentEnd) {
        currentEnd = range.end;
      }
      continue;
    }
    total += currentEnd - currentStart;
    currentStart = range.start;
    currentEnd = range.end;
  }
  return total + currentEnd - currentStart;
}

List<AiEditCut> _mergeCuts(List<AiEditCut> ranges) {
  final sorted = [
    for (final range in ranges)
      if (_isValidCutRange(range.start, range.end)) range,
  ]..sort(_compareCuts);
  if (sorted.isEmpty) {
    return const <AiEditCut>[];
  }

  final merged = <AiEditCut>[];
  var currentStart = sorted.first.start;
  var currentEnd = sorted.first.end;
  for (final range in sorted.skip(1)) {
    if (range.start <= currentEnd) {
      if (range.end > currentEnd) {
        currentEnd = range.end;
      }
      continue;
    }
    merged.add(AiEditCut(start: currentStart, end: currentEnd));
    currentStart = range.start;
    currentEnd = range.end;
  }
  merged.add(AiEditCut(start: currentStart, end: currentEnd));
  return merged;
}
