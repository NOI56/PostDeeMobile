import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../billing/paywall_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_skeleton.dart';

typedef AnalyticsLoader = Future<AnalyticsSummaryResult> Function();

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    this.showTitle = true,
    this.loadAnalytics,
  });

  final bool showTitle;
  final AnalyticsLoader? loadAnalytics;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _apiClient = PostDeeApiClient();
  bool _isLoading = false;
  AnalyticsSummaryResult? _summary;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  bool get _hasAnalyticsData =>
      (_summary?.totalViews ?? 0) > 0 ||
      (_summary?.totalLikes ?? 0) > 0 ||
      (_summary?.platforms ?? const [])
          .any((platform) => platform.views > 0 || platform.likes > 0);

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loader = widget.loadAnalytics ?? _apiClient.loadAnalyticsSummary;
      final summary = await loader();
      if (!mounted) return;
      setState(() => _summary = summary);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on SocketException {
      if (!mounted) return;
      setState(() => _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้');
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เกิดข้อผิดพลาดระหว่างโหลดข้อมูลวิเคราะห์');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = _summary?.totalViews ?? 0;
    final likes = _summary?.totalLikes ?? 0;

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      color: AppTheme.accent,
      child: ListView(
        key: const ValueKey('analytics-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, AppTheme.navOverlap),
        children: [
          if (widget.showTitle) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'วิเคราะห์',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'ยอดรวมจากโพสต์ที่ซิงก์แล้วทั้งหมด',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 13),
          ],
          if (_isLoading)
            const _AnalyticsSkeleton()
          else if (!_hasAnalyticsData)
            PostDeeNotice(
              message: 'ยังไม่มีข้อมูลวิเคราะห์ กลับมาดูหลังคลิปเริ่มมียอด',
              color: AppTheme.accentCyanInk,
              icon: Icons.hourglass_empty,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _StatCard(label: 'ยอดวิวรวม', value: views),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: _StatCard(label: 'ไลก์รวม', value: likes),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _PlatformPerformanceCard(
              metrics: _summary?.platforms ?? const [],
            ),
          ],
          const SizedBox(height: 13),
          const _ProInsightLockCard(),
          const SizedBox(height: 15),
          Text(
            'เครื่องมือวิเคราะห์ด้วย AI',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _AiToolCard(
            id: 'hashtag_radar',
            title: 'เรดาร์แฮชแท็กฮิต',
            subtitle: 'ดูแฮชแท็ก/คีย์เวิร์ดที่กำลังขึ้น เพื่อใช้กับคลิปต่อไป',
            status: 'SEO',
            icon: Icons.tag,
            color: AppTheme.accentCyanInk,
            tint: AppTheme.mint,
            settings: const [
              GrowthToolSettingOption(
                id: 'content_category',
                label: 'เลือกหมวดสินค้าหรือกลุ่มคอนเทนต์',
              ),
              GrowthToolSettingOption(
                id: 'next_clip_hashtags',
                label: 'ดูแฮชแท็กที่น่าลองใช้กับคลิปถัดไป',
              ),
              GrowthToolSettingOption(
                id: 'team_keywords',
                label: 'บันทึกชุดคีย์เวิร์ดสำหรับทีม',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AiToolCard(
            id: 'ai_comment_center',
            title: 'ศูนย์คอมเมนต์ AI',
            subtitle: 'สรุปคอมเมนต์และร่างคำตอบให้ลูกค้า รออนุมัติก่อนตอบ',
            status: 'ต้องอนุมัติ',
            icon: Icons.forum_outlined,
            color: const Color(0xFF6366F1),
            tint: const Color(0xFF6366F1).withValues(alpha: 0.13),
            settings: const [
              GrowthToolSettingOption(
                id: 'sentiment_summary',
                label: 'ดูสรุปคอมเมนต์บวก ลบ และคำถามที่พบบ่อย',
              ),
              GrowthToolSettingOption(
                id: 'reply_drafts',
                label: 'ให้ AI ร่างคำตอบไว้รอตรวจ',
              ),
              GrowthToolSettingOption(
                id: 'owner_approval',
                label: 'บังคับให้เจ้าของร้านอนุมัติก่อนเผยแพร่ทุกครั้ง',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _CommentApprovalNotice(),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceMd),
            PostDeeNotice(
              message: _errorMessage!,
              color: Theme.of(context).colorScheme.error,
              icon: Icons.error_outline,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _fmtNumber(value),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformPerformanceCard extends StatelessWidget {
  const _PlatformPerformanceCard({required this.metrics});

  final List<PlatformAnalyticsResult> metrics;

  static SocialPlatform? _platformFor(String apiValue) {
    for (final platform in SocialPlatform.values) {
      if (platform.apiValue == apiValue) return platform;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...metrics]..sort((a, b) => b.views.compareTo(a.views));
    final maxViews =
        sorted.fold<int>(1, (c, m) => m.views > c ? m.views : c);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ช่องทางที่ทำผลงานดีสุด',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < sorted.length; i += 1) ...[
            if (i > 0) const SizedBox(height: 12),
            _PlatformPerfRow(
              metric: sorted[i],
              platform: _platformFor(sorted[i].platform),
              maxViews: maxViews,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlatformPerfRow extends StatelessWidget {
  const _PlatformPerfRow({
    required this.metric,
    required this.platform,
    required this.maxViews,
  });

  final PlatformAnalyticsResult metric;
  final SocialPlatform? platform;
  final int maxViews;

  @override
  Widget build(BuildContext context) {
    final color = platform?.displayColor ?? AppTheme.textMuted;
    final factor = (metric.views / maxViews).clamp(0.04, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (platform != null) ...[
              SocialPlatformLogo(platform: platform!, size: 22),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              '${metric.views}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppTheme.borderSoft),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: factor,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${metric.likes} ไลก์',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ProInsightLockCard extends StatelessWidget {
  const _ProInsightLockCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'รายงานเชิงลึก (Pro)',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const PaywallScreen(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF122018).withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 21,
                  color: AppTheme.accentCyanInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รายงานเชิงลึก (Pro)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ยอดวิวรายชั่วโมง · จุดที่คนเลื่อนผ่าน',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiToolCard extends StatelessWidget {
  const _AiToolCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.color,
    required this.tint,
    required this.settings,
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color color;
  final Color tint;
  final List<GrowthToolSettingOption> settings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: () => showGrowthToolDetailSheet(
          context,
          GrowthToolDetail(
            id: id,
            title: title,
            description: subtitle,
            status: status,
            icon: icon,
            color: color,
            settings: settings,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentApprovalNotice extends StatelessWidget {
  const _CommentApprovalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.glassDeep,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 20,
            color: AppTheme.accentCyanInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'คอมเมนต์และคำตอบต้องให้เจ้าของร้านอนุมัติก่อนเผยแพร่',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(child: _SkeletonStatCard()),
            SizedBox(width: 11),
            Expanded(child: _SkeletonStatCard()),
          ],
        ),
        const SizedBox(height: 13),
        PostDeeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              PostDeeSkeleton(width: 140, height: 14),
              SizedBox(height: AppTheme.spaceMd),
              PostDeeSkeleton(width: double.infinity, height: 12),
              SizedBox(height: AppTheme.spaceSm),
              PostDeeSkeleton(width: double.infinity, height: 12),
              SizedBox(height: AppTheme.spaceSm),
              PostDeeSkeleton(width: 220, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonStatCard extends StatelessWidget {
  const _SkeletonStatCard();

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          PostDeeSkeleton(width: 56, height: 11),
          SizedBox(height: AppTheme.spaceSm),
          PostDeeSkeleton(width: 90, height: 24, radius: 10),
        ],
      ),
    );
  }
}

String _fmtNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}
