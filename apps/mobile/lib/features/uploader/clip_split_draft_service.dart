import 'dart:io';
import 'dart:math';

import 'clip_segmenter.dart';
import 'clip_group_draft.dart';
import 'clip_group_draft_store.dart';
import 'cover_image_processor.dart';
import 'clip_split_plan.dart';
import 'platform_publish_settings.dart';
import 'platform_publish_preflight.dart';
import 'publish_draft.dart';
import 'publish_draft_store.dart';

class ClipSplitDraftRequest {
  const ClipSplitDraftRequest({
    required this.plan,
    required this.inputFile,
    required this.fileName,
    required this.store,
    required this.ownerUserId,
    this.caption = '',
    this.aiGuidance = '',
    this.captionLanguage = 'auto',
    this.watermarkEnabled = false,
    this.platformSettings = const PlatformPublishSettings(),
    this.sourceMetadata,
    this.isCancelled,
    this.onProgress,
    this.sourceDraftId,
  });

  final ClipSplitPlan plan;
  final File inputFile;
  final String fileName;
  final PublishDraftStore store;
  final String ownerUserId;
  final String caption;
  final String aiGuidance;
  final String captionLanguage;
  final bool watermarkEnabled;
  final PlatformPublishSettings platformSettings;
  final PublishMediaMetadata? sourceMetadata;
  final bool Function()? isCancelled;
  final void Function(int completed, int total)? onProgress;
  final String? sourceDraftId;
}

class ClipSplitDraftBatchResult {
  ClipSplitDraftBatchResult({
    required List<PublishDraft> drafts,
    required Map<String, PublishMediaMetadata> metadataByDraftId,
    required this.totalPostUnits,
    this.group,
    this.sourceDraft,
  })  : drafts = List.unmodifiable(drafts),
        metadataByDraftId = Map.unmodifiable(metadataByDraftId);

  final List<PublishDraft> drafts;
  final Map<String, PublishMediaMetadata> metadataByDraftId;
  final int totalPostUnits;
  final ClipGroupDraft? group;
  final PublishDraft? sourceDraft;
}

class ClipSplitDraftException implements Exception {
  ClipSplitDraftException(
    this.message, {
    this.isCancelled = false,
    List<String> residualDraftIds = const [],
    List<String> residualGroupIds = const [],
    this.cleanupFailed = false,
  })  : residualDraftIds = List.unmodifiable(residualDraftIds),
        residualGroupIds = List.unmodifiable(residualGroupIds);

  final String message;
  final bool isCancelled;
  final List<String> residualDraftIds;
  final List<String> residualGroupIds;
  final bool cleanupFailed;

  @override
  String toString() => message;
}

/// Prepares device-local drafts only. Each draft keeps the existing publishing,
/// consent, idempotency and quota checks when the seller later submits it.
class ClipSplitDraftService {
  ClipSplitDraftService({
    UploaderClipSegmenter? segmenter,
    DateTime Function()? now,
    String Function()? createDraftId,
  })  : _segmenter = segmenter ?? FfmpegClipSegmenter().call,
        _now = now ?? DateTime.now,
        _createDraftId = createDraftId ?? _newDraftId;

