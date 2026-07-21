import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../analytics/analytics_error_message.dart';
import '../billing/paywall_screen.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../notifications/push_notification.dart';
import '../platforms/social_platform.dart';
import '../posts/post_detail_screen.dart';
import '../shared/growth_tool_detail_sheet.dart';
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
    this.onCreatePost,
    this.onViewAllPosts,
    this.onOpenNotifications,
    this.onOpenProfile,
    this.onOpenAi,
    this.userName,
  });

  final HomeAnalyticsLoader? loadAnalytics;
  final HomeSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final VoidCallback? onCreatePost;
  final VoidCallback? onViewAllPosts;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenAi;

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
  var _subscriptionLoadGeneration = 0;

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
    final loadGeneration = ++_subscriptionLoadGeneration;
    setState(() {
      _isLoadingSubscription = true;
      _subscriptionErrorMessage = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _subscription = subscription;
      });
    } on ApiException catch (error) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      setState(() {
        _subscriptionErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _subscriptionErrorMessage = l10n.homeApiConnectionError;
      });
    } catch (_) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return;
      }

      final l10n = PostDeeLocalizations.of(context);
      setState(() {
        _subscriptionErrorMessage = l10n.homeAnalyticsLoadError;
      });
    } finally {
      if (mounted && loadGeneration == _subscriptionLoadGeneration) {
        setState(() {
          _isLoadingSubscription = false;
        });
      }
    }
  }

  Future<void> _openPaywall() async {
    final loader =
        widget.loadSubscription ?? _apiClient.loadCurrentSubscription;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PaywallScreen(loadSubscription: loader),
      ),
    );

    if (mounted) {
      await _loadSubscription();
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
        _analyticsErrorMessage = analyticsErrorMessage(error);
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

  Future<void> _openPostDetail(PostSummaryResult post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PostDetailScreen(post: post),
      ),
    );

    // A publish-now or cancel changed the post list, so reload it.
    if (changed == true && mounted) {
      await _loadRecentPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final isThai = l10n.locale.languageCode == 'th';
    final totalViews = _analytics?.totalViews ?? 0;
    final totalLikes = _analytics?.totalLikes ?? 0;
    final name = widget.userName?.trim();
    final avatarInitial = (name != null && name.isNotEmpty)
        ? name.characters.first.toUpperCase()
        : 'P';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, AppTheme.navOverlap),
      children: [
        _HomeHeader(
          title: isThai ? 'หน้าแรก' : l10n.homeTab,
          avatarInitial: avatarInitial,
          notificationsLabel: l10n.notificationsAction,
          accountLabel: l10n.userAccountAction,
          onNotificationsPressed: widget.onOpenNotifications,
          onAccountPressed: widget.onOpenProfile,
        ),
        const SizedBox(height: 14),
        _PlanSummaryCard(
          subscription: _subscription,
          isLoading: _isLoadingSubscription,
          errorMessage: _subscriptionErrorMessage,
          onTap: _openPaywall,
        ),
        const SizedBox(height: 14),
        _AiEditingShortcutCard(onOpenAi: widget.onOpenAi),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _TotalPostsCard(
                totalViews: totalViews,
                totalLikes: totalLikes,
                isLoading: _isLoadingAnalytics,
                errorMessage: _analyticsErrorMessage,
                onRefresh: _isLoadingAnalytics ? null : _loadAnalytics,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LikesMetricCard(
                totalLikes: totalLikes,
                isLoading: _isLoadingAnalytics,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _CreatePostCard(onCreatePost: widget.onCreatePost),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                isThai ? 'โพสต์ล่าสุด' : l10n.homeLatestPostStatus,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (_recentPosts.isNotEmpty)
              TextButton(
                onPressed: widget.onViewAllPosts,
                child: Text(
                  isThai ? 'ดูทั้งหมด' : l10n.homeViewAll,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _LatestPostList(
          posts: _recentPosts,
          isLoading: _isLoadingPosts,
          onCreatePost: widget.onCreatePost,
          onOpenPost: _openPostDetail,
        ),
        const SizedBox(height: 18),
        // Not const: a kept-alive const subtree is skipped on rebuild and
        // keeps stale colors when the theme flips (AppTheme reads are
        // imperative, not inherited).
        _GrowthToolsPreview(),
        const SizedBox(height: AppTheme.spaceSm),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.title,
    required this.avatarInitial,
    required this.notificationsLabel,
    required this.accountLabel,
    required this.onNotificationsPressed,
    required this.onAccountPressed,
  });

  final String title;
  final String avatarInitial;
  final String notificationsLabel;
  final String accountLabel;
  final VoidCallback? onNotificationsPressed;
  final VoidCallback? onAccountPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        // The red dot only shows while there are unread notifications.
        ListenableBuilder(
          listenable: PostDeeNotificationCenter.instance,
          builder: (context, _) => _RoundHeaderButton(
            label: notificationsLabel,
            icon: Icons.notifications_none_rounded,
            onPressed: onNotificationsPressed,
            hasBadge: PostDeeNotificationCenter.instance.hasUnread,
          ),
        ),
        const SizedBox(width: 9),
        Semantics(
          label: accountLabel,
          button: true,
          child: GestureDetector(
            onTap: onAccountPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.mint,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    avatarInitial,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.accentCyanInk,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.hasBadge = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool hasBadge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.glass,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon, color: AppTheme.textSecondary, size: 22),
                ),
              ),
              if (hasBadge)
                Positioned(
                  top: 9,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.glass, width: 2),
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatePostCard extends StatelessWidget {
  const _CreatePostCard({required this.onCreatePost});

  final VoidCallback? onCreatePost;

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onCreatePost,
        icon: const Icon(Icons.add_circle_rounded, size: 25),
        label: Text(isThai ? 'สร้างโพสต์ใหม่' : 'Create a new post'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accent,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shadowColor: AppTheme.accent.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AiEditingShortcutCard extends StatelessWidget {
  const _AiEditingShortcutCard({required this.onOpenAi});

  final VoidCallback? onOpenAi;

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';

    return Semantics(
      button: true,
      label: isThai ? 'ตัดต่อด้วย AI' : 'AI editing',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpenAi,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E9F6E), Color(0xFF0A7A55)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B7A55).withValues(alpha: 0.32),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned(
                  top: -44,
                  right: -26,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 150, height: 150),
                  ),
                ),
                Positioned(
                  right: 48,
                  bottom: -54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 96, height: 96),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const SizedBox(
                          width: 54,
                          height: 54,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isThai ? 'ตัดต่อด้วย AI' : 'AI editing',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isThai
                                  ? 'ให้ AI ตัดคลิปให้กระชับ ใส่ซับ เป็นสไตล์ไวรัลอัตโนมัติ'
                                  : 'Let AI tighten clips, add captions, and prepare viral-ready edits.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.subscription,
    required this.isLoading,
    required this.errorMessage,
    required this.onTap,
  });

  final SubscriptionStatusResult? subscription;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onTap;

  String _planTitle(PostDeeLocalizations l10n) {
    final isThai = l10n.locale.languageCode == 'th';
    final current = subscription;

    if (isLoading) {
      return isThai ? 'กำลังโหลดแพ็กเกจ' : 'Loading package';
    }

    if (current == null) {
      return isThai ? 'แพ็กเกจฟรี' : 'Free package';
    }

    return switch (current.plan.toUpperCase()) {
      'PRO' => isThai ? 'แพ็กเกจ Pro' : 'Pro package',
      'STARTER' => isThai ? 'แพ็กเกจ Starter' : 'Starter package',
      'BASIC' || 'FREE' => isThai ? 'แพ็กเกจฟรี' : 'Free package',
      _ => current.plan,
    };
  }

  // Monthly post units included per plan (design handoff: free 3, Starter
  // 120, Pro 250).
  int _planIncludedUnits() {
    return switch (subscription?.plan.toUpperCase()) {
      'PRO' => 250,
      'STARTER' => 120,
      _ => 3,
    };
  }

  String _planSubtitle(PostDeeLocalizations l10n) {
    final isThai = l10n.locale.languageCode == 'th';

    if (isLoading) {
      return l10n.homeLoading;
    }

    if (errorMessage != null) {
      return errorMessage!;
    }

    final remainingPosts = subscription?.remainingPostsThisMonth ?? 1;
    final includedUnits = _planIncludedUnits();
    return isThai
        ? 'เหลือ $remainingPosts/$includedUnits หน่วย'
        : '$remainingPosts/$includedUnits units left';
  }

  double _planProgressRatio() {
    final includedUnits = _planIncludedUnits();
    final remainingPosts = subscription?.remainingPostsThisMonth ?? 1;
    final usedPosts = (includedUnits - remainingPosts).clamp(0, includedUnits);

    return usedPosts / includedUnits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final title = _planTitle(l10n);
    final subtitle = _planSubtitle(l10n);
    final progressRatio = _planProgressRatio();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.mint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.20)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.card_membership_rounded,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            key: const ValueKey('home-plan-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            subtitle,
                            key: const ValueKey('home-plan-subtitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: const ValueKey('home-plan-progress-fill'),
                            widthFactor: progressRatio,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.accentCyanInk,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const SizedBox(height: 6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.locale.languageCode == 'th' ? 'อัปเกรด' : 'Upgrade',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.accentCyanInk,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.accentCyanInk,
                    size: 15,
                  ),
                ],
              ),
            ],
          ),
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
    final isThai = Localizations.localeOf(context).languageCode == 'th';

    return _ReferenceMetricCard(
      label: isThai ? 'ยอดวิวเดือนนี้' : 'Views this month',
      value: isLoading ? '...' : '$totalViews',
      icon: Icons.visibility_outlined,
      errorMessage: errorMessage,
      onRefresh: onRefresh,
    );
  }
}

