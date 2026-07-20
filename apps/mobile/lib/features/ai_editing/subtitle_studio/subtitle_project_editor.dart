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
    _mutate((cues) {
      final index = _cueIndex(cues, cueId);
      cues.insert(index + 1, cue);
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
          soundEffect: cue.soundEffect,
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
      cues[index] = SubtitleCue(
        cueId: first.cueId,
        sourceStartMs: first.sourceStartMs,
        sourceEndMs: second.sourceEndMs,
        text: '${first.text}${second.text}',
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