  final UploaderClipSegmenter _segmenter;
  final DateTime Function() _now;
  final String Function() _createDraftId;
  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  Future<ClipSplitDraftBatchResult> call(ClipSplitDraftRequest request) async {
    ClipSegmentBatchResult? rendered;
    var cleanupAttempted = false;
    final intendedIds = <String>[];
    ClipGroupDraftStore? groupStore;
    ClipGroupDraft? intendedGroup;
    ClipGroupDraft? savedGroup;
    PublishDraft? originalDraft;
    PublishDraft? taggedSource;
    var sourceTagAttempted = false;
    try {
      _checkpoint(request);
      if (request.ownerUserId.trim().isEmpty ||
          request.ownerUserId.length > 256 ||
          request.fileName.trim().isEmpty ||
          request.plan.groupedParts.isEmpty ||
          request.plan.groupedParts.length > maxClipSplitParts) {
        throw ClipSplitDraftException(
            'ข้อมูลสำหรับแบ่งคลิปไม่ครบ กรุณาเลือกคลิปใหม่');
      }
      final sourceStamp = await _sourceStamp(request);
      final existing = await request.store.listDrafts();
      _checkpoint(request);
      if (existing.any((draft) => draft.ownerUserId != request.ownerUserId)) {
        throw ClipSplitDraftException(
            'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดฉบับร่างใหม่',
            isCancelled: true);
      }
      final reserved = existing.map((draft) => draft.id).toSet();
      if (request.sourceDraftId != null) {
        if (request.store is! ClipGroupDraftStore ||
            !isValidClipGroupId(request.sourceDraftId)) {
          throw ClipSplitDraftException('พื้นที่ฉบับร่างยังเก็บชุดคลิปไม่ได้');
        }
        groupStore = request.store as ClipGroupDraftStore;
        originalDraft = await request.store.loadDraft(request.sourceDraftId!);
        _checkpoint(request);
        if (originalDraft == null ||
            originalDraft.ownerUserId != request.ownerUserId ||
            originalDraft.clipGroupId != null ||
            _normalizedPath(await File(originalDraft.videoPath)
                    .resolveSymbolicLinks()) !=
                _normalizedPath(
                    await request.inputFile.resolveSymbolicLinks())) {
          throw ClipSplitDraftException(
              'เลือกฉบับร่างต้นฉบับใหม่ก่อนสร้างชุดคลิป');
        }
        _checkpoint(request);
      }
      final ids = <int, String>{};
      for (final part in request.plan.groupedParts) {
        ids[part.index] = await _reserveId(request, reserved);
      }
      String? groupId;
      if (groupStore != null) {
        for (var attempt = 0; attempt < 128; attempt++) {
          final candidate = await _reserveId(request, reserved);
          final collision = await groupStore.loadClipGroup(candidate);
          _checkpoint(request);
          if (collision == null) {
            groupId = candidate;
            break;
          }
        }
        if (groupId == null) {
          throw ClipSplitDraftException('สร้างชุดคลิปใหม่ไม่สำเร็จ');
        }
      }
      await _checkSource(request, sourceStamp);

      final ranges = [
        for (final part in request.plan.groupedParts)
          if (!part.isOriginal)
            ClipSegmentRange(
              index: part.index,
              startSeconds: part.startSeconds,
              endSeconds: part.endSeconds,
              minimumDurationSeconds: part.minDurationSeconds,
              maximumDurationSeconds: part.maxDurationSeconds,
            ),
      ];
      final encoded = <int, ClipSegmentResult>{};
      if (ranges.isNotEmpty) {
        rendered = await _segmenter(ClipSegmentRequest(
          inputFile: request.inputFile,
          fileName: request.fileName,
          ranges: ranges,
          isCancelled: request.isCancelled,
          onProgress: request.onProgress,
        ));
        await _checkSource(request, sourceStamp);
        await _validateRendered(request, rendered, ranges, encoded);
      }

      final drafts = <PublishDraft>[];
      final metadataByDraftId = <String, PublishMediaMetadata>{};
      final createdAt = _now().toUtc();
      for (final part in request.plan.groupedParts) {
        await _checkSource(request, sourceStamp);
        final id = ids[part.index]!;
        // saveDraft is an upsert. Never reuse an existing identity, including
        // one that appeared while encoding this batch.
        final collision = await request.store.loadDraft(id);
        _checkpoint(request);
        if (collision != null) {
          throw ClipSplitDraftException(
              'สร้างฉบับร่างใหม่ไม่สำเร็จ กรุณาลองอีกครั้ง');
        }
        final video =
            part.isOriginal ? request.inputFile : encoded[part.index]!.file;
        final metadata = part.isOriginal
            ? _originalMetadata(request, sourceStamp.sizeBytes)
            : encoded[part.index]!.metadata;
        // A filesystem promotion can succeed before saveDraft throws. Record
        // the intended identity first so rollback also removes that copy.
        intendedIds.add(id);
        final saved = await request.store.saveDraft(PublishDraftSaveRequest(
          id: id,
          createdAt: createdAt,
          updatedAt: createdAt,
          videoFile: video,
          videoName: part.isOriginal
              ? request.fileName
              : _partDisplayName(request.fileName, part),
          videoSizeBytes: metadata.sizeBytes,
          videoWidth: metadata.width,
          videoHeight: metadata.height,
          caption: request.caption,
          captionNeedsReview: request.caption.trim().isNotEmpty ||
              request.platformSettings.platformCaptions.values
                  .any((text) => text.trim().isNotEmpty),
          captionLanguage: request.captionLanguage,
          aiGuidance: request.aiGuidance,
          watermarkEnabled: request.watermarkEnabled,
          platformApiValues: part.platforms.map((p) => p.apiValue).toSet(),
          platformSettings: request.platformSettings.copyWith(
            youtubeCommunityGuidelinesCertified: false,
            tiktokMusicUsageConfirmed: false,
            tiktokBrandedContentPolicyConfirmed: false,
            tiktokCreatorInfoRevision: null,
            tiktokVideoDurationSeconds: null,
          ),
          clipGroupId: groupId,
          // Each new media intent starts without another clip's consent,
          // upload receipt, cover frame or scheduled time.
        ));
        _checkpoint(request);
        if (saved.id != id || saved.ownerUserId != request.ownerUserId) {
          throw ClipSplitDraftException(
              'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดฉบับร่างใหม่',
              isCancelled: true);
        }
        drafts.add(saved);
        metadataByDraftId[id] = metadata;
      }
      await _checkSource(request, sourceStamp);
      if (groupStore != null && originalDraft != null) {
        intendedGroup = ClipGroupDraft(
          id: groupId!,
          ownerUserId: request.ownerUserId,
          sourceDraftId: originalDraft.id,
          title: request.fileName,
          sharedCaption: request.caption,
          deliveryMode: ClipGroupDeliveryMode.immediate,
          createdAt: createdAt,
          updatedAt: createdAt,
          items: [
            for (final part in request.plan.groupedParts)
              ClipGroupItem(
                draftId: ids[part.index]!,
                index: part.index,
                sourceStartSeconds: part.startSeconds,
                sourceEndSeconds: part.endSeconds,
                platformApiValues:
                    part.platforms.map((p) => p.apiValue).toSet(),
              ),
          ],
        );
        savedGroup = await groupStore.saveClipGroup(intendedGroup,
            expectedRevision: null);
        _checkpoint(request);
        final latestSource = await request.store.loadDraft(originalDraft.id);
        _checkpoint(request);
        if (!_sameSourceIdentity(originalDraft, latestSource) ||
            latestSource!.clipGroupId != null ||
            latestSource.videoSizeBytes != originalDraft.videoSizeBytes) {
          throw ClipSplitDraftException(
              'ต้นฉบับเปลี่ยนแล้ว กรุณาเปิดชุดคลิปอีกครั้ง');
        }
        sourceTagAttempted = true;
        taggedSource = await request.store.saveDraft(_sourceSaveRequest(
            latestSource,
            clipGroupId: savedGroup.id,
            isSource: true));
        _checkpoint(request);
      }
      if (rendered != null) {
        cleanupAttempted = true;
        try {
          await rendered.cleanupTemporaryFiles();
        } catch (_) {
          throw ClipSplitDraftException('ล้างไฟล์แบ่งคลิปชั่วคราวไม่สำเร็จ',
              cleanupFailed: true);
        }
      }
      _checkpoint(request);
      return ClipSplitDraftBatchResult(
        drafts: drafts,
        metadataByDraftId: metadataByDraftId,
        totalPostUnits: request.plan.totalPostUnits,
        group: savedGroup,
        sourceDraft: taggedSource,
      );
    } catch (error) {
      var groupCleanupFailed = false;
      var rollbackAllowed = true;
      final residualGroups = <String>[];
      if (groupStore != null && intendedGroup != null) {
        try {
          final current = await groupStore.loadClipGroup(intendedGroup.id);
          if (current != null &&
              current.sourceDraftId == intendedGroup.sourceDraftId &&
              current.items.length == intendedGroup.items.length &&
              current.items
                  .every((item) => intendedIds.contains(item.draftId))) {
            final store = groupStore;
            rollbackAllowed = store is ClipGroupDraftRollbackStore &&
                await (store as ClipGroupDraftRollbackStore)
                    .deleteUnacceptedClipGroup(intendedGroup.id,
                        expectedRevision: savedGroup?.revision ?? 1);
            if (!rollbackAllowed) {
              groupCleanupFailed = true;
              residualGroups.add(intendedGroup.id);
            }
          }
        } catch (_) {
          groupCleanupFailed = true;
          rollbackAllowed = false;
          residualGroups.add(intendedGroup.id);
        }
      }
      if (rollbackAllowed && sourceTagAttempted && originalDraft != null) {
        try {
          final latestSource = await request.store.loadDraft(originalDraft.id);
          if (_sameSourceIdentity(originalDraft, latestSource) &&
              latestSource!.clipGroupId == intendedGroup?.id) {
            await request.store.saveDraft(_sourceSaveRequest(latestSource,
                clipGroupId: originalDraft.clipGroupId,
                isSource: originalDraft.isClipGroupSource));
          }
        } catch (_) {
          groupCleanupFailed = true;
        }
      }
      final residualIds = rollbackAllowed
          ? await _rollback(request.store, intendedIds)
          : await _existingDraftIds(request.store, intendedIds);
      var cleanupFailed = groupCleanupFailed ||
          (error is ClipSplitDraftException && error.cleanupFailed);
      if (rendered != null && !cleanupAttempted) {
        cleanupAttempted = true;
        try {
          await rendered.cleanupTemporaryFiles();
        } catch (_) {
          cleanupFailed = true;
        }
      }
      final cancelled = _isCancelled(request) ||
          (error is ClipSplitDraftException && error.isCancelled) ||
          (error is ClipSegmentException && error.isCancelled);
      final message = residualGroups.isNotEmpty
          ? 'ชุดคลิปมีข้อมูลใหม่แล้ว จึงเก็บชุดและฉบับร่างไว้ กรุณาเปิดชุดคลิปอีกครั้ง'
          : residualIds.isNotEmpty
              ? 'แบ่งคลิปไม่สำเร็จ และยังล้างร่างบางตอนไม่ครบ กรุณาตรวจฉบับร่างก่อนลองใหม่'
              : cleanupFailed
                  ? 'แบ่งคลิปไม่สำเร็จ และยังล้างไฟล์ชั่วคราวไม่ครบ'
                  : cancelled
                      ? 'หยุดแบ่งคลิปแล้ว ต้นฉบับยังอยู่'
                      : error is ClipSplitDraftException
                          ? error.message
                          : 'เตรียมร่างจากการแบ่งคลิปไม่สำเร็จ กรุณาตรวจพื้นที่ว่างแล้วลองใหม่';
      throw ClipSplitDraftException(message,
          isCancelled: cancelled,
          residualDraftIds: residualIds,
          residualGroupIds: residualGroups,
          cleanupFailed: cleanupFailed);
    }
  }

