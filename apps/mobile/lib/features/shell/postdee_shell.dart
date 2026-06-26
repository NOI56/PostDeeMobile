import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/language_controller.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../ai_editing/ai_editing_screen.dart';
import '../analytics/analytics_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/firebase_apple_auth_gateway.dart';
import '../auth/firebase_google_auth_gateway.dart';
import '../auth/firebase_id_token_refresher.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../notifications/firebase_push_messaging_gateway.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/push_messaging_gateway.dart';
import '../profile/profile_screen.dart';
import '../templates/templates_screen.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/video_picker_service.dart';

typedef AccountDeleter = Future<void> Function();

class PostDeeShell extends StatefulWidget {
  const PostDeeShell({
    super.key,
    required this.languageController,
    this.firebaseBootstrapResult,
    this.themeController,
    this.loadScheduledPosts,
    this.loadSubscription,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.createPost,
    this.deleteAccount,
    this.pushMessagingGateway,
  });

  final FirebaseBootstrapResult? firebaseBootstrapResult;
  final PostDeeLanguageController languageController;
  final PostDeeThemeController? themeController;
  final ScheduledPostsLoader? loadScheduledPosts;
  final UploaderSubscriptionLoader? loadSubscription;
  final UploaderVideoPicker? pickVideo;
  final UploaderUploadCreator? createUpload;
  final UploaderVideoUploader? uploadVideoFile;
  final UploaderPostCreator? createPost;
  final AccountDeleter? deleteAccount;
  final PushMessagingGateway? pushMessagingGateway;

  @override
  State<PostDeeShell> createState() => _PostDeeShellState();
}

class _PostDeeShellState extends State<PostDeeShell> {
  late final PostDeeAuthController _authController;
  late final PushMessagingGateway _pushMessagingGateway;
  int _selectedIndex = 0;
  int _calendarRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _authController = PostDeeAuthController(
      setupMessage: describeFirebaseAuthSetup(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      googleAuthGateway: createGoogleAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      appleAuthGateway: createAppleAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    // With Firebase enabled, fetch a fresh ID token per request so API calls
    // never carry an expired token (Firebase tokens expire ~1 hour after sign
    // in). In mock/dev the cached session token is used instead.
    if (AppConfig.enableFirebaseAuth &&
        (widget.firebaseBootstrapResult?.isInitialized ?? false)) {
      PostDeeAuthSessionStore.instance
          .setIdTokenRefresher(firebaseIdTokenRefresher);
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
    unawaited(_pushMessagingGateway.initialize());
  }

  List<Widget> _buildScreens() => [
        HomeScreen(
          loadSubscription: widget.loadSubscription,
          onViewAllPosts: () => _selectTab(3),
          userName: _authController.session.displayName,
        ),
        const AiEditingScreen(),
        UploaderScreen(
          loadSubscription: widget.loadSubscription,
          pickVideo: widget.pickVideo,
          createUpload: widget.createUpload,
          uploadVideoFile: widget.uploadVideoFile,
          createPost: widget.createPost,
          onScheduledPostCreated: _handleScheduledPostCreated,
        ),
        CalendarScreen(
          refreshToken: _calendarRefreshToken,
          loadScheduledPosts: widget.loadScheduledPosts,
          onAddPost: () => _selectTab(2),
        ),
        const AnalyticsScreen(showTitle: false),
      ];

  @override
  void dispose() {
    unawaited(_pushMessagingGateway.dispose());
    _authController.dispose();
    super.dispose();
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const NotificationsScreen(),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final l10n = PostDeeLocalizations.of(context);

          return Scaffold(
            appBar: AppBar(
              title: Text(
                l10n.profileTab,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ShellIconButton(
                    label: l10n.userAccountAction,
                    icon: Icons.logout,
                    onPressed: _signOutFromPushedRoute,
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: ProfileScreen(
                languageController: widget.languageController,
                themeController:
                    widget.themeController ?? PostDeeThemeController.instance,
                onOpenTemplates: _openTemplates,
                onDeleteAccount: _handleDeleteAccount,
              ),
            ),
          );
        },
      ),
    );
  }

  // Sign out from a pushed route (e.g. profile): drop back to the shell first so
  // the login gate isn't left hidden underneath the route.
  void _signOutFromPushedRoute() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _authController.signOut();
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
    setState(() => _selectedIndex = index);
  }

  void _handleScheduledPostCreated(QueuedPostResult _) {
    setState(() {
      _calendarRefreshToken += 1;
      _selectedIndex = 3;
    });
  }

