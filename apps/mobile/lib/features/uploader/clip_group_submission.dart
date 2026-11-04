import 'dart:convert';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import 'clip_group_draft.dart';
import 'clip_group_draft_store.dart';
import 'publish_draft.dart';
import 'publish_draft_store.dart';

typedef ClipGroupAcceptedCheckpoint = Future<void> Function(
    QueuedPostResult post);
typedef ClipGroupSubmitOne = Future<QueuedPostResult?> Function(
    PublishDraft draft,
    ClipGroupItem item,
    ClipGroupAcceptedCheckpoint checkpointAccepted);

enum ClipGroupSubmissionStage { checking, submitting, accepted, stopped, done }

class ClipGroupSubmissionProgress {
  const ClipGroupSubmissionProgress({
    required this.itemIndex,
    required this.completed,
    required this.total,
    required this.stage,
    required this.itemDraftId,
  });
  final int itemIndex;
  final int completed;
  final int total;
  final ClipGroupSubmissionStage stage;
  final String? itemDraftId;
}

class ClipGroupSubmissionResult {
  const ClipGroupSubmissionResult({
    required this.group,
    required this.completed,
    required this.remaining,
    this.error,
    this.cancelled = false,
  });
  final ClipGroupDraft group;
  final int completed;
  final int remaining;
  final Object? error;
  final bool cancelled;
}

enum ClipGroupSubmissionProblem {
  cancelled,
  alreadyRunning,
  groupChanged,
  missingDraft,
  draftChanged,
  invalidMember,
  unconfirmed,
  checkpointFailed,
}

class ClipGroupSubmissionException implements Exception {
  const ClipGroupSubmissionException(this.problem);
  final ClipGroupSubmissionProblem problem;
  @override
  String toString() => 'ClipGroupSubmissionException: ${problem.name}';
}

const _acceptedStatuses = {
  'QUEUED',
  'PUBLISHING',
  'PUBLISHED',
  'PARTIAL_PUBLISHED',
};
const _platforms = {
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS',
};

