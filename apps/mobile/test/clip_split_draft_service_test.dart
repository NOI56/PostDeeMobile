import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_segmenter.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/clip_split_draft_service.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';

const _owner = 'split-owner';
final _now = DateTime.utc(2026, 11, 4, 15);

class _ControlledStore
    implements
        PublishDraftStore,
        ClipGroupDraftStore,
        ClipGroupDraftRollbackStore {
  _ControlledStore(this.delegate);

  final PublishDraftStore delegate;
  final List<PublishDraftSaveRequest> saves = [];
  final List<String> deleted = [];
  int? failAfterSave;
  int? failBeforeSave;
  void Function(int saved)? afterSave;
  bool failDelete = false;
  bool failGroupAfterSave = false;
  bool failSourceTagAfterSave = false;
  Future<void> Function(ClipGroupDraft group)? afterGroupSave;

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    saves.add(request);
    if (saves.length == failBeforeSave) throw const FileSystemException('full');
    final draft = await delegate.saveDraft(request);
    if (request.isClipGroupSource && failSourceTagAfterSave) {
      throw const FileSystemException('late source tag');
    }
    afterSave?.call(saves.length);
    if (saves.length == failAfterSave) throw const FileSystemException('late');
    return draft;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deleted.add(id);
    if (failDelete) throw const FileSystemException('busy');
    await delegate.deleteDraft(id);
  }

  @override
  Future<PublishDraft?> loadDraft(String id) => delegate.loadDraft(id);
  @override
  Future<List<PublishDraft>> listDrafts() => delegate.listDrafts();
  @override
  Future<void> deleteAllDrafts() => delegate.deleteAllDrafts();

  @override
  Future<ClipGroupDraft?> loadClipGroup(String id) =>
      (delegate as ClipGroupDraftStore).loadClipGroup(id);
  @override
  Future<List<ClipGroupDraft>> listClipGroups() =>
      (delegate as ClipGroupDraftStore).listClipGroups();
  @override
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
      {required int? expectedRevision}) async {
    final saved = await (delegate as ClipGroupDraftStore)
        .saveClipGroup(group, expectedRevision: expectedRevision);
    await afterGroupSave?.call(saved);
    if (failGroupAfterSave) {
      throw const FileSystemException('late group commit');
    }
    return saved;
  }

  @override
  Future<void> deleteClipGroup(String id) =>
      (delegate as ClipGroupDraftStore).deleteClipGroup(id);

  @override
  Future<bool> deleteUnacceptedClipGroup(String id,
          {required int expectedRevision}) =>
      (delegate as ClipGroupDraftRollbackStore)
          .deleteUnacceptedClipGroup(id, expectedRevision: expectedRevision);
}

class _Fixture {
  _Fixture(this.root) {
    source = File('${root.path}/original.mp4')
      ..writeAsBytesSync(List.filled(512, 7));
    final boundary = Directory('${root.path}/owners');
    store = _ControlledStore(FilePublishDraftStore(
      rootDirectory: Directory('${boundary.path}/owner'),
      ownerRootBoundary: boundary,
      ownerUserId: _owner,
    ));
  }

  final Directory root;
  late File source;
  late _ControlledStore store;
  ClipSegmentRequest? segmentRequest;
  bool cancelled = false;
  int cleanupCalls = 0;
  int id = 0;
  bool cleanupFails = false;
  int? invalidIndex;
  bool duplicateOutput = false;
  bool missingOutput = false;
  bool sourceChangesDuringEncode = false;
  String? invalidMedia;
  Future<void> Function()? beforeCleanup;

  ClipSplitPlan plan({bool all = false, double duration = 270}) =>
      ClipSplitPlan.create(
        sourceDurationSeconds: duration,
        platforms: {
          SocialPlatform.facebookReels,
          SocialPlatform.youtubeShorts,
          SocialPlatform.tiktok,
          SocialPlatform.instagramReels,
        },
        mode: all ? ClipSplitMode.sameParts : ClipSplitMode.affectedChannels,
      );

