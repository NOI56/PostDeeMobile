import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import 'subtitle_draft_store.dart';
import 'subtitle_project.dart';
import 'subtitle_project_editor.dart';

class SubtitleStudioController extends ChangeNotifier {
  SubtitleStudioController({
    required SubtitleProject initialProject,
    required SubtitleDraftStore draftStore,
    required SubtitleNow now,
    required SubtitleIdGenerator idGenerator,
    this.autosaveDelay = const Duration(milliseconds: 500),
    this.textCommitDelay = const Duration(milliseconds: 350),
  })  : _initialProject = initialProject,
        _draftStore = draftStore,
        _now = now,
        _idGenerator = idGenerator,
        _editor = SubtitleProjectEditor(
          project: initialProject,
          idGenerator: idGenerator,
          now: now,
        ),
        _selectedCueId = initialProject.cues.isEmpty
            ? null
            : initialProject.cues.first.cueId;

  final SubtitleProject _initialProject;
  final SubtitleDraftStore _draftStore;
  final SubtitleNow _now;
  final SubtitleIdGenerator _idGenerator;
  final Duration autosaveDelay;
  final Duration textCommitDelay;
  SubtitleProjectEditor _editor;
  Timer? _autosaveTimer;
  Timer? _textCommitTimer;
  bool _initialized = false;
  String? _selectedCueId;
  String? _pendingCueId;
  String? _pendingText;
  String? _validationMessage;
  bool _saving = false;

  SubtitleProject get project => _editor.project;
  bool get isInitialized => _initialized;
  bool get canUndo => _editor.canUndo;
  bool get canRedo => _editor.canRedo;
  bool get isSaving => _saving;
  String? get validationMessage => _validationMessage;
  String? get selectedCueId => _selectedCueId;
  SubtitleCue? get selectedCue => _cueById(_selectedCueId);