  bool _sameSourceIdentity(PublishDraft original, PublishDraft? latest) =>
      latest != null &&
      latest.id == original.id &&
      latest.ownerUserId == original.ownerUserId &&
      latest.submissionRequestId == original.submissionRequestId &&
      _normalizedPath(latest.videoPath) == _normalizedPath(original.videoPath);

  Future<List<String>> _existingDraftIds(
      PublishDraftStore store, List<String> ids) async {
    final existing = <String>[];
    for (final id in ids) {
      try {
        if (await store.loadDraft(id) != null) existing.add(id);
      } catch (_) {
        existing.add(id);
      }
    }
    return existing;
  }

  PublishDraftSaveRequest _sourceSaveRequest(PublishDraft source,
      {required String? clipGroupId, required bool isSource}) {
    final cover = source.cover;
    return PublishDraftSaveRequest(
      id: source.id,
      createdAt: source.createdAt,
      updatedAt: _now().toUtc(),
      videoFile: File(source.videoPath),
      videoName: source.videoName,
      videoSizeBytes: source.videoSizeBytes,
      videoWidth: source.videoWidth,
      videoHeight: source.videoHeight,
      caption: source.caption,
      captionNeedsReview: source.captionNeedsReview,
      captionLanguage: source.captionLanguage,
      aiGuidance: source.aiGuidance,
      watermarkEnabled: source.watermarkEnabled,
      platformApiValues: source.platformApiValues,
      platformSettings: source.platformSettings,
      scheduledAt: source.scheduledAt,
      uploadedMedia: source.uploadedMedia,
      coverImageFile: cover == null ? null : File(cover.imagePath),
      coverDesign: cover?.design,
      coverDurationMs: cover?.durationMs,
      coverSourceKind: cover?.sourceKind ?? CoverSourceKind.videoFrame,
      coverSourceImageFile:
          cover?.sourceImagePath == null ? null : File(cover!.sourceImagePath!),
      coverSourceImageName: cover?.sourceImageName,
      clipGroupId: clipGroupId,
      isClipGroupSource: isSource,
    );
  }