  Future<ClipSegmentBatchResult> segment(ClipSegmentRequest request) async {
    segmentRequest = request;
    final parts = <ClipSegmentResult>[];
    for (final range in request.ranges) {
      final file = File('${root.path}/part_${range.index}.mp4')
        ..writeAsBytesSync(List.filled(256, range.index));
      parts.add(ClipSegmentResult(
        file: file,
        fileName: 'part_${range.index}.mp4',
        index: invalidIndex ?? range.index,
        startSeconds: range.startSeconds + (invalidMedia == 'range' ? 1 : 0),
        endSeconds: range.endSeconds,
        metadata: PublishMediaMetadata(
          durationSeconds: invalidMedia == 'duration'
              ? range.maximumDurationSeconds + 0.01
              : range.endSeconds - range.startSeconds,
          width: invalidMedia == 'dimensions' ? null : 1080,
          height: 1920,
          sizeBytes: invalidMedia == 'size' ? 257 : 256,
          hasAudio: invalidMedia != 'audio',
          videoCodec: 'h264',
          audioCodec: 'aac',
          fps: 30,
        ),
      ));
    }
    if (sourceChangesDuringEncode) {
      await source.writeAsBytes(List.filled(513, 8));
    }
    if (duplicateOutput && parts.isNotEmpty) parts.add(parts.first);
    if (missingOutput && parts.isNotEmpty) parts.removeLast();
    return ClipSegmentBatchResult(
      parts: parts,
      cleanup: () async {
        cleanupCalls++;
        await beforeCleanup?.call();
        if (cleanupFails) throw const FileSystemException('cleanup');
        for (final part in parts) {
          if (await part.file.exists()) await part.file.delete();
        }
      },
    );
  }

  ClipSplitDraftService service({String Function()? createDraftId}) =>
      ClipSplitDraftService(
        segmenter: segment,
        now: () => _now,
        createDraftId: createDraftId ?? () => 'new_${++id}',
      );

  ClipSplitDraftRequest request(
          {ClipSplitPlan? splitPlan, String? sourceDraftId}) =>
      ClipSplitDraftRequest(
        plan: splitPlan ?? plan(),
        inputFile: source,
        fileName: 'original.mp4',
        store: store,
        ownerUserId: _owner,
        caption: 'Original caption',
        aiGuidance: 'Keep the product name',
        captionLanguage: 'en',
        watermarkEnabled: true,
        platformSettings: const PlatformPublishSettings(
          tiktokPublishMode: TikTokPublishMode.directPost,
          tiktokMusicUsageConfirmed: true,
          tiktokBrandedContentPolicyConfirmed: true,
          tiktokCreatorInfoRevision: 'old-creator-revision',
          tiktokVideoDurationSeconds: 270,
          facebookPublishMode: FacebookPublishMode.pageDraft,
          facebookIsAiGenerated: true,
          youtubeCommunityGuidelinesCertified: true,
        ),
        sourceMetadata: const PublishMediaMetadata(
          durationSeconds: 270,
          width: 1080,
          height: 1920,
          sizeBytes: 512,
          hasAudio: true,
        ),
        isCancelled: () => cancelled,
        sourceDraftId: sourceDraftId,
      );

  Future<PublishDraft> seed(String id) => store.delegate.saveDraft(
        PublishDraftSaveRequest(
          id: id,
          createdAt: _now,
          updatedAt: _now,
          videoFile: source,
          videoName: 'existing.mp4',
          videoSizeBytes: 512,
          caption: 'Existing draft',
          aiGuidance: '',
          watermarkEnabled: false,
          platformApiValues: const {'FACEBOOK_REELS'},
        ),
      );
}

