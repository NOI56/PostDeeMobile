import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/network/api_error_message.dart';
import '../../core/theme/app_theme.dart';
import '../billing/paywall_screen.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../notifications/push_notification.dart';
import '../platforms/social_platform.dart';
import '../posts/post_detail_screen.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_skeleton.dart';

typedef HomeSubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef HomeRecentPostsLoader = Future<List<PostSummaryResult>> Function();
typedef HomeVideoThumbnailControllerFactory = VideoPlayerController Function(
  Uri videoUrl,
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActive = true,
    this.loadSubscription,
    this.loadRecentPosts,
    this.createVideoThumbnailController,
    this.onViewAllPosts,
    this.onOpenNotifications,
    this.onOpenProfile,
    this.onOpenLinkInBio,
    this.userName,
  });

  /// Whether the home tab is currently visible in the app shell.
  ///
  /// The latest-post list refreshes whenever this changes from false to true.
  final bool isActive;
  final HomeSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;
  final VoidCallback? onViewAllPosts;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenLinkInBio;

  /// Real signed-in display name, appended to the greeting. When null/empty the
  /// greeting shows without a name (no hardcoded demo name).
  final String? userName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiClient = PostDeeApiClient();
  SubscriptionStatusResult? _subscription;
  List<PostSummaryResult> _recentPosts = const [];
  bool _isLoadingSubscription = true;
  bool _isLoadingPosts = true;
  bool _postsLoadInProgress = false;
  bool _postsReloadPending = false;
  String? _postsErrorMessage;
  String? _subscriptionErrorMessage;
  var _subscriptionLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
    if (widget.isActive) {
      _loadRecentPosts();
    } else {
      _isLoadingPosts = false;
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isActive && widget.isActive) {
      _loadRecentPosts();
    }
  }

  Future<void> _loadRecentPosts() async {
    if (_postsLoadInProgress) {
      _postsReloadPending = widget.isActive;
      return;
    }
    _postsLoadInProgress = true;
    setState(() {
      _isLoadingPosts = true;
      _postsErrorMessage = null;
    });

    try {
      final loader = widget.loadRecentPosts ?? _apiClient.listRecentPosts;
      final posts = await loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _recentPosts = posts;
        _postsErrorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      final isThai = Localizations.localeOf(context).languageCode == 'th';
      setState(() {
        _postsErrorMessage =
            isThai ? 'โหลดโพสต์ล่าสุดไม่สำเร็จ' : 'Could not load latest posts';
      });
    } finally {
      _postsLoadInProgress = false;
      if (mounted) {
        setState(() => _isLoadingPosts = false);
      }
    }

    final shouldReload = _postsReloadPending && mounted && widget.isActive;
    _postsReloadPending = false;
    if (shouldReload) {
      await _loadRecentPosts();
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
        _subscriptionErrorMessage = apiErrorMessage(error,
            fallbackMessage: 'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
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
        _LinkInBioShortcutCard(onOpen: widget.onOpenLinkInBio),
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
          errorMessage: _postsErrorMessage,
          onRetry: _loadRecentPosts,
          onOpenPost: _openPostDetail,
          isActive: widget.isActive,
          createVideoThumbnailController: widget.createVideoThumbnailController,
        ),
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

class _LinkInBioShortcutCard extends StatelessWidget {
  const _LinkInBioShortcutCard({this.onOpen});

  final VoidCallback? onOpen;

  void _open(BuildContext context) {
    if (onOpen != null) {
      onOpen!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const LinkInBioScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';
    const accent = Color(0xFF0EA5B7);
    final tint = accent.withValues(alpha: 0.14);
    final statusBadge = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          isThai ? 'หน้าร้าน' : 'Storefront',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
    );

    return Semantics(
      excludeSemantics: true,
      button: true,
      label: isThai ? 'ลิงก์หน้าโปรไฟล์' : 'Profile link',
      hint: isThai
          ? 'เปิดหน้าสร้างลิงก์หน้าโปรไฟล์'
          : 'Open the profile link builder',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Material(
          key: const ValueKey('home-link-in-bio-shortcut'),
          color: AppTheme.glass,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: tint,
                    ),
                    child:
                        const Icon(Icons.link_rounded, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isThai ? 'ลิงก์หน้าโปรไฟล์' : 'Profile link',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isThai
                              ? 'รวมลิงก์ร้านและแคมเปญ'
                              : 'Store and campaign links',
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
                  statusBadge,
                  const SizedBox(width: AppTheme.spaceXs),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                ],
              ),
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

    if (current == null && errorMessage != null) {
      return isThai ? 'ตรวจสอบแพ็กเกจไม่ได้' : 'Could not check package';
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
    final remainingUnits = remainingPosts.clamp(0, includedUnits);

    return remainingUnits / includedUnits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final title = _planTitle(l10n);
    final subtitle = _planSubtitle(l10n);
    final progressRatio = _planProgressRatio();
    final isPro = subscription?.plan.toUpperCase() == 'PRO';
    final hasUnknownPlan = subscription == null && errorMessage != null;
    final showQuota = !isLoading && errorMessage == null;
    final showUpgrade =
        !isLoading && errorMessage == null && subscription != null && !isPro;

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      title,
                      key: const ValueKey('home-plan-title'),
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      key: const ValueKey('home-plan-subtitle'),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                    if (showQuota) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        value: subtitle,
                        child: ExcludeSemantics(
                          child: SizedBox(
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  key: const ValueKey(
                                    'home-plan-progress-fill',
                                  ),
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
                        ),
                      ),
                    ],
                    if (showUpgrade && !hasUnknownPlan) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.locale.languageCode == 'th'
                                  ? 'อัปเกรด'
                                  : 'Upgrade',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AppTheme.accentCyanInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: AppTheme.accentCyanInk,
                            size: 15,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestPostList extends StatelessWidget {
  const _LatestPostList({
    required this.posts,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpenPost,
    required this.isActive,
    required this.createVideoThumbnailController,
  });

  final List<PostSummaryResult> posts;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<PostSummaryResult> onOpenPost;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;

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

    if (errorMessage != null && posts.isEmpty) {
      return _LatestPostsErrorState(
        message: errorMessage!,
        onRetry: onRetry,
      );
    }

    if (posts.isEmpty) {
      return const _LatestPostsEmptyState();
    }

    return Column(
      children: [
        for (var index = 0; index < posts.length; index += 1) ...[
          _LatestPostRow(
            key: ValueKey(posts[index].id),
            post: posts[index],
            onTap: () => onOpenPost(posts[index]),
            isActive: isActive,
            createVideoThumbnailController: createVideoThumbnailController,
          ),
          if (index < posts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _LatestPostsErrorState extends StatelessWidget {
  const _LatestPostsErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      key: const ValueKey('home-latest-posts-error'),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: colors.onErrorContainer,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isThai ? 'ลองใหม่' : 'Try again'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onErrorContainer,
                minimumSize: const Size(48, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestPostsEmptyState extends StatelessWidget {
  const _LatestPostsEmptyState();

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

class _LatestPostRow extends StatelessWidget {
  const _LatestPostRow({
    super.key,
    required this.post,
    required this.onTap,
    required this.isActive,
    required this.createVideoThumbnailController,
  });

  final PostSummaryResult post;
  final VoidCallback onTap;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;

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

    if (hasUnconfirmedDeliveryOutcome(post.platformResults)) {
      return (
        label: 'ผลยังไม่ยืนยัน',
        bg: draftBg,
        ink: draftInk,
      );
    }

    final deliveryLabel = aggregatePostDeliveryOutcomeLabel(
      post.platformResults,
      compact: true,
    );
    if (deliveryLabel != null) {
      return (
        label: deliveryLabel,
        bg: publishedBg,
        ink: publishedInk,
      );
    }

    return switch (post.status.toUpperCase()) {
      'PUBLISHED' => (label: 'เผยแพร่', bg: publishedBg, ink: publishedInk),
      'PARTIAL_PUBLISHED' => (
          label: 'ส่งบางส่วน',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      'PUBLISHING' => (
          label: 'กำลังส่ง',
          bg: publishedBg,
          ink: publishedInk,
        ),
      'FAILED' => (
          label: 'ล้มเหลว',
          bg: const Color(0xFFFDE4E4),
          ink: const Color(0xFFDC2626),
        ),
      'QUEUED' when post.scheduledAt != null => (
          label: 'รอส่ง',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      _ => (label: 'รอส่ง', bg: draftBg, ink: draftInk),
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
              _LatestPostThumbnail(
                post: post,
                isActive: isActive,
                createController: createVideoThumbnailController,
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

class _LatestPostThumbnail extends StatelessWidget {
  const _LatestPostThumbnail({
    required this.post,
    required this.isActive,
    required this.createController,
  });

  final PostSummaryResult post;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createController;

  @override
  Widget build(BuildContext context) {
    final coverUrl = post.coverImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: coverUrl != null
            ? Image.network(
                coverUrl.toString(),
                key: ValueKey('home-latest-post-cover-${post.id}'),
                fit: BoxFit.cover,
                cacheWidth: 144,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, synchronouslyLoaded) =>
                    synchronouslyLoaded || frame != null
                        ? child
                        : _LatestPostThumbnailPlaceholder(postId: post.id),
                errorBuilder: (context, error, stackTrace) =>
                    _LatestPostThumbnailPlaceholder(postId: post.id),
              )
            : _LatestPostVideoPreview(
                postId: post.id,
                videoUrl: post.videoUrl,
                frameTimeMs: post.coverFrameTimeMs,
                isActive: isActive,
                createController: createController,
              ),
      ),
    );
  }
}

class _LatestPostVideoPreview extends StatefulWidget {
  const _LatestPostVideoPreview({
    required this.postId,
    required this.videoUrl,
    required this.frameTimeMs,
    required this.isActive,
    required this.createController,
  });

  final String postId;
  final Uri? videoUrl;
  final int? frameTimeMs;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createController;

  @override
  State<_LatestPostVideoPreview> createState() =>
      _LatestPostVideoPreviewState();
}

class _LatestPostVideoPreviewState extends State<_LatestPostVideoPreview> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _startController();
  }

  @override
  void didUpdateWidget(covariant _LatestPostVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.frameTimeMs != widget.frameTimeMs ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.createController != widget.createController) {
      _stopController();
      _startController();
    }
  }

  bool _isCurrent(VideoPlayerController controller, int generation) =>
      mounted &&
      widget.isActive &&
      generation == _generation &&
      identical(controller, _controller);

  void _startController() {
    if (!widget.isActive || widget.videoUrl == null) return;
    try {
      // This uses the player's network stream without saving a local copy.
      // A cover skips the player entirely; the fallback never calls play().
      final controller = widget.createController?.call(widget.videoUrl!) ??
          VideoPlayerController.networkUrl(
            widget.videoUrl!,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
      _controller = controller;
      controller.addListener(_onControllerChanged);
      unawaited(_initialize(controller, ++_generation));
    } catch (_) {
      _stopController();
    }
  }

  Future<void> _prepareFrame(
      VideoPlayerController controller, int generation) async {
    await controller.initialize();
    if (!_isCurrent(controller, generation)) return;
    await controller.setVolume(0);
    if (!_isCurrent(controller, generation)) return;
    await controller.pause();
    if (!_isCurrent(controller, generation)) return;
    final durationMs = controller.value.duration.inMilliseconds;
    final frameTimeMs = (widget.frameTimeMs ?? 0)
        .clamp(0, durationMs > 0 ? durationMs - 1 : 0)
        .toInt();
    await controller.seekTo(Duration(milliseconds: frameTimeMs));
  }

  Future<void> _initialize(
      VideoPlayerController controller, int generation) async {
    try {
      await _prepareFrame(controller, generation)
          .timeout(const Duration(seconds: 8));
      if (_isCurrent(controller, generation)) {
        setState(() => _isReady = true);
      }
    } catch (_) {
      if (_isCurrent(controller, generation)) {
        _stopController();
        if (mounted) setState(() {});
      }
    }
  }

  void _onControllerChanged() {
    if (_controller?.value.hasError == true) {
      _stopController();
      if (mounted) setState(() {});
    }
  }

  void _stopController() {
    _generation += 1;
    final previous = _controller;
    _controller = null;
    _isReady = false;
    if (previous != null) {
      previous.removeListener(_onControllerChanged);
      unawaited(_disposeController(previous));
    }
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // A failed native player must not affect the rest of the Home page.
    }
  }

  @override
  void dispose() {
    _stopController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = controller?.value.size ?? Size.zero;
    if (!_isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        size.width <= 0 ||
        size.height <= 0) {
      return _LatestPostThumbnailPlaceholder(postId: widget.postId);
    }
    return SizedBox.expand(
      key: ValueKey('home-latest-post-video-${widget.postId}'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _LatestPostThumbnailPlaceholder extends StatelessWidget {
  const _LatestPostThumbnailPlaceholder({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('home-latest-post-placeholder-$postId'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
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
      );
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
