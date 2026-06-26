import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
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

  int get _baseViews => _summary?.totalViews ?? 0;

  int get _baseLikes => _summary?.totalLikes ?? 0;

  List<PlatformAnalyticsResult> get _basePlatforms =>
      _summary?.platforms ?? const [];

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

  SocialPlatform? _socialPlatformFor(String platform) {
    for (final p in SocialPlatform.values) {
      if (p.apiValue == platform) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final views = _baseViews;
    final likes = _baseLikes;

    return ListView(
      key: const ValueKey('analytics-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (widget.showTitle) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'วิเคราะห์',
                  style: textTheme.headlineSmall?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
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
          const SizedBox(height: AppTheme.spaceMd),
        ],
        Row(
          children: [
            Expanded(
              child: Text('ภาพรวม',
                  style:
                      textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: _isLoading ? null : _loadAnalytics,
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'โหลดข้อมูลวิเคราะห์',
            ),
          ],
        ),
        Text(
          'ยอดรวมจากโพสต์ที่ซิงก์แล้วทั้งหมด',
          style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 10),
        if (_isLoading)
          const _AnalyticsSkeleton()
        else if (!_hasAnalyticsData)
          PostDeeNotice(
            message: 'ยังไม่มีข้อมูลวิเคราะห์ กลับมาดูหลังคลิปเริ่มมียอด',
            color: AppTheme.accentCyanInk,
            icon: Icons.hourglass_empty,
          )
        else ...[
          _KpiGrid(
            cards: [
              _KpiData('ยอดวิว', views, AppTheme.accent),
              _KpiData('ไลก์', likes, AppTheme.accentCyan),
            ],
          ),
          const SizedBox(height: AppTheme.spaceLg),
          PostDeeCard(
            child: _PlatformComparisonPanel(
              metrics: _basePlatforms,
              platformFor: _socialPlatformFor,
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spaceLg),
        const _AnalyticsGrowthToolsPanel(),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          PostDeeNotice(
            message: _errorMessage!,
            color: Theme.of(context).colorScheme.error,
            icon: Icons.error_outline,
          ),
        ],
      ],
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards});

  final List<_KpiData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((card) =>
                  SizedBox(width: cardWidth, child: _KpiCard(data: card)))
              .toList(),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      glowColor: data.color,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Text(
              _fmtNumber(data.value),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              'จากข้อมูลจริงที่ซิงก์แล้ว',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformComparisonPanel extends StatelessWidget {
  const _PlatformComparisonPanel({
    required this.metrics,
    required this.platformFor,
  });

  final List<PlatformAnalyticsResult> metrics;
  final SocialPlatform? Function(String platform) platformFor;

  @override
  Widget build(BuildContext context) {
    final maxViews =
        metrics.fold<int>(1, (c, m) => m.views > c ? m.views : c);
    final topViews = metrics.fold<int>(0, (c, m) => m.views > c ? m.views : c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('เปรียบเทียบแพลตฟอร์ม',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        for (final m in metrics)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PlatformBar(
              metric: m,
              platform: platformFor(m.platform),
              maxViews: maxViews,
              isTop: m.views > 0 && m.views == topViews,
            ),
          ),
      ],
    );
  }
}

class _PlatformBar extends StatelessWidget {
  const _PlatformBar({
    required this.metric,
    required this.platform,
    required this.maxViews,
    required this.isTop,
  });

  final PlatformAnalyticsResult metric;
  final SocialPlatform? platform;
  final int maxViews;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final color = platform?.color ?? const Color(0xFF6B7280);
    final factor = (metric.views / maxViews).clamp(0.04, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (platform != null) ...[
              SocialPlatformLogo(platform: platform!, size: 20),
              const SizedBox(width: AppTheme.spaceSm),
            ],
            Expanded(child: Text(metric.label)),
            if (isTop) ...[
              const PostDeeSoftPill(label: 'เด่นสุด', color: AppTheme.success),
              const SizedBox(width: AppTheme.spaceSm),
            ],
            Text('${metric.views}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.pitchBlack.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          child: SizedBox(
            height: 10,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: factor,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                  gradient:
                      LinearGradient(colors: [color, AppTheme.accentPink]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text('${metric.likes} ไลก์',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _AnalyticsGrowthToolsPanel extends StatelessWidget {
  const _AnalyticsGrowthToolsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PostDeeSectionHeader(
          title: 'เครื่องมือวิเคราะห์เพิ่ม',
          trailing: PostDeeSoftPill(
            label: 'เฟส 2',
            icon: Icons.insights,
            color: AppTheme.accentCyanInk,
          ),
        ),
        SizedBox(height: AppTheme.spaceSm),
        _AnalyticsGrowthToolCard(
          id: 'hashtag_radar',
          title: 'เรดาร์แฮชแท็กฮิต',
          description:
              'ดูแฮชแท็กและคีย์เวิร์ดที่กำลังขึ้น เพื่อนำไปใช้กับคลิปถัดไป',
          status: 'SEO',
          icon: Icons.trending_up,
          color: AppTheme.accentPinkInk,
          settings: [
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
        SizedBox(height: AppTheme.spaceSm),
        _AnalyticsGrowthToolCard(
          id: 'ai_comment_center',
          title: 'ศูนย์คอมเมนต์ AI',
          description: 'สรุปอารมณ์คอมเมนต์และร่างคำตอบให้เจ้าของร้านตรวจ',
          status: 'ต้องอนุมัติ',
          icon: Icons.forum_outlined,
          color: AppTheme.accent,
          settings: [
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
        SizedBox(height: AppTheme.spaceSm),
        _CommentApprovalNotice(),
      ],
    );
  }
}

class _AnalyticsGrowthToolCard extends StatelessWidget {
  const _AnalyticsGrowthToolCard({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.icon,
    required this.color,
    required this.settings,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final IconData icon;
  final Color color;
  final List<GrowthToolSettingOption> settings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: () => showGrowthToolDetailSheet(
          context,
          GrowthToolDetail(
            id: id,
            title: title,
            description: description,
            status: status,
            icon: icon,
            color: color,
            settings: settings,
          ),
        ),
        child: PostDeeCard(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          glowColor: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                      color: color.withValues(alpha: 0.14),
                      border: Border.all(color: color.withValues(alpha: 0.32)),
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(icon, color: color, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  PostDeeSoftPill(label: status, color: color),
                ],
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    return PostDeeCard(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      glowColor: AppTheme.accentPink,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentPink.withValues(alpha: 0.16),
            ),
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spaceSm),
              child: Icon(Icons.verified_user_outlined,
                  color: AppTheme.accentPinkInk, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'คอมเมนต์และคำตอบต้องให้เจ้าของร้านอนุมัติก่อนเผยแพร่',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
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
            Expanded(child: _SkeletonKpiCard()),
            SizedBox(width: AppTheme.spaceMd),
            Expanded(child: _SkeletonKpiCard()),
          ],
        ),
        const SizedBox(height: AppTheme.spaceLg),
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

class _SkeletonKpiCard extends StatelessWidget {
  const _SkeletonKpiCard();

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
