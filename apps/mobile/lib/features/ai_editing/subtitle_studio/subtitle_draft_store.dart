import 'dart:convert';
import 'dart:io';

import 'subtitle_project.dart';

abstract class SubtitleDraftStore {
  Future<SubtitleProject?> loadDraft(String projectId);
  Future<void> saveDraft(SubtitleProject project);
  Future<void> deleteDraft(String projectId);
}

class FileSubtitleDraftStore implements SubtitleDraftStore {
  static const maxProjectIdUtf8Bytes = 90;

  FileSubtitleDraftStore({
    required Directory rootDirectory,
    Future<void> Function()? beforePromotion,
    void Function()? onOperationStart,
  })  : _rootDirectory = rootDirectory,
        _beforePromotion = beforePromotion,
        _onOperationStart = onOperationStart;

  final Directory _rootDirectory;
  final Future<void> Function()? _beforePromotion;
  final void Function()? _onOperationStart;
  final Map<String, Future<void>> _operationTails = {};

  @override
  Future<SubtitleProject?> loadDraft(String projectId) =>
      Future.sync(() => _runSerialized(projectId, () async {
            _onOperationStart?.call();
            return _loadDraft(projectId);
          }));

  Future<SubtitleProject?> _loadDraft(String projectId) async {
    final file = fileForProject(projectId);
    await _recoverIfNeeded(projectId, file);
    if (!await file.exists()) return null;

    return _readMatchingProject(file, projectId);
  }

  @override
  Future<void> saveDraft(SubtitleProject project) =>
      Future.sync(() => _runSerialized(project.projectId, () async {
            _onOperationStart?.call();
            await _saveDraft(project);
          }));

  Future<void> _saveDraft(SubtitleProject project) async {
    final target = fileForProject(project.projectId);
    final next = _siblingFile(target, '.next');
    final backup = _siblingFile(target, '.backup');

    await _rootDirectory.create(recursive: true);
    await _recoverIfNeeded(project.projectId, target);
    await next.writeAsString(jsonEncode(project.toJson()), flush: true);

    if (await _readMatchingProject(next, project.projectId) == null) {
      await _deleteIfExists(next);
      throw const SubtitleProjectValidationException(
        'Draft could not be validated before saving.',
      );
    }

    var rotatedTarget = false;
    try {
      await _beforePromotion?.call();
      await _deleteIfExists(backup);
      if (await target.exists()) {
        await target.rename(backup.path);
        rotatedTarget = true;
      }
      await next.rename(target.path);
      await _deleteIfExists(backup);
    } catch (_) {
      if (rotatedTarget && !await target.exists() && await backup.exists()) {
        try {
          await backup.rename(target.path);
        } catch (_) {
          // Preserve the backup when restoration itself cannot complete.
        }
      }
      await _deleteIfExists(next);
      rethrow;
    }
  }

  @override
  Future<void> deleteDraft(String projectId) =>
      Future.sync(() => _runSerialized(projectId, () async {
            _onOperationStart?.call();
            await _deleteDraft(projectId);
          }));

  Future<void> _deleteDraft(String projectId) async {
    final target = fileForProject(projectId);
    await _deleteIfExists(target);
    await _deleteIfExists(_siblingFile(target, '.next'));
    await _deleteIfExists(_siblingFile(target, '.backup'));
  }

  File fileForProject(String projectId) {
    final encodedId = _encodedProjectId(projectId);
    return File(
        '${_rootDirectory.path}${Platform.pathSeparator}$encodedId.json');
  }

  File _siblingFile(File file, String suffix) => File('${file.path}$suffix');

  Future<void> _recoverIfNeeded(String projectId, File target) async {
    if (await target.exists()) return;

    final next = _siblingFile(target, '.next');
    final backup = _siblingFile(target, '.backup');
    final nextProject = await _readMatchingProject(next, projectId);
    final backupProject = await _readMatchingProject(backup, projectId);

    if (nextProject != null) {
      await next.rename(target.path);
      if (backupProject != null) await _deleteIfExists(backup);
      return;
    }
    if (backupProject != null) await backup.rename(target.path);
  }

  Future<SubtitleProject?> _readMatchingProject(
    File file,
    String projectId,
  ) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final project = SubtitleProject.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return project.projectId == projectId ? project : null;
    } on FormatException {
      return null;
    } on SubtitleProjectValidationException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<T> _runSerialized<T>(
    String projectId,
    Future<T> Function() operation,
  ) {
    final key = _encodedProjectId(projectId);
    final previous = _operationTails[key] ?? Future<void>.value();
    final operationFuture =
        previous.catchError((_) {}).then<T>((_) => operation());
    final tail = operationFuture.then<void>((_) {}, onError: (_, __) {});
    _operationTails[key] = tail;
    return operationFuture.whenComplete(() {
      if (identical(_operationTails[key], tail)) _operationTails.remove(key);
    });
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  String _encodedProjectId(String projectId) {
    final projectIdBytes = utf8.encode(projectId);
    if (projectIdBytes.length > maxProjectIdUtf8Bytes) {
      throw const SubtitleProjectValidationException(
        'Project ID is too long for local draft storage.',
      );
    }
    final base64UrlId = base64Url.encode(projectIdBytes).replaceAll('=', '');
    return base64UrlId.codeUnits
        .map((codeUnit) => codeUnit.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
