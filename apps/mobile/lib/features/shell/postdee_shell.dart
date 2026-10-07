import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/language_controller.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../analytics/analytics_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/firebase_apple_auth_gateway.dart';
import '../auth/firebase_account_access_revoker.dart';
import '../auth/firebase_email_auth_gateway.dart';
import '../auth/firebase_google_auth_gateway.dart';
import '../auth/firebase_id_token_refresher.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../link_in_bio/link_in_bio_draft_store.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../notifications/firebase_push_messaging_gateway.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/push_messaging_gateway.dart';
import '../onboarding/onboarding_flow.dart';
import '../profile/profile_screen.dart';
import '../posts/post_detail_screen.dart';
import '../shared/postdee_undo_toast.dart';
import '../templates/templates_screen.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/publish_draft_store.dart';
import '../uploader/publish_draft_store_factory.dart';
import '../uploader/video_picker_service.dart';

typedef AccountDeleter = Future<void> Function();
typedef AccountDeletionReadinessChecker = Future<bool> Function();
typedef AccountLocalPublishDraftDeleter = Future<void> Function();
typedef AccountLocalPublishDraftDeleterLoader
    = Future<AccountLocalPublishDraftDeleter?> Function();

class PostDeeShell extends StatefulWidget {
  const PostDeeShell({
    super.key,
    required this.languageController,
    this.firebaseBootstrapResult,
    this.themeController,
    this.loadScheduledPosts,
    this.loadSubscription,
    this.loadRecentPosts,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.createPost,
    this.checkPublishingReadiness,
    this.loadSocialConnections,
    this.deleteAccount,
    this.checkAccountDeletionReady,
    this.deleteLocalPublishDrafts,
    this.loadLocalPublishDraftDeleter,
    this.uploaderDraftStore,
    this.accountAccessRevoker,
    this.pushMessagingGateway,
  });

  final FirebaseBootstrapResult? firebaseBootstrapResult;
  final PostDeeLanguageController languageController;
  final PostDeeThemeController? themeController;
  final ScheduledPostsLoader? loadScheduledPosts;
  final UploaderSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final UploaderVideoPicker? pickVideo;
  final UploaderUploadCreator? createUpload;
  final UploaderVideoUploader? uploadVideoFile;
  final UploaderPostCreator? createPost;
  final UploaderPublishingReadinessChecker? checkPublishingReadiness;
  final UploaderConnectionsLoader? loadSocialConnections;
  final AccountDeleter? deleteAccount;
  final AccountDeletionReadinessChecker? checkAccountDeletionReady;
  final AccountLocalPublishDraftDeleter? deleteLocalPublishDrafts;
  final AccountLocalPublishDraftDeleterLoader? loadLocalPublishDraftDeleter;
  final PublishDraftStore? uploaderDraftStore;
  final AccountAccessRevoker? accountAccessRevoker;
  final PushMessagingGateway? pushMessagingGateway;

  @override
  State<PostDeeShell> createState() => _PostDeeShellState();
}

class _PostDeeShellState extends State<PostDeeShell> {
  static const _onboardingStore = OnboardingSeenStore();

  late final PostDeeAuthController _authController;
  late final AccountAccessRevoker _accountAccessRevoker;
  late final PushMessagingGateway _pushMessagingGateway;
  int _selectedIndex = 0;
  int _calendarRefreshToken = 0;
  bool _isDeletingAccount = false;
  MaterialPageRoute<void>? _composerRoute;
  String? _composerOwnerUserId;

