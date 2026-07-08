import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';

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
  });

  final String videoName;
  final String caption;
  final List<SocialPlatform> platforms;
  final DateTime? scheduledAt;
  final bool watermarkEnabled;

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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
                        child: Text(
                          platform.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppTheme.accentCyanInk,
                      ),
                    ],
                  ),
                ),
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
                      value: watermarkEnabled ? 'เปิด' : 'ปิด',
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
                onPressed: () => Navigator.of(context).pop(true),
                icon: Icon(_isScheduled ? Icons.schedule : Icons.bolt,
                    size: 21),
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
