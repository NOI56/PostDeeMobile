import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';
import 'clip_group_draft.dart';
import 'clip_group_localizations.dart';

/// Presentation only. The group review route owns navigation, saving and locks.
class ClipGroupCaptionHeader extends StatelessWidget {
  const ClipGroupCaptionHeader({
    super.key,
    required this.onBack,
    required this.onSave,
    required this.stage,
  });

  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final int stage;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.spaceSm, AppTheme.spaceSm, AppTheme.spaceLg, 0),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // BackButton's null callback normally performs an implicit pop.
            // Keep its native appearance without allowing that busy-state exit.
            Semantics(
              button: true,
              enabled: onBack != null,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: onBack,
              child: ExcludeSemantics(
                child: ExcludeFocus(
                  excluding: onBack == null,
                  child: IgnorePointer(
                    ignoring: onBack == null,
                    child: BackButton(
                      onPressed: onBack ?? () {},
                      color: onBack == null ? AppTheme.textMuted : null,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppTheme.spaceXs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(clipGroupText(context, 'สร้างโพสต์', 'Create post'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(
                      clipGroupText(context, 'เตรียมคลิป แล้วตรวจทานก่อนส่ง',
                          'Prepare your clips, then review before sending.'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spaceXs),
            IconButton(
              key: const ValueKey('clip-group-header-save'),
              onPressed: onSave,
              tooltip: clipGroupText(
                  context, 'เก็บร่างทั้งชุด', 'Save the set as a draft'),
              icon: const Icon(Icons.save_outlined),
            ),
          ]),
          const SizedBox(height: AppTheme.spaceMd),
          Padding(
            padding: const EdgeInsets.only(left: AppTheme.spaceSm),
            child: _progress(context),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ]),
      );

  Widget _progress(BuildContext context) {
    final current = stage == 0 ? 2 : 3;
    final labels = [
      clipGroupText(context, 'ช่องทาง', 'Channels'),
      clipGroupText(context, 'คลิป', 'Video'),
      clipGroupText(context, 'แคปชัน', 'Caption'),
      clipGroupText(context, 'ตรวจทาน', 'Review'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final stepWidth = constraints.maxWidth / labels.length;
      return Stack(children: [
        for (var index = 0; index < labels.length - 1; index++)
          Positioned(
            left: stepWidth * (index + .5) + 13,
            top: 12,
            width: stepWidth - 26,
            height: 2,
            child: ExcludeSemantics(child: ColoredBox(color: AppTheme.border)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Semantics(
                selected: index == current,
                label: clipGroupText(
                    context,
                    'ขั้นตอน ${index + 1} จาก 4 · ${labels[index]}',
                    'Step ${index + 1} of 4 · ${labels[index]}'),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spaceXs),
                    child: Column(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: index > current
                              ? Border.all(color: AppTheme.border)
                              : null,
                          color: index == current
                              ? AppTheme.accent
                              : index < current
                                  ? AppTheme.accent.withValues(alpha: .12)
                                  : AppTheme.glassDeep,
                        ),
                        child: index < current
                            ? Icon(Icons.check_rounded,
                                size: 17, color: AppTheme.accent)
                            : Text('${index + 1}',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: index == current
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                )),
                      ),
                      const SizedBox(height: AppTheme.spaceXs),
                      Text(labels[index],
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: index == current
                                        ? AppTheme.accentCyanInk
                                        : AppTheme.textSecondary,
                                    fontWeight: index == current
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  )),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ]);
    });
  }
}

/// Uses only persisted group metadata; ranges and member actions stay caller-owned.
class ClipGroupSplitSummary extends StatelessWidget {
  const ClipGroupSplitSummary({
    super.key,
    required this.group,
    required this.onShowParts,
  });

  final ClipGroupDraft group;
  final VoidCallback? onShowParts;

  @override
  Widget build(BuildContext context) {
    final count = group.items.length;
    final destinations = {
      for (final item in group.items) ...item.platformApiValues,
    };
    final platforms = SocialPlatform.values
        .where((platform) => destinations.contains(platform.apiValue));
    return PostDeeCard(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.content_cut_rounded,
                color: AppTheme.accentCyanInk, size: 20),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                clipGroupText(context, 'เตรียมคลิปแล้ว $count คลิป',
                    'Prepared $count ${count == 1 ? 'clip' : 'clips'}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ]),
          const SizedBox(height: AppTheme.spaceSm),
          Text(group.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceMd,
            runSpacing: AppTheme.spaceSm,
            children: [
              for (final platform in platforms)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  ExcludeSemantics(
                      child: SocialPlatformLogo(platform: platform, size: 20)),
                  const SizedBox(width: AppTheme.spaceXs),
                  Flexible(
                      child: Text(platform.label,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textSecondary))),
                ]),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('clip-group-show-parts'),
              onPressed: onShowParts,
              icon: const Icon(Icons.view_list_outlined, size: 18),
              label: Text(
                  clipGroupText(context, 'ดูตอนที่แบ่ง', 'View split parts')),
            ),
          ),
        ],
      ),
    );
  }
}