  Future<String> _reserveId(
      ClipSplitDraftRequest request, Set<String> reserved) async {
    for (var attempt = 0; attempt < 128; attempt++) {
      _checkpoint(request);
      final candidate = _createDraftId();
      if (!_safeId.hasMatch(candidate) || reserved.contains(candidate)) {
        continue;
      }
      final found = await request.store.loadDraft(candidate);
      _checkpoint(request);
      if (found != null) {
        reserved.add(candidate);
        continue;
      }
      reserved.add(candidate);
      return candidate;
    }
    throw ClipSplitDraftException(
        'สร้างฉบับร่างใหม่ไม่สำเร็จ กรุณาลองอีกครั้ง');
  }

  Future<void> _validateRendered(
    ClipSplitDraftRequest request,
    ClipSegmentBatchResult rendered,
    List<ClipSegmentRange> ranges,
    Map<int, ClipSegmentResult> encoded,
  ) async {
    if (rendered.parts.length != ranges.length) {
      throw ClipSplitDraftException(
          'ตรวจไฟล์แต่ละตอนไม่สำเร็จ กรุณาลองแบ่งคลิปใหม่');
    }
    final byIndex = {for (final range in ranges) range.index: range};
    final paths = <String>{};
    final inputPath =
        _normalizedPath(await request.inputFile.resolveSymbolicLinks());
    _checkpoint(request);
    for (final result in rendered.parts) {
      _checkpoint(request);
      final range = byIndex[result.index];
      if (range == null || encoded.containsKey(result.index)) {
        throw ClipSplitDraftException(
            'ตรวจไฟล์แต่ละตอนไม่สำเร็จ กรุณาลองแบ่งคลิปใหม่');
      }
      final path = _normalizedPath(await result.file.resolveSymbolicLinks());
      _checkpoint(request);
      final size = await result.file.length();
      _checkpoint(request);
      final meta = result.metadata;
      final duration = meta.durationSeconds;
      final expected = range.endSeconds - range.startSeconds;
      if (path == inputPath ||
          !paths.add(path) ||
          (result.startSeconds - range.startSeconds).abs() > 0.000001 ||
          (result.endSeconds - range.endSeconds).abs() > 0.000001 ||
          size <= 0 ||
          meta.sizeBytes != size ||
          !meta.hasVideo ||
          meta.width == null ||
          meta.width! <= 0 ||
          meta.height == null ||
          meta.height! <= 0 ||
          duration == null ||
          !duration.isFinite ||
          duration < range.minimumDurationSeconds ||
          duration > range.maximumDurationSeconds ||
          (duration - expected).abs() > 1 / 30 + 0.025 ||
          (request.sourceMetadata?.hasAudio == true && !meta.hasAudio)) {
        throw ClipSplitDraftException(
            'ตรวจไฟล์แต่ละตอนไม่สำเร็จ กรุณาลองแบ่งคลิปใหม่');
      }
      encoded[result.index] = result;
    }
  }