  // null = still loading; the main shell shows meanwhile so the flow never
  // blocks startup. true only on a genuine first run.
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _loadOnboardingSeen();
    _authController = PostDeeAuthController(
      setupMessage: describeFirebaseAuthSetup(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      googleAuthGateway: createGoogleAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      emailAuthGateway: createEmailAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      appleAuthGateway: createAppleAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    _authController.addListener(_handleComposerOwnerChanged);
    _accountAccessRevoker = widget.accountAccessRevoker ??
        createAccountAccessRevokerFromConfig(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
    // With Firebase enabled, fetch a fresh ID token per request so API calls
    // never carry an expired token (Firebase tokens expire ~1 hour after sign
    // in). In mock/dev the cached session token is used instead.
    if (AppConfig.enableFirebaseAuth &&
        (widget.firebaseBootstrapResult?.isInitialized ?? false)) {
      PostDeeAuthSessionStore.instance
          .setAuthCredentialRefresher(firebaseAuthCredentialRefresher);
    }
    // Start push delivery. The factory returns a no-op gateway unless Firebase
    // is enabled and initialized, so this is harmless in dev and tests.
    _pushMessagingGateway = widget.pushMessagingGateway ??
        createPushMessagingGatewayFromConfig(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
          // Send the FCM token to the backend so it can target this device.
          onToken: (token) => unawaited(
            PostDeeApiClient().registerDeviceToken(token).catchError((_) {}),
          ),
        );
  }

  List<Widget> _buildScreens() => [
        HomeScreen(
          isActive: _selectedIndex == 0,
          loadSubscription: widget.loadSubscription,
          loadRecentPosts: widget.loadRecentPosts,
          onViewAllPosts: () => _selectTab(3),
          onOpenNotifications: _openNotifications,
          onOpenProfile: () => _selectTab(5),
          onOpenLinkInBio: () => _selectTab(1),
          userName: _authController.session.displayName,
        ),
        LinkInBioScreen(
          key: ValueKey(_authController.session.stableUserId),
          onBack: () => _selectTab(0),
          embeddedInTab: true,
          isActive: _selectedIndex == 1,
        ),
        const SizedBox.shrink(),
        CalendarScreen(
          refreshToken: _calendarRefreshToken,
          isActive: _selectedIndex == 3,
          loadScheduledPosts: widget.loadScheduledPosts,
          onAddPost: () => _selectTab(2),
          onOpenPostDetail: _openCalendarPostDetail,
        ),
        const AnalyticsScreen(showTitle: true),
        // Profile is the 5th nav tab per the design handoff (no pushed route).
        ProfileScreen(
          languageController: widget.languageController,
          themeController:
              widget.themeController ?? PostDeeThemeController.instance,
          onOpenTemplates: _openTemplates,
          onDeleteAccount: _handleDeleteAccount,
          isDeletingAccount: _isDeletingAccount,
          onSignOut: _authController.signOut,
        ),
      ];

  @override
  void dispose() {
    unawaited(_pushMessagingGateway.dispose());
    _authController.removeListener(_handleComposerOwnerChanged);
    _authController.dispose();
    super.dispose();
  }

  void _openNotifications() {
    unawaited(_openNotificationsAfterPermission());
  }

  Future<void> _openNotificationsAfterPermission() async {
    // Ask for notification permission only after the user taps the bell. This
    // gives the system prompt clear context instead of interrupting sign-in.
    await _pushMessagingGateway.initialize();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const NotificationsScreen(),
      ),
    );
  }

  void _openTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final l10n = PostDeeLocalizations.of(context);

