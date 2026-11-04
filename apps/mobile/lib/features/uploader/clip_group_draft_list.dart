import 'clip_group_draft.dart';
import 'publish_draft.dart';

/// Reconciles list identity from committed manifests without changing storage.
/// Orphaned or conflicting tags remain reachable as ordinary local drafts.
List<PublishDraft> projectClipGroupDrafts(
    Iterable<PublishDraft> drafts, Iterable<ClipGroupDraft> validGroups) {
  final bindings = <(String, String), (ClipGroupDraft, bool)>{};
  final groupIds = <(String, String)>{};
  final conflicts = <(String, String)>{};
  for (final group in validGroups) {
    try {
      validateClipGroupDraft(group);
    } on FormatException {
      continue;
    }
    final groupKey = (group.ownerUserId, group.id);
    if (!groupIds.add(groupKey)) conflicts.add(groupKey);
    for (final (id, isSource) in [
      (group.sourceDraftId, true),
      for (final item in group.items) (item.draftId, false),
    ]) {
      final draftKey = (group.ownerUserId, id);
      final previous = bindings[draftKey];
      if (previous != null) {
        conflicts.add((previous.$1.ownerUserId, previous.$1.id));
        conflicts.add(groupKey);
      } else {
        bindings[draftKey] = (group, isSource);
      }
    }
  }
  return List.unmodifiable([
    for (final draft in drafts)
      () {
        final binding = bindings[(draft.ownerUserId, draft.id)];
        final usable = binding != null &&
            !conflicts.contains((binding.$1.ownerUserId, binding.$1.id));
        final groupId = usable ? binding.$1.id : null;
        final isSource = usable && binding.$2;
        if (draft.clipGroupId == groupId &&
            draft.isClipGroupSource == isSource) {
          return draft;
        }
        return PublishDraft(
          version: draft.version,
          id: draft.id,
          ownerUserId: draft.ownerUserId,
          submissionRequestId: draft.submissionRequestId,
          createdAt: draft.createdAt,
          updatedAt: draft.updatedAt,
          videoPath: draft.videoPath,
          videoName: draft.videoName,
          videoSizeBytes: draft.videoSizeBytes,
          videoWidth: draft.videoWidth,
          videoHeight: draft.videoHeight,
          caption: draft.caption,
          captionNeedsReview: draft.captionNeedsReview,
          captionLanguage: draft.captionLanguage,
          aiGuidance: draft.aiGuidance,
          watermarkEnabled: draft.watermarkEnabled,
          platformApiValues: draft.platformApiValues,
          platformSettings: draft.platformSettings,
          scheduledAt: draft.scheduledAt,
          cover: draft.cover,
          mediaContentFingerprint: draft.mediaContentFingerprint,
          uploadedMedia: draft.uploadedMedia,
          clipGroupId: groupId,
          isClipGroupSource: isSource,
        );
      }(),
  ]);
}

/// A group and all its local media have one entry in every draft list.
/// The source stays reachable even after accepted members have been removed.
class ClipGroupDraftListEntry {
  ClipGroupDraftListEntry(List<PublishDraft> drafts) : this._(drafts, null);

  ClipGroupDraftListEntry._(List<PublishDraft> drafts, this._group)
      : members = List.unmodifiable(
          drafts.toList()
            ..sort((a, b) {
              if (a.isClipGroupSource != b.isClipGroupSource) {
                return a.isClipGroupSource ? -1 : 1;
              }
              final created = a.createdAt.compareTo(b.createdAt);
              return created != 0 ? created : a.id.compareTo(b.id);
            }),
        );

  final List<PublishDraft> members;
  final ClipGroupDraft? _group;
  PublishDraft get primaryDraft => members.first;

  /// Current journal text is display metadata, never a rewritten source draft.
  String get displayTitle {
    final group = _group;
    if (group != null) {
      return group.sharedCaption.trim().isEmpty
          ? group.title.trim()
          : group.sharedCaption.trim();
    }
    return primaryDraft.caption.trim().isEmpty
        ? primaryDraft.videoName
        : primaryDraft.caption.trim();
  }

  String? get groupId => primaryDraft.clipGroupId;
  bool get isGroup => groupId != null;
  int get clipCount =>
      members.where((draft) => !draft.isClipGroupSource).length;
  DateTime get updatedAt {
    final latest = members
        .map((draft) => draft.updatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final groupTime = _group?.updatedAt;
    return groupTime != null && groupTime.isAfter(latest) ? groupTime : latest;
  }

  Set<String> get platformApiValues {
    final clips = members.where((draft) => !draft.isClipGroupSource).toList();
    return {
      for (final draft in clips.isEmpty ? members : clips)
        ...draft.platformApiValues,
    };
  }
}

List<ClipGroupDraftListEntry> clipGroupDraftList(Iterable<PublishDraft> drafts,
    {Iterable<ClipGroupDraft> groups = const []}) {
  final allDrafts = drafts.toList();
  final manifests = groups.toList();
  final displayGroups = <(String, String), ClipGroupDraft>{};
  for (final group in manifests) {
    try {
      validateClipGroupDraft(group);
      displayGroups[(group.ownerUserId, group.id)] = group;
    } on FormatException {
      // Invalid or conflicting metadata cannot replace an ordinary preview.
    }
  }
  final projected = {
    for (final draft in manifests.isEmpty
        ? const <PublishDraft>[]
        : projectClipGroupDrafts(allDrafts, manifests))
      (draft.ownerUserId, draft.id): draft,
  };
  final grouped = <(String, String), List<PublishDraft>>{};
  final entries = <ClipGroupDraftListEntry>[];
  for (final draft in allDrafts) {
    final group = draft.clipGroupId;
    if (group == null) {
      entries.add(ClipGroupDraftListEntry([draft]));
    } else {
      grouped.putIfAbsent(
          (draft.ownerUserId, group), () => <PublishDraft>[]).add(draft);
    }
  }
  for (final entry in grouped.entries) {
    final candidate = displayGroups[entry.key];
    final usable = candidate != null &&
        entry.value.every((draft) =>
            projected[(draft.ownerUserId, draft.id)]?.clipGroupId ==
            candidate.id);
    entries
        .add(ClipGroupDraftListEntry._(entry.value, usable ? candidate : null));
  }
  entries.sort((a, b) {
    final updated = b.updatedAt.compareTo(a.updatedAt);
    return updated != 0
        ? updated
        : a.primaryDraft.id.compareTo(b.primaryDraft.id);
  });
  return List.unmodifiable(entries);
}
