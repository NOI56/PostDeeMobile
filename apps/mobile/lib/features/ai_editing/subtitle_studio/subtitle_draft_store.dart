import 'dart:convert';
import 'dart:io';

import 'subtitle_project.dart';

abstract class SubtitleDraftStore {
  Future<SubtitleProject?> loadDraft(String projectId);
  Future<void> saveDraft(SubtitleProject project);
  Future<void> deleteDraft(String projectId);
}

class FileSubtitleDraftStore implements SubtitleDraftStore {
  FileSubtitleDraftStore({required Directory rootDirectory})
      : _rootDirectory = rootDirectory;

  final Directory _rootDirectory;

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async {
    final file = fileForProject(projectId);
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

  @override
  Future<void> saveDraft(SubtitleProject project) async {
    final target = fileForProject(project.projectId);
    final next = _siblingFile(target, '.next');
    final backup = _siblingFile(target, '.backup');

    await _rootDirectory.create(recursive: true);
    await next.writeAsString(jsonEncode(project.toJson()), flush: true);

    final validated = await _readValidated(next);
    if (validated == null || validated.projectId != project.projectId) {
      await _deleteIfExists(next);
      throw const SubtitleProjectValidationException(
        'Draft could not be validated before saving.',
      );
    }

    var rotatedTarget = false;
    try {
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
  Future<void> deleteDraft(String projectId) async {
    final target = fileForProject(projectId);
    await _deleteIfExists(target);
    await _deleteIfExists(_siblingFile(target, '.next'));
    await _deleteIfExists(_siblingFile(target, '.backup'));
  }

  File fileForProject(String projectId) {
    final encodedId =
        base64Url.encode(utf8.encode(projectId)).replaceAll('=', '');
    return File(
        '${_rootDirectory.path}${Platform.pathSeparator}$encodedId.json');
  }

  File _siblingFile(File file, String suffix) => File('${file.path}$suffix');

  Future<SubtitleProject?> _readValidated(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return SubtitleProject.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    } on SubtitleProjectValidationException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