  void _saveDraft() {
    final l10n = PostDeeLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.uploadDraftSavedMessage)),
    );
  }

  Future<void> _handleDeleteAccount() async {
    // Permanently deletes the account via DELETE /account, then signs out so the
    // user lands back on the login gate. Only sign out after the delete succeeds.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final deleteAccount =
        widget.deleteAccount ?? PostDeeApiClient().deleteAccount;

    try {
      await deleteAccount();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ลบบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    navigator.popUntil((route) => route.isFirst);
    _authController.signOut();
    messenger.showSnackBar(
      const SnackBar(content: Text('ลบบัญชีและออกจากระบบแล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authController,
      builder: (context, _) {
        if (!_authController.session.isSignedIn) {
          return _LoginGate(controller: _authController);
        }

        return _buildMainShell(context);
      },
    );
  }

  Widget _buildMainShell(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);

    // Paint one continuous gradient across the whole screen (status bar + app
    // bar included) and keep the Scaffold transparent, so the top blends into
    // the body with no hard seam.
    return DecoratedBox(
      decoration: AppTheme.screenBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(l10n),
        body: SafeArea(
          top: false,
          bottom: false,
          child: IndexedStack(
            index: _selectedIndex,
            children: _buildScreens(),
          ),
        ),
        bottomNavigationBar: _PostDeeBottomNav(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          l10n: l10n,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(PostDeeLocalizations l10n) {
    return switch (_selectedIndex) {
      0 => _HomeAppBar(
          notificationsLabel: l10n.notificationsAction,
          accountLabel: l10n.userAccountAction,
          onAccountPressed: _openProfile,
          onNotificationsPressed: _openNotifications,
        ),
      1 => _FeatureAppBar(
          title: l10n.editTab,
          accountLabel: l10n.userAccountAction,
          onAccountPressed: _openProfile,
        ),
      2 => _UploadAppBar(
          title: l10n.uploadTab,
          saveDraftLabel: l10n.uploadSaveDraftAction,
          accountLabel: l10n.userAccountAction,
          onBack: () => _selectTab(0),
          onSaveDraft: _saveDraft,
          onAccountPressed: _openProfile,
        ),
      3 => _FeatureAppBar(
          title: l10n.captionTab,
          leadingIcon: Icons.arrow_back,
          leadingLabel: l10n.homeTab,
          onLeadingPressed: () => _selectTab(0),
          accountLabel: l10n.userAccountAction,
          onAccountPressed: _openProfile,
        ),
      _ => _FeatureAppBar(
          title: l10n.analyticsTab,
          accountLabel: l10n.userAccountAction,
          onAccountPressed: _openProfile,
        ),
    };
  }
}

class _PostDeeBottomNav extends StatelessWidget {
  const _PostDeeBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.l10n,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final PostDeeLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.navSurface,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: onTap,
            backgroundColor: Colors.transparent,
            selectedItemColor: AppTheme.navActive,
            unselectedItemColor: AppTheme.navInactive,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            selectedIconTheme: const IconThemeData(size: 22),
            unselectedIconTheme: const IconThemeData(size: 23),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: [
              _navItem(Icons.dashboard_outlined, Icons.dashboard, l10n.homeTab),
              _navItem(Icons.movie_creation_outlined, Icons.movie_creation,
                  l10n.editTab),
              _navItem(Icons.cloud_upload_outlined, Icons.cloud_upload,
                  l10n.uploadTab),
              _navItem(Icons.calendar_month_outlined, Icons.calendar_month,
                  l10n.captionTab),
              _navItem(
                  Icons.bar_chart_outlined, Icons.bar_chart, l10n.analyticsTab),
            ],
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _navItem(
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    // No highlight box: the bar's selectedItemColor tints the active icon and
    // label purple on its own.
    return BottomNavigationBarItem(
      icon: Icon(icon),
      activeIcon: Icon(activeIcon),
      label: label,
    );
  }
}

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({
    required this.notificationsLabel,
    required this.accountLabel,
    required this.onAccountPressed,
    required this.onNotificationsPressed,
  });

  final String notificationsLabel;
  final String accountLabel;
  final VoidCallback onAccountPressed;
  final VoidCallback onNotificationsPressed;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: 16,
      title: const _PostDeeLogo(),
      actions: [
        _ShellIconButton(
          label: notificationsLabel,
          icon: Icons.notifications_none,
          onPressed: onNotificationsPressed,
          isProminent: true,
        ),
        const SizedBox(width: AppTheme.spaceXs),
        _ShellIconButton(
          label: accountLabel,
          icon: Icons.person_outline,
          onPressed: onAccountPressed,
          isProminent: true,
        ),
        const SizedBox(width: AppTheme.spaceSm),
      ],
    );
  }
}

class _UploadAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _UploadAppBar({
    required this.title,
    required this.saveDraftLabel,
    required this.accountLabel,
    required this.onBack,
    required this.onSaveDraft,
    required this.onAccountPressed,
  });

  final String title;
  final String saveDraftLabel;
  final String accountLabel;
  final VoidCallback onBack;
  final VoidCallback onSaveDraft;
  final VoidCallback onAccountPressed;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: 0,
      leading: IconButton(
        tooltip: title,
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _HeaderPillButton(
            label: saveDraftLabel,
            icon: Icons.bookmark_border,
            onPressed: onSaveDraft,
          ),
        ),
        _ShellIconButton(
          label: accountLabel,
          icon: Icons.person_outline,
          onPressed: onAccountPressed,
          isProminent: true,
        ),
        const SizedBox(width: AppTheme.spaceSm),
      ],
    );
  }
}

