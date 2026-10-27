import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_session.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/network/api_error_message.dart';
import '../../core/theme/app_theme.dart';
import '../billing/paywall_screen.dart';
import '../link_in_bio/link_in_bio_publication_status.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../notifications/push_notification.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../posts/post_detail_screen.dart';
import '../posts/posts_screen.dart';
import '../shared/post_delivery_outcome.dart';
import '../shared/postdee_skeleton.dart';
import '../shared/postdee_press_feedback.dart';
import '../shared/postdee_publishing_motion.dart';
import '../uploader/publish_draft.dart';
import '../uploader/uploader_screen.dart';
import 'home_activity_section.dart';
import 'home_draft_thumbnail.dart';
import 'home_service_status_banner.dart';

typedef HomeSubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef HomeRecentPostsLoader = Future<List<PostSummaryResult>> Function();
typedef HomeLinkProfileLoader = Future<LinkInBioProfileResult?> Function();
typedef HomeVideoThumbnailControllerFactory = VideoPlayerController Function(
  Uri videoUrl,
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActive = true,
    this.loadSubscription,
    this.loadRecentPosts,
    this.loadAllPosts,
    this.createVideoThumbnailController,
    this.createDraftThumbnailController,
    this.onViewAllPosts,
    this.onOpenNotifications,
    this.onOpenProfile,
    this.onOpenLinkInBio,
    this.loadDrafts,
    this.loadConnections,
    this.loadScheduledPosts,
    this.loadLinkProfile,
    this.loadServiceStatus,
    this.onCreatePost,
    this.onResumeDraft,
    this.onOpenConnections,
    this.onOpenCalendar,
    this.now,
    this.userName,
  });

  /// Whether the home tab is currently visible in the app shell.
  ///
  /// The latest-post list refreshes whenever this changes from false to true.
  final bool isActive;
  final HomeSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final PostsLoader? loadAllPosts;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;
  final HomeDraftThumbnailControllerFactory? createDraftThumbnailController;
  final VoidCallback? onViewAllPosts;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenLinkInBio;
  final Future<List<PublishDraft>> Function()? loadDrafts;
  final Future<List<SocialConnectionResult>> Function()? loadConnections;
  final HomeRecentPostsLoader? loadScheduledPosts;
  final HomeLinkProfileLoader? loadLinkProfile;
  final HomeServiceStatusLoader? loadServiceStatus;
  final Future<void> Function()? onCreatePost;
  final Future<void> Function(PublishDraft)? onResumeDraft;
  final VoidCallback? onOpenConnections;
  final VoidCallback? onOpenCalendar;
  final DateTime Function()? now;

  /// Real signed-in display name, appended to the greeting. When null/empty the
  /// greeting shows without a name (no hardcoded demo name).
  final String? userName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _apiClient = PostDeeApiClient();
  SubscriptionStatusResult? _subscription;
  List<PostSummaryResult> _recentPosts = const [];
  bool _isLoadingSubscription = true;
  bool _isLoadingPosts = true;
  bool _hasLoadedPosts = false;
  Future<bool>? _postsLoadFuture;
  Future<bool>? _subscriptionLoadFuture;
  Future<void>? _dashboardRefreshFuture;
  final _activityKey = GlobalKey<HomeActivitySectionState>();
  final _shopKey = GlobalKey<_LinkInBioShortcutCardState>();
  final _statusKey = GlobalKey<HomeServiceStatusBannerState>();
  bool? _refreshSucceeded;
  bool _postsLoadFailed = false;
  Object? _subscriptionError;
  var _subscriptionLoadGeneration = 0;
  var _activityRefreshToken = 0;
  String? _ownerUserId;
  var _ownerGeneration = 0;
  bool _openingComposer = false;
  Timer? _sendingRefreshTimer;
  bool _appIsResumed = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appIsResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    PostDeeAuthSessionStore.instance.addListener(_handleOwnerChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadSubscription();
    if (widget.isActive) {
      _loadRecentPosts();
    } else {
      _isLoadingPosts = false;
    }
  }

  @override
  void dispose() {
    _sendingRefreshTimer?.cancel();
    PostDeeAuthSessionStore.instance.removeListener(_handleOwnerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleOwnerChanged() {
    final owner = PostDeeAuthSessionStore.instance.session.stableUserId;
    if (!mounted || owner == _ownerUserId) return;
    _ownerUserId = owner;
    _ownerGeneration++;
    _sendingRefreshTimer?.cancel();
    _sendingRefreshTimer = null;
    _subscriptionLoadGeneration++;
    _postsLoadFuture = null;
    _subscriptionLoadFuture = null;
    _dashboardRefreshFuture = null;
    setState(() {
      _subscription = null;
      _recentPosts = const [];
      _hasLoadedPosts = false;
      _postsLoadFailed = false;
      _subscriptionError = null;
      _isLoadingPosts = widget.isActive;
      _isLoadingSubscription = true;
      _openingComposer = false;
      _refreshSucceeded = null;
    });
    _loadSubscription();
    if (widget.isActive) _loadRecentPosts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    _syncSendingRefresh();
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _loadSubscription();
      if (_recentPosts
          .any((post) => post.status.toUpperCase() == 'PUBLISHING')) {
        _loadRecentPosts(preserveContent: true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSendingRefresh();

    if (!oldWidget.isActive && widget.isActive) {
      _loadRecentPosts();
      _loadSubscription();
    }
  }

  Future<bool> _loadRecentPosts({bool preserveContent = false}) {
    final pending = _postsLoadFuture;
    if (pending != null) return pending;
    final operation = _performRecentPostsLoad(preserveContent: preserveContent);
    _postsLoadFuture = operation;
    unawaited(operation.then((_) {
      if (identical(_postsLoadFuture, operation)) {
        _postsLoadFuture = null;
        _syncSendingRefresh();
      }
    }));
    return operation;
  }

  void _syncSendingRefresh() {
    _sendingRefreshTimer?.cancel();
    _sendingRefreshTimer = null;
    if (!mounted ||
        !widget.isActive ||
        !_appIsResumed ||
        _ownerUserId == null ||
        !_recentPosts
            .any((post) => post.status.toUpperCase() == 'PUBLISHING')) {
      return;
    }
    _sendingRefreshTimer = Timer(const Duration(seconds: 30), () {
      _sendingRefreshTimer = null;
      if (!mounted || !widget.isActive || !_appIsResumed) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        unawaited(_loadRecentPosts(preserveContent: true));
      } else {
        _syncSendingRefresh();
      }
    });
  }

  Future<bool> _performRecentPostsLoad({required bool preserveContent}) async {
    final ownerGeneration = _ownerGeneration;
    setState(() {
      _isLoadingPosts =
          !_hasLoadedPosts && (!preserveContent || _recentPosts.isEmpty);
      _postsLoadFailed = false;
      _refreshSucceeded = null;
    });

    try {
      final loader = widget.loadRecentPosts ?? _apiClient.listRecentPosts;
      final posts = await loader();

      if (mounted && ownerGeneration == _ownerGeneration) {
        setState(() {
          _recentPosts = posts;
          _hasLoadedPosts = true;
          _postsLoadFailed = false;
        });
        return true;
      }
    } catch (_) {
      if (mounted && ownerGeneration == _ownerGeneration) {
        setState(() {
          _postsLoadFailed = true;
        });
      }
    } finally {
      if (mounted && ownerGeneration == _ownerGeneration) {
        setState(() => _isLoadingPosts = false);
      }
    }

    return false;
  }

  Future<bool> _loadSubscription({
    bool preserveContent = false,
    bool force = false,
  }) {
    final pending = _subscriptionLoadFuture;
    if (!force && pending != null) return pending;
    final operation =
        _performSubscriptionLoad(preserveContent: preserveContent);
    _subscriptionLoadFuture = operation;
    unawaited(operation.then((_) {
      if (identical(_subscriptionLoadFuture, operation)) {
        _subscriptionLoadFuture = null;
      }
    }));
    return operation;
  }

  Future<bool> _performSubscriptionLoad({required bool preserveContent}) async {
    final loadGeneration = ++_subscriptionLoadGeneration;
    setState(() {
      _isLoadingSubscription = _subscription == null;
      _subscriptionError = null;
      _refreshSucceeded = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();

      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return false;
      }

      setState(() {
        _subscription = subscription;
      });
      return true;
    } catch (error) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) {
        return false;
      }

      setState(() {
        _subscriptionError = error;
      });
    } finally {
      if (mounted && loadGeneration == _subscriptionLoadGeneration) {
        setState(() {
          _isLoadingSubscription = false;
        });
      }
    }
    return false;
  }

  Future<void> _refreshDashboard() {
    if (!mounted || !widget.isActive || _ownerUserId == null) {
      return Future<void>.value();
    }
    final pending = _dashboardRefreshFuture;
    if (pending != null) return pending;
    final operation = _performDashboardRefresh();
    _dashboardRefreshFuture = operation;
    unawaited(operation.then((_) {
      if (identical(_dashboardRefreshFuture, operation)) {
        _dashboardRefreshFuture = null;
      }
    }));
    return operation;
  }

  Future<void> _performDashboardRefresh() async {
    final ownerGeneration = _ownerGeneration;
    setState(() => _refreshSucceeded = null);
    bool succeeded;
    try {
      // Service notices are best-effort, so they never count as a failed refresh.
      final statusRefresh =
          _statusKey.currentState?.refresh() ?? Future<void>.value();
      final results = await Future.wait<bool>([
        _loadSubscription(preserveContent: true),
        _loadRecentPosts(preserveContent: true),
        _activityKey.currentState?.refresh(preserveContent: true) ??
            Future<bool>.value(false),
        _shopKey.currentState?.refresh(preserveContent: true) ??
            Future<bool>.value(false),
      ]);
      await statusRefresh;
      succeeded = results.every((result) => result);
    } catch (_) {
      succeeded = false;
    }
    if (mounted && ownerGeneration == _ownerGeneration) {
      setState(() => _refreshSucceeded = succeeded);
    }
  }

  Future<void> _openPaywall() async {
    final loader =
        widget.loadSubscription ?? _apiClient.loadCurrentSubscription;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PaywallScreen(
            loadSubscription: loader,
            onAddonPurchased: () {
              if (mounted) _loadSubscription(force: true);
            }),
      ),
    );

    if (mounted) {
      await _loadSubscription(force: true);
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
      setState(() => _activityRefreshToken++);
      await Future.wait([_loadRecentPosts(), _loadSubscription()]);
    } else if (mounted &&
        widget.isActive &&
        post.status.toUpperCase() == 'PUBLISHING') {
      await _loadRecentPosts(preserveContent: true);
    }
  }

  Future<void> _openAllPosts() async {
    if (widget.onViewAllPosts != null) {
      widget.onViewAllPosts!();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostsScreen(loadPosts: widget.loadAllPosts),
    ));
    if (mounted) {
      setState(() => _activityRefreshToken++);
      await Future.wait([_loadRecentPosts(), _loadSubscription()]);
    }
  }

  Future<void> _createPost() async {
    if (_openingComposer) return;
    final ownerGeneration = _ownerGeneration;
    setState(() => _openingComposer = true);
    try {
      if (widget.onCreatePost != null) {
        await widget.onCreatePost!();
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const UploaderScreen(),
        ));
      }
      if (mounted && ownerGeneration == _ownerGeneration) {
        setState(() => _activityRefreshToken++);
        await Future.wait([_loadRecentPosts(), _loadSubscription()]);
      }
    } finally {
      if (mounted && ownerGeneration == _ownerGeneration) {
        setState(() => _openingComposer = false);
      }
    }
  }

  Future<void> _resumeDraft(PublishDraft draft) async {
    if (widget.onResumeDraft != null) {
      await widget.onResumeDraft!(draft);
    } else {
      if (PostDeeAuthSessionStore.instance.session.stableUserId !=
          draft.ownerUserId) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => UploaderScreen(initialDraftId: draft.id),
      ));
    }
    if (mounted) {
      setState(() => _activityRefreshToken++);
      await Future.wait([_loadRecentPosts(), _loadSubscription()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final isThai = l10n.locale.languageCode == 'th';
    final subscriptionErrorMessage = _subscriptionError == null
        ? null
        : apiErrorMessage(
            _subscriptionError!,
            languageCode: l10n.locale.languageCode,
            fallbackMessage: isThai
                ? 'ตรวจสอบแพ็กเกจไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'
                : 'Could not check your plan. Please try again.',
          );
    final postsErrorMessage = !_postsLoadFailed
        ? null
        : isThai
            ? 'โหลดโพสต์ล่าสุดไม่สำเร็จ'
            : 'Could not load latest posts';
    final name = widget.userName?.trim();
    final avatarInitial = (name != null && name.isNotEmpty)
        ? name.characters.first.toUpperCase()
        : 'P';

    return ColoredBox(
        color: AppTheme.ink,
        child: RefreshIndicator(
            key: const ValueKey('home-pull-refresh'),
            color: AppTheme.accent,
            onRefresh: _refreshDashboard,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, AppTheme.navOverlap),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeHeader(
                      title: isThai ? 'หน้าแรก' : l10n.homeTab,
                      avatarInitial: avatarInitial,
                      notificationsLabel: l10n.notificationsAction,
                      accountLabel: l10n.userAccountAction,
                      onNotificationsPressed: widget.onOpenNotifications,
                      onAccountPressed: widget.onOpenProfile,
                    ),
                    HomeServiceStatusBanner(
                      key: _statusKey,
                      isActive: widget.isActive,
                      loadStatus: widget.loadServiceStatus,
                      now: widget.now,
                    ),
                    const SizedBox(height: 14),
                    _PlanSummaryCard(
                      subscription: _subscription,
                      isLoading: _isLoadingSubscription,
                      errorMessage: subscriptionErrorMessage,
                      onTap: _openPaywall,
                      onRetry: _loadSubscription,
                      animateSkeleton: widget.isActive && _ownerUserId != null,
                    ),
                    if (_refreshSucceeded != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _refreshSucceeded!
                            ? (isThai
                                ? 'อัปเดตข้อมูลล่าสุดแล้ว'
                                : 'Home is up to date')
                            : (isThai
                                ? 'อัปเดตข้อมูลยังไม่ครบ ลองใหม่ในส่วนที่มีปัญหา'
                                : 'Some updates failed. Retry the affected section'),
                        key: const ValueKey('home-refresh-status'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _refreshSucceeded!
                              ? AppTheme.accentCyanInk
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    HomeActivitySection(
                      key: _activityKey,
                      isActive: widget.isActive,
                      hasPosts: _isLoadingPosts || _postsLoadFailed
                          ? null
                          : _recentPosts.isNotEmpty,
                      loadDrafts: widget.loadDrafts,
                      loadConnections: widget.loadConnections,
                      loadScheduledPosts: widget.loadScheduledPosts,
                      onCreatePost: _createPost,
                      onResumeDraft: _resumeDraft,
                      onOpenConnections: widget.onOpenConnections,
                      onOpenCalendar: widget.onOpenCalendar,
                      now: widget.now,
                      createDraftThumbnailController:
                          widget.createDraftThumbnailController,
                      refreshToken: _activityRefreshToken,
                    ),
                    const SizedBox(height: 20),
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
                          PostDeePressFeedback(
                              child: TextButton(
                            onPressed: _openAllPosts,
                            child: Text(
                              isThai ? 'ดูทั้งหมด' : l10n.homeViewAll,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentCyanInk,
                              ),
                            ),
                          )),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _LatestPostList(
                      posts: _recentPosts,
                      isLoading: _isLoadingPosts,
                      errorMessage: postsErrorMessage,
                      onRetry: _loadRecentPosts,
                      onOpenPost: _openPostDetail,
                      isActive: widget.isActive,
                      createVideoThumbnailController:
                          widget.createVideoThumbnailController,
                      onCreatePost: _openingComposer ? null : _createPost,
                      now: widget.now,
                    ),
                    const SizedBox(height: 16),
                    _LinkInBioShortcutCard(
                      key: _shopKey,
                      isActive: widget.isActive,
                      loadProfile: widget.loadLinkProfile,
                      onOpen: widget.onOpenLinkInBio,
                    ),
                  ]),
            )));
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Post',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  const TextSpan(
                      text: 'Dee', style: TextStyle(color: AppTheme.accent)),
                ]),
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    )),
          ]),
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
          child: PostDeePressFeedback(
            enabled: onAccountPressed != null,
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
    return PostDeePressFeedback(
      enabled: onPressed != null,
      child: Semantics(
        label: label,
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
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
      ),
    );
  }
}