          return Scaffold(
            appBar: AppBar(
              title: Text(
                l10n.templatesTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            body: const SafeArea(child: TemplatesScreen()),
          );
        },
      ),
    );
  }

  void _selectTab(int index) {
    if (index == 2) {
      unawaited(_openPostComposer());
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openPostComposer() async {
    if (_composerRoute != null || !_authController.session.isSignedIn) return;

    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/create-post'),
      builder: (context) => DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: UploaderScreen(
              fullScreen: true,
              draftStore: widget.uploaderDraftStore,
              loadSubscription: widget.loadSubscription,
              pickVideo: widget.pickVideo,
              createUpload: widget.createUpload,
              uploadVideoFile: widget.uploadVideoFile,
              createPost: widget.createPost,
              checkPublishingReadiness: widget.checkPublishingReadiness,
              loadSocialConnections: widget.loadSocialConnections,
              onScheduledPostCreated: (post) {
                if (_composerBelongsToCurrentOwner(route)) {
                  _handleScheduledPostCreated(post);
                }
              },
              onPublishFinished: () => _finishPostComposer(route, 0),
              onViewAnalytics: () => _finishPostComposer(route, 4),
            ),
          ),
        ),
      ),
    );
    _composerRoute = route;
    _composerOwnerUserId = _authController.session.stableUserId;
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (identical(_composerRoute, route)) {
        _composerRoute = null;
        _composerOwnerUserId = null;
      }
    }
  }

  void _finishPostComposer(MaterialPageRoute<void> route, int targetIndex) {
    if (!route.isCurrent || !_composerBelongsToCurrentOwner(route)) {
      return;
    }
    route.navigator?.pop();
    _selectTab(targetIndex);
  }

  bool _composerBelongsToCurrentOwner(MaterialPageRoute<void> route) =>
      mounted &&
      identical(_composerRoute, route) &&
      route.isActive &&
      _authController.session.isSignedIn &&
      _authController.session.stableUserId == _composerOwnerUserId;

  void _handleComposerOwnerChanged() {
    final route = _composerRoute;
    if (route == null ||
        (_authController.session.isSignedIn &&
            _authController.session.stableUserId == _composerOwnerUserId)) {
      return;
    }
    final navigator = route.navigator;
    if (navigator == null || !route.isActive) return;
    navigator.popUntil(
        (candidate) => identical(candidate, route) || candidate.isFirst);
    if (route.isCurrent) navigator.pop();
  }

  void _handleScheduledPostCreated(QueuedPostResult _) {
    setState(() {
      _calendarRefreshToken += 1;
      _selectedIndex = 3;
    });
  }

  Future<void> _openCalendarPostDetail(ScheduledPostResult post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PostDetailScreen(
          post: PostSummaryResult(
            id: post.id,
            caption: post.caption,
            videoS3Key: post.videoS3Key,
            platforms: post.platforms,
            status: post.status,
            createdAt: post.createdAt,
            scheduledAt: post.scheduledAt,
            publishedAt: post.publishedAt,
            platformResults: post.platformResults,
          ),
        ),
      ),
    );

    if (changed == true && mounted) {
      setState(() => _calendarRefreshToken += 1);
    }
  }

  Future<void> _handleDeleteAccount() async {
    if (_isDeletingAccount) {
      return;
    }

    setState(() => _isDeletingAccount = true);
    // Permanently deletes the account via DELETE /account, then signs out so the
    // user lands back on the login gate. Only sign out after the delete succeeds.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final apiClient = PostDeeApiClient();
    final linkInBioOwnerId = _authController.session.stableUserId;
    final deleteAccount = widget.deleteAccount ?? apiClient.deleteAccount;
    final checkAccountDeletionReady = widget.checkAccountDeletionReady ??
        (widget.deleteAccount == null
            ? apiClient.checkAccountDeletionReady
            : () async => false);
    var localDraftCleanupFailed = false;
    final localDraftDeleterFuture = widget.deleteLocalPublishDrafts != null
        ? Future<AccountLocalPublishDraftDeleter?>.value(
            widget.deleteLocalPublishDrafts,
          )
        : (widget.loadLocalPublishDraftDeleter ??
            () async {
              final store = await createPublishDraftStoreForSession();
              return store?.deleteAllDrafts;
            })();

    try {
      final identityAlreadyDeleted = await checkAccountDeletionReady();
      if (!identityAlreadyDeleted) {
        await _accountAccessRevoker.revokeBeforeAccountDeletion();
      }
      await deleteAccount();
      try {
        final deleteLocalPublishDrafts = await localDraftDeleterFuture;
        await deleteLocalPublishDrafts?.call();
      } catch (_) {
        // The server account is already deleted. Continue signing out, but
        // tell the user how to remove any local files the OS would not delete.
        localDraftCleanupFailed = true;
      }

      if (linkInBioOwnerId != null) {
        try {
          await clearLinkInBioDraftForUser(linkInBioOwnerId);
        } catch (_) {
          localDraftCleanupFailed = true;
        }
      }

      if (!mounted) {
        return;
      }

      navigator.popUntil((route) => route.isFirst);
      try {
        await _authController.signOut();
      } catch (_) {
        // The controller always clears the local session in a finally block.
      }
      if (!mounted) {
        return;
      }
      // The auth change swaps the signed-in Scaffold for the login Scaffold.
      // Wait until that frame is mounted so the success toast attaches to the
      // screen the user actually lands on instead of the Scaffold being removed.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      showPostDeeUndoToast(
        context,
        message: localDraftCleanupFailed
            ? 'ลบบัญชีแล้ว แต่ลบร่างในเครื่องไม่ครบ กรุณาล้างข้อมูลแอป'
            : 'ลบบัญชีและออกจากระบบแล้ว',
      );
    } on AccountAccessRevocationException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on ApiException catch (error) {
      final message = switch (error.code) {
        'ACCOUNT_DELETION_UNAVAILABLE' =>
          'ระบบลบบัญชียังไม่พร้อม กรุณาลองใหม่ภายหลัง',
        'ACCOUNT_MEDIA_CLEANUP_UNAVAILABLE' =>
          'ระบบลบวิดีโอยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
        'ACCOUNT_MEDIA_CLEANUP_FAILED' =>
          'ลบวิดีโอยังไม่สำเร็จ บัญชีของคุณยังอยู่ กรุณาลองใหม่',
        'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE' =>
          'ระบบถอนการเชื่อมต่อโซเชียลยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
        'ACCOUNT_SOCIAL_CLEANUP_FAILED' =>
          'ถอนการเชื่อมต่อโซเชียลยังไม่ครบ บัญชียังไม่ถูกลบ กรุณาลองใหม่',
        'ACCOUNT_IDENTITY_DELETE_FAILED' =>
          'ลบข้อมูลแล้ว แต่ยังปิดการเข้าสู่ระบบไม่สำเร็จ กรุณากดลบบัญชีอีกครั้ง',
        'ACCOUNT_REAUTHENTICATION_REQUIRED' =>
          'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ จากนั้นลบบัญชีภายใน 5 นาที',
        _ => error.message,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ลบบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  Future<void> _loadOnboardingSeen() async {
    final seen = await _onboardingStore.loadSeen();
    if (!mounted) return;
    setState(() => _showOnboarding = !seen);
  }

  void _finishOnboarding() {
    unawaited(_onboardingStore.markSeen());
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authController,
      builder: (context, _) {
        if (!_authController.session.isSignedIn) {
          return _LoginGate(controller: _authController);
        }

        if (_showOnboarding == true) {
          return OnboardingFlow(onFinished: _finishOnboarding);
        }

        return _buildMainShell(context);
      },
    );
  }

  Widget _buildMainShell(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);

    return DecoratedBox(
      decoration: AppTheme.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The docked nav overlays the content; tab
        // screens reserve AppTheme.navOverlap at the bottom to scroll clear.
        extendBody: true,
        body: SafeArea(
          top: true,
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: _buildScreens(),
          ),
        ),
        bottomNavigationBar: _PostDeeBottomNav(
          currentIndex: _selectedIndex,
          onHome: () => _selectTab(0),
          onCalendar: () => _selectTab(3),
          onCreate: () => _selectTab(2),
          onLinkInBio: () => _selectTab(1),
          onProfile: () => _selectTab(5),
          l10n: l10n,
        ),
      ),
    );
  }
}