class _FeatureAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _FeatureAppBar({
    required this.title,
    required this.accountLabel,
    required this.onAccountPressed,
    this.leadingIcon,
    this.leadingLabel,
    this.onLeadingPressed,
  });

  final String title;
  final String accountLabel;
  final VoidCallback onAccountPressed;
  final IconData? leadingIcon;
  final String? leadingLabel;
  final VoidCallback? onLeadingPressed;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: leadingIcon == null ? 16 : 0,
      leading: leadingIcon == null
          ? null
          : IconButton(
              tooltip: leadingLabel ?? title,
              onPressed: onLeadingPressed,
              icon: Icon(leadingIcon),
            ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
      ),
      actions: [
        _ShellIconButton(
          label: accountLabel,
          icon: Icons.person_outline,
          onPressed: onAccountPressed,
          isProminent: true,
        ),
        const SizedBox(width: AppTheme.spaceSm),
      ],
    );
  }
}

class _LoginGate extends StatelessWidget {
  const _LoginGate({required this.controller});

  final PostDeeAuthController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);
    final setupMessage = controller.setupMessage ?? '';
    final helperMessage = setupMessage.toLowerCase().contains('local mock auth')
        ? l10n.loginMockHelper
        : setupMessage.isNotEmpty
            ? setupMessage
            : l10n.loginDefaultHelper;

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            children: [
              const _PostDeeLogo(height: 86),
              const SizedBox(height: 52),
              Text(
                l10n.loginTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                l10n.loginSubtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 22),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.glass.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.border.withValues(alpha: 0.45),
                  ),
                  // Match the soft neutral shadow used by PostDeeCard instead of
                  // a heavy accent glow.
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.13),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.lock_outline,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spaceMd),
                          Expanded(
                            child: Text(
                              l10n.loginRequirementMessage,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _GradientLoginButton(
                        label: controller.isSigningIn
                            ? l10n.signingInButton
                            : l10n.loginButton,
                        onPressed: controller.isSigningIn
                            ? null
                            : controller.signInWithGoogle,
                      ),
                      const SizedBox(height: 10),
                      _AppleLoginButton(
                        label: l10n.appleLoginButton,
                        onPressed: controller.isSigningIn
                            ? null
                            : controller.signInWithApple,
                      ),
                      const SizedBox(height: AppTheme.spaceMd),
                      Text(
                        helperMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      if (controller.errorMessage != null) ...[
                        const SizedBox(height: AppTheme.spaceMd),
                        Text(
                          controller.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
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

class _GradientLoginButton extends StatelessWidget {
  const _GradientLoginButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isEnabled
              ? const [
                  AppTheme.accentPink,
                  AppTheme.accent,
                  AppTheme.accentCyan,
                ]
              : const [
                  Color(0xFF2A2D36),
                  Color(0xFF20232B),
                ],
        ),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.mail_outline, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }
}

class _AppleLoginButton extends StatelessWidget {
  const _AppleLoginButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.apple, color: Colors.black, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _PostDeeLogo extends StatelessWidget {
  const _PostDeeLogo({this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    final assetName = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/brand/postdee_logo_dark.png'
        : 'assets/images/brand/postdee_logo.png';

    return Semantics(
      label: 'PostDee logo',
      container: true,
      child: ExcludeSemantics(
        child: Image.asset(
          assetName,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: 16, color: AppTheme.textPrimary),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: AppTheme.border.withValues(alpha: 0.75)),
          backgroundColor: AppTheme.glassDeep.withValues(alpha: 0.72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ShellIconButton extends StatelessWidget {
  const _ShellIconButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.isProminent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isProminent;

  @override
  Widget build(BuildContext context) {
    final iconSize = isProminent ? 22.0 : 18.0;
    final padding = isProminent ? 9.0 : 6.0;
    final minimumSize =
        isProminent ? const Size(44, 44) : const Size(32, 32);

    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: label,
          onPressed: onPressed ?? () {},
          icon: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.glass.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(isProminent ? 28 : 24),
              border: Border.all(color: AppTheme.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Icon(icon, size: iconSize),
            ),
          ),
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: minimumSize,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
