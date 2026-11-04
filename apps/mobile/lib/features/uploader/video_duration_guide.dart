import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';
import 'platform_publish_preflight.dart';
import 'platform_publish_settings.dart';
import 'uploader_localizations.dart';

/// A duration-only guide for the clip selection step. Passing a time limit
/// does not establish account readiness or verify the file's other properties.
class VideoDurationGuide extends StatelessWidget {
  const VideoDurationGuide({
    super.key,
    this.durationSeconds,
    this.tikTokMaxDurationSeconds,
    this.tikTokPublishMode = TikTokPublishMode.inboxDraft,
    this.tikTokConnected = false,
    this.isLoadingTikTokLimit = false,
    this.tikTokLimitFailed = false,
    this.onRetryTikTokLimit,
  });

  final double? durationSeconds;
  final int? tikTokMaxDurationSeconds;
  final TikTokPublishMode tikTokPublishMode;
  final bool tikTokConnected;
  final bool isLoadingTikTokLimit;
  final bool tikTokLimitFailed;
  final VoidCallback? onRetryTikTokLimit;

  static const _platforms = [
    SocialPlatform.tiktok,
    SocialPlatform.facebookReels,
    SocialPlatform.instagramReels,
    SocialPlatform.youtubeShorts,
  ];

  bool get _hasCreatorLimit =>
      tikTokMaxDurationSeconds != null && tikTokMaxDurationSeconds! > 0;

  bool get _isTikTokDirect => tikTokPublishMode == TikTokPublishMode.directPost;

  PlatformVideoDurationRule _rule(SocialPlatform platform) =>
      platformVideoDurationRule(platform,
          tikTokMaxDurationSeconds:
              _isTikTokDirect ? tikTokMaxDurationSeconds : null)!;

  String _directRange(BuildContext context) {
    if (!_hasCreatorLimit) {
      return uploaderText(context, 'โพสต์ตรง: รอตรวจบัญชี',
          'Direct post: account check pending');
    }
    final maximum = platformVideoDurationRule(SocialPlatform.tiktok,
            tikTokMaxDurationSeconds: tikTokMaxDurationSeconds)!
        .maximumSeconds;
    return uploaderText(context, 'โพสต์ตรง: สูงสุด $maximum วินาที',
        'Direct post: up to $maximum seconds');
  }

  String _range(BuildContext context, SocialPlatform platform) {
    final rule = _rule(platform);
    final maximum = rule.maximumSeconds;
    if (platform == SocialPlatform.tiktok) {
      return _isTikTokDirect
          ? _directRange(context)
          : uploaderText(context, 'ส่งเป็นร่าง: สูงสุด $maximum วินาที',
              'Send to drafts: up to $maximum seconds');
    }
    if (rule.minimumSeconds case final minimum?) {
      return uploaderText(
          context, '$minimum–$maximum วินาที', '$minimum–$maximum seconds');
    }
    return uploaderText(
        context, 'สูงสุด $maximum วินาที', 'Up to $maximum seconds');
  }

  (String, Color, IconData)? _status(
      BuildContext context, SocialPlatform platform) {
    final duration = durationSeconds;
    if (duration == null || !duration.isFinite || duration <= 0) return null;
    final rule = _rule(platform);
    final maximum = rule.maximumSeconds;
    final problem = validatePlatformVideoDuration(
        platform: platform,
        durationSeconds: duration,
        tikTokMaxDurationSeconds:
            _isTikTokDirect ? tikTokMaxDurationSeconds : null);
    if (problem != null && duration > maximum) {
      final excess = (duration - maximum).ceil();
      return (
        uploaderText(
            context, 'ยาวเกิน $excess วินาที', '$excess seconds too long'),
        Theme.of(context).colorScheme.error,
        Icons.error_outline_rounded,
      );
    }
    if (problem != null) {
      return (
        uploaderText(context, 'ต้องยาวอย่างน้อย ${rule.minimumSeconds} วินาที',
            'At least ${rule.minimumSeconds} seconds required'),
        Theme.of(context).colorScheme.error,
        Icons.error_outline_rounded,
      );
    }
    if (platform == SocialPlatform.tiktok &&
        _isTikTokDirect &&
        !_hasCreatorLimit) {
      return (
        uploaderText(context, 'รอตรวจบัญชี', 'Account check pending'),
        AppTheme.textSecondary,
        Icons.info_outline_rounded,
      );
    }
    return (
      platform == SocialPlatform.tiktok && !_isTikTokDirect
          ? uploaderText(
              context, 'เวลาส่งร่างผ่านเกณฑ์', 'Within draft transfer limit')
          : uploaderText(context, 'ผ่านเกณฑ์เวลา', 'Within time limit'),
      AppTheme.successInk,
      Icons.check_circle_outline_rounded,
    );
  }

