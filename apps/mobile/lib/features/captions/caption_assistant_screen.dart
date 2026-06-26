import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';

typedef CaptionGenerator = Future<CaptionResult> Function(
  List<String> keywords,
);
typedef CaptionSubscriptionLoader = Future<SubscriptionStatusResult> Function();

class CaptionAssistantScreen extends StatelessWidget {
  const CaptionAssistantScreen({
    super.key,
    this.showTitle = true,
    this.generateCaption,
    this.loadSubscription,
  });

  final bool showTitle;
  final CaptionGenerator? generateCaption;
  final CaptionSubscriptionLoader? loadSubscription;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (showTitle) ...[
          Text(
            'AI แคปชั่นจากคลิปจริง',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
        ],
        PostDeeCard(
          key: const ValueKey('caption-assistant-real-clip-message'),
          glowColor: AppTheme.accentCyan,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: AppTheme.accentCyanInk,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ใช้ AI จากหน้าอัปโหลด',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const PostDeeSoftPill(
                    label: 'Clip-first',
                    icon: Icons.movie_creation_outlined,
                    color: AppTheme.accent,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'ระบบใหม่ต้องเลือกคลิปก่อน แล้ว AI จะฟังเสียงจริงในคลิปเพื่อช่วยทำ Caption, Hook, SEO และ Hashtag ให้เหมาะกับโพสต์นั้น',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _CaptionModeTile(
                key: ValueKey('caption-assistant-starter-mode'),
                title: 'Starter 199',
                detail: 'ฟังเสียงคลิปจริง 50 ครั้งต่อเดือน',
                icon: Icons.graphic_eq,
                color: AppTheme.accentPinkInk,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _CaptionModeTile(
                key: ValueKey('caption-assistant-pro-mode'),
                title: 'Pro 299',
                detail: 'ฟังเสียง + ดูภาพตัวอย่าง 120 ครั้งต่อเดือน',
                icon: Icons.visibility_outlined,
                color: AppTheme.accentCyanInk,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptionModeTile extends StatelessWidget {
  const _CaptionModeTile({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    super.key,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.25,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
