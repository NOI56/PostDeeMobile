import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';

class PostQuotaStrip extends StatelessWidget {
  const PostQuotaStrip({
    super.key = const ValueKey('uploader-post-quota-strip'),
    required this.subscription,
  });

  final SubscriptionStatusResult subscription;

  String get _planLabel => switch (subscription.plan.toUpperCase()) {
        'STARTER' => 'Starter',
        'PRO' => 'Pro',
        'BASIC' => 'Basic',
        _ => subscription.plan,
      };

  @override
  Widget build(BuildContext context) {
    final limit = subscription.monthlyPostLimit;
    final used = subscription.usedPostsThisMonth;
    final remaining = subscription.remainingPostsThisMonth;
    if (limit == null ||
        used == null ||
        remaining == null ||
        limit < 0 ||
        used < 0 ||
        remaining < 0 ||
        remaining > limit) {
      return const SizedBox.shrink();
    }
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.textSecondary,
          fontSize: 11,
        );
    final remainingFraction =
        limit > 0 ? (remaining / limit).clamp(0.0, 1.0) : 0.0;
    final canSpendAddon = subscription.isStarter || subscription.isPro;

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
                    'โพสต์คงเหลือ',
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
                        text: '$remaining',
                        style: secondaryStyle?.copyWith(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: ' / $limit หน่วย'),
                    ],
                  ),
                  style: secondaryStyle,
                ),
                Text('ใช้ไป $used หน่วย', style: secondaryStyle),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const ValueKey('uploader-post-quota-progress'),
                value: remainingFraction,
                minHeight: 3,
                backgroundColor: AppTheme.border,
                color: AppTheme.accentCyanInk,
                semanticsLabel: 'โพสต์เหลือ $remaining จาก $limit หน่วย',
              ),
            ),
            if (canSpendAddon && subscription.addonPostUnits > 0) ...[
              const SizedBox(height: 4),
              Text('+ เครดิตเติม ${subscription.addonPostUnits} หน่วย',
                  style: secondaryStyle),
            ],
            if (subscription.requiresPhoneVerification) ...[
              const SizedBox(height: 4),
              Text('ยืนยันเบอร์เพื่อใช้โควตาฟรี', style: secondaryStyle),
            ],
          ],
        ),
      ),
    );
  }
}
