import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../shared/postdee_card.dart';
import 'uploader_localizations.dart';

/// Advisory only: opening a plan never writes media or consumes post units.
class ClipSplitPrompt extends StatelessWidget {
  const ClipSplitPrompt({
    super.key,
    required this.exceededPlatforms,
    required this.onOpen,
    this.needsSubmissionRecovery = false,
  });

  final List<SocialPlatform> exceededPlatforms;
  final VoidCallback? onOpen;
  final bool needsSubmissionRecovery;

  @override
  Widget build(BuildContext context) => PostDeeCard(
        key: const ValueKey('uploader-clip-split-prompt'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.content_cut_rounded,
                  size: 20, color: AppTheme.accentCyanInk),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  uploaderText(
                      context,
                      'คลิปยาวเกิน ${exceededPlatforms.length} ช่องทาง',
                      'Too long for ${exceededPlatforms.length} ${exceededPlatforms.length == 1 ? 'channel' : 'channels'}'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ]),
            const SizedBox(height: AppTheme.spaceSm),
            Text(exceededPlatforms.map((p) => p.label).join(' · '),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: AppTheme.spaceSm),
            Text(uploaderText(
                context,
                'แบ่งเป็นตอนให้พอดีกับแต่ละช่องทางไหม? ช่องทางที่ลงเต็มได้จะใช้คลิปเดิม',
                'Split into parts for each channel? Channels that accept the full video can keep it.')),
            const SizedBox(height: AppTheme.spaceMd),
            FilledButton.icon(
              key: const ValueKey('uploader-clip-split-open'),
              onPressed: onOpen,
              icon: const Icon(Icons.content_cut_rounded, size: 18),
              label: Text(
                  uploaderText(context, 'ดูแผนแบ่งคลิป', 'Review split plan')),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              uploaderText(
                  context,
                  needsSubmissionRecovery
                      ? 'ตรวจรายการโพสต์เดิมก่อนแบ่ง เพื่อป้องกันการสร้างรายการซ้ำ'
                      : 'เก็บต้นฉบับไว้ · ยังไม่สร้างโพสต์หรือใช้โควตา',
                  needsSubmissionRecovery
                      ? 'Check the existing submission before splitting to avoid duplicate posts.'
                      : 'Keep the original · No posts or post units used yet'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
}