  PublishMediaMetadata _originalMetadata(
      ClipSplitDraftRequest request, int size) {
    final source = request.sourceMetadata;
    return PublishMediaMetadata(
      durationSeconds: request.plan.sourceDurationSeconds,
      width: source?.width,
      height: source?.height,
      sizeBytes: size,
      hasVideo: source?.hasVideo ?? true,
      hasAudio: source?.hasAudio ?? false,
      videoCodec: source?.videoCodec,
      audioCodec: source?.audioCodec,
      fps: source?.fps,
      sampleRate: source?.sampleRate,
      channels: source?.channels,
      container: source?.container,
    );
  }

  Future<({int sizeBytes, DateTime modified})> _sourceStamp(
      ClipSplitDraftRequest request) async {
    _checkpoint(request);
    final stamp = await request.inputFile.stat();
    _checkpoint(request);
    if (stamp.type != FileSystemEntityType.file || stamp.size <= 0) {
      throw ClipSplitDraftException('ไม่พบวิดีโอต้นฉบับ กรุณาเลือกคลิปใหม่');
    }
    return (sizeBytes: stamp.size, modified: stamp.modified);
  }

  Future<void> _checkSource(ClipSplitDraftRequest request,
      ({int sizeBytes, DateTime modified}) expected) async {
    final current = await _sourceStamp(request);
    if (current != expected) {
      throw ClipSplitDraftException(
          'วิดีโอต้นฉบับเปลี่ยนแล้ว กรุณาเลือกคลิปอีกครั้ง');
    }
  }

