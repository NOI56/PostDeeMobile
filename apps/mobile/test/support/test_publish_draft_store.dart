import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';

class TestPublishDraftStore implements PublishDraftStore {
  TestPublishDraftStore({this.ownerUserId = 'test-user'});

  final String ownerUserId;
  final Map<String, PublishDraft> drafts = {};
  final List<PublishDraftSaveRequest> savedRequests = [];

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    savedRequests.add(request);
    final coverFile = request.coverImageFile;
    final coverDesign = request.coverDesign;
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
      caption: request.caption,
      aiGuidance: request.aiGuidance,
      watermarkEnabled: request.watermarkEnabled,
      platformApiValues: request.platformApiValues,
      platformSettings: request.platformSettings,
      scheduledAt: request.scheduledAt,
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
  }
}

String _submissionRequestId(String seed) {
  final encoded = seed.codeUnits
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final digest = (encoded + List.filled(64, '0').join()).substring(0, 64);
  return 'submit_$digest';
}
