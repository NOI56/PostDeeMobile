import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'edit_styles.dart';

/// Opens the auto-edit style gallery and returns the user's selection (or null
/// if dismissed). Custom Prompt carries the typed prompt.
Future<EditStyleSelection?> showEditStyleGallery(BuildContext context) {
  return showModalBottomSheet<EditStyleSelection>(
    context: context,
    backgroundColor: AppTheme.charcoal,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.cardRadius)),
    ),
    builder: (context) => const _EditStyleGallerySheet(),
  );
}

class _EditStyleGallerySheet extends StatefulWidget {
  const _EditStyleGallerySheet();

  @override
  State<_EditStyleGallerySheet> createState() => _EditStyleGallerySheetState();
}

class _EditStyleGallerySheetState extends State<_EditStyleGallerySheet> {
  final _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _select(EditStyle style, {String? prompt}) {
    Navigator.of(context).pop(EditStyleSelection(style: style, prompt: prompt));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTheme.spaceSm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderSoft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.spaceLg,
                  AppTheme.spaceMd, AppTheme.spaceLg, AppTheme.spaceSm),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.accent),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Text(
                      'เลือกสไตล์ตัดต่ออัตโนมัติ',
                      style:
                          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.spaceLg, 0,
                    AppTheme.spaceLg, AppTheme.spaceLg),
                children: [
                  for (final group in EditStyleGroup.values)
                    ..._buildGroup(context, group),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroup(BuildContext context, EditStyleGroup group) {
    final styles = editStyles.where((s) => s.group == group).toList();

    if (styles.isEmpty) {
      return const [];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(top: AppTheme.spaceMd, bottom: AppTheme.spaceSm),
        child: Text(
          group.label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.accentCyanInk,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
      for (final style in styles)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
          child: style.plan.isCustomPrompt
              ? _CustomPromptCard(
                  style: style,
                  controller: _promptController,
                  onSubmit: () => _select(
                    style,
                    prompt: _promptController.text.trim(),
                  ),
                )
              : _StyleCard(style: style, onTap: () => _select(style)),
        ),
    ];
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.style, required this.onTap});

  final EditStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppTheme.borderSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(style.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            style.name,
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (style.plan.comingSoon) ...[
                          const SizedBox(width: AppTheme.spaceSm),
                          const _Badge(label: 'เร็วๆ นี้'),
                        ] else if (style.plan.requiresAi) ...[
                          const SizedBox(width: AppTheme.spaceSm),
                          const _Badge(label: 'ใช้ AI'),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(style.editingNote,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text('เหมาะกับ: ${style.suitableFor}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomPromptCard extends StatelessWidget {
  const _CustomPromptCard({
    required this.style,
    required this.controller,
    required this.onSubmit,
  });

  final EditStyle style;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(style.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Text(style.name,
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const _Badge(label: 'Pro'),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXs),
            Text(style.editingNote,
                style:
                    textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: AppTheme.spaceMd),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'เช่น "เหลือ 45 วิ" หรือ "ตัดคำหยาบออก" '
                    '(เลือกฉากจากภาพ — เร็วๆ นี้)',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('ให้ AI ตัดให้'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
