import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';

class CaptionQuotaStrip extends StatelessWidget {
  const CaptionQuotaStrip({
    super.key = const ValueKey('uploader-ai-caption-quota-strip'),
    required this.plan,
    required this.quota,
  });

  final String plan;
  final RealClipCaptionQuota quota;

  String get _planLabel => switch (plan.toUpperCase()) {
        'STARTER' => 'Starter',
        'PRO' => 'Pro',
        'BASIC' => 'Basic',
        _ => plan,
      };

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.textSecondary,
          fontSize: 11,
        );
    final remainingFraction = quota.limit > 0
        ? (quota.remainingThisMonth / quota.limit).clamp(0.0, 1.0)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'แคปชั่น AI คงเหลือ',
                    style: secondaryStyle?.copyWith(fontSize: 12),
                  ),
                ),
                const SizedBox(width: AppTheme.spaceSm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.mint,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      _planLabel,
                      style: secondaryStyle?.copyWith(
                        color: AppTheme.accentCyanInk,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppTheme.spaceMd,
              runSpacing: 2,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${quota.remainingThisMonth}',
                        style: secondaryStyle?.copyWith(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: ' / ${quota.limit} เครดิต'),
                    ],
                  ),
                  style: secondaryStyle,
                ),
                Text('ใช้ไป ${quota.usedThisMonth} เครดิต',
                    style: secondaryStyle),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const ValueKey('uploader-ai-caption-quota-progress'),
                value: remainingFraction,
                minHeight: 3,
                backgroundColor: AppTheme.border,
                color: AppTheme.accentCyanInk,
                semanticsLabel:
                    'แคปชั่น AI เหลือ ${quota.remainingThisMonth} จาก ${quota.limit} เครดิต',
              ),
            ),
            if (quota.addonRemaining > 0) ...[
              const SizedBox(height: 4),
              Text('+ เครดิตเติม ${quota.addonRemaining} เครดิต',
                  style: secondaryStyle),
            ],
          ],
        ),
      ),
    );
  }
}
