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
  ClipGroupDraftListEntry(List<PublishDraft> drafts)
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
  PublishDraft get primaryDraft => members.first;
  String? get groupId => primaryDraft.clipGroupId;
  bool get isGroup => groupId != null;
  int get clipCount =>
      members.where((draft) => !draft.isClipGroupSource).length;
  DateTime get updatedAt => members
      .map((draft) => draft.updatedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  Set<String> get platformApiValues {
    final clips = members.where((draft) => !draft.isClipGroupSource).toList();
    return {
      for (final draft in clips.isEmpty ? members : clips)
        ...draft.platformApiValues,
    };
  }
}

List<ClipGroupDraftListEntry> clipGroupDraftList(
    Iterable<PublishDraft> drafts) {
  final grouped = <(String, String), List<PublishDraft>>{};
  final entries = <ClipGroupDraftListEntry>[];
  for (final draft in drafts) {
    final group = draft.clipGroupId;
    if (group == null) {
      entries.add(ClipGroupDraftListEntry([draft]));
    } else {
      grouped.putIfAbsent(
          (draft.ownerUserId, group), () => <PublishDraft>[]).add(draft);
    }
  }
  entries.addAll(grouped.values.map(ClipGroupDraftListEntry.new));
  entries.sort((a, b) {
    final updated = b.updatedAt.compareTo(a.updatedAt);
    return updated != 0
        ? updated
        : a.primaryDraft.id.compareTo(b.primaryDraft.id);
  });
  return List.unmodifiable(entries);
}
