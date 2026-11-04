import 'dart:convert';
import 'dart:io';

import 'clip_group_draft.dart';

abstract interface class ClipGroupDraftStore {
  Future<ClipGroupDraft?> loadClipGroup(String id);
  Future<List<ClipGroupDraft>> listClipGroups();
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
      {required int? expectedRevision});
  Future<void> deleteClipGroup(String id);
}

/// Optional atomic rollback capability; ordinary group-store implementers keep
/// their existing interface. A false result preserves newer/accepted user work.
abstract interface class ClipGroupDraftRollbackStore {
  Future<bool> deleteUnacceptedClipGroup(String id,
      {required int expectedRevision});
}

class ClipGroupDraftException implements Exception {
  const ClipGroupDraftException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ClipGroupDraftConflictException extends ClipGroupDraftException {
  const ClipGroupDraftConflictException()
      : super('ชุดคลิปเปลี่ยนแล้ว กรุณาเปิดชุดคลิปอีกครั้ง');
}

typedef ClipGroupOperationSerializer = Future<T> Function<T>(
    Future<T> Function() operation);

/// Shares the existing owner's operation queue with ordinary draft mutations.
/// A separate small journal avoids recopying every video for each checkpoint.
class FileClipGroupDraftRepository
    implements ClipGroupDraftStore, ClipGroupDraftRollbackStore {
  FileClipGroupDraftRepository({
    required Directory rootDirectory,
    required String ownerUserId,
    required ClipGroupOperationSerializer serialize,
    required void Function() validateBoundary,
  })  : _ownerRoot = rootDirectory,
        _owner = ownerUserId,
        _serialize = serialize,
        _validateBoundary = validateBoundary;

  final Directory _ownerRoot;
  final String _owner;
  final ClipGroupOperationSerializer _serialize;
  final void Function() _validateBoundary;
  Directory get _root =>
      Directory('${_ownerRoot.path}${Platform.pathSeparator}.clip-groups');

  @override
  Future<ClipGroupDraft?> loadClipGroup(String id) => _serialize(() async {
        await _validateRoot();
        _validateId(id);
        return _recover(id);
      });

  @override
  Future<List<ClipGroupDraft>> listClipGroups() => _serialize(() async {
        await _validateRoot();
        if (!await _root.exists()) return const [];
        final ids = <String>{};
        await for (final file in _root.list(followLinks: false)) {
          if (file is! File) continue;
          var name = file.uri.pathSegments.last;
          for (final suffix in ['.next', '.backup']) {
            if (name.endsWith(suffix)) {
              name = name.substring(0, name.length - suffix.length);
            }
          }
          if (!name.endsWith('.json')) continue;
          final id = name.substring(0, name.length - 5);
          if (isValidClipGroupId(id)) ids.add(id);
        }
        final groups = <ClipGroupDraft>[];
        for (final id in ids) {
          final group = await _recover(id);
          if (group != null) groups.add(group);
        }
        groups.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return List.unmodifiable(groups);
      });

  @override
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
          {required int? expectedRevision}) =>
      _serialize(() async {
        await _validateRoot();
        try {
          validateClipGroupDraft(group);
        } on FormatException {
          throw const ClipGroupDraftException('ข้อมูลชุดคลิปไม่ถูกต้อง');
        }
        if (group.ownerUserId != _owner) {
          throw const ClipGroupDraftException('ชุดคลิปนี้เป็นของบัญชีอื่น');
        }
        final current = await _recover(group.id);
        if ((expectedRevision == null && current != null) ||
            (expectedRevision != null &&
                current?.revision != expectedRevision)) {
          throw const ClipGroupDraftConflictException();
        }
        if (current == null) {
          for (final path in [
            _file(group.id).path,
            '${_file(group.id).path}.next',
            '${_file(group.id).path}.backup'
          ]) {
            if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              throw const ClipGroupDraftException(
                  'อ่านข้อมูลชุดคลิปเดิมไม่ได้ กรุณาตรวจฉบับร่าง');
            }
          }
          // This shares deleteAllDrafts' owner queue. A late create must not
          // resurrect the removed account directory after its source vanished.
          if (!await _hasOwnedSource(group.sourceDraftId, group.id)) {
            throw const ClipGroupDraftException(
                'ไม่พบฉบับร่างต้นฉบับของชุดคลิป');
          }
          for (final item in group.items) {
            if (!await _hasCompatibleMember(item.draftId, group.id)) {
              throw const ClipGroupDraftException(
                  'ฉบับร่างเป็นส่วนหนึ่งของชุดคลิปอื่น');
            }
          }
        }
        if (current != null) _validateUpdate(current, group);
        final saved = group.copyWith(revision: (current?.revision ?? 0) + 1);
        final encoded = jsonEncode(saved.toJson());
        if (utf8.encode(encoded).length > 262144) {
          throw const ClipGroupDraftException('ข้อมูลชุดคลิปมีขนาดใหญ่เกินไป');
        }
        await _root.create(recursive: true);
        final target = _file(saved.id);
        final next = File('${target.path}.next');
        final backup = File('${target.path}.backup');
        await _remove(next);
        await next.writeAsString(encoded, flush: true);
        if (await _read(next, saved.id) == null) {
          throw const ClipGroupDraftException('บันทึกชุดคลิปไม่สำเร็จ');
        }
        var rotated = false;
        try {
          if (await target.exists()) {
            await _remove(backup);
            await target.rename(backup.path);
            rotated = true;
          }
          await next.rename(target.path);
          await _remove(backup);
        } catch (_) {
          if (rotated && !await target.exists() && await backup.exists()) {
            try {
              await backup.rename(target.path);
            } catch (_) {/* Retain recovery files. */}
          }
          rethrow;
        }
        return saved;
      });

  @override
  Future<void> deleteClipGroup(String id) => _serialize(() async {
        await _validateRoot();
        _validateId(id);
        final target = _file(id);
        for (final path in [
          target.path,
          '${target.path}.next',
          '${target.path}.backup'
        ]) {
          await _remove(File(path));
        }
      });

  @override
  Future<bool> deleteUnacceptedClipGroup(String id,
          {required int expectedRevision}) =>
      _serialize(() async {
        await _validateRoot();
        _validateId(id);
        final current = await _recover(id);
        final target = _file(id);
        final paths = [
          target.path,
          '${target.path}.next',
          '${target.path}.backup'
        ];
        if (current == null) {
          for (final path in paths) {
            if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              return false;
            }
          }
          return true;
        }
        if (current.revision != expectedRevision ||
            current.items.any((item) => item.isAccepted)) {
          return false;
        }
        for (final path in paths) {
          await _remove(File(path));
        }
        return true;
      });

  Future<ClipGroupDraft?> _recover(String id) async {
    final target = _file(id);
    final next = File('${target.path}.next');
    final backup = File('${target.path}.backup');
    final current = await _read(target, id);
    if (current != null) {
      await _remove(next);
      await _remove(backup);
      return current;
    }
    final pending = await _read(next, id);
    final previous = await _read(backup, id);
    final recovered = pending ?? previous;
    if (recovered == null) return null;
    await _remove(target);
    if (pending != null) {
      await next.rename(target.path);
      await _remove(backup);
    } else {
      await backup.rename(target.path);
      await _remove(next);
    }
    return recovered;
  }

  Future<ClipGroupDraft?> _read(File file, String id) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    try {
      if (await file.length() > 262144) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final group = ClipGroupDraft.fromJson(json);
      return group.id == id && group.ownerUserId == _owner ? group : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _validateRoot() async {
    _validateBoundary();
    if (_owner.trim().isEmpty) {
      throw const ClipGroupDraftException('บัญชีไม่ถูกต้อง');
    }
    for (final path in [_ownerRoot.path, _root.path]) {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const ClipGroupDraftException('พื้นที่ชุดคลิปไม่ปลอดภัย');
      }
    }
  }

  Future<bool> _hasOwnedSource(String id, String groupId) async {
    final source = File(
        '${_ownerRoot.path}${Platform.pathSeparator}$id${Platform.pathSeparator}manifest.json');
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    try {
      if (await source.length() > 1048576) return false;
      final json = jsonDecode(await source.readAsString());
      return json is Map<String, dynamic> &&
          json['id'] == id &&
          json['ownerUserId'] == _owner &&
          (json['clipGroupId'] == null || json['clipGroupId'] == groupId);
    } on FormatException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _hasCompatibleMember(String id, String groupId) async {
    final member = File(
        '${_ownerRoot.path}${Platform.pathSeparator}$id${Platform.pathSeparator}manifest.json');
    final type = await FileSystemEntity.type(member.path, followLinks: false);
    // Missing members remain explicit recovery work, never an accepted post.
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.file) return false;
    try {
      if (await member.length() > 1048576) return false;
      final json = jsonDecode(await member.readAsString());
      return json is Map<String, dynamic> &&
          json['id'] == id &&
          json['ownerUserId'] == _owner &&
          json['clipGroupId'] == groupId &&
          json['isClipGroupSource'] != true;
    } on FormatException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  void _validateUpdate(ClipGroupDraft previous, ClipGroupDraft next) {
    bool sameIdentity(ClipGroupItem a, ClipGroupItem b) =>
        a.draftId == b.draftId &&
        a.index == b.index &&
        a.sourceStartSeconds == b.sourceStartSeconds &&
        a.sourceEndSeconds == b.sourceEndSeconds &&
        a.platformApiValues.length == b.platformApiValues.length &&
        a.platformApiValues.containsAll(b.platformApiValues);
    if (previous.sourceDraftId != next.sourceDraftId ||
        previous.createdAt != next.createdAt ||
        previous.items.length != next.items.length) {
      throw const ClipGroupDraftException('สมาชิกชุดคลิปเปลี่ยนแล้ว');
    }
    for (var i = 0; i < previous.items.length; i++) {
      final old = previous.items[i];
      final item = next.items[i];
      if (!sameIdentity(old, item) ||
          (old.isAccepted &&
              (old.acceptedPostId != item.acceptedPostId ||
                  old.acceptedScheduledAt != item.acceptedScheduledAt))) {
        throw const ClipGroupDraftException(
            'เปลี่ยนรายการโพสต์ที่รับแล้วไม่ได้');
      }
    }
  }

  void _validateId(String id) {
    if (!isValidClipGroupId(id)) {
      throw const ClipGroupDraftException('รหัสชุดคลิปไม่ถูกต้อง');
    }
  }

  File _file(String id) =>
      File('${_root.path}${Platform.pathSeparator}$id.json');
  Future<void> _remove(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw const ClipGroupDraftException('ไฟล์ชุดคลิปไม่ปลอดภัย');
    }
    await file.delete();
  }
}
