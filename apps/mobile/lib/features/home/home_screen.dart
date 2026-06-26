import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../billing/paywall_screen.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_skeleton.dart';

typedef HomeAnalyticsLoader = Future<AnalyticsSummaryResult> Function();
typedef HomeSubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef HomeRecentPostsLoader = Future<List<PostSummaryResult>> Function();

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.loadAnalytics,
    this.loadSubscription,
    this.loadRecentPosts,
    this.onViewAllPosts,
    this.userName,
  });

  final HomeAnalyticsLoader? loadAnalytics;
  final HomeSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final VoidCallback? onViewAllPosts;

  /// Real signed-in display name, appended to the greeting. When null/empty the
  /// greeting shows without a name (no hardcoded demo name).
  final String? userName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiClient = PostDeeApiClient();
  AnalyticsSummaryResult? _analytics;
  SubscriptionStatusResult? _subscription;
  List<PostSummaryResult> _recentPosts = const [];
  bool _isLoadingAnalytics = false;
  bool _isLoadingSubscription = true;
  bool _isLoadingPosts = true;
  String? _analyticsErrorMessage;
  String? _subscriptionErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
    _loadAnalytics();
    _loadRecentPosts();
  }

  Future<void> _loadRecentPosts() async {
    setState(() => _isLoadingPosts = true);

    try {
      final loader = widget.loadRecentPosts ?? _apiClient.listRecentPosts;
      final posts = await loader();

      if (!mounted) {
        return;
      }

      setState(() => _recentPosts = posts);
    } catch (_) {
      // Non-fatal: the latest-post card falls back to the empty state.
      if (!mounted) {
        return;
      }

      setState(() => _recentPosts = const []);
    } finally {
      if (mounted) {
        setState(() => _isLoadingPosts = false);
      }
    }
  }

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoadingSubscription = true;
      _subscriptionErrorMessage = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _subscription = subscription;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _subscriptionErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _subscriptionErrorMessage = l10n.homeApiConnectionError;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _subscriptionErrorMessage = l10n.homeAnalyticsLoadError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSubscription = false;
        });
      }
    }
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoadingAnalytics = true;
      _analyticsErrorMessage = null;
    });

    try {
      final loader = widget.loadAnalytics ?? _apiClient.loadAnalyticsSummary;
      final analytics = await loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _analytics = analytics;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _analyticsErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _analyticsErrorMessage = l10n.homeApiConnectionError;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _analyticsErrorMessage = l10n.homeAnalyticsLoadError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAnalytics = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final totalViews = _analytics?.totalViews ?? 0;
    final totalLikes = _analytics?.totalLikes ?? 0;
    final name = widget.userName?.trim();
    final greeting = (name != null && name.isNotEmpty)
        ? '${l10n.homeGreeting}, $name'
        : l10n.homeGreeting;

    return ListView(
      padding: AppTheme.screenPadding,
      children: [
        Text(
          greeting,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          l10n.homeOverviewSubtitle,
          style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Row(
          children: [
            Expanded(
              child: _PlanSummaryCard(
                subscription: _subscription,
                isLoading: _isLoadingSubscription,
                errorMessage: _subscriptionErrorMessage,
              ),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: _TotalPostsCard(
                totalViews: totalViews,
                totalLikes: totalLikes,
                isLoading: _isLoadingAnalytics,
                errorMessage: _analyticsErrorMessage,
                onRefresh: _isLoadingAnalytics ? null : _loadAnalytics,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.homeLatestPostStatus,
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: widget.onViewAllPosts,
              child: Text(
                l10n.homeViewAll,
                style: textTheme.labelLarge?.copyWith(
                  color: AppTheme.accentCyanInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        _LatestPostList(
          posts: _recentPosts,
          isLoading: _isLoadingPosts,
        ),
        const SizedBox(height: AppTheme.spaceXl),
        const _GrowthToolsPreview(),
        const SizedBox(height: AppTheme.spaceSm),
      ],
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.subscription,
    required this.isLoading,
    required this.errorMessage,
  });

  final SubscriptionStatusResult? subscription;
  final bool isLoading;
  final String? errorMessage;

  String _planTitle(PostDeeLocalizations l10n) {
    final isThai = l10n.locale.languageCode == 'th';
    final current = subscription;

    if (isLoading) {
      return isThai ? 'กำลังโหลดแพ็กเกจ' : 'Loading plan';
    }

    if (current == null) {
      return isThai ? 'ยังไม่มีข้อมูลแพ็กเกจ' : 'Plan status unavailable';
    }

    return switch (current.plan.toUpperCase()) {
      'PRO' => isThai ? 'แพ็กเกจ Pro' : 'Pro plan',
      'STARTER' => isThai ? 'แพ็กเกจ Starter' : 'Starter plan',
      'BASIC' || 'FREE' => isThai ? 'แพ็กเกจฟรี' : 'Free plan',
      _ => current.plan,
    };
  }

  String _planSubtitle(PostDeeLocalizations l10n) {
    final isThai = l10n.locale.languageCode == 'th';
    final current = subscription;

    if (isLoading) {
      return l10n.homeLoading;
    }

    if (errorMessage != null) {
      return errorMessage!;
    }

    if (current == null) {
      return isThai
          ? 'รอข้อมูลจริงจากระบบแพ็กเกจ'
          : 'Waiting for real billing data';
    }

    final remainingPosts = current.remainingPostsThisMonth;
    if (remainingPosts != null) {
      return isThai
          ? 'เหลือ $remainingPosts โพสต์เดือนนี้'
          : '$remainingPosts posts left this month';
    }

    return isThai ? 'สถานะ ${current.status}' : 'Status ${current.status}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final title = _planTitle(l10n);
    final subtitle = _planSubtitle(l10n);

    return PostDeeCard(
      glowColor: AppTheme.accentPink,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: SizedBox(
        height: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFFFD166),
                  size: 20,
                ),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: isLoading
                      ? const PostDeeSkeleton(
                          key: ValueKey('home-plan-title'),
                          width: 96,
                          height: 12,
                        )
                      : Text(
                          title,
                          key: const ValueKey('home-plan-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXs),
            isLoading
                ? const PostDeeSkeleton(
                    key: ValueKey('home-plan-subtitle'),
                    width: 130,
                    height: 10,
                  )
                : Text(
                    subtitle,
                    key: const ValueKey('home-plan-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 24,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const PaywallScreen(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
                ),
                child: Text(l10n.homeViewPackage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalPostsCard extends StatelessWidget {
  const _TotalPostsCard({
    required this.totalViews,
    required this.totalLikes,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  final int totalViews;
  final int totalLikes;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      glowColor: AppTheme.accentCyan,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: SizedBox(
        height: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeTotalPosts,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '$totalViews',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (errorMessage != null)
              Text(
                errorMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$totalLikes ${l10n.homeLikesMetric}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  height: 18,
                  child: TextButton.icon(
                    onPressed: onRefresh,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh, size: 12),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 56),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isLoading ? l10n.homeLoading : l10n.homeRefreshViews,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestPostList extends StatelessWidget {
  const _LatestPostList({
    required this.posts,
    required this.isLoading,
  });

  final List<PostSummaryResult> posts;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading && posts.isEmpty) {
      return Column(
        children: const [
          PostDeeSkeleton(width: double.infinity, height: 58),
          SizedBox(height: AppTheme.spaceSm),
          PostDeeSkeleton(width: double.infinity, height: 58),
        ],
      );
    }

    if (posts.isEmpty) {
      return const _LatestPostsEmptyState();
    }

    return Column(
      children: [
        for (var index = 0; index < posts.length; index += 1) ...[
          _LatestPostRow(post: posts[index]),
          if (index < posts.length - 1)
            const SizedBox(height: AppTheme.spaceSm),
        ],
      ],
    );
  }
}

class _LatestPostsEmptyState extends StatelessWidget {
  const _LatestPostsEmptyState();

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      key: const ValueKey('home-latest-posts-empty'),
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              border: Border.all(
                color: AppTheme.accentCyan.withValues(alpha: 0.28),
              ),
            ),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(
                Icons.inbox_outlined,
                color: AppTheme.accentCyanInk,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ยังไม่มีโพสต์จริง',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'เมื่อมีโพสต์จากระบบจริง รายการล่าสุดจะแสดงที่นี่',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthToolsPreview extends StatelessWidget {
  const _GrowthToolsPreview();

  static const _items = [
    _GrowthToolItem(
      id: 'bio_link',
      title: 'ลิงก์หน้าโปรไฟล์',
      description: 'สร้างหน้าเว็บรวมลิงก์ร้านและอัปเดตจากโพสต์ที่ตั้งเวลา',
      status: 'หน้าร้าน',
      icon: Icons.link,
      color: AppTheme.accentCyan,
      settings: [
        GrowthToolSettingOption(
          id: 'store_url',
          label: 'ชื่อร้านและ URL เช่น postdee.link/store-name',
        ),
        GrowthToolSettingOption(
          id: 'affiliate_links',
          label: 'ลิงก์สินค้า แคมเปญ และแอฟฟิลิเอต',
        ),
        GrowthToolSettingOption(
          id: 'auto_update_links',
          label: 'เลือกโพสต์ที่ให้อัปเดตลิงก์อัตโนมัติ',
        ),
      ],
    ),
    _GrowthToolItem(
      id: 'team_access',
      title: 'ทีมและผู้ช่วย',
      description: 'เชิญผู้ช่วยเตรียมโพสต์ได้ โดยไม่ต้องเห็นรหัสผ่าน',
      status: 'Pro 299',
      icon: Icons.groups_2,
      color: Color(0xFF60A5FA),
      settings: [
        GrowthToolSettingOption(
          id: 'invite_email',
          label: 'เชิญอีเมลผู้ช่วยหรือแอดมินร้าน',
        ),
        GrowthToolSettingOption(
          id: 'schedule_permission',
          label: 'กำหนดสิทธิ์เตรียมโพสต์และตั้งเวลา',
        ),
        GrowthToolSettingOption(
          id: 'hide_owner_tokens',
          label: 'ซ่อนรหัสผ่านและ OAuth ของเจ้าของร้าน',
        ),
      ],
    ),
    _GrowthToolItem(
      id: 'viral_alert',
      title: 'แจ้งเตือนคลิปไวรัล',
      description: 'แจ้งเตือนเมื่อยอดวิวโตเร็วกว่าปกติ',
      status: 'แจ้งเตือน',
      icon: Icons.notifications_active_outlined,
      color: Color(0xFFFB923C),
      settings: [
        GrowthToolSettingOption(
          id: 'view_threshold',
          label: 'ตั้งเกณฑ์ยอดวิวโตเร็วผิดปกติ',
        ),
        GrowthToolSettingOption(
          id: 'app_notification',
          label: 'เลือกช่องทางแจ้งเตือนในแอป',
        ),
        GrowthToolSettingOption(
          id: 'rising_clips',
          label: 'ดูรายการคลิปที่กำลังพุ่ง',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PostDeeSectionHeader(
          title: 'เครื่องมือเติบโต',
          trailing: PostDeeSoftPill(
            label: 'เฟส 2',
            icon: Icons.auto_graph,
            color: AppTheme.accentCyanInk,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          'ตัวอย่างหน้าตาเครื่องมือชุดถัดไปในแผน',
          style: textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        PostDeeCard(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
          child: Column(
            children: [
              for (var index = 0; index < _items.length; index += 1) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    color: AppTheme.border.withValues(alpha: 0.4),
                  ),
                _GrowthToolRow(item: _items[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GrowthToolItem {
  const _GrowthToolItem({
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
}

class _GrowthToolRow extends StatelessWidget {
  const _GrowthToolRow({required this.item});

  final _GrowthToolItem item;

  void _open(BuildContext context) {
    if (item.id == 'bio_link') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const LinkInBioScreen(),
        ),
      );
      return;
    }

    showGrowthToolDetailSheet(
      context,
      GrowthToolDetail(
        id: item.id,
        title: item.title,
        description: item.description,
        status: item.status,
        icon: item.icon,
        color: item.color,
        settings: item.settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: item.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceMd),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                  color: item.color.withValues(alpha: 0.14),
                  border:
                      Border.all(color: item.color.withValues(alpha: 0.3)),
                ),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    item.icon,
                    color: AppTheme.inkFor(item.color),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              PostDeeSoftPill(label: item.status, color: item.color),
              const SizedBox(width: AppTheme.spaceXs),
              Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestPostRow extends StatelessWidget {
  const _LatestPostRow({required this.post});

  final PostSummaryResult post;

  static SocialPlatform? _platformFor(String apiValue) {
    for (final platform in SocialPlatform.values) {
      if (platform.apiValue == apiValue) {
        return platform;
      }
    }
    return null;
  }

  ({String label, Color color}) _statusInfo() {
    return switch (post.status.toUpperCase()) {
      'PUBLISHED' => (label: 'โพสต์แล้ว', color: AppTheme.success),
      'PARTIAL_PUBLISHED' =>
        (label: 'โพสต์บางส่วน', color: const Color(0xFFFB923C)),
      'PUBLISHING' => (label: 'กำลังโพสต์', color: AppTheme.accentCyanInk),
      'FAILED' => (label: 'ล้มเหลว', color: AppTheme.accentPinkInk),
      'QUEUED' when post.scheduledAt != null =>
        (label: 'ตั้งเวลาไว้', color: AppTheme.accentCyanInk),
      _ => (label: 'อยู่ในคิว', color: AppTheme.textSecondary),
    };
  }

  String _relativeTime() {
    final reference = post.publishedAt ?? post.scheduledAt ?? post.createdAt;
    final now = DateTime.now();
    final diff = now.difference(reference.toLocal());

    if (diff.isNegative) {
      final ahead = reference.toLocal().difference(now);
      if (ahead.inDays >= 1) return 'อีก ${ahead.inDays} วัน';
      if (ahead.inHours >= 1) return 'อีก ${ahead.inHours} ชม.';
      return 'อีก ${ahead.inMinutes.clamp(1, 59)} นาที';
    }

    if (diff.inDays >= 1) return '${diff.inDays} วันก่อน';
    if (diff.inHours >= 1) return '${diff.inHours} ชม.ก่อน';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} นาทีก่อน';
    return 'เมื่อสักครู่';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final platforms = post.platforms
        .map(_platformFor)
        .whereType<SocialPlatform>()
        .toList();
    final glowColor =
        platforms.isNotEmpty ? platforms.first.color : AppTheme.accent;
    final status = _statusInfo();
    final caption = post.caption.trim();
    final subtitle = caption.isEmpty ? _relativeTime() : caption;

    return PostDeeCard(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: AppTheme.spaceSm),
      glowColor: glowColor,
      child: Row(
        children: [
          if (platforms.isEmpty)
            Icon(Icons.movie_outlined, color: AppTheme.textSecondary, size: 26)
          else
            SizedBox(
              width: (platforms.length.clamp(1, 4)) * 20 + 8,
              height: 30,
              child: Stack(
                children: [
                  for (var index = 0;
                      index < platforms.length && index < 4;
                      index += 1)
                    Positioned(
                      left: index * 18,
                      child: SocialPlatformLogo(
                        platform: platforms[index],
                        size: 26,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  caption.isEmpty
                      ? '${platforms.length} แพลตฟอร์ม'
                      : _relativeTime(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _StatusPill(label: status.label, color: status.color),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 108),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}
