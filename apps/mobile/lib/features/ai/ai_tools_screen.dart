import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';

class AiToolsScreen extends StatelessWidget {
  const AiToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppTheme.screenPadding,
      children: [
        PostDeeCard(
          key: const ValueKey('ai-tools-real-clip-caption'),
          glowColor: AppTheme.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI แคปชั่นจากคลิปจริง',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  PostDeeSoftPill(
                    label: 'หน้าอัปโหลด',
                    icon: Icons.cloud_upload_outlined,
                    color: AppTheme.accentCyanInk,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'ฟีเจอร์ AI ตอนนี้ย้ายไปอยู่ในหน้าอัปโหลดแล้ว เลือกคลิปก่อน จากนั้น AI จะฟังเสียงคลิปจริงเพื่อช่วยทำ Hook, SEO และแฮชแท็ก',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              const _AiToolsFeatureRow(
                icon: Icons.graphic_eq,
                label: 'Starter 199',
                value: 'ฟังเสียงคลิปจริง 50 ครั้ง/เดือน',
              ),
              SizedBox(height: AppTheme.spaceSm),
              const _AiToolsFeatureRow(
                icon: Icons.visibility_outlined,
                label: 'Pro 299',
                value: 'ฟังเสียง + ดูภาพตัวอย่าง 120 ครั้ง/เดือน',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiToolsFeatureRow extends StatelessWidget {
  const _AiToolsFeatureRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accentCyanInk, size: 18),
        const SizedBox(width: AppTheme.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
