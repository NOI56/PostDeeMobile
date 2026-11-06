import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import 'clip_group_draft.dart';
import 'publish_draft.dart';
import 'uploader_localizations.dart';

/// A caption target derived from committed membership, never the backup draft.
class ClipGroupCaptionScope {
  ClipGroupCaptionScope({
    required this.draftId,
    required this.isFull,
    required this.index,
    required Set<String> platformApiValues,
    this.sourceStartSeconds,
    this.sourceEndSeconds,
  }) : platformApiValues = Set.unmodifiable(platformApiValues);

  final String? draftId;
  final bool isFull;

  /// One-based part number. All and full-length members do not consume one.
  final int index;
  final Set<String> platformApiValues;
  final double? sourceStartSeconds;
  final double? sourceEndSeconds;
  bool get isAll => draftId == null;
  double? get durationSeconds =>
      sourceStartSeconds == null || sourceEndSeconds == null
          ? null
          : sourceEndSeconds! - sourceStartSeconds!;

  List<SocialPlatform> get platforms =>
      List.unmodifiable(SocialPlatform.values.where((platform) =>
          _publishingPlatforms.contains(platform) &&
          platformApiValues.contains(platform.apiValue)));
}

const _publishingPlatforms = {
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
};

/// The caller supplies measured original duration: PublishDraft does not store
/// it. A last part's endpoint cannot establish full length after manual cuts.
List<ClipGroupCaptionScope> clipGroupCaptionScopes(
    ClipGroupDraft group, Map<String, PublishDraft> draftsById,
    {double? sourceDurationSeconds}) {
  final source = draftsById[group.sourceDraftId];
  final hasSourceDuration = source != null &&
      source.id == group.sourceDraftId &&
      source.ownerUserId == group.ownerUserId &&
      source.clipGroupId == group.id &&
      source.isClipGroupSource &&
      sourceDurationSeconds != null &&
      sourceDurationSeconds.isFinite &&
      sourceDurationSeconds > 0;
  bool isFull(ClipGroupItem item) =>
      hasSourceDuration &&
      item.sourceStartSeconds.abs() <= .001 &&
      (item.sourceEndSeconds - sourceDurationSeconds).abs() <= .001;
  final seen = <String>{};
  final members = group.items.where((item) {
    final draft = draftsById[item.draftId];
    return item.draftId != group.sourceDraftId &&
        seen.add(item.draftId) &&
        item.sourceStartSeconds.isFinite &&
        item.sourceEndSeconds.isFinite &&
        item.sourceStartSeconds >= 0 &&
        item.sourceEndSeconds > item.sourceStartSeconds &&
        draft != null &&
        draft.id == item.draftId &&
        draft.ownerUserId == group.ownerUserId &&
        draft.clipGroupId == group.id &&
        !draft.isClipGroupSource;
  }).toList()
    ..sort((a, b) {
      if (isFull(a) != isFull(b)) return isFull(a) ? -1 : 1;
      final start = a.sourceStartSeconds.compareTo(b.sourceStartSeconds);
      return start != 0 ? start : a.index.compareTo(b.index);
    });
  var partNumber = 0;
  return List.unmodifiable([
    ClipGroupCaptionScope(
      draftId: null,
      isFull: false,
      index: 0,
      platformApiValues: {
        for (final item in members) ...item.platformApiValues,
      },
      sourceStartSeconds: hasSourceDuration ? 0 : null,
      sourceEndSeconds: hasSourceDuration ? sourceDurationSeconds : null,
    ),
    for (final item in members)
      ClipGroupCaptionScope(
        draftId: item.draftId,
        isFull: isFull(item),
        index: isFull(item) ? 0 : ++partNumber,
        platformApiValues: item.platformApiValues,
        sourceStartSeconds: item.sourceStartSeconds,
        sourceEndSeconds: item.sourceEndSeconds,
      ),
  ]);
}

class ClipGroupCaptionSelector extends StatelessWidget {
  const ClipGroupCaptionSelector({
    super.key,
    required this.group,
    required this.draftsById,
    required this.selectedDraftId,
    required this.onSelected,
    this.enabled = true,
    this.sourceDurationSeconds,
  });

  final ClipGroupDraft group;
  final Map<String, PublishDraft> draftsById;
  final String? selectedDraftId;
  final ValueChanged<String?> onSelected;
  final bool enabled;
  final double? sourceDurationSeconds;

  // This is outside the persisted draft ID alphabet, so All cannot collide.
  static const _allValue = '@all';
  String _value(ClipGroupCaptionScope scope) => scope.draftId ?? _allValue;
  Key _key(ClipGroupCaptionScope scope) =>
      ValueKey('clip-group-caption-scope-${scope.draftId ?? 'all'}');

  String _label(BuildContext context, ClipGroupCaptionScope scope) =>
      scope.isAll
          ? uploaderText(context, 'ทั้งหมด', 'All')
          : scope.isFull
              ? uploaderText(context, 'คลิปเต็ม', 'Full clip')
              : uploaderText(
                  context, 'ตอนที่ ${scope.index}', 'Part ${scope.index}');

  @override
  Widget build(BuildContext context) {
    final scopes = clipGroupCaptionScopes(group, draftsById,
        sourceDurationSeconds: sourceDurationSeconds);
    final selected =
        scopes.where((scope) => scope.draftId == selectedDraftId).firstOrNull ??
            scopes.first;
    return Column(
      key: const ValueKey('clip-group-caption-scopes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scopes.length <= 4)
          Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceXs,
            children: [
              for (final scope in scopes)
                ChoiceChip(
                  key: _key(scope),
                  label: Text(_label(context, scope)),
                  selected: identical(scope, selected),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: enabled ? (_) => onSelected(scope.draftId) : null,
                ),
            ],
          )
        else
          InputDecorator(
            decoration: InputDecoration(
              labelText:
                  uploaderText(context, 'เขียนแคปชั่นให้', 'Caption for'),
              enabled: enabled,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('clip-group-caption-scope-picker'),
                value: _value(selected),
                isExpanded: true,
                itemHeight: null,
                items: [
                  for (final scope in scopes)
                    DropdownMenuItem(
                      key: _key(scope),
                      value: _value(scope),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spaceSm),
                        child: Text(_label(context, scope),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        final scope = scopes
                            .where((scope) => _value(scope) == value)
                            .firstOrNull;
                        if (scope != null) onSelected(scope.draftId);
                      }
                    : null,
              ),
            ),
          ),
        if (selected.platforms.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            selected.platforms.map((platform) => platform.label).join(' · '),
            key: const ValueKey('clip-group-caption-scope-platforms'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
