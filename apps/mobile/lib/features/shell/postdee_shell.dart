import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
import '../auth/firebase_email_auth_gateway.dart';
import '../auth/firebase_google_auth_gateway.dart';
import '../auth/firebase_id_token_refresher.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../notifications/firebase_push_messaging_gateway.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/push_messaging_gateway.dart';
import '../onboarding/onboarding_flow.dart';
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
  static const _onboardingStore = OnboardingSeenStore();

  late final PostDeeAuthController _authController;
  late final PushMessagingGateway _pushMessagingGateway;
  int _selectedIndex = 0;
  int _calendarRefreshToken = 0;

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
          onCreatePost: () => _selectTab(2),
          onViewAllPosts: () => _selectTab(3),
          onOpenNotifications: _openNotifications,
          onOpenProfile: () => _selectTab(5),
          onOpenAi: () => _selectTab(1),
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
        const AnalyticsScreen(showTitle: true),
        // Profile is the 4th nav tab per the design handoff (no pushed route).
        ProfileScreen(
          languageController: widget.languageController,
          themeController:
              widget.themeController ?? PostDeeThemeController.instance,
          onOpenTemplates: _openTemplates,
          onDeleteAccount: _handleDeleteAccount,
          onSignOut: _authController.signOut,
        ),
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
        // The capsule nav is translucent and floats over the content; tab
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
          onAnalytics: () => _selectTab(4),
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
    required this.onAnalytics,
    required this.onProfile,
    required this.l10n,
  });

  final int currentIndex;
  final VoidCallback onHome;
  final VoidCallback onCalendar;
  final VoidCallback onCreate;
  final VoidCallback onAnalytics;
  final VoidCallback onProfile;
  final PostDeeLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: DecoratedBox(
          key: const ValueKey('postdee-reference-bottom-nav'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF122018).withValues(alpha: 0.28),
                blurRadius: 30,
                spreadRadius: -14,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          // Translucent capsule: content scrolls behind it, blurred, per the
          // design handoff (card 70% + backdrop blur 12).
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.glass.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.border.withValues(alpha: 0.70),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ReferenceNavButton(
                      label: l10n.homeTab,
                      icon: Icons.home_rounded,
                      selected: currentIndex == 0,
                      onPressed: onHome,
                    ),
                    _ReferenceNavButton(
                      label: l10n.captionTab,
                      icon: Icons.calendar_month_rounded,
                      selected: currentIndex == 3,
                      onPressed: onCalendar,
                    ),
                    _ReferenceCreateNavButton(
                      label: l10n.locale.languageCode == 'th'
                          ? 'สร้างโพสต์'
                          : 'Create post',
                      selected: currentIndex == 2,
                      onPressed: onCreate,
                    ),
                    _ReferenceNavButton(
                      label: l10n.analyticsTab,
                      icon: Icons.bar_chart_rounded,
                      selected: currentIndex == 4,
                      onPressed: onAnalytics,
                    ),
                    _ReferenceNavButton(
                      label: l10n.profileTab,
                      icon: Icons.person_rounded,
                      selected: currentIndex == 5,
                      onPressed: onProfile,
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

class _ReferenceNavButton extends StatelessWidget {
  const _ReferenceNavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Selected tab sits in a mint capsule with the green-ink icon; others show
    // just a faint icon (no labels), per the design handoff.
    final color = selected ? AppTheme.accentCyanInk : AppTheme.textMuted;

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: AnimatedScale(
            scale: selected ? 1.05 : 1,
            duration: const Duration(milliseconds: 200),
            child: Icon(icon, color: color, size: 24),
          ),
          style: IconButton.styleFrom(
            backgroundColor: selected ? AppTheme.mint : null,
            fixedSize: const Size(56, 44),
            shape: const StadiumBorder(),
            padding: EdgeInsets.zero,
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
    return Transform.translate(
      offset: const Offset(0, -10),
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: ExcludeSemantics(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Soft green halo bleeding slightly past the button.
                  Positioned(
                    left: -6,
                    top: -6,
                    right: -6,
                    bottom: -6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 0.45, 1.0],
                          colors: [
                            Color(0xFF19C98E),
                            Color(0xFF0E9F6E),
                            Color(0xFF086A49),
                          ],
                        ),
                        boxShadow: [
                          // Card-colored ring separating the button from the
                          // capsule behind it (box-shadow 0 0 0 5px var(--card)).
                          BoxShadow(color: AppTheme.glass, spreadRadius: 5),
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.65),
                            blurRadius: 26,
                            spreadRadius: -8,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                  ),
                  // Glossy highlight near the top edge.
                  Positioned(
                    top: 6,
                    left: 11,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const SizedBox(width: 24, height: 11),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.55),
                              blurRadius: 24,
                              spreadRadius: -8,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Center(
                            child: Transform.rotate(
                              angle: -20 * math.pi / 180,
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                          SizedBox(
                            height: 54,
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
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Center(
                                        child: Text(
                                          'G',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.accentCyanInk,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    controller.isSigningIn
                                        ? l10n.signingInButton
                                        : googleLabel,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 11),
                          SizedBox(
                            height: 54,
                            child: OutlinedButton.icon(
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
                              icon: Icon(
                                Icons.mail_outline,
                                size: 21,
                                color: AppTheme.textPrimary,
                              ),
                              label: Text(
                                emailLabel,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppTheme.border),
                                foregroundColor: AppTheme.textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
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