class _LikesMetricCard extends StatelessWidget {
  const _LikesMetricCard({
    required this.totalLikes,
    required this.isLoading,
  });

  final int totalLikes;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';

    return _ReferenceMetricCard(
      label: isThai ? 'ไลก์เดือนนี้' : 'Likes this month',
      value: isLoading ? '...' : '$totalLikes',
      icon: Icons.favorite_border_rounded,
    );
  }
}

class _ReferenceMetricCard extends StatelessWidget {
  const _ReferenceMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.errorMessage,
    this.onRefresh,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? errorMessage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRefresh == null)
                  Icon(icon, color: AppTheme.textMuted, size: 18)
                else
                  GestureDetector(
                    onTap: onRefresh,
                    child: Icon(icon, color: AppTheme.textMuted, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 2),
              Text(
                errorMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
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
    required this.onCreatePost,
    required this.onOpenPost,
  });

  final List<PostSummaryResult> posts;
  final bool isLoading;
  final VoidCallback? onCreatePost;
  final ValueChanged<PostSummaryResult> onOpenPost;

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
      return _LatestPostsEmptyState(onCreatePost: onCreatePost);
    }

    return Column(
      children: [
        for (var index = 0; index < posts.length; index += 1) ...[
          _LatestPostRow(
            post: posts[index],
            onTap: () => onOpenPost(posts[index]),
          ),
          if (index < posts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _LatestPostsEmptyState extends StatelessWidget {
  const _LatestPostsEmptyState({required this.onCreatePost});

  final VoidCallback? onCreatePost;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('home-latest-posts-empty'),
      foregroundPainter: _DashedRRectBorderPainter(
        color: AppTheme.border,
        radius: 16,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.mint,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.movie_outlined,
                    color: AppTheme.accentCyanInk,
                    size: 27,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'ยังไม่มีโพสต์',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'เริ่มสร้างโพสต์แรกของร้านคุณ\nโพสต์คลิปเดียวไปได้ทุกช่องทาง',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: FilledButton.icon(
                  onPressed: onCreatePost,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('สร้างโพสต์'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.accent,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1;

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _GrowthToolsPreview extends StatelessWidget {
  const _GrowthToolsPreview();

  // Two tools on Home, per the prototype; "team" lives in the growth detail
  // screen instead.
  static const _items = [
    _GrowthToolItem(
      id: 'bio_link',
      title: 'ลิงก์หน้าโปรไฟล์',
      description: 'รวมลิงก์ร้าน อัปเดตจากโพสต์ที่ตั้งเวลา',
      status: 'หน้าร้าน',
      icon: Icons.link,
      color: Color(0xFF0EA5B7),
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
      id: 'viral_alert',
      title: 'แจ้งเตือนคลิปไวรัล',
      description: 'เตือนเมื่อยอดวิวโตเร็วกว่าปกติ',
      status: 'เร็ว ๆ นี้',
      icon: Icons.notifications_active,
      color: Color(0xFFF59E0B),
      prototypeOnly: true,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'เครื่องมือเติบโต',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  'ช่วยให้ขายดี',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
              for (var index = 0; index < _items.length; index += 1) ...[
                if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
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
    this.prototypeOnly = false,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final IconData icon;
  final Color color;
  final List<GrowthToolSettingOption> settings;
  final bool prototypeOnly;
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
        prototypeOnly: item.prototypeOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tint = item.color.withValues(alpha: 0.14);

    return Semantics(
      button: true,
      label: item.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: tint,
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
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
                      item.description,
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
              const SizedBox(width: AppTheme.spaceSm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  child: Text(
                    item.status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: item.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spaceXs),
              Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestPostRow extends StatelessWidget {
  const _LatestPostRow({required this.post, required this.onTap});

  final PostSummaryResult post;
  final VoidCallback onTap;

  static SocialPlatform? _platformFor(String apiValue) {
    for (final platform in SocialPlatform.values) {
      if (platform.apiValue == apiValue) {
        return platform;
      }
    }
    return null;
  }

  // Pill colors are fixed in both themes, matching the prototype's statusMeta
  // (published mint, scheduled cream, draft gray).
  ({String label, Color bg, Color ink}) _statusInfo() {
    const publishedBg = Color(0xFFE2F3EA);
    const publishedInk = Color(0xFF0E9F6E);
    const scheduledBg = Color(0xFFFBEFD7);
    const scheduledInk = Color(0xFFB5740B);
    const draftBg = Color(0xFFEEF2EF);
    const draftInk = Color(0xFF778276);

    return switch (post.status.toUpperCase()) {
      'PUBLISHED' => (label: 'เผยแพร่', bg: publishedBg, ink: publishedInk),
      'PARTIAL_PUBLISHED' => (
          label: 'โพสต์บางส่วน',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      'PUBLISHING' => (
          label: 'กำลังโพสต์',
          bg: publishedBg,
          ink: publishedInk,
        ),
      'FAILED' => (
          label: 'ล้มเหลว',
          bg: const Color(0xFFFDE4E4),
          ink: const Color(0xFFDC2626),
        ),
      'QUEUED' when post.scheduledAt != null => (
          label: 'ตั้งเวลา',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      _ => (label: 'อยู่ในคิว', bg: draftBg, ink: draftInk),
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
    final platforms =
        post.platforms.map(_platformFor).whereType<SocialPlatform>().toList();
    final status = _statusInfo();
    final caption = post.caption.trim();
    final title = caption.isEmpty ? _relativeTime() : caption;
    final sub = platforms.isEmpty
        ? _relativeTime()
        : platforms.map((p) => p.label).join(' · ');

    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(15),
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
              // Placeholder video thumbnail (the prototype has no real images).
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE7EFE9), Color(0xFFD6E3DA)],
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF8FA197),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (final platform in platforms.take(4)) ...[
                          Container(
                            width: 13,
                            height: 13,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: platform.displayColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                        if (platforms.isNotEmpty) const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _StatusPill(label: status.label, bg: status.bg, ink: status.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.bg, required this.ink});

  final String label;
  final Color bg;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 108),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}
