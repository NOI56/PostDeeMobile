import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import 'cover_editor_screen.dart';
import 'cover_image_processor.dart';
import 'platform_publish_settings.dart';

String? publishReviewOutcomeFor(
  SocialPlatform platform, {
  required PlatformPublishSettings settings,
  DateTime? scheduledAt,
}) {
  switch (platform) {
    case SocialPlatform.tiktok:
      return switch (settings.tiktokPublishMode) {
        TikTokPublishMode.inboxDraft =>
          '${_providerDraftTimingLabel(scheduledAt, destination: 'TikTok')} · ส่งออกจริงและใช้โควตาโพสต์',
        TikTokPublishMode.directPost => 'ยังไม่พร้อมโพสต์ตรง',
      };
    case SocialPlatform.youtubeShorts:
      if (!settings.canSubmit(platform)) return 'ตั้งค่า YouTube ยังไม่ครบ';
      return switch (settings.youtubeVisibility) {
        YouTubeVisibility.private => 'ส่วนตัว (Private)',
        YouTubeVisibility.unlisted => 'ไม่เป็นสาธารณะ (Unlisted)',
        YouTubeVisibility.public => 'สาธารณะ (Public)',
      };
    case SocialPlatform.instagramReels:
      return 'เผยแพร่ตามบัญชี';
    case SocialPlatform.facebookReels:
      return switch (settings.facebookPublishMode) {
        FacebookPublishMode.publish => 'เผยแพร่บนเพจ',
        FacebookPublishMode.pageDraft =>
          '${scheduledAt == null ? 'เก็บเป็นร่างบนเพจ' : _providerDraftTimingLabel(scheduledAt, destination: 'Facebook Page')} · ส่งออกจริงและใช้โควตาโพสต์',
        null => 'ตั้งค่า Facebook ยังไม่ครบ',
      };
    case SocialPlatform.shopeeVideo:
    case SocialPlatform.lazadaVideo:
      return null;
  }
}

String publishReviewPlatformLabel(SocialPlatform platform) =>
    platform == SocialPlatform.facebookReels
        ? 'Facebook Page Video'
        : platform.label;

/// Pre-publish review (design screen #7): the user checks the clip, caption,
/// channels, and schedule/watermark summary, then confirms. Pops `true` on
/// confirm so the uploader runs the real post flow.
class PublishReviewScreen extends StatelessWidget {
  const PublishReviewScreen({
    super.key,
    required this.videoName,
    required this.caption,
    required this.platforms,
    required this.scheduledAt,
    required this.watermarkEnabled,
    this.platformSettings = const PlatformPublishSettings(),
    this.connectionDisplayNames = const {},
    this.coverResult,
  });

  final String videoName;
  final String caption;
  final List<SocialPlatform> platforms;
  final DateTime? scheduledAt;
  final bool watermarkEnabled;
  final PlatformPublishSettings platformSettings;
  final Map<SocialPlatform, String> connectionDisplayNames;
  final CoverEditorResult? coverResult;

  bool get _isScheduled => scheduledAt != null;

  String get _scheduleLabel {
    final at = scheduledAt;
    if (at == null) {
      return 'โพสต์ทันที';
    }
    final local = at.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${_thaiMonthsShort[local.month - 1]} ${local.year} · $hour:$minute น.';
  }

