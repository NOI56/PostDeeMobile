import 'package:characters/characters.dart';

import 'subtitle_project.dart';

typedef SubtitleIdGenerator = String Function();
typedef SubtitleNow = DateTime Function();

class SubtitleProjectEditor {
  SubtitleProjectEditor({
    required SubtitleProject project,
    required SubtitleIdGenerator idGenerator,
    required SubtitleNow now,
    int historyLimit = 50,
  })  : _project = project,
        _idGenerator = idGenerator,
        _now = now,
        _historyLimit = historyLimit {
    if (historyLimit <= 0) {
      throw ArgumentError.value(
          historyLimit, 'historyLimit', 'Must be positive.');
    }
    validateSubtitleProject(project);
  }

  final SubtitleIdGenerator _idGenerator;
  final SubtitleNow _now;
  final int _historyLimit;
  final List<SubtitleProject> _undoHistory = [];
  final List<SubtitleProject> _redoHistory = [];
  SubtitleProject _project;

  SubtitleProject get project => _project;
  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  void updateCueText(String cueId, String text) {
    _mutate((cues) {
      final index = _cueIndex(cues, cueId);
      cues[index] = cues[index].copyWith(
        text: text,
        words: const [],
        timingMode: SubtitleTimingMode.estimated,
      );
      return cues;
    });
  }

  void updateCueTiming(
    String cueId, {
    required int startMs,
    required int endMs,
  }) {
    _mutate((cues) {
      final index = _cueIndex(cues, cueId);
      final cue = cues[index];
      cues[index] = cue.copyWith(
        sourceStartMs: startMs,
        sourceEndMs: endMs,
        words: cue.timingMode == SubtitleTimingMode.word ? const [] : cue.words,
        timingMode: cue.timingMode == SubtitleTimingMode.word
            ? SubtitleTimingMode.estimated
            : cue.timingMode,
      );
      return cues;
    });
  }

  void insertCueAfter(String cueId, SubtitleCue cue) {
    final index = _cueIndex(_project.cues, cueId);
    insertCueAt(index + 1, cue);
  }

  void insertCueAt(int index, SubtitleCue cue) {
    _mutate((cues) {
      if (index < 0 || index > cues.length) {
        throw const SubtitleProjectValidationException(
          'Cue insertion index is out of bounds.',
        );
      }
      cues.insert(index, cue);
      return cues;
    });
  }

  void deleteCue(String cueId) {
    _mutate((cues) {
      cues.removeAt(_cueIndex(cues, cueId));
      return cues;
    });
  }

  void splitCue(String cueId, {required int graphemeOffset}) {
    _mutate((cues) {
      final index = _cueIndex(cues, cueId);
      final cue = cues[index];
      final graphemes = cue.text.characters;
      if (graphemeOffset <= 0 || graphemeOffset >= graphemes.length) {
        throw const SubtitleProjectValidationException(
          'Split offset must be within the cue text.',
        );
      }

      final splitAtMs = cue.sourceStartMs +
          ((cue.sourceEndMs - cue.sourceStartMs) *
              graphemeOffset ~/
              graphemes.length);
      if (splitAtMs <= cue.sourceStartMs || splitAtMs >= cue.sourceEndMs) {
        throw const SubtitleProjectValidationException(
          'Cue timing is too short to split safely.',
        );
      }

      final firstText = graphemes.take(graphemeOffset).toString();
      final secondText = graphemes.skip(graphemeOffset).toString();
      cues[index] = SubtitleCue(
        cueId: cue.cueId,
        sourceStartMs: cue.sourceStartMs,
        sourceEndMs: splitAtMs,
        text: firstText,
        timingMode: SubtitleTimingMode.estimated,
        styleOverride: cue.styleOverride,
        positionOverride: cue.positionOverride,
        soundEffect: cue.soundEffect,
      );
      cues.insert(
        index + 1,
        SubtitleCue(
          cueId: _idGenerator(),
          sourceStartMs: splitAtMs,
          sourceEndMs: cue.sourceEndMs,
          text: secondText,
          timingMode: SubtitleTimingMode.estimated,
          styleOverride: cue.styleOverride,
          positionOverride: cue.positionOverride,
        ),
      );
      return cues;
    });
  }