  String displayTextFor(SubtitleCue cue) =>
      _pendingCueId == cue.cueId ? _pendingText ?? cue.text : cue.text;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final draft = await _draftStore.loadDraft(_initialProject.projectId);
      if (draft != null &&
          draft.sourceFingerprint == _initialProject.sourceFingerprint &&
          draft.sourceDurationMs == _initialProject.sourceDurationMs) {
        _editor = SubtitleProjectEditor(
          project: draft,
          idGenerator: _idGenerator,
          now: _now,
        );
        _selectedCueId = draft.cues.isEmpty ? null : draft.cues.first.cueId;
      }
    } catch (_) {
      _validationMessage =
          'เปิดฉบับร่างเดิมไม่สำเร็จ เริ่มจากซับที่ AI สร้างให้แทน';
    }
    _selectFirstAvailableCue();
    _initialized = true;
    notifyListeners();
  }

  void selectCue(String cueId) {
    if (_cueById(cueId) == null || cueId == _selectedCueId) return;
    if (!_commitPendingText()) return;
    _selectedCueId = cueId;
    _clearError();
    notifyListeners();
  }

  void stageSelectedCueText(String text) {
    final cue = selectedCue;
    if (cue == null) return;
    _pendingCueId = cue.cueId;
    _pendingText = text;
    _validationMessage = text.trim().isEmpty ? 'ข้อความซับต้องไม่ว่าง' : null;
    _textCommitTimer?.cancel();
    if (text.trim().isNotEmpty) {
      _textCommitTimer = Timer(
        textCommitDelay,
        () => unawaited(flushPendingText()),
      );
    }
    notifyListeners();
  }

  Future<bool> flushPendingText() async {
    final committed = _commitPendingText();
    if (committed) await saveNow();
    return committed;
  }

  bool adjustSelectedTiming({int startDeltaMs = 0, int endDeltaMs = 0}) {
    return _runMutation(() {
      final cue = _requireSelectedCue();
      _editor.updateCueTiming(
        cue.cueId,
        startMs: cue.sourceStartMs + startDeltaMs,
        endMs: cue.sourceEndMs + endDeltaMs,
      );
    });
  }

  bool splitSelectedCue() {
    return _runMutation(() {
      final cue = _requireSelectedCue();
      final count = cue.text.characters.length;
      if (count < 2) {
        throw const SubtitleProjectValidationException(
          'ข้อความสั้นเกินไปสำหรับแยกประโยค',
        );
      }
      _editor.splitCue(cue.cueId, graphemeOffset: count ~/ 2);
    });
  }

  bool mergeSelectedWithNext() => _runMutation(() {
        _editor.mergeWithNext(_requireSelectedCue().cueId);
      });

  bool addCueAfterSelected() {
    return _runMutation(() {
      final cues = project.cues;
      final selected = selectedCue;
      final index = selected == null
          ? -1
          : cues.indexWhere((cue) => cue.cueId == selected.cueId);
      final startMs = selected?.sourceEndMs ?? 0;
      final endLimit = index >= 0 && index + 1 < cues.length
          ? cues[index + 1].sourceStartMs
          : project.sourceDurationMs;
      if (endLimit - startMs < 300) {
        throw const SubtitleProjectValidationException(
          'ช่วงว่างสั้นเกินไปสำหรับเพิ่มซับใหม่',
        );
      }
      final cue = SubtitleCue(
        cueId: _idGenerator(),
        sourceStartMs: startMs,
        sourceEndMs: startMs + (endLimit - startMs).clamp(300, 1500),
        text: 'ซับใหม่',
        timingMode: SubtitleTimingMode.estimated,
      );
      if (selected == null) {
        _editor.insertCueAt(0, cue);
      } else {
        _editor.insertCueAfter(selected.cueId, cue);
      }
      _selectedCueId = cue.cueId;
    });
  }

  bool deleteSelectedCue() {
    return _runMutation(() {
      final cue = _requireSelectedCue();
      final index = project.cues.indexWhere((item) => item.cueId == cue.cueId);
      _editor.deleteCue(cue.cueId);
      if (project.cues.isEmpty) {
        _selectedCueId = null;
      } else {
        _selectedCueId =
            project.cues[index.clamp(0, project.cues.length - 1)].cueId;
      }
    });
  }

  void updateDefaultStyle(SubtitleStyle style) {
    _runMutation(() => _editor.updateDefaultStyle(style));
  }

  void undo() {
    if (!_commitPendingText() || !_editor.canUndo) return;
    _editor.undo();
    _repairSelection();
    _scheduleAutosave();
    notifyListeners();
  }

  void redo() {
    if (!_commitPendingText() || !_editor.canRedo) return;
    _editor.redo();
    _repairSelection();
    _scheduleAutosave();
    notifyListeners();
  }

  bool cueIsRemovedByCut(SubtitleCue cue) => project.cutRanges.any(
        (range) =>
            range.sourceStartMs <= cue.sourceStartMs &&
            range.sourceEndMs >= cue.sourceEndMs,
      );

  SubtitleCue? cueAt(int sourcePositionMs) {
    for (final cue in project.cues) {
      if (cue.sourceStartMs <= sourcePositionMs &&
          sourcePositionMs < cue.sourceEndMs &&
          !cueIsRemovedByCut(cue)) {
        return cue;
      }
    }
    return null;
  }

  Future<void> saveNow() async {
    _autosaveTimer?.cancel();
    _saving = true;
    notifyListeners();
    try {
      await _draftStore.saveDraft(project);
    } catch (_) {
      _validationMessage = 'บันทึกฉบับร่างไม่สำเร็จ แต่ยังแก้ต่อได้';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<SubtitleProject> finish() async {
    if (!_commitPendingText()) {
      throw const SubtitleProjectValidationException('ข้อความซับต้องไม่ว่าง');
    }
    await saveNow();
    validateSubtitleProject(project);
    return project;
  }

  bool _runMutation(VoidCallback mutation) {
    if (!_commitPendingText()) return false;
    try {
      mutation();
      _clearError();
      _scheduleAutosave();
      notifyListeners();
      return true;
    } on SubtitleProjectValidationException catch (error) {
      _validationMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  bool _commitPendingText() {
    _textCommitTimer?.cancel();
    final cueId = _pendingCueId;
    final text = _pendingText;
    if (cueId == null || text == null) return true;
    if (text.trim().isEmpty) {
      _validationMessage = 'ข้อความซับต้องไม่ว่าง';
      notifyListeners();
      return false;
    }
    final cue = _cueById(cueId);
    _pendingCueId = null;
    _pendingText = null;
    if (cue != null && cue.text != text) {
      _editor.updateCueText(cueId, text);
      _scheduleAutosave();
    }
    _clearError();
    notifyListeners();
    return true;
  }

  SubtitleCue _requireSelectedCue() {
    final cue = selectedCue;
    if (cue == null) {
      throw const SubtitleProjectValidationException('กรุณาเลือกประโยคซับ');
    }
    return cue;
  }

  SubtitleCue? _cueById(String? cueId) {
    if (cueId == null) return null;
    for (final cue in project.cues) {
      if (cue.cueId == cueId) return cue;
    }
    return null;
  }

  void _repairSelection() {
    if (_cueById(_selectedCueId) != null) return;
    _selectedCueId = project.cues.isEmpty ? null : project.cues.first.cueId;
  }

  void _selectFirstAvailableCue() {
    for (final cue in project.cues) {
      if (!cueIsRemovedByCut(cue)) {
        _selectedCueId = cue.cueId;
        return;
      }
    }
    _selectedCueId = project.cues.isEmpty ? null : project.cues.first.cueId;
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(autosaveDelay, () => unawaited(saveNow()));
  }

  void _clearError() => _validationMessage = null;

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _textCommitTimer?.cancel();
    super.dispose();
  }
}

SubtitleStyle copySubtitleStyle(
  SubtitleStyle style, {
  String? fontId,
  int? fontWeight,
  double? fontSize,
  String? textColor,
  String? activeWordColor,
  String? outlineColor,
  double? outlineWidth,
  String? shadowColor,
  double? shadowDepth,
  SubtitleAlignment? alignment,
  double? normalizedX,
  double? normalizedY,
  int? maxLines,
  String? animation,
}) =>
    SubtitleStyle(
      fontId: fontId ?? style.fontId,
      fontWeight: fontWeight ?? style.fontWeight,
      fontSize: fontSize ?? style.fontSize,
      textColor: textColor ?? style.textColor,
      activeWordColor: activeWordColor ?? style.activeWordColor,
      outlineColor: outlineColor ?? style.outlineColor,
      outlineWidth: outlineWidth ?? style.outlineWidth,
      shadowColor: shadowColor ?? style.shadowColor,
      shadowDepth: shadowDepth ?? style.shadowDepth,
      alignment: alignment ?? style.alignment,
      normalizedX: normalizedX ?? style.normalizedX,
      normalizedY: normalizedY ?? style.normalizedY,
      maxLines: maxLines ?? style.maxLines,
      animation: animation ?? style.animation,
    );