  @override
  Widget build(BuildContext context) {
    final trimmedCaption = caption.trim();
    final coverBytes = coverResult?.imageBytes;
    final hasCoverBytes = coverBytes?.isNotEmpty == true;
    final coverFile =
        coverResult == null ? null : File(coverResult!.localImagePath);
    final hasCover = hasCoverBytes || coverFile?.existsSync() == true;
    final hasMissingConnectionIdentity = platforms.any(
      (platform) => connectionDisplayNames[platform]?.trim().isNotEmpty != true,
    );
    final hasUnknownOutcome = platforms.isEmpty ||
        hasMissingConnectionIdentity ||
        platforms.any(
          (platform) =>
              !platformSettings.canSubmit(platform) ||
              publishReviewOutcomeFor(
                    platform,
                    settings: platformSettings,
                    scheduledAt: scheduledAt,
                  ) ==
                  null,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ตรวจทานก่อนโพสต์',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 88,
                    height: 120,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE7EFE9), Color(0xFFD6E3DA)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (hasCover)
                          Positioned.fill(
                            child: hasCoverBytes
                                ? Image.memory(
                                    coverBytes!,
                                    key: const ValueKey(
                                      'publish-review-cover-image',
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    coverFile!,
                                    key: const ValueKey(
                                      'publish-review-cover-image',
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                          )
                        else
                          const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 30,
                              color: Color(0xFF8FA197),
                            ),
                          ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: Text(
                                '9:16',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'แคปชั่น',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          trimmedCaption.isEmpty
                              ? '(ไม่มีแคปชั่น)'
                              : trimmedCaption,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: trimmedCaption.isEmpty
                                ? AppTheme.textMuted
                                : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          videoName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (coverResult != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.photo_outlined,
                      size: 18,
                      color: AppTheme.accentCyanInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'หน้าปกเลือกจากวินาทีที่ '
                        '${(coverResult!.coverFrameTimeMs / 1000).toStringAsFixed(1)}',
                        key: const ValueKey('publish-review-cover-time'),
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CoverPlatformCapabilityNotice(
                  platforms: platforms,
                  compact: true,
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'โพสต์ไปยัง ${platforms.length} ช่องทาง',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              for (final platform in platforms)
                _PlatformOutcomeRow(
                  platform: platform,
                  settings: platformSettings,
                  scheduledAt: scheduledAt,
                  connectionDisplayName: connectionDisplayNames[platform],
                ),
              if (hasUnknownOutcome) ...[
                Container(
                  key: const ValueKey('publish-review-unknown-outcome'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasMissingConnectionIdentity
                              ? 'ยังยืนยันบัญชีหรือเพจปลายทางของบางช่องทางไม่ได้ กรุณารีเฟรชหรือเชื่อมต่อใหม่'
                              : 'ยังยืนยันรูปแบบเผยแพร่ของบางช่องทางไม่ได้ กรุณากลับไปเลือกช่องทางใหม่',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.glass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF122018).withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _SummaryRow(
                      icon: _isScheduled ? Icons.event : Icons.bolt,
                      label: 'กำหนดเวลา',
                      value: _scheduleLabel,
                      valueColor: AppTheme.textPrimary,
                    ),
                    Divider(height: 1, color: AppTheme.borderSoft),
                    _SummaryRow(
                      icon: Icons.branding_watermark_outlined,
                      label: 'ลายน้ำร้าน',
                      value: watermarkEnabled
                          ? 'เปิด'
                          : platforms.contains(SocialPlatform.tiktok)
                              ? 'ปิด · TikTok ไม่รับลายน้ำ PostDee'
                              : 'ปิด',
                      valueColor: watermarkEnabled
                          ? AppTheme.accentCyanInk
                          : AppTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const ValueKey('publish-review-confirm'),
                onPressed: hasUnknownOutcome
                    ? null
                    : () => Navigator.of(context).pop(true),
                icon:
                    Icon(_isScheduled ? Icons.schedule : Icons.bolt, size: 21),
                label: Text(
                  _isScheduled ? 'ยืนยันตั้งเวลาโพสต์' : 'ยืนยันโพสต์เลย',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformOutcomeRow extends StatelessWidget {
  const _PlatformOutcomeRow({
    required this.platform,
    required this.settings,
    required this.scheduledAt,
    this.connectionDisplayName,
  });

  final SocialPlatform platform;
  final PlatformPublishSettings settings;
  final DateTime? scheduledAt;
  final String? connectionDisplayName;

  @override
  Widget build(BuildContext context) {
    final outcome = publishReviewOutcomeFor(
      platform,
      settings: settings,
      scheduledAt: scheduledAt,
    );
    final hasConnectionIdentity =
        connectionDisplayName?.trim().isNotEmpty == true;
    final isKnown = outcome != null &&
        settings.canSubmit(platform) &&
        hasConnectionIdentity;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          SocialPlatformLogo(platform: platform, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  publishReviewPlatformLabel(platform),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (hasConnectionIdentity) ...[
                  const SizedBox(height: 1),
                  Text(
                    connectionDisplayName!.trim(),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 1),
                  Text(
                    'ยังยืนยันบัญชีปลายทางไม่ได้',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  outcome ?? 'ยังไม่ทราบรูปแบบเผยแพร่',
                  key: ValueKey(
                    'publish-review-outcome-${platform.apiValue}',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isKnown
                        ? AppTheme.textSecondary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isKnown ? Icons.check_circle : Icons.error_outline,
            size: 20,
            color: isKnown
                ? AppTheme.accentCyanInk
                : Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }
}

String _providerDraftTimingLabel(
  DateTime? scheduledAt, {
  required String destination,
}) {
  if (scheduledAt == null) return 'ส่งเป็นร่างเข้า $destination';
  final local = scheduledAt.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'ส่งเข้าร่างเวลา ${local.day} '
      '${_thaiMonthsShort[local.month - 1]} $hour:$minute น. · $destination';
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.accentCyanInk),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

const _thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];
