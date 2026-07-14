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
import 'analytics_error_message.dart';

typedef AnalyticsLoader = Future<AnalyticsSummaryResult> Function();
typedef AnalyticsRangeLoader = Future<AnalyticsSummaryResult> Function(
  String range,
);
typedef AnalyticsSubscriptionLoader = Future<SubscriptionStatusResult>
    Function();

enum AnalyticsRangeOption {
  today('today', 'วันนี้'),
  sevenDays('7d', '7 วัน'),
  thirtyDays('30d', '30 วัน'),
  ninetyDays('90d', '90 วัน'),
  year('year', 'ปีนี้');

  const AnalyticsRangeOption(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    this.showTitle = true,
    this.loadAnalytics,
    this.loadAnalyticsForRange,
    this.loadSubscription,
  });

  final bool showTitle;
  final AnalyticsLoader? loadAnalytics;
  final AnalyticsRangeLoader? loadAnalyticsForRange;
  final AnalyticsSubscriptionLoader? loadSubscription;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _apiClient = PostDeeApiClient();
  bool _isLoading = false;
  AnalyticsSummaryResult? _summary;
  String? _errorMessage;
  bool _isProLocked = false;
  AnalyticsRangeOption _selectedRange = AnalyticsRangeOption.thirtyDays;

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
      _isProLocked = false;
    });

    try {
      final shouldPreflightSubscription = widget.loadSubscription != null ||
          (widget.loadAnalytics == null &&
              widget.loadAnalyticsForRange == null);
      if (shouldPreflightSubscription) {
        final subscription = widget.loadSubscription != null
            ? await widget.loadSubscription!()
            : await _apiClient.loadCurrentSubscription();
        if (!subscription.canUseAnalytics) {
          if (!mounted) return;
          setState(() {
            _summary = null;
            _isProLocked = true;
          });
          return;
        }
      }

      final summary = widget.loadAnalyticsForRange != null
          ? await widget.loadAnalyticsForRange!(_selectedRange.apiValue)
          : widget.loadAnalytics != null
              ? await widget.loadAnalytics!()
              : await _apiClient.loadAnalyticsSummary(
                  range: _selectedRange.apiValue,
                );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isProLocked = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isProLocked = isAnalyticsPlanRequired(error);
        _errorMessage = _isProLocked ? null : analyticsErrorMessage(error);
      });
    } on SocketException {
      if (!mounted) return;
      setState(() => _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้');
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _errorMessage = 'เกิดข้อผิดพลาดระหว่างโหลดข้อมูลวิเคราะห์');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectRange(AnalyticsRangeOption range) async {
    if (_selectedRange == range || _isLoading) return;
    setState(() => _selectedRange = range);
    await _loadAnalytics();
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
              _rangeLabel(_selectedRange, DateTime.now()),
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 13),
          ],
          SizedBox(
            height: 38,
            child: ListView.separated(
              key: const ValueKey('analytics-range-filters'),
              scrollDirection: Axis.horizontal,
              itemCount: AnalyticsRangeOption.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final range = AnalyticsRangeOption.values[index];
                return _RangeChip(
                  key: ValueKey('analytics-range-${range.apiValue}'),
                  range: range,
                  selected: range == _selectedRange,
                  onTap: () => _selectRange(range),
                );
              },
            ),
          ),
          const SizedBox(height: 13),
          if (_isLoading)
            _AnalyticsSkeleton()
          else if (!_hasAnalyticsData)
            PostDeeNotice(
              message: _isProLocked
                  ? 'ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro'
                  : 'ยังไม่มีข้อมูลวิเคราะห์ กลับมาดูหลังคลิปเริ่มมียอด',
              color: AppTheme.accentCyanInk,
              icon: _isProLocked ? Icons.lock_outline : Icons.hourglass_empty,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'ยอดวิวรวม',
                    value: _fmtNumber(views),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: _StatCard(
                    label: 'เอนเกจเมนต์',
                    value: views == 0
                        ? '0%'
                        : '${(likes * 100 / views).toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            if ((_summary?.daily ?? const []).isNotEmpty) ...[
              _DailyViewsChart(
                metrics: _summary!.daily,
                rangeLabel: _selectedRange.label,
              ),
              const SizedBox(height: 13),
            ],
            _PlatformPerformanceCard(
              metrics: _summary?.platforms ?? const [],
            ),
          ],
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
            status: 'เร็ว ๆ นี้',
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
            ],
          ),
          const SizedBox(height: 10),
          _AiToolCard(
            id: 'ai_comment_center',
            title: 'ศูนย์คอมเมนต์ AI',
            subtitle: 'สรุปคอมเมนต์และเตรียมร่างคำตอบให้ตรวจภายหลัง',
            status: 'เร็ว ๆ นี้',
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
            ],
          ),
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
  final String value;

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
            value,
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

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.range,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AnalyticsRangeOption range;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.glass,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: AppTheme.border),
        ),
        child: Text(
          range.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DailyViewsChart extends StatelessWidget {
  const _DailyViewsChart({
    required this.metrics,
    required this.rangeLabel,
  });

  final List<DailyAnalyticsResult> metrics;
  final String rangeLabel;

  List<DailyAnalyticsResult> get _points {
    if (metrics.length <= 7) return metrics;

    final bucketSize = (metrics.length / 7).ceil();
    final buckets = <DailyAnalyticsResult>[];
    for (var start = 0; start < metrics.length; start += bucketSize) {
      final end = (start + bucketSize).clamp(0, metrics.length).toInt();
      final slice = metrics.sublist(start, end);
      buckets.add(
        DailyAnalyticsResult(
          date: slice.last.date,
          views: slice.fold(0, (sum, metric) => sum + metric.views),
          likes: slice.fold(0, (sum, metric) => sum + metric.likes),
        ),
      );
    }
    return buckets.take(7).toList();
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final maxViews = points.fold<int>(1, (max, point) {
      return point.views > max ? point.views : max;
    });

    return Container(
      key: const ValueKey('analytics-daily-chart'),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'ยอดวิวรายวัน',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                rangeLabel,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < points.length; index += 1) ...[
                  if (index > 0) const SizedBox(width: 7),
                  Expanded(
                    child: _DailyBar(
                      metric: points[index],
                      maxViews: maxViews,
                      highlighted: index == points.length - 1,
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
}

class _DailyBar extends StatelessWidget {
  const _DailyBar({
    required this.metric,
    required this.maxViews,
    required this.highlighted,
  });

  final DailyAnalyticsResult metric;
  final int maxViews;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final factor = (metric.views / maxViews).clamp(0.08, 1.0).toDouble();
    final barHeight = 88 * factor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          _fmtCompact(metric.views),
          maxLines: 1,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: highlighted ? AppTheme.accentCyanInk : AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: barHeight,
          decoration: BoxDecoration(
            color: highlighted
                ? AppTheme.accent
                : AppTheme.accent.withValues(alpha: 0.28),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(7),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${metric.date.day}',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ],
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
    final maxViews = sorted.fold<int>(1, (c, m) => m.views > c ? m.views : c);

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
            prototypeOnly: true,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PostDeeSoftPill(label: status, color: color),
                      ],
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

String _fmtCompact(int n) => _fmtNumber(n).replaceAll('.0', '');

String _rangeLabel(AnalyticsRangeOption range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = switch (range) {
    AnalyticsRangeOption.today => today,
    AnalyticsRangeOption.sevenDays => today.subtract(const Duration(days: 6)),
    AnalyticsRangeOption.thirtyDays => today.subtract(const Duration(days: 29)),
    AnalyticsRangeOption.ninetyDays => today.subtract(const Duration(days: 89)),
    AnalyticsRangeOption.year => DateTime(today.year),
  };
  const months = [
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

  if (range == AnalyticsRangeOption.today) {
    return '${today.day} ${months[today.month - 1]} ${today.year}';
  }
  return '${start.day} ${months[start.month - 1]} – '
      '${today.day} ${months[today.month - 1]} ${today.year}';
}
