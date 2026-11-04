import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
import 'test_publish_media_identity.dart';

class TestPublishDraftStore
    implements
        PublishDraftStore,
        ClipGroupDraftStore,
        ClipGroupDraftRollbackStore {
  TestPublishDraftStore({this.ownerUserId = 'test-user'});

  final String ownerUserId;
  final Map<String, PublishDraft> drafts = {};
  final List<PublishDraftSaveRequest> savedRequests = [];
  final Map<String, ClipGroupDraft> groups = {};

  @override
  Future<ClipGroupDraft?> loadClipGroup(String id) async {
    final group = groups[id];
    return group?.ownerUserId == ownerUserId ? group : null;
  }

  @override
  Future<List<ClipGroupDraft>> listClipGroups() async =>
      groups.values.where((group) => group.ownerUserId == ownerUserId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
      {required int? expectedRevision}) async {
    validateClipGroupDraft(group);
    if (group.ownerUserId != ownerUserId) {
      throw const ClipGroupDraftException('Wrong group owner');
    }
    final existing = groups[group.id];
    if ((expectedRevision == null && existing != null) ||
        (expectedRevision != null && existing?.revision != expectedRevision)) {
      throw const ClipGroupDraftConflictException();
    }
    if (existing != null) {
      if (existing.sourceDraftId != group.sourceDraftId ||
          existing.items.length != group.items.length) {
        throw const ClipGroupDraftException('Group identity changed');
      }
      for (var i = 0; i < existing.items.length; i++) {
        final old = existing.items[i];
        final next = group.items[i];
        if (old.draftId != next.draftId ||
            old.index != next.index ||
            old.sourceStartSeconds != next.sourceStartSeconds ||
            old.sourceEndSeconds != next.sourceEndSeconds ||
            (old.isAccepted && old.acceptedPostId != next.acceptedPostId)) {
          throw const ClipGroupDraftException('Group identity changed');
        }
      }
    }
    final saved = group.copyWith(revision: (existing?.revision ?? 0) + 1);
    groups[group.id] = saved;
    return saved;
  }

  @override
  Future<void> deleteClipGroup(String id) async {
    groups.remove(id);
  }

  @override
  Future<bool> deleteUnacceptedClipGroup(String id,
      {required int expectedRevision}) async {
    final current = await loadClipGroup(id);
    if (current == null) return true;
    if (current.revision != expectedRevision ||
        current.items.any((item) => item.isAccepted)) {
      return false;
    }
    groups.remove(id);
    return true;
  }

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    savedRequests.add(request);
    final coverFile = request.coverImageFile;
    final coverDesign = request.coverDesign;
    final fingerprint = testPublishMediaFingerprint(request);
    final draft = PublishDraft(
      version: publishDraftManifestVersion,
      id: request.id,
      ownerUserId: ownerUserId,
      submissionRequestId: _submissionRequestId(request.id),
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      videoPath: request.videoFile.path,
      videoName: request.videoName,
      videoSizeBytes: request.videoFile.lengthSync(),
      videoWidth: request.videoWidth,
      videoHeight: request.videoHeight,
      clipGroupId: request.clipGroupId,
      isClipGroupSource: request.isClipGroupSource,
      caption: request.caption,
      captionNeedsReview: request.captionNeedsReview,
      aiGuidance: request.aiGuidance,
      captionLanguage: request.captionLanguage,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: request.platformApiValues,
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
      mediaContentFingerprint: fingerprint,
      uploadedMedia:
          request.uploadedMedia?.mediaContentFingerprint == fingerprint
              ? request.uploadedMedia
              : null,
      cover: coverFile == null || coverDesign == null
          ? null
          : PublishDraftCover(
              imagePath: coverFile.path,
              sizeBytes: coverFile.lengthSync(),
              design: coverDesign,
              durationMs: request.coverDurationMs,
              sourceKind: request.coverSourceKind,
              sourceImagePath: request.coverSourceImageFile?.path,
              sourceImageName: request.coverSourceImageName,
            ),
    );
    drafts[draft.id] = draft;
    return draft;
  }

  @override
  Future<PublishDraft?> loadDraft(String draftId) async => drafts[draftId];

  @override
  Future<List<PublishDraft>> listDrafts() async {
    final values = drafts.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    drafts.remove(draftId);
  }

  @override
  Future<void> deleteAllDrafts() async {
    drafts.clear();
    groups.clear();
  }
}

String _submissionRequestId(String seed) {
  final encoded = seed.codeUnits
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final digest = (encoded + List.filled(64, '0').join()).substring(0, 64);
  return 'submit_$digest';
}