/// Serializes reviewed local drafts through the existing single-post pipeline.
/// The adapter must await checkpointAccepted before deleting a child draft.
/// A persisted upload receipt may reach the adapter after its scheduled time;
/// recover the original request first and never issue a fresh expired POST.
/// A completed server acknowledgement is persisted independently per member;
/// this class never uploads, retries a POST, or rolls back accepted posts.
class ClipGroupSubmission {
  ClipGroupSubmission({
    required this.groupStore,
    required this.draftStore,
    required this.submitOne,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ClipGroupDraftStore groupStore;
  final PublishDraftStore draftStore;
  final ClipGroupSubmitOne submitOne;
  final DateTime Function() _now;
  static final _activeGroups = <String>{};

  Future<ClipGroupSubmissionResult> call(
    ClipGroupDraft confirmedGroup, {
    AuthSessionBinding? session,
    bool Function()? isCancelled,
    void Function(ClipGroupSubmissionProgress)? onProgress,
  }) async {
    final binding =
        session ?? PostDeeAuthSessionStore.instance.captureSession();
    var group = confirmedGroup;
    final confirmedSnapshot = _groupSnapshot(confirmedGroup);
    final runKey = jsonEncode([confirmedGroup.ownerUserId, confirmedGroup.id]);
    var ownsRun = false;
    ClipGroupItem? activeItem;

    bool cancelled() {
      try {
        return isCancelled?.call() ?? false;
      } catch (_) {
        return true;
      }
    }

    void guardSession() {
      final current = PostDeeAuthSessionStore.instance.session;
      if (!binding.isCurrent ||
          binding.userId != confirmedGroup.ownerUserId ||
          current.stableUserId != confirmedGroup.ownerUserId ||
          !current.isSignedIn) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.cancelled);
      }
    }

    void guard() {
      guardSession();
      if (cancelled()) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.cancelled);
      }
    }

    int completed() => group.items.where((item) => item.isAccepted).length;
    void report(ClipGroupSubmissionStage stage) {
      try {
        onProgress?.call(ClipGroupSubmissionProgress(
          itemIndex: activeItem?.index ?? -1,
          completed: completed(),
          total: group.items.length,
          stage: stage,
          itemDraftId: activeItem?.draftId,
        ));
      } catch (_) {
        /* A progress observer cannot repeat or undo a submission. */
      }
    }

    ClipGroupSubmissionResult result(
            {Object? error, bool wasCancelled = false}) =>
        ClipGroupSubmissionResult(
            group: group,
            completed: completed(),
            remaining: group.items.length - completed(),
            error: error,
            cancelled: wasCancelled);

    Future<void> verifyGroup({bool allowStopRequested = false}) async {
      if (allowStopRequested) {
        guardSession();
      } else {
        guard();
      }
      final expected = _groupSnapshot(group);
      final latest = await groupStore.loadClipGroup(group.id);
      if (allowStopRequested) {
        guardSession();
      } else {
        guard();
      }
      if (latest == null || _groupSnapshot(latest) != expected) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.groupChanged);
      }
    }

    try {
      guard();
      if (!_activeGroups.add(runKey)) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.alreadyRunning);
      }
      ownsRun = true;
      report(ClipGroupSubmissionStage.checking);
      guard();
      final latest = await groupStore.loadClipGroup(confirmedGroup.id);
      guard();
      if (latest == null || _groupSnapshot(latest) != confirmedSnapshot) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.groupChanged);
      }
      group = latest;
      _validateGroup(group);

      // Snapshot every pending member before the first remote side effect.
      // Recheck the same intent immediately before its own submission.
      final snapshots = <String, String>{};
      for (final item in group.items.where((item) => !item.isAccepted)) {
        guard();
        final draft = await draftStore.loadDraft(item.draftId);
        guard();
        if (draft == null) {
          throw const ClipGroupSubmissionException(
              ClipGroupSubmissionProblem.missingDraft);
        }
        _validateMember(group, item, draft);
        snapshots[item.draftId] = _draftSnapshot(draft);
      }

      // Iterate the confirmed membership, never a newly loaded edited list.
      for (final member in confirmedGroup.items) {
        activeItem =
            group.items.firstWhere((item) => item.draftId == member.draftId);
        if (activeItem.isAccepted) continue;
        guard();
        await verifyGroup();
        final item = activeItem;
        final draft = await draftStore.loadDraft(item.draftId);
        guard();
        if (draft == null) {
          throw const ClipGroupSubmissionException(
              ClipGroupSubmissionProblem.missingDraft);
        }
        _validateMember(group, item, draft);
        if (_draftSnapshot(draft) != snapshots[item.draftId]) {
          throw const ClipGroupSubmissionException(
              ClipGroupSubmissionProblem.draftChanged);
        }
        var checkpointOpen = true;
        QueuedPostResult? acknowledged;
        Future<void> checkpointAccepted(QueuedPostResult post) async {
          guardSession();
          if (!checkpointOpen) {
            throw const ClipGroupSubmissionException(
                ClipGroupSubmissionProblem.unconfirmed);
          }
          _validateAcknowledgement(post, item);
          if (acknowledged != null) {
            if (!_sameAcknowledgement(acknowledged!, post)) {
              throw const ClipGroupSubmissionException(
                  ClipGroupSubmissionProblem.unconfirmed);
            }
            return;
          }
          // Stop requests prevent the next member. A response to the current
          // request still needs its local acknowledgement while the owner is
          // unchanged, otherwise a completed remote effect would be forgotten.
          await verifyGroup(allowStopRequested: true);
          guardSession();
          final expectedRevision = group.revision;
          final candidate = group.copyWith(
            updatedAt: _now().toUtc(),
            items: [
              for (final entry in group.items)
                if (entry.draftId == item.draftId)
                  entry.copyWith(
                    acceptedPostId: post.id,
                    acceptedPostStatus: post.status.toUpperCase(),
                    acceptedScheduledAt:
                        group.deliveryMode == ClipGroupDeliveryMode.scheduled
                            ? item.scheduledAt
                            : null,
                  )
                else
                  entry
            ],
          );
          ClipGroupDraft saved;
          try {
            saved = await groupStore.saveClipGroup(candidate,
                expectedRevision: expectedRevision);
          } catch (_) {
            throw const ClipGroupSubmissionException(
                ClipGroupSubmissionProblem.checkpointFailed);
          }
          guardSession();
          if (saved.revision != expectedRevision + 1 ||
              _groupSnapshot(saved.copyWith(revision: candidate.revision)) !=
                  _groupSnapshot(candidate)) {
            throw const ClipGroupSubmissionException(
                ClipGroupSubmissionProblem.checkpointFailed);
          }
          group = saved;
          acknowledged = post;
          report(ClipGroupSubmissionStage.accepted);
        }

        report(ClipGroupSubmissionStage.submitting);
        guard();
        QueuedPostResult? post;
        try {
          post = await submitOne(draft, item, checkpointAccepted);
        } finally {
          checkpointOpen = false;
        }
        guard();
        if (post == null ||
            acknowledged == null ||
            !_sameAcknowledgement(acknowledged!, post)) {
          throw const ClipGroupSubmissionException(
              ClipGroupSubmissionProblem.unconfirmed);
        }
      }
      guard();
      await verifyGroup();
      activeItem = null;
      report(ClipGroupSubmissionStage.done);
      return result();
    } catch (error) {
      final wasCancelled = !binding.isCurrent ||
          cancelled() ||
          (error is ClipGroupSubmissionException &&
              error.problem == ClipGroupSubmissionProblem.cancelled);
      // A failed save may have promoted its manifest before throwing. Read
      // explicit accepted identities back, but never submit from this reload.
      if (binding.isCurrent &&
          binding.userId == confirmedGroup.ownerUserId &&
          PostDeeAuthSessionStore.instance.session.stableUserId ==
              confirmedGroup.ownerUserId &&
          PostDeeAuthSessionStore.instance.session.isSignedIn) {
        try {
          final current = await groupStore.loadClipGroup(confirmedGroup.id);
          guardSession();
          if (current != null &&
              current.ownerUserId == confirmedGroup.ownerUserId &&
              _sameMembership(current, confirmedGroup)) {
            group = current;
          }
        } catch (_) {/* Existing child receipts remain the recovery source. */}
      }
      report(ClipGroupSubmissionStage.stopped);
      return result(error: error, wasCancelled: wasCancelled);
    } finally {
      if (ownsRun) _activeGroups.remove(runKey);
    }
  }

  void _validateGroup(ClipGroupDraft group) {
    final ids = <String>{};
    final indices = <int>{};
    if (group.items.isEmpty || group.items.length > 64) {
      throw const ClipGroupSubmissionException(
          ClipGroupSubmissionProblem.invalidMember);
    }
    for (final item in group.items) {
      if (item.draftId.trim().isEmpty ||
          !ids.add(item.draftId) ||
          item.index < 0 ||
          !indices.add(item.index) ||
          !item.sourceStartSeconds.isFinite ||
          !item.sourceEndSeconds.isFinite ||
          item.sourceStartSeconds < 0 ||
          item.sourceEndSeconds <= item.sourceStartSeconds ||
          item.platformApiValues.isEmpty ||
          !item.platformApiValues.every(_platforms.contains) ||
          (item.isAccepted && item.acceptedPostId!.trim().isEmpty)) {
        throw const ClipGroupSubmissionException(
            ClipGroupSubmissionProblem.invalidMember);
      }
    }
  }

  void _validateMember(
      ClipGroupDraft group, ClipGroupItem item, PublishDraft draft) {
    final expectedSchedule =
        group.deliveryMode == ClipGroupDeliveryMode.scheduled
            ? item.scheduledAt
            : null;
    if (draft.id != item.draftId ||
        draft.ownerUserId != group.ownerUserId ||
        draft.clipGroupId != group.id ||
        draft.isClipGroupSource ||
        draft.submissionRequestId.isEmpty ||
        !_samePlatforms(draft.platformApiValues, item.platformApiValues) ||
        draft.scheduledAt != expectedSchedule ||
        (item.usesSharedCaption && draft.caption != group.sharedCaption) ||
        (group.deliveryMode == ClipGroupDeliveryMode.scheduled &&
            (expectedSchedule == null ||
                (!expectedSchedule.isAfter(_now()) &&
                    draft.uploadedMedia == null)))) {
      throw const ClipGroupSubmissionException(
          ClipGroupSubmissionProblem.invalidMember);
    }
  }

  void _validateAcknowledgement(QueuedPostResult post, ClipGroupItem item) {
    if (post.id.trim().isEmpty ||
        post.videoS3Key.trim().isEmpty ||
        !_acceptedStatuses.contains(post.status.toUpperCase()) ||
        post.platforms.length != post.platforms.toSet().length ||
        !_samePlatforms(post.platforms.toSet(), item.platformApiValues)) {
      throw const ClipGroupSubmissionException(
          ClipGroupSubmissionProblem.unconfirmed);
    }
  }
}