class _LinkInBioShortcutCard extends StatefulWidget {
  const _LinkInBioShortcutCard({
    super.key,
    this.onOpen,
    required this.isActive,
    this.loadProfile,
  });

  final VoidCallback? onOpen;
  final bool isActive;
  final HomeLinkProfileLoader? loadProfile;

  @override
  State<_LinkInBioShortcutCard> createState() => _LinkInBioShortcutCardState();
}

class _LinkInBioShortcutCardState extends State<_LinkInBioShortcutCard>
    with WidgetsBindingObserver {
  LinkInBioProfileResult? _profile;
  bool _loading = true;
  bool _failed = false;
  bool _hasLoaded = false;
  Future<bool>? _loadFuture;
  int _generation = 0;
  String? _owner;

  @override
  void initState() {
    super.initState();
    _owner = PostDeeAuthSessionStore.instance.session.stableUserId;
    PostDeeAuthSessionStore.instance.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _load();
  }

  @override
  void dispose() {
    _generation++;
    _loadFuture = null;
    PostDeeAuthSessionStore.instance.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSessionChanged() {
    final owner = PostDeeAuthSessionStore.instance.session.stableUserId;
    if (_owner == owner) return;
    _owner = owner;
    _generation++;
    _loadFuture = null;
    setState(() {
      _profile = null;
      _loading = true;
      _failed = false;
      _hasLoaded = false;
    });
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant _LinkInBioShortcutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _load();
    }
  }

  Future<bool> _load() => refresh(preserveContent: false);

  Future<bool> refresh({bool preserveContent = true}) {
    final pending = _loadFuture;
    if (pending != null) return pending;
    final operation = _performLoad(preserveContent: preserveContent);
    _loadFuture = operation;
    unawaited(operation.then((_) {
      if (identical(_loadFuture, operation)) _loadFuture = null;
    }));
    return operation;
  }

  Future<bool> _performLoad({required bool preserveContent}) async {
    final generation = ++_generation;
    final owner = _owner;
    setState(() {
      _loading = !_hasLoaded;
      _failed = false;
    });
    try {
      if (owner == null) {
        throw const AuthSessionChangedException();
      }
      final profile = await (widget.loadProfile ??
          PostDeeApiClient().loadLinkInBioProfile)();
      if (!mounted || generation != _generation || owner != _owner) {
        return false;
      }
      setState(() {
        _profile = profile;
        _loading = false;
        _hasLoaded = true;
      });
      return true;
    } catch (_) {
      if (!mounted || generation != _generation || owner != _owner) {
        return false;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
      return false;
    }
  }

  Future<void> _open(BuildContext context) async {
    if (widget.onOpen != null) {
      widget.onOpen!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const LinkInBioScreen(),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isThai = Localizations.localeOf(context).languageCode == 'th';
    const accent = Color(0xFF0EA5B7);
    final tint = accent.withValues(alpha: 0.14);
    final published =
        _profile?.isPublished == true && _profile?.publicUrl != null;
    final publication = linkInBioPublicationStatus(_profile,
        confirmed: _hasLoaded && !_loading && !_failed && _owner != null);
    final subtitle = _loading
        ? (isThai ? 'กำลังตรวจสอบลิงก์ร้าน' : 'Checking shop link')
        : _failed
            ? (isThai ? 'ตรวจสอบลิงก์ร้านไม่ได้' : 'Could not check shop link')
            : published
                ? (isThai ? 'เผยแพร่แล้ว' : 'Published')
                : _profile == null
                    ? (isThai ? 'สร้างหน้าร้าน' : 'Create your shop page')
                    : _profile!.isPublished
                        ? (isThai
                            ? 'ยังยืนยันการเผยแพร่ไม่ได้'
                            : 'Publication not confirmed')
                        : (isThai ? 'ยังไม่เผยแพร่' : 'Not published');
    final statusBadge = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          published
              ? (isThai ? 'จัดการ' : 'Manage')
              : (isThai ? 'เปิด' : 'Open'),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ),
    );

    return PostDeePressFeedback(
      child: Semantics(
        button: true,
        explicitChildNodes: true,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: tint,
                      ),
                      child: const Icon(Icons.link_rounded,
                          color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                              child: Text(
                            isThai ? 'ลิงก์หน้าโปรไฟล์' : 'Profile link',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          )),
                          const SizedBox(height: 2),
                          Row(children: [
                            LinkInBioPublicationDot(published: publication),
                            const SizedBox(width: 6),
                            Flexible(
                              child: _loading && !_hasLoaded
                                  ? Semantics(
                                      label: subtitle,
                                      child: PostDeeSkeleton(
                                        key: const ValueKey(
                                            'home-shop-skeleton'),
                                        width: 130,
                                        height: 11,
                                        animate:
                                            widget.isActive && _owner != null,
                                      ),
                                    )
                                  : Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    if (_failed)
                      IconButton(
                        key: const ValueKey('home-shop-retry'),
                        tooltip:
                            isThai ? 'ลองตรวจลิงก์ร้านใหม่' : 'Retry shop link',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded,
                            color: accent, size: 20),
                      )
                    else
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
    required this.onRetry,
    this.animateSkeleton = false,
  });

  final SubscriptionStatusResult? subscription;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final bool animateSkeleton;

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
    final effectiveLimit = subscription?.monthlyPostLimit;
    if (effectiveLimit != null) return effectiveLimit;
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

    final remainingPosts = subscription?.remainingPostsThisMonth;
    if (remainingPosts == null) {
      return isThai ? 'ยังไม่ทราบหน่วยคงเหลือ' : 'Remaining units unavailable';
    }
    final includedUnits = _planIncludedUnits();
    return isThai
        ? 'เหลือ $remainingPosts/$includedUnits หน่วย'
        : '$remainingPosts/$includedUnits units left';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final title = _planTitle(l10n);
    final subtitle = _planSubtitle(l10n);
    final isPro = subscription?.plan.toUpperCase() == 'PRO';
    final canSpendCredits =
        isPro || subscription?.plan.toUpperCase() == 'STARTER';
    final bankPosts = subscription?.addonPostUnits ?? 0;
    final bankCaptions = subscription?.addonAiCaptions ?? 0;
    final hasBank = bankPosts > 0 || bankCaptions > 0;
    final availablePosts = subscription?.availablePostUnits;
    final isThai = l10n.locale.languageCode == 'th';
    final showUpgrade =
        !isLoading && errorMessage == null && subscription != null && !isPro;

    return PostDeePressFeedback(
      child: Material(
        key: const ValueKey('home-plan-summary'),
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title,
                        key: const ValueKey('home-plan-title'),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary)),
                    if (isLoading && subscription == null && animateSkeleton)
                      PostDeeSkeleton(
                        key: const ValueKey('home-plan-skeleton'),
                        width: 145,
                        height: 12,
                        animate: animateSkeleton,
                      )
                    else
                      Text(subtitle,
                          key: const ValueKey('home-plan-subtitle'),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    if (hasBank)
                      Text(
                          isThai
                              ? 'เครดิตเติมคงเหลือ: โพสต์ $bankPosts หน่วย · AI $bankCaptions เครดิต'
                              : 'Purchased balance: $bankPosts post units · $bankCaptions AI credits',
                          key: const ValueKey('home-addon-balance'),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    if (hasBank && canSpendCredits && availablePosts != null)
                      Text(
                          isThai
                              ? 'โพสต์ได้รวม $availablePosts หน่วย'
                              : '$availablePosts post units available',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    if (hasBank && !canSpendCredits)
                      Text(
                          isThai
                              ? 'เครดิตยังอยู่ ใช้ได้เมื่อสมัคร Starter หรือ Pro'
                              : 'Credits remain available after subscribing to Starter or Pro',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              if (errorMessage != null)
                IconButton(
                  key: const ValueKey('home-plan-retry'),
                  onPressed: onRetry,
                  tooltip: l10n.locale.languageCode == 'th'
                      ? 'ลองตรวจแพ็กเกจใหม่'
                      : 'Retry package',
                  icon: Icon(Icons.refresh_rounded,
                      size: 20, color: AppTheme.accentCyanInk),
                )
              else if (showUpgrade)
                Text(
                  l10n.locale.languageCode == 'th' ? 'อัปเกรด' : 'Upgrade',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentCyanInk),
                )
              else
                Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 18),
            ]),
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
    required this.onCreatePost,
    this.now,
  });

  final List<PostSummaryResult> posts;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<PostSummaryResult> onOpenPost;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;
  final VoidCallback? onCreatePost;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    if (isLoading && posts.isEmpty) {
      return Column(
        children: [
          PostDeeSkeleton(
            width: double.infinity,
            height: 58,
            animate: isActive &&
                PostDeeAuthSessionStore.instance.session.stableUserId != null,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          PostDeeSkeleton(
            width: double.infinity,
            height: 58,
            animate: isActive &&
                PostDeeAuthSessionStore.instance.session.stableUserId != null,
          ),
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
      return _LatestPostsEmptyState(onCreatePost: onCreatePost);
    }

    return Column(
      children: [
        if (errorMessage != null) ...[
          _LatestPostsErrorState(message: errorMessage!, onRetry: onRetry),
          const SizedBox(height: 9),
        ],
        for (var index = 0; index < posts.length; index += 1) ...[
          _LatestPostRow(
            key: ValueKey(posts[index].id),
            post: posts[index],
            onTap: () => onOpenPost(posts[index]),
            isActive: isActive,
            createVideoThumbnailController: createVideoThumbnailController,
            now: now,
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
            PostDeePressFeedback(
                child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isThai ? 'ลองใหม่' : 'Try again'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onErrorContainer,
                minimumSize: const Size(48, 48),
              ),
            )),
          ],
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                Localizations.localeOf(context).languageCode == 'th'
                    ? 'ยังไม่มีโพสต์'
                    : 'No posts yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                Localizations.localeOf(context).languageCode == 'th'
                    ? 'โพสต์ที่สร้างจะแสดงที่นี่'
                    : 'Your posts will appear here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              PostDeePressFeedback(
                  enabled: onCreatePost != null,
                  child: TextButton(
                    key: const ValueKey('home-empty-create-post'),
                    onPressed: onCreatePost,
                    child: Text(
                        Localizations.localeOf(context).languageCode == 'th'
                            ? 'สร้างโพสต์'
                            : 'Create post'),
                  )),
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
    this.now,
  });

  final PostSummaryResult post;
  final VoidCallback onTap;
  final bool isActive;
  final HomeVideoThumbnailControllerFactory? createVideoThumbnailController;
  final DateTime Function()? now;

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
  ({String label, Color bg, Color ink}) _statusInfo(String languageCode) {
    final isThai = languageCode == 'th';
    const publishedBg = Color(0xFFE2F3EA);
    const publishedInk = Color(0xFF0E9F6E);
    const scheduledBg = Color(0xFFFBEFD7);
    const scheduledInk = Color(0xFFB5740B);
    const draftBg = Color(0xFFEEF2EF);
    const draftInk = Color(0xFF778276);

    if (hasUnconfirmedDeliveryOutcome(post.platformResults)) {
      return (
        label: isThai ? 'ผลยังไม่ยืนยัน' : 'Delivery unconfirmed',
        bg: draftBg,
        ink: draftInk,
      );
    }

    // Some providers finish before others and the API may omit pending rows.
    // The aggregate post is still sending until its actual status changes.
    if (post.status.toUpperCase() == 'PUBLISHING') {
      return (
        label: isThai ? 'กำลังส่ง' : 'Sending',
        bg: publishedBg,
        ink: publishedInk
      );
    }

    final deliveryLabel = aggregatePostDeliveryOutcomeLabel(
      post.platformResults,
      compact: true,
      languageCode: languageCode,
    );
    if (deliveryLabel != null) {
      return (
        label: deliveryLabel,
        bg: publishedBg,
        ink: publishedInk,
      );
    }

    return switch (post.status.toUpperCase()) {
      'PUBLISHED' => (
          label: isThai ? 'เผยแพร่' : 'Published',
          bg: publishedBg,
          ink: publishedInk
        ),
      'PARTIAL_PUBLISHED' => (
          label: isThai ? 'ส่งบางส่วน' : 'Partially delivered',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      'PUBLISHING' => (
          label: isThai ? 'กำลังส่ง' : 'Sending',
          bg: publishedBg,
          ink: publishedInk,
        ),
      'FAILED' => (
          label: isThai ? 'ล้มเหลว' : 'Failed',
          bg: const Color(0xFFFDE4E4),
          ink: const Color(0xFFDC2626),
        ),
      'QUEUED' when post.scheduledAt != null => (
          label: isThai ? 'รอส่ง' : 'Scheduled',
          bg: scheduledBg,
          ink: scheduledInk,
        ),
      _ => (label: isThai ? 'รอส่ง' : 'Queued', bg: draftBg, ink: draftInk),
    };
  }

  String _relativeTime(String languageCode) {
    final isThai = languageCode == 'th';
    String englishTime(int count, String unit, {bool future = false}) {
      final duration = '$count $unit${count == 1 ? '' : 's'}';
      return future ? 'in $duration' : '$duration ago';
    }

    final reference = post.publishedAt ?? post.scheduledAt ?? post.createdAt;
    final currentTime = (now ?? DateTime.now)();
    final diff = currentTime.difference(reference.toLocal());

    if (diff.isNegative) {
      final ahead = reference.toLocal().difference(currentTime);
      if (ahead.inDays >= 1) {
        return isThai
            ? 'อีก ${ahead.inDays} วัน'
            : englishTime(ahead.inDays, 'day', future: true);
      }
      if (ahead.inHours >= 1) {
        return isThai
            ? 'อีก ${ahead.inHours} ชม.'
            : englishTime(ahead.inHours, 'hour', future: true);
      }
      final minutes = ahead.inMinutes.clamp(1, 59);
      return isThai
          ? 'อีก $minutes นาที'
          : englishTime(minutes, 'minute', future: true);
    }

    if (diff.inDays >= 1) {
      return isThai
          ? '${diff.inDays} วันก่อน'
          : englishTime(diff.inDays, 'day');
    }
    if (diff.inHours >= 1) {
      return isThai
          ? '${diff.inHours} ชม.ก่อน'
          : englishTime(diff.inHours, 'hour');
    }
    if (diff.inMinutes >= 1) {
      return isThai
          ? '${diff.inMinutes} นาทีก่อน'
          : englishTime(diff.inMinutes, 'minute');
    }
    return isThai ? 'เมื่อสักครู่' : 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final platforms =
        post.platforms.map(_platformFor).whereType<SocialPlatform>().toList();
    final languageCode = Localizations.localeOf(context).languageCode;
    final status = _statusInfo(languageCode);
    final unconfirmed = hasUnconfirmedDeliveryOutcome(post.platformResults);
    final sending = post.status.toUpperCase() == 'PUBLISHING' && !unconfirmed;
    final stackStatus = MediaQuery.textScalerOf(context).scale(13.5) > 18;
    final statusBadge = ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: sending || stackStatus
              ? 190
              : languageCode == 'th'
                  ? 108
                  : 160),
      child: _StatusPill(
        label: status.label,
        bg: status.bg,
        ink: status.ink,
        sending: sending,
        icon: post.status.toUpperCase() == 'PUBLISHED' && !unconfirmed
            ? Icons.check_circle_outline_rounded
            : null,
      ),
    );
    final caption = post.caption.trim();
    final title = caption.isEmpty ? _relativeTime(languageCode) : caption;
    final sub = platforms.isEmpty
        ? _relativeTime(languageCode)
        : platforms.map((p) => p.label).join(' · ');

    return Semantics(
      button: true,
      label: title,
      child: PostDeePublishingMotion(
        key: ValueKey('home-publishing-${post.id}'),
        sending: sending,
        animate: isActive,
        child: PostDeePressFeedback(
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.glass,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: sending
                        ? status.ink.withValues(alpha: .25)
                        : AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF122018).withValues(alpha: 0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: sending
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
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
                                maxLines: sending ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (!sending) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    for (final platform
                                        in platforms.take(4)) ...[
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 3),
                                        child: SocialPlatformLogo(
                                          platform: platform,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                    if (platforms.isNotEmpty)
                                      const SizedBox(width: 3),
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
                              if (sending || stackStatus) ...[
                                const SizedBox(height: 6),
                                statusBadge,
                              ],
                            ],
                          ),
                        ),
                        if (!sending && !stackStatus) ...[
                          const SizedBox(width: 6),
                          statusBadge,
                        ],
                      ],
                    ),
                  ),
                  if (sending) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          KeyedSubtree(
                            key: ValueKey('home-publishing-rail-${post.id}'),
                            child: PostDeePublishingRail(color: status.ink),
                          ),
                          const SizedBox(height: 10),
                          KeyedSubtree(
                            key:
                                ValueKey('home-publishing-channels-${post.id}'),
                            child: PostDeePlatformDeliveryRow(
                              platforms: post.platforms,
                              results: post.platformResults,
                              languageCode: languageCode,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
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

class _LatestPostVideoPreviewState extends State<_LatestPostVideoPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isReady = false;
  int _generation = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _startController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _stopController();
    if (_foreground) _startController();
    if (mounted) setState(() {});
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
      _foreground &&
      generation == _generation &&
      identical(controller, _controller);

  void _startController() {
    if (!widget.isActive || !_foreground || widget.videoUrl == null) return;
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
    WidgetsBinding.instance.removeObserver(this);
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
  const _StatusPill(
      {required this.label,
      required this.bg,
      required this.ink,
      this.sending = false,
      this.icon});

  final String label;
  final Color bg;
  final Color ink;
  final bool sending;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return PostDeePublishingBadge(
      label: label,
      background: bg,
      foreground: ink,
      sending: sending,
      icon: icon,
      fontSize: 10.5,
    );
  }
}
