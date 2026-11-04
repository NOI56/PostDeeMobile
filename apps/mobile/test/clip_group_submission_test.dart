import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/clip_group_caption_context.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft_store.dart';
import 'package:postdee_mobile/features/uploader/clip_group_submission.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

import 'support/test_publish_draft_store.dart';

const _owner = 'group-owner';
const _platform = 'FACEBOOK_REELS';
final _now = DateTime.utc(2026, 11, 5, 10);

ClipGroupDraft _group(
        {int count = 3,
        int revision = 1,
        ClipGroupDeliveryMode mode = ClipGroupDeliveryMode.immediate}) =>
    ClipGroupDraft(
      id: 'group-1',
      ownerUserId: _owner,
      sourceDraftId: 'original',
      title: 'Video group',
      sharedCaption: 'Shared caption',
      deliveryMode: mode,
      createdAt: _now,
      updatedAt: _now,
      revision: revision,
      items: [
        for (var index = 0; index < count; index++)
          ClipGroupItem(
            draftId: 'part-$index',
            index: index,
            sourceStartSeconds: index * 90.0,
            sourceEndSeconds: (index + 1) * 90.0,
            platformApiValues: const {_platform},
            usesSharedCaption: true,
            scheduledAt: mode == ClipGroupDeliveryMode.scheduled
                ? _now.add(Duration(days: 1, hours: index))
                : null,
          )
      ],
    );

PublishDraft _draft(String id,
        {String owner = _owner,
        String caption = 'Shared caption',
        Set<String> platforms = const {_platform},
        DateTime? scheduledAt,
        String fingerprint = 'media-1',
        String? groupId = 'group-1',
        bool source = false,
        PublishDraftUploadedMedia? uploadedMedia,
        PublishDraftCover? cover}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: owner,
      submissionRequestId: 'submit-$id',
      createdAt: _now,
      updatedAt: _now,
      videoPath: '/owned/$id.mp4',
      videoName: '$id.mp4',
      videoSizeBytes: 100,
      videoWidth: 1080,
      videoHeight: 1920,
      caption: caption,
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: platforms,
      scheduledAt: scheduledAt,
      mediaContentFingerprint: fingerprint,
      uploadedMedia: uploadedMedia,
      clipGroupId: groupId,
      isClipGroupSource: source,
      cover: cover,
    );

QueuedPostResult _post(String draftId,
        {String status = 'QUEUED',
        String? id,
        List<String> platforms = const [_platform]}) =>
    QueuedPostResult(
      id: id ?? 'post-$draftId',
      videoS3Key: 'uploads/$draftId.mp4',
      platforms: platforms,
      status: status,
    );

class _Groups implements ClipGroupDraftStore {
  _Groups(this.current);
  ClipGroupDraft? current;
  int writes = 0;
  int reads = 0;
  bool failSave = false;
  void Function(int)? onRead;
  void Function(ClipGroupDraft)? onSaved;

  @override
  Future<ClipGroupDraft?> loadClipGroup(String id) async {
    reads++;
    onRead?.call(reads);
    return current?.id == id ? current : null;
  }

  @override
  Future<List<ClipGroupDraft>> listClipGroups() async =>
      current == null ? [] : [current!];
  @override
  Future<ClipGroupDraft> saveClipGroup(ClipGroupDraft group,
      {required int? expectedRevision}) async {
    writes++;
    if (failSave || expectedRevision != current?.revision) {
      throw StateError('CAS failed');
    }
    current = group.copyWith(revision: group.revision + 1);
    onSaved?.call(current!);
    return current!;
  }

  @override
  Future<void> deleteClipGroup(String id) async {
    if (current?.id == id) current = null;
  }
}