bool _sameAcknowledgement(QueuedPostResult a, QueuedPostResult b) =>
    a.id == b.id &&
    a.videoS3Key == b.videoS3Key &&
    a.status.toUpperCase() == b.status.toUpperCase() &&
    _samePlatforms(a.platforms.toSet(), b.platforms.toSet());

bool _samePlatforms(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

String? _date(DateTime? value) => value?.toUtc().toIso8601String();

String _groupSnapshot(ClipGroupDraft group) => jsonEncode([
      group.id,
      group.ownerUserId,
      group.sourceDraftId,
      group.title,
      group.sharedCaption,
      group.captionContext?.toJson(),
      group.deliveryMode.name,
      _date(group.createdAt),
      _date(group.updatedAt),
      group.revision,
      [
        for (final item in group.items)
          [
            item.draftId,
            item.index,
            item.sourceStartSeconds,
            item.sourceEndSeconds,
            (item.platformApiValues.toList()..sort()),
            item.usesSharedCaption,
            _date(item.scheduledAt),
            item.acceptedPostId,
            item.acceptedPostStatus,
            _date(item.acceptedScheduledAt),
          ]
      ],
    ]);

bool _sameMembership(ClipGroupDraft a, ClipGroupDraft b) =>
    a.id == b.id &&
    a.items.length == b.items.length &&
    List.generate(a.items.length, (index) {
      final left = a.items[index], right = b.items[index];
      return left.draftId == right.draftId &&
          left.index == right.index &&
          left.sourceStartSeconds == right.sourceStartSeconds &&
          left.sourceEndSeconds == right.sourceEndSeconds &&
          _samePlatforms(left.platformApiValues, right.platformApiValues);
    }).every((same) => same);

String _draftSnapshot(PublishDraft draft) => jsonEncode([
      draft.id,
      draft.ownerUserId,
      draft.clipGroupId,
      draft.isClipGroupSource,
      draft.submissionRequestId,
      _date(draft.createdAt),
      _date(draft.updatedAt),
      draft.videoPath,
      draft.videoName,
      draft.videoSizeBytes,
      draft.videoWidth,
      draft.videoHeight,
      draft.mediaContentFingerprint,
      draft.caption,
      draft.captionNeedsReview,
      draft.captionLanguage,
      draft.aiGuidance,
      draft.watermarkEnabled,
      (draft.platformApiValues.toList()..sort()),
      draft.platformSettings.toDraftJson(),
      _date(draft.scheduledAt),
      draft.cover == null
          ? null
          : [
              draft.cover!.imagePath,
              draft.cover!.sizeBytes,
              draft.cover!.design.coverFrameTimeMs,
              draft.cover!.design.text,
              draft.cover!.design.fontFamily.name,
              draft.cover!.design.fontWeight,
              draft.cover!.design.fontSize,
              draft.cover!.design.textColor.toARGB32(),
              draft.cover!.design.backgroundColor.toARGB32(),
              draft.cover!.design.dx,
              draft.cover!.design.dy,
              draft.cover!.durationMs,
              draft.cover!.sourceKind.name,
              draft.cover!.sourceImagePath,
              draft.cover!.sourceImageName,
            ],
      draft.uploadedMedia == null
          ? null
          : [
              draft.uploadedMedia!.mediaContentFingerprint,
              draft.uploadedMedia!.videoS3Key,
              draft.uploadedMedia!.coverImageS3Key,
              draft.uploadedMedia!.videoPreparationPolicy,
              draft.uploadedMedia!.videoDurationSeconds,
              draft.uploadedMedia!.videoMetadata?.toJson(),
            ],
    ]);