class _PostDeeBottomNav extends StatelessWidget {
  const _PostDeeBottomNav({
    required this.currentIndex,
    required this.onHome,
    required this.onCalendar,
    required this.onCreate,
    required this.onLinkInBio,
    required this.onProfile,
    required this.l10n,
  });

  final int currentIndex;
  final VoidCallback onHome;
  final VoidCallback onCalendar;
  final VoidCallback onCreate;
  final VoidCallback onLinkInBio;
  final VoidCallback onProfile;
  final PostDeeLocalizations l10n;

  // Includes 8 dp above the surface for the raised upload action.
  static const _height = 84.0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // Screens without an AppBar also inherit status-bar contrast here.
        statusBarIconBrightness:
            AppTheme.isLightMode ? Brightness.dark : Brightness.light,
        statusBarBrightness:
            AppTheme.isLightMode ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: AppTheme.navSurface,
        systemNavigationBarDividerColor: AppTheme.navSurface,
        systemNavigationBarIconBrightness:
            AppTheme.isLightMode ? Brightness.dark : Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: DecoratedBox(
        key: const ValueKey('postdee-reference-bottom-nav'),
        decoration: const BoxDecoration(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 8,
              child: Material(
                key: const ValueKey('postdee-nav-surface'),
                color: AppTheme.navSurface,
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ReferenceNavButton(
                        label: l10n.navigationHome,
                        icon: Icons.home_outlined,
                        selected: currentIndex == 0,
                        onPressed: onHome,
                      ),
                    ),
                    Expanded(
                      child: _ReferenceNavButton(
                        label: l10n.captionTab,
                        icon: Icons.calendar_today_outlined,
                        selected: currentIndex == 3,
                        onPressed: onCalendar,
                      ),
                    ),
                    Expanded(
                      child: _ReferenceCreateNavButton(
                        label: l10n.createPostTab,
                        selected: currentIndex == 2,
                        onPressed: onCreate,
                      ),
                    ),
                    Expanded(
                      child: _ReferenceNavButton(
                        label: l10n.navigationStoreLink,
                        icon: Icons.link_outlined,
                        selected: currentIndex == 1,
                        onPressed: onLinkInBio,
                      ),
                    ),
                    Expanded(
                      child: _ReferenceNavButton(
                        label: l10n.navigationAccount,
                        icon: Icons.person_outline_rounded,
                        selected: currentIndex == 5,
                        onPressed: onProfile,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceNavButton extends StatelessWidget {
  const _ReferenceNavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.isCreateAction = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final bool isCreateAction;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.navActive : AppTheme.textSecondary;

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: _PostDeeBottomNav._height,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: isCreateAction
                            ? Transform.translate(
                                offset: const Offset(0, -8),
                                child: DecoratedBox(
                                  key: const ValueKey(
                                      'postdee-nav-create-surface'),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child:
                                      Icon(icon, color: Colors.white, size: 25),
                                ),
                              )
                            : Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(height: 1),
                      if (isCreateAction)
                        const SizedBox(height: 15)
                      else
                        _ReferenceNavLabel(label: label, selected: selected),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 4,
                        height: 4,
                        child: selected
                            ? DecoratedBox(
                                key: const ValueKey(
                                    'postdee-nav-selected-indicator'),
                                decoration: BoxDecoration(
                                  color: AppTheme.navActive,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                    ],
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

class _ReferenceCreateNavButton extends StatelessWidget {
  const _ReferenceCreateNavButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _ReferenceNavButton(
      label: label,
      icon: Icons.ios_share_outlined,
      selected: selected,
      onPressed: onPressed,
      isCreateAction: true,
    );
  }
}

class _ReferenceNavLabel extends StatelessWidget {
  const _ReferenceNavLabel({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        width: double.infinity,
        height: 15,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? AppTheme.navActive : AppTheme.textSecondary,
              fontSize: 11,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginGate extends StatelessWidget {
  const _LoginGate({required this.controller});

  final PostDeeAuthController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final isThai = l10n.locale.languageCode == 'th';
    final setupMessage = controller.setupMessage ?? '';
    final helperMessage = setupMessage.toLowerCase().contains('local mock auth')
        ? l10n.loginMockHelper
        : setupMessage.isNotEmpty
            ? setupMessage
            : l10n.loginDefaultHelper;
    final heroTitle = isThai ? 'ลงครั้งเดียว ขายได้ทุกที่' : l10n.loginTitle;
    final heroSubtitle = isThai
        ? 'โพสต์วิดีโอเดียวไป TikTok, Shorts,\nReels และ Facebook พร้อมกัน'
        : l10n.loginSubtitle;
    final requirement = isThai
        ? 'เชื่อมต่อบัญชีเพียงครั้งเดียว ปลอดภัย ไม่เก็บรหัสผ่านของคุณ'
        : l10n.loginRequirementMessage;
    final googleLabel = isThai ? 'เข้าสู่ระบบด้วย Google' : l10n.loginButton;
    final emailLabel = isThai ? 'เข้าสู่ระบบด้วยอีเมล' : 'Sign in with email';

    return Scaffold(
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: const ValueKey('login-brand-mark-box'),
                          width: 64,
                          height: 64,
                          child: Transform.scale(
                            scale: 1.55,
                            child: Image.asset(
                              'assets/images/brand/postdee_mark.png',
                              key: const ValueKey('login-brand-mark'),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(
                          key: ValueKey('login-brand-gap'),
                          width: 4,
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Post',
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                              TextSpan(
                                text: 'Dee',
                                style: TextStyle(color: AppTheme.accentCyanInk),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.64,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    heroTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.25,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    heroSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 38),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.glass,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF122018).withValues(alpha: 0.04),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                        BoxShadow(
                          color:
                              const Color(0xFF12281C).withValues(alpha: 0.18),
                          blurRadius: 40,
                          spreadRadius: -22,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.glassDeep,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    color: AppTheme.accentCyanInk,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Text(
                                      requirement,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.5,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 54),
                            child: FilledButton(
                              onPressed: controller.isSigningIn
                                  ? null
                                  : controller.signInWithGoogle,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppTheme.accent,
                                disabledForegroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Image.asset(
                                      'assets/images/brand/google_sign_in_light_square.png',
                                      key: const ValueKey(
                                        'google-sign-in-logo',
                                      ),
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      controller.isSigningIn
                                          ? l10n.signingInButton
                                          : googleLabel,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 11),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 54),
                            child: OutlinedButton(
                              key: const ValueKey('login-email-sign-in'),
                              onPressed: controller.isSigningIn
                                  ? null
                                  : () => showDialog<void>(
                                        context: context,
                                        builder: (context) =>
                                            _EmailSignInDialog(
                                          controller: controller,
                                        ),
                                      ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppTheme.border),
                                foregroundColor: AppTheme.textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.mail_outline,
                                    size: 21,
                                    color: AppTheme.textPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      emailLabel,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            helperMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          if (controller.errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              controller.errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: isThai
                              ? 'การเข้าใช้งานถือว่ายอมรับ'
                              : 'By continuing you accept our ',
                        ),
                        TextSpan(
                          text: isThai
                              ? 'เงื่อนไขการใช้บริการ'
                              : 'Terms of Service',
                          style: TextStyle(
                            color: AppTheme.accentCyanInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: isThai ? '\nและ' : '\nand '),
                        TextSpan(
                          text: isThai
                              ? 'นโยบายความเป็นส่วนตัว'
                              : 'Privacy Policy',
                          style: TextStyle(
                            color: AppTheme.accentCyanInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: AppTheme.textMuted,
                    ),
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

class _EmailSignInDialog extends StatefulWidget {
  const _EmailSignInDialog({required this.controller});

  final PostDeeAuthController controller;

  @override
  State<_EmailSignInDialog> createState() => _EmailSignInDialogState();
}

class _EmailSignInDialogState extends State<_EmailSignInDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _createAccount = false;
  var _isSubmitting = false;
  String? _validationMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!email.contains('@')) {
      setState(() => _validationMessage = 'กรอกอีเมลให้ถูกต้อง');
      return;
    }

    if (password.length < 6) {
      setState(() => _validationMessage = 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _validationMessage = null;
    });

    await widget.controller.signInWithEmail(
      email: email,
      password: password,
      createAccount: _createAccount,
    );

    if (!mounted) {
      return;
    }

    if (widget.controller.session.isSignedIn) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSubmitting = false;
      _validationMessage = widget.controller.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _createAccount ? 'สร้างบัญชีด้วยอีเมล' : 'เข้าสู่ระบบด้วยอีเมล';
    final submitLabel = _createAccount ? 'สร้างบัญชี' : 'เข้าสู่ระบบ';

    return AlertDialog(
      key: const ValueKey('email-sign-in-form'),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'อีเมล',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_isSubmitting,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'รหัสผ่าน',
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _validationMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _createAccount = !_createAccount),
              child: Text(
                _createAccount
                    ? 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'
                    : 'ยังไม่มีบัญชี? สร้างบัญชีใหม่',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(_isSubmitting ? 'กำลังดำเนินการ...' : submitLabel),
        ),
      ],
    );
  }
}