void main() {
  late _Groups groups;
  late TestPublishDraftStore drafts;
  late ClipGroupDraft confirmed;
  late List<String> submissions;
  late List<String> events;
  late List<ClipGroupSubmissionProgress> progress;

  setUp(() {
    final sessions = PostDeeAuthSessionStore.instance;
    final previous = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: _owner, idToken: 'group-token'));
    addTearDown(() =>
        previous.isSignedIn ? sessions.signIn(previous) : sessions.clear());
    confirmed = _group();
    groups = _Groups(confirmed);
    drafts = TestPublishDraftStore(ownerUserId: _owner);
    for (final item in confirmed.items) {
      drafts.drafts[item.draftId] = _draft(item.draftId);
    }
    submissions = [];
    events = [];
    progress = [];
  });

  ClipGroupSubmission coordinator({ClipGroupSubmitOne? submitOne}) =>
      ClipGroupSubmission(
        groupStore: groups,
        draftStore: drafts,
        now: () => _now,
        submitOne: submitOne ??
            (draft, item, checkpoint) async {
              submissions.add(draft.id);
              events.add('submit:${draft.id}');
              final post = _post(draft.id);
              await checkpoint(post);
              events.add('cleanup:${draft.id}');
              await drafts.deleteDraft(draft.id);
              return post;
            },
      );

  test('submits serially and checkpoints acknowledgement before child cleanup',
      () async {
    groups.onSaved = (group) => events.add(
        'checkpoint:${group.items.where((item) => item.isAccepted).length}');
    final result = await coordinator()(confirmed, onProgress: progress.add);
    expect(submissions, ['part-0', 'part-1', 'part-2']);
    expect(events, [
      'submit:part-0',
      'checkpoint:1',
      'cleanup:part-0',
      'submit:part-1',
      'checkpoint:2',
      'cleanup:part-1',
      'submit:part-2',
      'checkpoint:3',
      'cleanup:part-2'
    ]);
    expect(result.completed, 3);
    expect(result.remaining, 0);
    expect(result.error, isNull);
    expect(result.cancelled, isFalse);
    expect(result.group.items.every((item) => item.isAccepted), isTrue);
    expect(result.group.revision, 4);
    expect(progress.last.stage, ClipGroupSubmissionStage.done);
  });

  test(
      'skips only explicit accepted identities even when their source draft is absent',
      () async {
    confirmed = confirmed.copyWith(items: [
      confirmed.items[0].copyWith(
          acceptedPostId: 'already-accepted', acceptedPostStatus: 'FAILED'),
      ...confirmed.items.skip(1),
    ]);
    groups.current = confirmed;
    drafts.drafts.remove('part-0');
    final result = await coordinator()(confirmed);
    expect(submissions, ['part-1', 'part-2']);
    expect(result.completed, 3);
    expect(result.group.items.first.acceptedPostId, 'already-accepted');
  });

  test('a missing unaccepted draft blocks the entire batch before remote work',
      () async {
    drafts.drafts.remove('part-2');
    final result = await coordinator()(confirmed);
    expect(result.error, isNotNull);
    expect(result.completed, 0);
    expect(submissions, isEmpty);
    expect(groups.writes, 0);
  });

  test('a stale confirmed revision or edited group cannot submit', () async {
    groups.current = confirmed.copyWith(
        sharedCaption: 'Changed after confirmation', revision: 2);
    final result = await coordinator()(confirmed);
    expect(result.error, isNotNull);
    expect(submissions, isEmpty);
    expect(groups.writes, 0);
  });

  test('same-revision mutation of a confirmed group is rejected', () async {
    groups.current = confirmed.copyWith(title: 'Changed without a revision');
    final result = await coordinator()(confirmed);
    expect(result.error, isNotNull);
    expect(submissions, isEmpty);
  });

  test('changed shared AI context invalidates the confirmed group snapshot',
      () async {
    groups.current = confirmed.copyWith(
        captionContext: const ClipGroupCaptionContext(
            aiGuidance: 'Changed after confirmation', captionLanguage: 'th'));
    final result = await coordinator()(confirmed);
    expect(result.error, isNotNull);
    expect(submissions, isEmpty);
    expect(groups.writes, 0);
  });

  test('rejects a member with another owner or platform membership', () async {
    for (final invalid in [
      _draft('part-2', owner: 'another-owner'),
      _draft('part-2', platforms: const {'TIKTOK'}),
      _draft('part-2', groupId: 'another-group'),
      _draft('part-2', source: true),
    ]) {
      drafts.drafts['part-2'] = invalid;
      final result = await coordinator()(confirmed);
      expect(result.error, isNotNull);
      expect(submissions, isEmpty);
    }
  });

  test('all scheduled member times must match the confirmed independent dates',
      () async {
    confirmed = _group(mode: ClipGroupDeliveryMode.scheduled);
    groups.current = confirmed;
    for (final item in confirmed.items) {
      drafts.drafts[item.draftId] =
          _draft(item.draftId, scheduledAt: item.scheduledAt);
    }
    final sentTimes = <DateTime?>[];
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      sentTimes.add(draft.scheduledAt);
      final post = _post(draft.id);
      await checkpoint(post);
      return post;
    })(confirmed);
    expect(sentTimes, confirmed.items.map((item) => item.scheduledAt));
    expect(
        result.group.items.map((item) => item.acceptedScheduledAt), sentTimes);
    expect(result.remaining, 0);
  });

  test('a mismatched member schedule blocks all submissions', () async {
    drafts.drafts['part-2'] =
        _draft('part-2', scheduledAt: _now.add(const Duration(days: 1)));
    final result = await coordinator()(confirmed);
    expect(result.error, isNotNull);
    expect(submissions, isEmpty);
  });

  test('an expired unknown receipt can checkpoint its recovered accepted post',
      () async {
    final past = _now.subtract(const Duration(hours: 1));
    confirmed = _group(count: 1, mode: ClipGroupDeliveryMode.scheduled);
    confirmed = confirmed
        .copyWith(items: [confirmed.items.single.copyWith(scheduledAt: past)]);
    groups.current = confirmed;
    drafts.drafts['part-0'] = _draft('part-0',
        scheduledAt: past,
        uploadedMedia: const PublishDraftUploadedMedia(
            mediaContentFingerprint: 'media-1',
            videoS3Key: 'uploads/part-0.mp4'));
    final result = await coordinator()(confirmed);
    expect(submissions, ['part-0']);
    expect(result.error, isNull);
    expect(result.completed, 1);
    expect(result.group.items.single.acceptedScheduledAt, past);
    expect(drafts.drafts.containsKey('part-0'), isFalse);
  });

  test('an expired fresh draft is rejected before the submission adapter',
      () async {
    final past = _now.subtract(const Duration(hours: 1));
    confirmed = _group(count: 1, mode: ClipGroupDeliveryMode.scheduled);
    confirmed = confirmed
        .copyWith(items: [confirmed.items.single.copyWith(scheduledAt: past)]);
    groups.current = confirmed;
    drafts.drafts['part-0'] = _draft('part-0', scheduledAt: past);
    final result = await coordinator()(confirmed);
    expect(submissions, isEmpty);
    expect(result.error, isNotNull);
    expect(result.completed, 0);
    expect(groups.writes, 0);
  });

  test('an expired receipt without recovered acceptance stops without cleanup',
      () async {
    final past = _now.subtract(const Duration(hours: 1));
    confirmed = _group(count: 1, mode: ClipGroupDeliveryMode.scheduled);
    confirmed = confirmed
        .copyWith(items: [confirmed.items.single.copyWith(scheduledAt: past)]);
    groups.current = confirmed;
    drafts.drafts['part-0'] = _draft('part-0',
        scheduledAt: past,
        uploadedMedia: const PublishDraftUploadedMedia(
            mediaContentFingerprint: 'media-1',
            videoS3Key: 'uploads/part-0.mp4'));
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      return null;
    })(confirmed);
    expect(submissions, ['part-0']);
    expect(result.error, isNotNull);
    expect(result.completed, 0);
    expect(groups.writes, 0);
    expect(drafts.drafts.containsKey('part-0'), isTrue);
  });

  test(
      'later member edits while an earlier request is pending stop at that member',
      () async {
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      await checkpoint(_post(draft.id));
      drafts.drafts['part-1'] = _draft('part-1', caption: 'Concurrent edit');
      return _post(draft.id);
    })(confirmed);
    expect(submissions, ['part-0']);
    expect(result.completed, 1);
    expect(result.remaining, 2);
    expect(result.error, isNotNull);
  });

  test('cover design edits after confirmation stop the changed member',
      () async {
    PublishDraftCover cover(double x) => PublishDraftCover(
          imagePath: '/owned/cover.jpg',
          sizeBytes: 100,
          design: CoverDesign(text: 'Same text', dx: x),
          sourceKind: CoverSourceKind.videoFrame,
        );
    drafts.drafts['part-1'] = _draft('part-1', cover: cover(.2));
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      await checkpoint(_post(draft.id));
      drafts.drafts['part-1'] = _draft('part-1', cover: cover(.8));
      return _post(draft.id);
    })(confirmed);
    expect(submissions, ['part-0']);
    expect(result.completed, 1);
    expect(result.error, isNotNull);
  });

  test('stops on null, unknown, or failed responses without accepting them',
      () async {
    for (final response in <QueuedPostResult?>[
      null,
      _post('part-0', status: 'UNKNOWN'),
      _post('part-0', status: 'FAILED')
    ]) {
      submissions.clear();
      final result =
          await coordinator(submitOne: (draft, item, checkpoint) async {
        submissions.add(draft.id);
        return response;
      })(confirmed);
      expect(submissions, ['part-0']);
      expect(result.completed, 0);
      expect(result.error, isNotNull);
      expect(groups.writes, 0);
    }
  });

  test(
      'returning an accepted status without the durable checkpoint is not accepted',
      () async {
    final result = await coordinator(
        submitOne: (draft, item, checkpoint) async =>
            _post(draft.id))(confirmed);
    expect(result.error, isNotNull);
    expect(result.completed, 0);
    expect(groups.writes, 0);
  });

  test('checkpoint validates returned post identity, status and destinations',
      () async {
    for (final post in [
      _post('part-0', id: ''),
      _post('part-0', status: 'FAILED'),
      _post('part-0', platforms: const ['TIKTOK']),
      _post('part-0', platforms: const [_platform, _platform])
    ]) {
      final result =
          await coordinator(submitOne: (draft, item, checkpoint) async {
        await checkpoint(post);
        return post;
      })(confirmed);
      expect(result.error, isNotNull);
      expect(result.completed, 0);
      expect(groups.writes, 0);
    }
  });

  test(
      'CAS checkpoint failure leaves the child receipt available and stops the batch',
      () async {
    groups.failSave = true;
    final result = await coordinator()(confirmed);
    expect(submissions, ['part-0']);
    expect(result.error, isNotNull);
    expect(result.completed, 0);
    expect(drafts.drafts.containsKey('part-0'), isTrue);
    expect(events, ['submit:part-0']);
  });

  test('concurrent group edits cannot be overwritten by an accepted checkpoint',
      () async {
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      groups.current =
          confirmed.copyWith(title: 'Concurrent group edit', revision: 2);
      await checkpoint(_post(draft.id));
      return _post(draft.id);
    })(confirmed);
    expect(result.error, isNotNull);
    expect(groups.current!.title, 'Concurrent group edit');
    expect(groups.current!.items.any((item) => item.isAccepted), isFalse);
  });

  test(
      'failure after checkpoint preserves acceptance and never retries that member',
      () async {
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      await checkpoint(_post(draft.id));
      throw StateError('cleanup failed after API acknowledgement');
    })(confirmed);
    expect(result.completed, 1);
    expect(result.remaining, 2);
    expect(result.error, isNotNull);
    submissions.clear();
    final resumed = await coordinator()(result.group);
    expect(submissions, ['part-1', 'part-2']);
    expect(resumed.completed, 3);
  });

  test('a cancelled run has no remote side effects', () async {
    final result = await coordinator()(confirmed, isCancelled: () => true);
    expect(result.cancelled, isTrue);
    expect(submissions, isEmpty);
    expect(groups.writes, 0);
  });

  test(
      'a session changed by the checking observer prevents the initial storage read',
      () async {
    final result = await coordinator()(confirmed, onProgress: (value) {
      if (value.stage == ClipGroupSubmissionStage.checking) {
        PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
            userId: 'new-owner', idToken: 'new-session'));
      }
    });
    expect(result.cancelled, isTrue);
    expect(groups.reads, 0);
    expect(groups.writes, 0);
    expect(submissions, isEmpty);
  });

  test('cancellation after acceptance stops only subsequent members', () async {
    var cancelled = false;
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      await checkpoint(_post(draft.id));
      cancelled = true;
      return _post(draft.id);
    })(confirmed, isCancelled: () => cancelled);
    expect(submissions, ['part-0']);
    expect(result.cancelled, isTrue);
    expect(result.completed, 1);
    expect(result.remaining, 2);
  });

  test(
      'a stop request during an active submission still checkpoints its known acknowledgement',
      () async {
    var cancelled = false;
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      submissions.add(draft.id);
      cancelled = true;
      await checkpoint(_post(draft.id));
      return _post(draft.id);
    })(confirmed, isCancelled: () => cancelled);
    expect(submissions, ['part-0']);
    expect(result.cancelled, isTrue);
    expect(result.completed, 1);
    expect(groups.writes, 1);
  });

  test('a late checkpoint cannot mutate the group after its adapter returned',
      () async {
    ClipGroupAcceptedCheckpoint? retained;
    final result =
        await coordinator(submitOne: (draft, item, checkpoint) async {
      retained = checkpoint;
      return null;
    })(confirmed);
    expect(result.error, isNotNull);
    await expectLater(retained!(_post('part-0')),
        throwsA(isA<ClipGroupSubmissionException>()));
    expect(groups.writes, 0);
  });

  for (final sameOwner in [false, true]) {
    test(
        'a stale ${sameOwner ? 'same-owner' : 'different-owner'} session cannot checkpoint or continue',
        () async {
      final result =
          await coordinator(submitOne: (draft, item, checkpoint) async {
        submissions.add(draft.id);
        PostDeeAuthSessionStore.instance.signIn(AuthSession.authenticated(
            userId: sameOwner ? _owner : 'other-owner',
            idToken: 'new-session'));
        await checkpoint(_post(draft.id));
        return _post(draft.id);
      })(confirmed);
      expect(submissions, ['part-0']);
      expect(result.cancelled, isTrue);
      expect(groups.writes, 0);
    });
  }

  test(
      'rejects concurrent submission of the same owner group across coordinator instances',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final first = coordinator(submitOne: (draft, item, checkpoint) async {
      if (!entered.isCompleted) entered.complete();
      await gate.future;
      await checkpoint(_post(draft.id));
      return _post(draft.id);
    })(confirmed);
    await entered.future;
    final duplicate = await coordinator()(confirmed);
    expect(duplicate.error, isNotNull);
    expect(submissions, isEmpty);
    gate.complete();
    final completed = await first;
    expect(completed.completed, 3);
  });
}
