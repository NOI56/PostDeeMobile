import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../analytics/analytics_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';

/// Post detail (design screen #12). Shows the caption, channels, and honest
/// status-driven actions: scheduled posts can be published now (reschedule to
/// the current time) or cancelled; published posts link to analytics.
/// Per-post stat tiles from the design are omitted until the API exposes them.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post, this.apiClient});

  final PostSummaryResult post;
  final PostDeeApiClient? apiClient;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();
  bool _isWorking = false;

  bool get _isScheduled =>
      widget.post.status.toUpperCase() == 'QUEUED' &&
      widget.post.scheduledAt != null;

  bool get _isPublished => widget.post.status.toUpperCase() == 'PUBLISHED';

  bool get _hasPublishedChannel =>
      _isPublished ||
      widget.post.platformResults.any(
        (result) => result.status.toUpperCase() == 'PUBLISHED',
      );

  ({String label, IconData icon, Color bg, Color ink}) get _statusMeta {
    return switch (widget.post.status.toUpperCase()) {
      'PUBLISHED' => (
          label: 'เผยแพร่แล้ว',
          icon: Icons.check_circle,
          bg: const Color(0xFFE2F3EA),
          ink: const Color(0xFF0E9F6E),
        ),
      'QUEUED' when widget.post.scheduledAt != null => (
          label: 'ตั้งเวลาไว้',
          icon: Icons.schedule,
          bg: const Color(0xFFFBEFD7),
          ink: const Color(0xFFB5740B),
        ),
      'PUBLISHING' => (
          label: 'กำลังโพสต์',
          icon: Icons.sync,
          bg: const Color(0xFFE2F3EA),
          ink: const Color(0xFF0E9F6E),
        ),
      'PARTIAL_PUBLISHED' => (
          label: 'สำเร็จบางช่องทาง',
          icon: Icons.info_outline,
          bg: const Color(0xFFFBEFD7),
          ink: const Color(0xFFB5740B),
        ),
      'FAILED' => (
          label: 'โพสต์ไม่สำเร็จ',
          icon: Icons.error_outline,
          bg: const Color(0xFFFDE4E4),
          ink: const Color(0xFFDC2626),
        ),
      _ => (
          label: 'อยู่ในคิว',
          icon: Icons.hourglass_top,
          bg: const Color(0xFFEEF2EF),
          ink: const Color(0xFF778276),
        ),
    };
  }

  String get _dateLabel {
    final post = widget.post;
    if (_isPublished && post.publishedAt != null) {
      return 'เผยแพร่ ${_formatThaiDateTime(post.publishedAt!)}';
    }
    if (post.status.toUpperCase() == 'PARTIAL_PUBLISHED' &&
        post.publishedAt != null) {
      return 'เผยแพร่บางช่องทาง ${_formatThaiDateTime(post.publishedAt!)}';
    }
    if (post.scheduledAt != null) {
      return 'ตั้งเวลา ${_formatThaiDateTime(post.scheduledAt!)}';
    }
    return 'สร้างเมื่อ ${_formatThaiDateTime(post.createdAt)}';
  }

  List<SocialPlatform> get _platforms => widget.post.platforms
      .map(_platformFor)
      .whereType<SocialPlatform>()
      .toList();

  PostPlatformResult? _resultFor(SocialPlatform platform) {
    for (final result in widget.post.platformResults) {
      if (result.platform == platform.apiValue) return result;
    }
    return null;
  }

  String _platformStatLine(SocialPlatform platform) {
    final resultStatus = _resultFor(platform)?.status.toUpperCase();
    if (resultStatus == 'PUBLISHED') return 'เผยแพร่สำเร็จ';
    if (resultStatus == 'FAILED') return 'โพสต์ไม่สำเร็จ';
    if (resultStatus == 'PUBLISHING') return 'กำลังโพสต์';
    if (resultStatus == 'PENDING') return 'รอส่งไปยังช่องทาง';
    if (_isPublished) return 'เผยแพร่แล้ว';
    if (_isScheduled) return 'รอเผยแพร่ตามเวลา';
    if (widget.post.status.toUpperCase() == 'FAILED') return 'โพสต์ไม่สำเร็จ';
    return 'ยังไม่เผยแพร่';
  }

  Color _platformStatusColor(SocialPlatform platform) {
    return switch (_resultFor(platform)?.status.toUpperCase()) {
      'PUBLISHED' => const Color(0xFF0E9F6E),
      'FAILED' => const Color(0xFFDC2626),
      _ => AppTheme.textMuted,
    };
  }

  String _localizedPlatformError(String message) {
    return switch (message) {
      'Publishing to this platform failed. Please try again later.' =>
        'โพสต์ไปยังช่องทางนี้ไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
      'Publishing result could not be confirmed. Check the platform before trying again.' =>
        'ยังยืนยันผลการโพสต์ไม่ได้ กรุณาตรวจสอบช่องทางนี้ก่อนลองใหม่ เพื่อป้องกันโพสต์ซ้ำ',
      _ => message,
    };
  }

  bool _isWebLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> _openPostLink(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !_isWebLink(value)) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดลิงก์โพสต์ไม่สำเร็จ')),
      );
    }
  }

  Widget _buildPlatformCard(SocialPlatform platform) {
    final result = _resultFor(platform);
    final errorMessage = result?.errorMessage?.trim();
    final externalReference = result?.externalPostId?.trim();
    final hasError = errorMessage != null && errorMessage.isNotEmpty;
    final hasReference =
        externalReference != null && externalReference.isNotEmpty;
    final referenceIsLink = externalReference != null &&
        externalReference.isNotEmpty &&
        _isWebLink(externalReference);

    return Container(
      padding: const EdgeInsets.all(12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialPlatformLogo(platform: platform, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _platformStatLine(platform),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        result == null ? FontWeight.w400 : FontWeight.w600,
                    color: _platformStatusColor(platform),
                  ),
                ),
                if (hasError) ...[
                  const SizedBox(height: 4),
                  Text(
                    'สาเหตุ: ${_localizedPlatformError(errorMessage)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
                if (hasReference) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: referenceIsLink
                        ? () => _openPostLink(externalReference)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        referenceIsLink
                            ? 'ลิงก์โพสต์: $externalReference'
                            : 'รหัสโพสต์: $externalReference',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: referenceIsLink
                              ? AppTheme.accent
                              : AppTheme.textMuted,
                          decoration: referenceIsLink
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publishNow() async {
    final confirmed = await _confirm(
      title: 'โพสต์เลยตอนนี้?',
      body: 'โพสต์นี้จะถูกส่งไปทุกช่องทางที่เลือกทันที',
      confirmLabel: 'โพสต์เลย',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await _apiClient.reschedulePost(widget.post.id, DateTime.now());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โพสต์เลยไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    }
  }

  Future<void> _cancelPost() async {
    final confirmed = await _confirm(
      title: 'ยกเลิกโพสต์นี้?',
      body: 'โพสต์ที่ตั้งเวลาไว้จะถูกนำออกจากคิว',
      confirmLabel: 'ยกเลิกโพสต์',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await _apiClient.cancelPost(widget.post.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยกเลิกโพสต์ไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ไม่'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _openAnalytics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'วิเคราะห์',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          body: DecoratedBox(
            decoration: AppTheme.screenBackground,
            child: const SafeArea(
              child: AnalyticsScreen(showTitle: false),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusMeta;
    final caption = widget.post.caption.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'รายละเอียดโพสต์',
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
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: status.bg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, size: 16, color: status.ink),
                          const SizedBox(width: 5),
                          Text(
                            status.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: status.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 104,
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE7EFE9), Color(0xFFD6E3DA)],
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 34,
                      color: Color(0xFF8FA197),
                    ),
                  ),
                  const SizedBox(width: 14),
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
                          caption.isEmpty ? '(ไม่มีแคปชั่น)' : caption,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.55,
                            color: caption.isEmpty
                                ? AppTheme.textMuted
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'ช่องทางที่โพสต์',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              for (final platform in _platforms) ...[
                _buildPlatformCard(platform),
              ],
              if (_platforms.isEmpty)
                Text(
                  'ไม่พบข้อมูลช่องทาง',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  Widget? _buildActionBar(BuildContext context) {
    if (!_isScheduled && !_hasPublishedChannel) {
      return null;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        border: Border(top: BorderSide(color: AppTheme.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              if (_isScheduled) ...[
                Semantics(
                  button: true,
                  label: 'ยกเลิกโพสต์',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isWorking ? null : _cancelPost,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.glass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 21,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PrimaryActionButton(
                    key: const ValueKey('post-detail-publish-now'),
                    label: _isWorking ? 'กำลังส่ง...' : 'โพสต์เลย',
                    icon: Icons.bolt,
                    onPressed: _isWorking ? null : _publishNow,
                  ),
                ),
              ] else if (_hasPublishedChannel)
                Expanded(
                  child: _PrimaryActionButton(
                    key: const ValueKey('post-detail-open-analytics'),
                    label: 'ดูสถิติ',
                    icon: Icons.bar_chart_rounded,
                    onPressed: _openAnalytics,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

SocialPlatform? _platformFor(String apiValue) {
  for (final platform in SocialPlatform.values) {
    if (platform.apiValue == apiValue) {
      return platform;
    }
  }
  return null;
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

String _formatThaiDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_thaiMonthsShort[local.month - 1]} ${local.year} · $hour:$minute น.';
}