  void mergeWithNext(String cueId) {
    _mutate((cues) {
      final index = _cueIndex(cues, cueId);
      if (index == cues.length - 1) {
        throw const SubtitleProjectValidationException('Cue has no next cue.');
      }
      final first = cues[index];
      final second = cues[index + 1];
      if (!_stylesEqual(first.styleOverride, second.styleOverride) ||
          first.positionOverride != second.positionOverride) {
        throw const SubtitleProjectValidationException(
          'Cues with different visual overrides cannot be merged safely.',
        );
      }
      if (second.soundEffect != null) {
        throw const SubtitleProjectValidationException(
          'A cue with its own sound effect cannot be merged safely.',
        );
      }
      cues[index] = SubtitleCue(
        cueId: first.cueId,
        sourceStartMs: first.sourceStartMs,
        sourceEndMs: second.sourceEndMs,
        text: _joinCueText(first.text, second.text, _project.language),
        timingMode: SubtitleTimingMode.estimated,
        styleOverride: first.styleOverride,
        positionOverride: first.positionOverride,
        soundEffect: first.soundEffect,
      );
      cues.removeAt(index + 1);
      return cues;
    });
  }

  void undo() {
    if (!canUndo) return;
    _push(_redoHistory, _project);
    _project = _undoHistory.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _push(_undoHistory, _project);
    _project = _redoHistory.removeLast();
  }

  void _mutate(List<SubtitleCue> Function(List<SubtitleCue>) transform) {
    final cues = transform(List<SubtitleCue>.of(_project.cues));
    final next = _project.copyWith(
      cues: cues,
      revision: _project.revision + 1,
      updatedAt: _now(),
    );
    validateSubtitleProject(next);
    _push(_undoHistory, _project);
    _redoHistory.clear();
    _project = next;
  }

  int _cueIndex(List<SubtitleCue> cues, String cueId) {
    final index = cues.indexWhere((cue) => cue.cueId == cueId);
    if (index == -1) {
      throw SubtitleProjectValidationException('Unknown cue ID: $cueId.');
    }
    return index;
  }

  void _push(List<SubtitleProject> history, SubtitleProject project) {
    history.add(project);
    if (history.length > _historyLimit) history.removeAt(0);
  }
}

String _joinCueText(String first, String second, String language) {
  final leftBoundary = first.characters.last;
  final rightBoundary = second.characters.first;
  final leftHasWhitespace = _whitespace.hasMatch(leftBoundary);
  final rightHasWhitespace = _whitespace.hasMatch(rightBoundary);
  if (leftHasWhitespace && rightHasWhitespace) {
    return '$first${second.replaceFirst(RegExp(r'^\s+'), '')}';
  }
  if (leftHasWhitespace || rightHasWhitespace) return '$first$second';

  if (_closingPunctuation.contains(rightBoundary) ||
      _openingOrPrefixPunctuation.contains(leftBoundary)) {
    return '$first$second';
  }
  if (_thai.hasMatch(leftBoundary) && _thai.hasMatch(rightBoundary)) {
    return '$first$second';
  }
  if (_asciiLetterOrDigit.hasMatch(leftBoundary) ||
      _asciiLetterOrDigit.hasMatch(rightBoundary)) {
    return '$first $second';
  }
  if (!language.toLowerCase().startsWith('th') &&
      _wordLike.hasMatch(leftBoundary) &&
      _wordLike.hasMatch(rightBoundary)) {
    return '$first $second';
  }
  return '$first$second';
}

bool _stylesEqual(SubtitleStyle? first, SubtitleStyle? second) {
  if (identical(first, second)) return true;
  if (first == null || second == null) return false;
  return first.fontId == second.fontId &&
      first.fontWeight == second.fontWeight &&
      first.fontSize == second.fontSize &&
      first.textColor == second.textColor &&
      first.activeWordColor == second.activeWordColor &&
      first.outlineColor == second.outlineColor &&
      first.outlineWidth == second.outlineWidth &&
      first.shadowColor == second.shadowColor &&
      first.shadowDepth == second.shadowDepth &&
      first.alignment == second.alignment &&
      first.normalizedX == second.normalizedX &&
      first.normalizedY == second.normalizedY &&
      first.maxLines == second.maxLines &&
      first.animation == second.animation;
}

final _whitespace = RegExp(r'^\s+$');
final _thai = RegExp(r'[\u0E00-\u0E7F]');
final _asciiLetterOrDigit = RegExp(r'[A-Za-z0-9]');
final _wordLike = RegExp(r'[\p{L}\p{N}]', unicode: true);
const _closingPunctuation = <String>{
  '.',
  ',',
  '!',
  '?',
  ':',
  ';',
  '%',
  ')',
  ']',
  '}',
  '»',
  '”',
  '’',
};
const _openingOrPrefixPunctuation = <String>{
  '(',
  '[',
  '{',
  '«',
  '“',
  '‘',
  r'$',
  '฿',
  '€',
  '£',
  '¥',
};
