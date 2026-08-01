import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/speech_reduction_review.dart';

const _readyReduction = AiEditSpeechReductionResult(
  version: 1,
  status: 'ready',
  groups: [
    AiEditSpeechReductionGroupResult(
      id: 'late-group',
      text: 'really',
      normalizedText: 'really',
      totalOccurrences: 2,
      occurrenceIds: ['late-cut', 'late-overlap'],
    ),
    AiEditSpeechReductionGroupResult(
      id: 'early-group',
      text: 'actually',
      normalizedText: 'actually',
      totalOccurrences: 1,
      occurrenceIds: ['early-keep'],
    ),
    AiEditSpeechReductionGroupResult(
      id: 'frequent-group',
      text: 'brand',
      normalizedText: 'brand',
      totalOccurrences: 1,
      occurrenceIds: ['frequent-only'],
    ),
  ],
  occurrences: [
    AiEditSpeechReductionOccurrenceResult(
      id: 'late-overlap',
      groupId: 'late-group',
      text: 'really',
      normalizedText: 'really',
      start: 5.25,
      end: 5.5,
      occurrenceIndex: 2,
      occurrenceCount: 2,
      kind: 'adjacent-word',
      recommendation: 'cut',
      selectedByDefault: true,
      confidence: 0.9,
      contextBefore: 'really',
      contextAfter: 'good',
      canAutoRemove: true,
    ),
    AiEditSpeechReductionOccurrenceResult(
      id: 'early-keep',
      groupId: 'early-group',
      text: 'actually',
      normalizedText: 'actually',
      start: 1,
      end: 1.25,
      occurrenceIndex: 1,
      occurrenceCount: 1,
      kind: 'adjacent-word',
      recommendation: 'keep',
      selectedByDefault: false,
      confidence: 0.72,
      contextBefore: 'I',
      contextAfter: 'like it',
      canAutoRemove: true,
    ),
    AiEditSpeechReductionOccurrenceResult(
      id: 'late-cut',
      groupId: 'late-group',
      text: 'really',
      normalizedText: 'really',
      start: 5,
      end: 5.3,
      occurrenceIndex: 1,
      occurrenceCount: 2,
      kind: 'adjacent-word',
      recommendation: 'cut',
      selectedByDefault: true,
      confidence: 0.94,
      contextBefore: 'is',
      contextAfter: 'really good',
      canAutoRemove: true,
    ),
    AiEditSpeechReductionOccurrenceResult(
      id: 'frequent-only',
      groupId: 'frequent-group',
      text: 'brand',
      normalizedText: 'brand',
      start: 8,
      end: 8.4,
      occurrenceIndex: 1,
      occurrenceCount: 1,
      kind: 'frequent-only',
      recommendation: 'keep',
      selectedByDefault: true,
      confidence: 0.4,
      contextBefore: '',
      contextAfter: '',
      canAutoRemove: false,
    ),
    AiEditSpeechReductionOccurrenceResult(
      id: 'orphan',
      groupId: 'missing-group',
      text: 'well',
      normalizedText: 'well',
      start: 3,
      end: 3.2,
      occurrenceIndex: 1,
      occurrenceCount: 1,
      kind: 'adjacent-word',
      recommendation: 'keep',
      selectedByDefault: false,
      confidence: 0.65,
      contextBefore: '',
      contextAfter: '',
      canAutoRemove: true,
    ),
  ],
  defaultCutRanges: [
    AiEditSpeechReductionCutResult(
      occurrenceId: 'late-cut',
      start: 4.98,
      end: 5.32,
    ),
    AiEditSpeechReductionCutResult(
      occurrenceId: 'late-overlap',
      start: 5.24,
      end: 5.52,
    ),
  ],
);

void main() {
  test('null selection uses defaults while an empty set keeps everything', () {
    expect(
      sanitizeSpeechReductionSelection(_readyReduction, null),
      {'late-cut', 'late-overlap'},
    );
    expect(
      sanitizeSpeechReductionSelection(_readyReduction, <String>{}),
      isEmpty,
    );
  });

  test('selection removes unknown and non-removable occurrence IDs', () {
    expect(
      sanitizeSpeechReductionSelection(
        _readyReduction,
        {'early-keep', 'missing', 'frequent-only'},
      ),
      {'early-keep'},
    );
  });

  test('cut ranges prefer server-safe defaults and fall back to occurrence',
      () {
    final defaults = buildSpeechReductionCutRanges(_readyReduction, null);
    expect(defaults, hasLength(2));
    expect(defaults.first.start, 4.98);
    expect(defaults.first.end, 5.32);
    expect(defaults.last.start, 5.24);
    expect(defaults.last.end, 5.52);

    final explicit = buildSpeechReductionCutRanges(
      _readyReduction,
      {'early-keep'},
    );
    expect(explicit, hasLength(1));
    expect(explicit.single.start, 1);
    expect(explicit.single.end, 1.25);
  });

  test('review groups and occurrences are ordered by their timeline', () {
    final groups = buildSpeechReductionReviewGroups(_readyReduction);

    expect(
      groups.map((group) => group.id),
      ['early-group', 'missing-group', 'late-group', 'frequent-group'],
    );
    expect(
      groups[2].occurrences.map((occurrence) => occurrence.id),
      ['late-cut', 'late-overlap'],
    );
    expect(groups[1].text, 'well');
  });

  test('summary counts kept items and unions overlapping cut durations', () {
    final summary = summarizeSpeechReductionSelection(_readyReduction, null);

    expect(summary.totalGroups, 4);
    expect(summary.totalOccurrences, 5);
    expect(summary.removableOccurrences, 4);
    expect(summary.selectedOccurrences, 2);
    expect(summary.keptOccurrences, 3);
    expect(summary.selectedDurationSeconds, closeTo(0.54, 0.0001));
  });

  test('applied selection contains only occurrences accepted by sanitizer', () {
    expect(
      resolveAppliedSpeechReductionSelection(
        _readyReduction,
        null,
        const [AiEditCut(start: 4.98, end: 5.4)],
      ),
      {'late-cut'},
    );
    expect(
      resolveAppliedSpeechReductionSelection(
        _readyReduction,
        null,
        const [AiEditCut(start: 4.98, end: 5.52)],
      ),
      {'late-cut', 'late-overlap'},
    );
  });

  test('unavailable results stay empty and never produce cuts', () {
    const unavailable = AiEditSpeechReductionResult.unavailable(
      unavailableReason: 'unsafe-word-timing',
    );

    expect(sanitizeSpeechReductionSelection(unavailable, null), isEmpty);
    expect(buildSpeechReductionCutRanges(unavailable, null), isEmpty);
    expect(buildSpeechReductionReviewGroups(unavailable), isEmpty);
    expect(
      summarizeSpeechReductionSelection(unavailable, null).selectedOccurrences,
      0,
    );
  });
}
