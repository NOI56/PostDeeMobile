import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_segmenter.dart';
import 'package:postdee_mobile/features/uploader/clip_split_draft_service.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft_store.dart';

const _owner = 'split-owner';
final _now = DateTime.utc(2026, 11, 4, 15);

class _ControlledStore implements PublishDraftStore {
  _ControlledStore(this.delegate);

  final PublishDraftStore delegate;
  final List<PublishDraftSaveRequest> saves = [];
  final List<String> deleted = [];
  int? failAfterSave;
  int? failBeforeSave;
  void Function(int saved)? afterSave;
  bool failDelete = false;

  @override
  Future<PublishDraft> saveDraft(PublishDraftSaveRequest request) async {
    saves.add(request);
    if (saves.length == failBeforeSave) throw const FileSystemException('full');
    final draft = await delegate.saveDraft(request);
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

  ClipSplitDraftRequest request({ClipSplitPlan? splitPlan}) =>
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
}