void main() {
  late _Fixture f;

  setUp(() async {
    final root =
        await Directory.systemTemp.createTemp('postdee-split-drafts-test-');
    f = _Fixture(root);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  test('270 seconds creates six copied drafts and seven independent post units',
      () async {
    final originalBytes = await f.source.readAsBytes();
    final result = await f.service().call(f.request());

    expect(result.drafts, hasLength(6));
    expect(result.totalPostUnits, 7);
    expect(f.segmentRequest!.ranges, hasLength(5));
    expect(f.cleanupCalls, 1);
    expect(await f.source.readAsBytes(), originalBytes);
    expect(
        result.drafts.map((d) => d.submissionRequestId).toSet(), hasLength(6));
    for (final draft in result.drafts) {
      expect(await File(draft.videoPath).exists(), isTrue);
      expect(draft.caption, 'Original caption');
      expect(draft.captionNeedsReview, isTrue);
      expect(draft.captionLanguage, 'en');
      expect(draft.aiGuidance, 'Keep the product name');
      expect(draft.watermarkEnabled, isTrue);
      expect(draft.cover, isNull);
      expect(draft.scheduledAt, isNull);
      expect(draft.uploadedMedia, isNull);
      expect(draft.platformSettings.tiktokMusicUsageConfirmed, isFalse);
      expect(
          draft.platformSettings.tiktokBrandedContentPolicyConfirmed, isFalse);
      expect(draft.platformSettings.tiktokCreatorInfoRevision, isNull);
      expect(draft.platformSettings.tiktokVideoDurationSeconds, isNull);
      expect(draft.platformSettings.tiktokPublishMode,
          TikTokPublishMode.directPost);
      expect(draft.platformSettings.facebookPublishMode,
          FacebookPublishMode.pageDraft);
      expect(draft.platformSettings.facebookIsAiGenerated, isTrue);
      expect(
          draft.platformSettings.youtubeCommunityGuidelinesCertified, isFalse);
      expect(draft.videoWidth, 1080);
      expect(draft.videoHeight, 1920);
    }
    final full =
        result.drafts.singleWhere((d) => d.platformApiValues.length == 2);
    expect(full.platformApiValues, {'TIKTOK', 'INSTAGRAM_REELS'});
    expect(await File(full.videoPath).readAsBytes(), originalBytes);
  });

  test('shared parts encode once and group all four channels per draft',
      () async {
    final result =
        await f.service().call(f.request(splitPlan: f.plan(all: true)));
    expect(result.drafts, hasLength(3));
    expect(f.segmentRequest!.ranges, hasLength(3));
    expect(result.totalPostUnits, 12);
    expect(result.drafts.every((d) => d.platformApiValues.length == 4), isTrue);
  });

  test('manual source ranges reach encoding and the saved group unchanged',
      () async {
    final source = await f.seed('manual_source');
    f.source = File(source.videoPath);
    final originalBytes = await f.source.readAsBytes();
    final plan = ClipSplitPlan.create(
      sourceDurationSeconds: 270,
      platforms: f.plan().platforms,
      segmentOverrides: const {
        SocialPlatform.facebookReels: [
          ClipSplitSegment(startSeconds: 20, endSeconds: 90),
          ClipSplitSegment(startSeconds: 105, endSeconds: 180),
          ClipSplitSegment(startSeconds: 195, endSeconds: 260),
        ],
      },
    );
    final result = await f
        .service()
        .call(f.request(splitPlan: plan, sourceDraftId: source.id));

    final facebookRanges = f.segmentRequest!.ranges
        .where((range) => plan.groupedParts[range.index].platforms
            .contains(SocialPlatform.facebookReels))
        .toList();
    expect(facebookRanges.map((r) => (r.startSeconds, r.endSeconds)),
        [(20, 90), (105, 180), (195, 260)]);
    final persisted = (await f.store.loadClipGroup(result.group!.id))!;
    final members = persisted.items
        .where((item) => item.platformApiValues.contains('FACEBOOK_REELS'))
        .toList();
    expect(members.map((m) => (m.sourceStartSeconds, m.sourceEndSeconds)),
        [(20, 90), (105, 180), (195, 260)]);
    for (final member in members) {
      final draft = (await f.store.loadDraft(member.draftId))!;
      expect(result.metadataByDraftId[draft.id]!.durationSeconds,
          member.sourceEndSeconds - member.sourceStartSeconds);
      expect(draft.scheduledAt, isNull);
      expect(draft.uploadedMedia, isNull);
      expect(draft.platformSettings.facebookPublishMode,
          FacebookPublishMode.pageDraft);
      expect(draft.platformSettings.facebookIsAiGenerated, isTrue);
    }
    expect(result.drafts, hasLength(6));
    expect(result.totalPostUnits, 7);
    final full = result.drafts.singleWhere(
        (draft) => draft.platformApiValues.contains('INSTAGRAM_REELS'));
    expect(full.platformApiValues, {'TIKTOK', 'INSTAGRAM_REELS'});
    expect(await File(full.videoPath).readAsBytes(), originalBytes);
    expect(await f.source.readAsBytes(), originalBytes);
    expect((await f.store.loadDraft(source.id))!.caption, 'Existing draft');
    expect(result.drafts.map((d) => d.submissionRequestId).toSet(),
        hasLength(result.drafts.length));
    expect(f.cleanupCalls, 1);
  });

  test('manual shared parts encode once for all destinations', () async {
    final plan = ClipSplitPlan.create(
      sourceDurationSeconds: 270,
      platforms: f.plan().platforms,
      mode: ClipSplitMode.sameParts,
      segmentOverrides: const {
        SocialPlatform.facebookReels: [
          ClipSplitSegment(startSeconds: 20, endSeconds: 90),
          ClipSplitSegment(startSeconds: 105, endSeconds: 180),
          ClipSplitSegment(startSeconds: 195, endSeconds: 260),
        ],
      },
    );
    final result = await f.service().call(f.request(splitPlan: plan));
    expect(f.segmentRequest!.ranges.map((r) => (r.startSeconds, r.endSeconds)),
        [(20, 90), (105, 180), (195, 260)]);
    expect(result.drafts, hasLength(3));
    expect(result.drafts.every((d) => d.platformApiValues.length == 4), isTrue);
    expect(result.totalPostUnits, 12);
  });

  test('a full-length-only plan copies the original without native work',
      () async {
    final plan = ClipSplitPlan.create(
      sourceDurationSeconds: 30,
      platforms: {SocialPlatform.tiktok, SocialPlatform.instagramReels},
    );
    final result = await f.service().call(f.request(splitPlan: plan));
    expect(result.drafts, hasLength(1));
    expect(f.segmentRequest, isNull);
    expect(f.cleanupCalls, 0);
  });

  test('pre-existing drafts and repeated id collisions are never overwritten',
      () async {
    final existing = await f.seed('taken');
    var attempts = 0;
    final result = await f
        .service(
            createDraftId: () => attempts++ < 2 ? 'taken' : 'safe_$attempts')
        .call(f.request());
    expect(result.drafts, hasLength(6));
    expect((await f.store.loadDraft(existing.id))!.caption, 'Existing draft');
    expect(f.store.saves.every((r) => r.id != 'taken'), isTrue);
  });

  test('an id provider that never produces a fresh id fails without writes',
      () async {
    await f.seed('taken');
    await expectLater(f.service(createDraftId: () => 'taken').call(f.request()),
        throwsA(isA<ClipSplitDraftException>()));
    expect(f.store.saves, isEmpty);
    expect((await f.store.listDrafts()).single.id, 'taken');
  });

  test('cancellation before work does not encode or save', () async {
    f.cancelled = true;
    await expectLater(
        f.service().call(f.request()),
        throwsA(isA<ClipSplitDraftException>()
            .having((e) => e.isCancelled, 'cancelled', true)));
    expect(f.segmentRequest, isNull);
    expect(f.store.saves, isEmpty);
  });

  test('owner cancellation after a save rolls back only the new drafts',
      () async {
    await f.seed('old');
    f.store.afterSave = (_) => f.cancelled = true;
    await expectLater(
        f.service().call(f.request()),
        throwsA(isA<ClipSplitDraftException>()
            .having((e) => e.isCancelled, 'cancelled', true)));
    expect((await f.store.listDrafts()).map((d) => d.id), ['old']);
    expect(f.cleanupCalls, 1);
    expect(await f.source.exists(), isTrue);
  });

  test('a save failure after promotion rolls back the failing id as well',
      () async {
    await f.seed('old');
    f.store.failAfterSave = 2;
    await expectLater(
        f.service().call(f.request()), throwsA(isA<ClipSplitDraftException>()));
    expect((await f.store.listDrafts()).map((d) => d.id), ['old']);
    expect(f.store.deleted, containsAll(['new_1', 'new_2']));
    expect(f.cleanupCalls, 1);
  });

  test('failure before a save does not leave earlier drafts behind', () async {
    f.store.failBeforeSave = 2;
    await expectLater(
        f.service().call(f.request()), throwsA(isA<ClipSplitDraftException>()));
    expect(await f.store.listDrafts(), isEmpty);
    expect(f.cleanupCalls, 1);
  });

  test(
      'rollback failures identify residual drafts instead of reporting success',
      () async {
    f.store.failAfterSave = 2;
    f.store.failDelete = true;
    await expectLater(
        f.service().call(f.request()),
        throwsA(isA<ClipSplitDraftException>().having((e) => e.residualDraftIds,
            'residual ids', containsAll(['new_1', 'new_2']))));
    expect(f.cleanupCalls, 1);
  });

  test('temporary cleanup failure is surfaced and new drafts are rolled back',
      () async {
    f.cleanupFails = true;
    await expectLater(
        f.service().call(f.request()), throwsA(isA<ClipSplitDraftException>()));
    expect(await f.store.listDrafts(), isEmpty);
    expect(f.cleanupCalls, 1);
  });

  for (final invalid in [
    'unknown index',
    'duplicate result',
    'missing result'
  ]) {
    test('invalid native batch: $invalid never creates a draft', () async {
      f.invalidIndex = invalid == 'unknown index' ? 900 : null;
      f.duplicateOutput = invalid == 'duplicate result';
      f.missingOutput = invalid == 'missing result';
      await expectLater(f.service().call(f.request()),
          throwsA(isA<ClipSplitDraftException>()));
      expect(f.store.saves, isEmpty);
      expect(f.cleanupCalls, 1);
    });
  }

  test(
      'source replacement during native work aborts and preserves other drafts',
      () async {
    await f.seed('old');
    f.sourceChangesDuringEncode = true;
    await expectLater(
        f.service().call(f.request()), throwsA(isA<ClipSplitDraftException>()));
    expect((await f.store.listDrafts()).map((d) => d.id), ['old']);
    expect(f.cleanupCalls, 1);
  });

  for (final invalid in ['range', 'duration', 'dimensions', 'size', 'audio']) {
    test('invalid native media: $invalid is rejected before any draft write',
        () async {
      f.invalidMedia = invalid;
      await expectLater(f.service().call(f.request()),
          throwsA(isA<ClipSplitDraftException>()));
      expect(f.store.saves, isEmpty);
      expect(f.cleanupCalls, 1);
      expect(await f.source.readAsBytes(), List.filled(512, 7));
    });
  }

  test(
      'new split drafts commit one owner-bound group and tag its original only after commit',
      () async {
    final source = await f.seed('original');
    f.source = File(source.videoPath);
    final result = await f.service().call(f.request(sourceDraftId: source.id));
    final group = result.group!;
    expect(group.ownerUserId, _owner);
    expect(group.sourceDraftId, source.id);
    expect(group.items, hasLength(6));
    expect(group.revision, 1);
    expect(group.items.map((item) => item.draftId).toSet(),
        result.drafts.map((d) => d.id).toSet());
    expect(
        group.items.every((item) =>
            item.usesSharedCaption &&
            !item.isAccepted &&
            item.scheduledAt == null),
        isTrue);
    final original = (await f.store.loadDraft(source.id))!;
    expect(original.clipGroupId, group.id);
    expect(original.isClipGroupSource, isTrue);
    expect(original.submissionRequestId, source.submissionRequestId);
    expect(result.sourceDraft!.id, source.id);
    expect(
        result.drafts
            .every((d) => d.clipGroupId == group.id && !d.isClipGroupSource),
        isTrue);
    expect((await f.store.loadClipGroup(group.id))!.items, hasLength(6));
  });

  for (final failed in ['group commit', 'source tagging']) {
    test(
        '$failed failure rolls back the new group and leaves original standalone',
        () async {
      final original = await f.seed('original');
      f.source = File(original.videoPath);
      f.store.failGroupAfterSave = failed == 'group commit';
      f.store.failSourceTagAfterSave = failed == 'source tagging';
      await expectLater(f.service().call(f.request(sourceDraftId: original.id)),
          throwsA(isA<ClipSplitDraftException>()));
      expect(await f.store.listClipGroups(), isEmpty);
      final drafts = await f.store.listDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.id, original.id);
      expect(drafts.single.clipGroupId, isNull);
      expect(drafts.single.isClipGroupSource, isFalse);
      expect(await File(drafts.single.videoPath).readAsBytes(),
          List.filled(512, 7));
    });
  }

  test('a grouped source cannot be split again or modify its existing group',
      () async {
    final original = await f.seed('original');
    f.source = File(original.videoPath);
    final first = await f.service().call(f.request(sourceDraftId: original.id));
    final existingIds =
        (await f.store.listDrafts()).map((draft) => draft.id).toSet();
    final existingGroup = first.group!;
    final writesBefore = f.store.saves.length;
    f.segmentRequest = null;
    await expectLater(f.service().call(f.request(sourceDraftId: original.id)),
        throwsA(isA<ClipSplitDraftException>()));
    expect(f.segmentRequest, isNull);
    expect(f.store.saves.length, writesBefore);
    expect((await f.store.listDrafts()).map((draft) => draft.id).toSet(),
        existingIds);
    expect((await f.store.loadClipGroup(existingGroup.id))!.toJson(),
        existingGroup.toJson());
  });

  for (final moment in ['before tag', 'during rollback']) {
    test('source $moment keeps a concurrent caption cover and schedule edit',
        () async {
      final original = await f.seed('original');
      f.source = File(original.videoPath);
      final cover = File('${f.root.path}/new-cover.jpg')
        ..writeAsBytesSync([8, 7, 6]);
      Future<void> editSource() async {
        final latest = (await f.store.loadDraft(original.id))!;
        await f.store.delegate.saveDraft(PublishDraftSaveRequest(
          id: latest.id,
          createdAt: latest.createdAt,
          updatedAt: _now,
          videoFile: File(latest.videoPath),
          videoName: latest.videoName,
          videoSizeBytes: latest.videoSizeBytes,
          caption: 'Concurrent caption',
          aiGuidance: latest.aiGuidance,
          watermarkEnabled: latest.watermarkEnabled,
          platformApiValues: latest.platformApiValues,
          scheduledAt: _now.add(const Duration(days: 2)),
          coverImageFile: cover,
          coverDesign: const CoverDesign(text: 'New cover'),
          clipGroupId: latest.clipGroupId,
          isClipGroupSource: latest.isClipGroupSource,
        ));
      }

      if (moment == 'before tag') {
        f.store.afterGroupSave = (_) => editSource();
        await f.service().call(f.request(sourceDraftId: original.id));
      } else {
        f.beforeCleanup = editSource;
        f.cleanupFails = true;
        await expectLater(
            f.service().call(f.request(sourceDraftId: original.id)),
            throwsA(isA<ClipSplitDraftException>()));
      }
      final latest = (await f.store.loadDraft(original.id))!;
      expect(latest.caption, 'Concurrent caption');
      expect(latest.scheduledAt, _now.add(const Duration(days: 2)));
      expect(latest.cover!.design.text, 'New cover');
      expect(latest.submissionRequestId, original.submissionRequestId);
    });
  }

  for (final accepted in [false, true]) {
    test(
        'cleanup failure never erases a concurrently ${accepted ? 'accepted' : 'edited'} group',
        () async {
      final original = await f.seed('original');
      f.source = File(original.videoPath);
      String? groupId;
      f.beforeCleanup = () async {
        final group = (await f.store.listClipGroups()).single;
        groupId = group.id;
        final items = [...group.items];
        if (accepted) {
          items[0] = items[0].copyWith(
              acceptedPostId: 'already-posted', acceptedPostStatus: 'QUEUED');
        }
        await (f.store.delegate as ClipGroupDraftStore).saveClipGroup(
            group.copyWith(sharedCaption: 'New user work', items: items),
            expectedRevision: group.revision);
        if (accepted) await f.store.delegate.deleteDraft(items[0].draftId);
      };
      f.cleanupFails = true;
      await expectLater(
          f.service().call(f.request(sourceDraftId: original.id)),
          throwsA(isA<ClipSplitDraftException>().having(
              (e) => e.residualDraftIds, 'preserved members', isNotEmpty)));
      final retained = (await f.store.loadClipGroup(groupId!))!;
      expect(retained.revision, 2);
      expect(retained.sharedCaption, 'New user work');
      expect(retained.items.first.acceptedPostId,
          accepted ? 'already-posted' : null);
      expect((await f.store.listDrafts()), hasLength(accepted ? 6 : 7));
      expect((await f.store.loadDraft(original.id))!.clipGroupId, retained.id);
    });
  }
}