  Widget _buildRow(BuildContext context, SocialPlatform platform) {
    final status = _status(context, platform);
    return Padding(
      key: ValueKey('video-duration-${platform.apiValue}'),
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialPlatformLogo(platform: platform),
          const SizedBox(width: AppTheme.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Wrap(
                  spacing: AppTheme.spaceMd,
                  runSpacing: AppTheme.spaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _range(context, platform),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                    ),
                    if (status != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.$3, size: 14, color: status.$2),
                          const SizedBox(width: AppTheme.spaceXs),
                          Flexible(
                            child: Text(
                              status.$1,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: status.$2),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (platform == SocialPlatform.tiktok) ...[
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                      _isTikTokDirect
                          ? uploaderText(
                              context,
                              'PostDee รองรับไม่เกิน $tikTokPostDeeMaxDurationSeconds วินาที',
                              'PostDee ceiling: $tikTokPostDeeMaxDurationSeconds seconds')
                          : _directRange(context),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          )),
                  if (isLoadingTikTokLimit)
                    Padding(
                        padding: const EdgeInsets.only(top: AppTheme.spaceXs),
                        child: Row(children: [
                          const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: AppTheme.spaceSm),
                          Expanded(
                              child: Text(
                                  uploaderText(
                                      context,
                                      'กำลังตรวจบัญชี TikTok...',
                                      'Checking TikTok account...'),
                                  style:
                                      Theme.of(context).textTheme.bodySmall)),
                        ])),
                  if (tikTokLimitFailed && tikTokConnected) ...[
                    Text(
                        uploaderText(context, 'ตรวจขีดจำกัดบัญชีไม่สำเร็จ',
                            'Could not check the account limit'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textSecondary)),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('video-duration-tiktok-retry'),
                          onPressed:
                              isLoadingTikTokLimit ? null : onRetryTikTokLimit,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label:
                              Text(uploaderText(context, 'ลองใหม่', 'Retry')),
                        )),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = durationSeconds;
    final measured = duration != null && duration.isFinite && duration > 0;
    final displayedSeconds = measured
        ? (duration == duration.roundToDouble()
            ? duration.toInt().toString()
            : duration.toStringAsFixed(1))
        : null;
    return PostDeeCard(
      key: const ValueKey('video-duration-guide'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            uploaderText(context, 'ความยาวคลิปที่แต่ละช่องทางรับได้',
                'Video length by channel'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            measured
                ? uploaderText(
                    context,
                    'คลิปนี้ยาว $displayedSeconds วินาที · ส่งผ่าน PostDee',
                    'This clip: $displayedSeconds seconds · Via PostDee')
                : uploaderText(context, 'เงื่อนไขการส่งผ่าน PostDee',
                    'Limits when sending through PostDee'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          for (var index = 0; index < _platforms.length; index++) ...[
            if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
            _buildRow(context, _platforms[index]),
          ],
          Divider(height: 1, color: AppTheme.borderSoft),
          const SizedBox(height: AppTheme.spaceMd),
          Text(
            uploaderText(
                context,
                'ร่าง TikTok ต้องไปโพสต์ต่อในแอปตามสิทธิ์บัญชี · Shorts ต้องเป็นแนวตั้งหรือสี่เหลี่ยม',
                'Finish publishing TikTok drafts in TikTok, subject to account limits. Shorts must be vertical or square.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