  Future<List<String>> _rollback(
      PublishDraftStore store, List<String> ids) async {
    final residual = <String>[];
    for (final id in ids.reversed) {
      try {
        await store.deleteDraft(id);
        if (await store.loadDraft(id) != null) residual.add(id);
      } catch (_) {
        residual.add(id);
      }
    }
    return residual;
  }

  bool _isCancelled(ClipSplitDraftRequest request) {
    try {
      return request.isCancelled?.call() ?? false;
    } catch (_) {
      return true;
    }
  }

  void _checkpoint(ClipSplitDraftRequest request) {
    if (_isCancelled(request)) {
      throw ClipSplitDraftException('หยุดแบ่งคลิปแล้ว ต้นฉบับยังอยู่',
          isCancelled: true);
    }
  }

  static String _newDraftId() {
    final random = Random.secure();
    return 'split_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  String _partDisplayName(String name, ClipSplitPart part) {
    final base =
        name.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.[^.]+$'), '');
    String clock(double value) {
      final seconds = value.floor();
      return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    }

    return '$base (${clock(part.startSeconds)}-${clock(part.endSeconds)}).mp4';
  }

  String _normalizedPath(String path) {
    final value = path.replaceAll('\\', '/');
    return Platform.isWindows ? value.toLowerCase() : value;
  }
}
