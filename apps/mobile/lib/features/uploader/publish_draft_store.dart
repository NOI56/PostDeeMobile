import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'cover_image_processor.dart';
import 'platform_publish_settings.dart';
import 'publish_draft.dart';

abstract class PublishDraftStore {
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request);
  Future<PublishDraft?> loadDraft(String draftId);
  Future<List<PublishDraft>> listDrafts();
  Future<void> deleteDraft(String draftId);
  Future<void> deleteAllDrafts();
}

class FilePublishDraftStore implements PublishDraftStore {
  FilePublishDraftStore({
    required Directory rootDirectory,
    required Directory ownerRootBoundary,
    required String ownerUserId,
    Future<void> Function()? beforePromotion,
    Future<void> Function(Directory directory)? deleteDraftDirectory,
  })  : _rootDirectory = rootDirectory,
        _ownerRootBoundary = ownerRootBoundary,
        _ownerUserId = ownerUserId,
        _beforePromotion = beforePromotion,
        _deleteDraftDirectory = deleteDraftDirectory;

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
  static final RegExp _safeRelativePath = RegExp(
    r'^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$',
  );
  static final RegExp _submissionRequestId = RegExp(
    r'^submit_[0-9a-f]{64}$',
  );

  final Directory _rootDirectory;
  final Directory _ownerRootBoundary;
  final String _ownerUserId;
  final Future<void> Function()? _beforePromotion;
  final Future<void> Function(Directory directory)? _deleteDraftDirectory;
  static final Map<String, Future<void>> _operationTails = {};

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) =>
      Future.sync(() => _runSerialized(request.id, () async {
            _validateId(request.id);
            await _validateSaveRequest(request);
            await _rootDirectory.create(recursive: true);

            final target = _draftDirectory(request.id);
            final next = _siblingDirectory(target, '.next');
            final backup = _siblingDirectory(target, '.backup');
            await _recoverIfNeeded(request.id);

            final hadTarget = await target.exists();
            await _deleteDirectoryIfExists(next);
            await next.create(recursive: true);

            try {
              final manifest = await _materializeRequest(request, next);
              await File(_join(next.path, 'manifest.json')).writeAsString(
                jsonEncode(manifest),
                flush: true,
              );
              final validated = await _readDraft(next, request.id);
              if (validated == null) {
                throw const PublishDraftValidationException(
                  'Draft could not be validated before saving.',
                );
              }

              await _beforePromotion?.call();
              var rotatedTarget = false;
              try {
                if (hadTarget) {
                  await _deleteDirectoryIfExists(backup);
                  await target.rename(backup.path);
                  rotatedTarget = true;
                }
                await next.rename(target.path);
                await _deleteDirectoryIfExists(backup);
              } catch (_) {
                if (rotatedTarget &&
                    !await target.exists() &&
                    await backup.exists()) {
                  try {
                    await backup.rename(target.path);
                  } catch (_) {
                    // Keep recovery artifacts when the filesystem cannot restore.
                  }
                }
                rethrow;
              }
              return (await _readDraft(target, request.id))!;
            } catch (_) {
              if (hadTarget) await _deleteDirectoryIfExists(next);
              rethrow;
            }
          }));

  @override
  Future<PublishDraft?> loadDraft(String draftId) =>
      Future.sync(() => _runSerialized(draftId, () async {
            _validateId(draftId);
            await _recoverIfNeeded(draftId);
            return _readDraft(_draftDirectory(draftId), draftId);
          }));

  @override
  Future<List<PublishDraft>> listDrafts() async {
    _validateOwnerUserId();
    if (!await _rootDirectory.exists()) return const [];

    final ids = <String>{};
    await for (final entity in _rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      var name = _basename(entity.path);
      for (final suffix in const ['.next', '.backup']) {
        if (name.endsWith(suffix)) {
          name = name.substring(0, name.length - suffix.length);
        }
      }
      if (_safeId.hasMatch(name)) ids.add(name);
    }

    final drafts = <PublishDraft>[];
    for (final id in ids) {
      final draft = await loadDraft(id);
      if (draft != null) drafts.add(draft);
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(drafts);
  }

  @override
  Future<void> deleteDraft(String draftId) =>
      Future.sync(() => _runSerialized(draftId, () async {
            _validateId(draftId);
            final target = _draftDirectory(draftId);
            final artifacts = [
              target,
              _siblingDirectory(target, '.next'),
              _siblingDirectory(target, '.backup'),
            ];
            for (final artifact in artifacts) {
              try {
                final deleteDirectory =
                    _deleteDraftDirectory ?? _deleteDirectoryIfExists;
                await deleteDirectory(artifact);
              } catch (_) {
                // Try every artifact before checking the raw filesystem. A
                // partial delete must never be reported as a successful erase.
              }
            }
            final leftovers = <String>[];
            for (final artifact in artifacts) {
              final type = await FileSystemEntity.type(
                artifact.path,
                followLinks: false,
              );
              if (type != FileSystemEntityType.notFound) {
                leftovers.add(artifact.path);
              }
            }
            if (leftovers.isNotEmpty) {
              throw FileSystemException(
                'Draft files could not be deleted completely.',
                target.path,
              );
            }
          }));

  @override
  Future<void> deleteAllDrafts() =>
      Future.sync(() => _runSerialized('__all__', () async {
            _validateOwnerRootBoundary();
            final rootType = await FileSystemEntity.type(
              _rootDirectory.path,
              followLinks: false,
            );
            if (rootType == FileSystemEntityType.notFound) return;
            if (rootType != FileSystemEntityType.directory) {
              throw const PublishDraftValidationException(
                'Draft owner directory is unsafe.',
              );
            }
            await _rootDirectory.delete(recursive: true);
          }, validateId: false));

  Future<Map<String, Object?>> _materializeRequest(
    PublishDraftSaveRequest request,
    Directory next,
  ) async {
    final media = Directory(_join(next.path, 'media'));
    await media.create(recursive: true);

    final videoRelativePath =
        'media/video${_safeExtension(request.videoFile.path, '.mp4')}';
    final videoTarget = File(_resolveRelative(next, videoRelativePath).path);
    await request.videoFile.copy(videoTarget.path);
    final videoSizeBytes = await videoTarget.length();

    Map<String, Object?>? cover;
    if (request.coverImageFile != null) {
      final coverRelativePath =
          'media/cover${_safeExtension(request.coverImageFile!.path, '.jpg')}';
      final coverTarget = File(_resolveRelative(next, coverRelativePath).path);
      await request.coverImageFile!.copy(coverTarget.path);

      String? sourceRelativePath;
      int? sourceSizeBytes;
      if (request.coverSourceImageFile != null) {
        sourceRelativePath =
            'media/cover-source${_safeExtension(request.coverSourceImageFile!.path, '.png')}';
        final sourceTarget =
            File(_resolveRelative(next, sourceRelativePath).path);
        await request.coverSourceImageFile!.copy(sourceTarget.path);
        sourceSizeBytes = await sourceTarget.length();
      }

      cover = {
        'imageRelativePath': coverRelativePath,
        'sizeBytes': await coverTarget.length(),
        'durationMs': request.coverDurationMs,
        'sourceKind': request.coverSourceKind.name,
        'sourceImageRelativePath': sourceRelativePath,
        'sourceImageSizeBytes': sourceSizeBytes,
        'sourceImageName': request.coverSourceImageName,
        'design': _coverDesignToJson(request.coverDesign!),
      };
    }

    final platforms = request.platformApiValues.toList()..sort();
    final submissionRequestId = _buildSubmissionRequestId(request.id);
    return {
      'version': publishDraftManifestVersion,
      'id': request.id,
      'ownerUserId': _ownerUserId,
      'submissionRequestId': submissionRequestId,
      'createdAt': request.createdAt.toUtc().toIso8601String(),
      'updatedAt': request.updatedAt.toUtc().toIso8601String(),
      'videoName': request.videoName,
      'videoRelativePath': videoRelativePath,
      'videoSizeBytes': videoSizeBytes,
      'videoWidth': request.videoWidth,
      'videoHeight': request.videoHeight,
      'caption': request.caption,
      'aiGuidance': request.aiGuidance,
      'watermarkEnabled': request.watermarkEnabled,
      'platformApiValues': platforms,
      'platformSettings': request.platformSettings.toDraftJson(),
      'scheduledAt': request.scheduledAt?.toUtc().toIso8601String(),
      'cover': cover,
    };
  }

  Future<void> _recoverIfNeeded(String draftId) async {
    final target = _draftDirectory(draftId);
    final next = _siblingDirectory(target, '.next');
    final backup = _siblingDirectory(target, '.backup');
    final targetDraft = await _readDraft(target, draftId);

    if (targetDraft != null) {
      await _deleteDirectoryIfExists(next);
      await _deleteDirectoryIfExists(backup);
      return;
    }

    final nextDraft = await _readDraft(next, draftId);
    final backupDraft = await _readDraft(backup, draftId);

    if (nextDraft != null) {
      await _deleteDirectoryIfExists(target);
      await next.rename(target.path);
      await _deleteDirectoryIfExists(backup);
      return;
    }
    if (backupDraft != null) {
      await _deleteDirectoryIfExists(target);
      await backup.rename(target.path);
    }
  }

  Future<PublishDraft?> _readDraft(
    Directory directory,
    String expectedId,
  ) async {
    if (!await directory.exists()) return null;
    final manifestFile = File(_join(directory.path, 'manifest.json'));
    if (!await manifestFile.exists()) return null;
    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final manifest = Map<String, Object?>.from(decoded);
      final manifestVersion = manifest['version'];
      if ((manifestVersion != publishDraftManifestVersion &&
              manifestVersion != legacyPublishDraftManifestVersion) ||
          manifest['id'] != expectedId ||
          manifest['ownerUserId'] != _ownerUserId) {
        return null;
      }
      final submissionRequestId = _requiredString(
        manifest,
        'submissionRequestId',
      );
      if (!_submissionRequestId.hasMatch(submissionRequestId)) return null;

      final videoRelativePath = _requiredString(manifest, 'videoRelativePath');
      final videoFile = _resolveRelative(directory, videoRelativePath);
      final expectedVideoSize = _requiredPositiveInt(
        manifest,
        'videoSizeBytes',
      );
      if (!await videoFile.exists() ||
          await videoFile.length() != expectedVideoSize) {
        return null;
      }

      final createdAt = DateTime.parse(_requiredString(manifest, 'createdAt'));
      final updatedAt = DateTime.parse(_requiredString(manifest, 'updatedAt'));
      final platformValues = manifest['platformApiValues'];
      if (platformValues is! List ||
          platformValues.any((value) => value is! String)) {
        return null;
      }
      if (manifestVersion == publishDraftManifestVersion &&
          !manifest.containsKey('platformSettings')) {
        return null;
      }
      final platformSettings = PlatformPublishSettings.fromDraftJson(
        manifest['platformSettings'],
        strict: manifestVersion == publishDraftManifestVersion,
      );

      PublishDraftCover? cover;
      final coverValue = manifest['cover'];
      if (coverValue != null) {
        if (coverValue is! Map<String, dynamic>) return null;
        cover = await _readCover(
          directory,
          Map<String, Object?>.from(coverValue),
        );
        if (cover == null) return null;
      }

      return PublishDraft(
        version: manifestVersion as int,
        id: expectedId,
        ownerUserId: _ownerUserId,
        submissionRequestId: submissionRequestId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        videoPath: videoFile.path,
        videoName: _requiredString(manifest, 'videoName'),
        videoSizeBytes: expectedVideoSize,
        videoWidth: _optionalPositiveInt(manifest['videoWidth']),
        videoHeight: _optionalPositiveInt(manifest['videoHeight']),
        caption: _requiredString(manifest, 'caption', allowEmpty: true),
        aiGuidance: _requiredString(
          manifest,
          'aiGuidance',
          allowEmpty: true,
        ),
        watermarkEnabled: _requiredBool(manifest, 'watermarkEnabled'),
        platformApiValues: Set.unmodifiable(platformValues.cast<String>()),
        platformSettings: platformSettings,
        scheduledAt: _optionalDateTime(manifest['scheduledAt']),
        cover: cover,
      );
    } on FormatException {
      return null;
    } on PublishDraftValidationException {
      return null;
    } on TypeError {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<PublishDraftCover?> _readCover(
    Directory directory,
    Map<String, Object?> json,
  ) async {
    final imageFile = _resolveRelative(
      directory,
      _requiredString(json, 'imageRelativePath'),
    );
    final expectedImageSize = _requiredPositiveInt(json, 'sizeBytes');
    if (!await imageFile.exists() ||
        await imageFile.length() != expectedImageSize) {
      return null;
    }

    String? sourceImagePath;
    final sourceRelativePath = json['sourceImageRelativePath'];
    if (sourceRelativePath != null) {
      if (sourceRelativePath is! String) return null;
      final sourceFile = _resolveRelative(directory, sourceRelativePath);
      final expectedSourceSize = _requiredPositiveInt(
        json,
        'sourceImageSizeBytes',
      );
      if (!await sourceFile.exists() ||
          await sourceFile.length() != expectedSourceSize) {
        return null;
      }
      sourceImagePath = sourceFile.path;
    }

    final designValue = json['design'];
    if (designValue is! Map<String, dynamic>) return null;
    final sourceKindName = _requiredString(json, 'sourceKind');
    final sourceKind = CoverSourceKind.values
        .where((value) => value.name == sourceKindName)
        .firstOrNull;
    if (sourceKind == null) return null;

    return PublishDraftCover(
      imagePath: imageFile.path,
      sizeBytes: expectedImageSize,
      design: _coverDesignFromJson(Map<String, Object?>.from(designValue)),
      durationMs: _optionalPositiveInt(json['durationMs']),
      sourceKind: sourceKind,
      sourceImagePath: sourceImagePath,
      sourceImageName: json['sourceImageName'] as String?,
    );
  }

  Future<void> _validateSaveRequest(PublishDraftSaveRequest request) async {
    if (!await request.videoFile.exists() ||
        await request.videoFile.length() <= 0) {
      throw const PublishDraftValidationException(
        'A non-empty local video is required.',
      );
    }
    if (request.videoName.trim().isEmpty ||
        request.createdAt.isAfter(request.updatedAt)) {
      throw const PublishDraftValidationException('Draft metadata is invalid.');
    }
    if ((request.coverImageFile == null) != (request.coverDesign == null)) {
      throw const PublishDraftValidationException(
        'Cover image and design must be saved together.',
      );
    }
    if (request.coverImageFile != null &&
        (!await request.coverImageFile!.exists() ||
            await request.coverImageFile!.length() <= 0)) {
      throw const PublishDraftValidationException(
          'Cover image is unavailable.');
    }
    if (request.coverSourceImageFile != null &&
        (!await request.coverSourceImageFile!.exists() ||
            await request.coverSourceImageFile!.length() <= 0)) {
      throw const PublishDraftValidationException(
        'Cover source image is unavailable.',
      );
    }
  }

  String _buildSubmissionRequestId(String draftId) {
    final stableDraftIdentity = '$_ownerUserId\u0000$draftId';
    return 'submit_${sha256.convert(utf8.encode(stableDraftIdentity))}';
  }

  Map<String, Object?> _coverDesignToJson(CoverDesign design) => {
        'coverFrameTimeMs': design.coverFrameTimeMs,
        'text': design.text,
        'fontFamily': design.fontFamily.name,
        'fontWeight': design.fontWeight,
        'fontSize': design.fontSize,
        'textColor': design.textColor.toARGB32(),
        'backgroundColor': design.backgroundColor.toARGB32(),
        'dx': design.dx,
        'dy': design.dy,
      };

  CoverDesign _coverDesignFromJson(Map<String, Object?> json) {
    final fontFamilyName = _requiredString(json, 'fontFamily');
    final fontFamily = CoverFontFamily.values
        .where((value) => value.name == fontFamilyName)
        .firstOrNull;
    if (fontFamily == null) {
      throw const PublishDraftValidationException('Unknown cover font.');
    }
    return CoverDesign(
      coverFrameTimeMs: _requiredNonNegativeInt(json, 'coverFrameTimeMs'),
      text: _requiredString(json, 'text', allowEmpty: true),
      fontFamily: fontFamily,
      fontWeight: _requiredPositiveInt(json, 'fontWeight'),
      fontSize: _requiredPositiveNumber(json, 'fontSize'),
      textColor: Color(_requiredNonNegativeInt(json, 'textColor')),
      backgroundColor: Color(_requiredNonNegativeInt(json, 'backgroundColor')),
      dx: _requiredFiniteNumber(json, 'dx'),
      dy: _requiredFiniteNumber(json, 'dy'),
    );
  }

  File _resolveRelative(Directory directory, String relativePath) {
    if (!_safeRelativePath.hasMatch(relativePath) ||
        relativePath.split('/').any((part) => part == '.' || part == '..')) {
      throw const PublishDraftValidationException(
        'Draft contains an unsafe media path.',
      );
    }
    return File(
      _joinAll([directory.path, ...relativePath.split('/')]),
    );
  }

  Directory _draftDirectory(String id) =>
      Directory(_join(_rootDirectory.path, id));

  Directory _siblingDirectory(Directory directory, String suffix) =>
      Directory('${directory.path}$suffix');

  Future<T> _runSerialized<T>(
    String id,
    Future<T> Function() operation, {
    bool validateId = true,
  }) {
    _validateOwnerUserId();
    if (validateId) _validateId(id);
    final serializationKey = _serializationKey();
    final previous = _operationTails[serializationKey] ?? Future<void>.value();
    final future = previous.catchError((_) {}).then<T>((_) => operation());
    final tail = future.then<void>((_) {}, onError: (_, __) {});
    _operationTails[serializationKey] = tail;
    return future.whenComplete(() {
      if (identical(_operationTails[serializationKey], tail)) {
        _operationTails.remove(serializationKey);
      }
    });
  }

  String _serializationKey() {
    final normalizedRoot = _rootDirectory.absolute.path.replaceAll('\\', '/');
    final platformRoot =
        Platform.isWindows ? normalizedRoot.toLowerCase() : normalizedRoot;
    return platformRoot;
  }

  void _validateOwnerRootBoundary() {
    final normalizedRoot = _normalizedAbsolutePath(_rootDirectory);
    final normalizedBoundary = _normalizedAbsolutePath(_ownerRootBoundary);
    final normalizedParent = _normalizedAbsolutePath(_rootDirectory.parent);
    if (normalizedRoot == normalizedBoundary ||
        normalizedParent != normalizedBoundary) {
      throw const PublishDraftValidationException(
        'Draft owner directory is outside its storage boundary.',
      );
    }
  }

  String _normalizedAbsolutePath(Directory directory) {
    var value = directory.absolute.path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  void _validateOwnerUserId() {
    if (_ownerUserId.trim().isEmpty || _ownerUserId.length > 256) {
      throw const PublishDraftValidationException('Draft owner is invalid.');
    }
  }

  void _validateId(String id) {
    if (!_safeId.hasMatch(id)) {
      throw const PublishDraftValidationException('Draft ID is invalid.');
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  String _safeExtension(String path, String fallback) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return fallback;
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : fallback;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  String _join(String left, String right) =>
      '$left${Platform.pathSeparator}$right';

  String _joinAll(List<String> parts) => parts.join(Platform.pathSeparator);

  String _requiredString(
    Map<String, Object?> json,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = json[key];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value;
  }

  int _requiredPositiveInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int || value <= 0) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value;
  }

  bool _requiredBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value;
  }

  int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int || value < 0) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value;
  }

  double _requiredPositiveNumber(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num || !value.isFinite || value <= 0) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value.toDouble();
  }

  double _requiredFiniteNumber(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num || !value.isFinite) {
      throw PublishDraftValidationException('$key is invalid.');
    }
    return value.toDouble();
  }

  int? _optionalPositiveInt(Object? value) {
    if (value == null) return null;
    if (value is! int || value <= 0) {
      throw const PublishDraftValidationException('Numeric value is invalid.');
    }
    return value;
  }

  DateTime? _optionalDateTime(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const PublishDraftValidationException('Date value is invalid.');
    }
    return DateTime.parse(value);
  }
}
