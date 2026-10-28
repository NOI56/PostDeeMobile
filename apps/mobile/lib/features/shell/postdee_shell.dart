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
import '../auth/auth_message_localization.dart';
import '../auth/firebase_apple_auth_gateway.dart';
import '../auth/firebase_account_access_revoker.dart';
import '../auth/firebase_email_auth_gateway.dart';
import '../auth/firebase_google_auth_gateway.dart';
import '../auth/firebase_id_token_refresher.dart';
import '../calendar/calendar_screen.dart';
import '../billing/addon_pending_store.dart';
import '../captions/caption_writing_style_store.dart';
import '../home/home_screen.dart';
import '../link_in_bio/link_in_bio_draft_store.dart';
import '../link_in_bio/link_in_bio_screen.dart';
import '../notifications/firebase_push_messaging_gateway.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/push_messaging_gateway.dart';
import '../notifications/push_notification.dart';
import '../onboarding/onboarding_flow.dart';
import '../platforms/connections_screen.dart';
import '../profile/profile_screen.dart';
import '../posts/post_detail_screen.dart';
import '../posts/posts_screen.dart';
import '../legal/legal_document_screen.dart';
import '../shared/postdee_undo_toast.dart';
import '../templates/templates_screen.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/platform_publish_defaults_store.dart';
import '../uploader/publish_draft.dart';
import '../uploader/publish_draft_store.dart';
import '../uploader/publish_draft_store_factory.dart';
import '../uploader/publish_media_probe.dart';
import '../uploader/tiktok_video_preparer.dart';
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
    this.loadCalendarPosts,
    this.loadSubscription,
    this.loadRecentPosts,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.prepareTikTokVideo,
    this.createPost,
    this.checkPublishingReadiness,
    this.loadSocialConnections,
    this.loadSocialPublishingReadiness,
    this.probePublishMedia,
    this.deleteAccount,
    this.checkAccountDeletionReady,
    this.deleteLocalPublishDrafts,
    this.loadLocalPublishDraftDeleter,
    this.uploaderDraftStore,
    this.accountAccessRevoker,
    this.pushMessagingGateway,
    this.emailAuthGateway,
  });

  final FirebaseBootstrapResult? firebaseBootstrapResult;
  final PostDeeLanguageController languageController;
  final PostDeeThemeController? themeController;
  final ScheduledPostsLoader? loadScheduledPosts;
  final CalendarPostsLoader? loadCalendarPosts;
  final UploaderSubscriptionLoader? loadSubscription;
  final HomeRecentPostsLoader? loadRecentPosts;
  final UploaderVideoPicker? pickVideo;
  final UploaderUploadCreator? createUpload;
  final UploaderVideoUploader? uploadVideoFile;
  final UploaderTikTokVideoPreparer? prepareTikTokVideo;
  final UploaderPostCreator? createPost;
  final UploaderPublishingReadinessChecker? checkPublishingReadiness;
  final UploaderConnectionsLoader? loadSocialConnections;
  final UploaderSocialReadinessLoader? loadSocialPublishingReadiness;
  final PublishMediaProbe? probePublishMedia;
  final AccountDeleter? deleteAccount;
  final AccountDeletionReadinessChecker? checkAccountDeletionReady;
  final AccountLocalPublishDraftDeleter? deleteLocalPublishDrafts;
  final AccountLocalPublishDraftDeleterLoader? loadLocalPublishDraftDeleter;
  final PublishDraftStore? uploaderDraftStore;
  final AccountAccessRevoker? accountAccessRevoker;
  final PushMessagingGateway? pushMessagingGateway;
  final EmailAuthGateway? emailAuthGateway;

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
  bool _isHomeConnectionsOpen = false;
  MaterialPageRoute<void>? _composerRoute;
  String? _composerOwnerUserId;
  String? _notificationOwnerUserId;
  final Set<MaterialPageRoute<void>> _notificationRoutes = {};
  late AuthSessionBinding _notificationSession;
  int _linkSessionGeneration = 0;

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
      emailAuthGateway: widget.emailAuthGateway ??
          createEmailAuthGatewayFromConfig(
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          ),
      appleAuthGateway: createAppleAuthGatewayFromConfig(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    _authController.addListener(_handleComposerOwnerChanged);
    _notificationSession = PostDeeAuthSessionStore.instance.captureSession();
    _authController.addListener(_handleNotificationSessionChanged);
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
          registerBoundToken: (token, binding) => PostDeeApiClient(sessionBinding: binding).registerDeviceToken(token),
          unregisterToken: (token, session) =>
              PostDeeApiClient(authTokenProvider: () async => session.idToken)
                  .unregisterDeviceToken(token),
          onOpenPost: (postId) {
            final binding = PostDeeAuthSessionStore.instance.captureSession();
            final owner = _authController.session.stableUserId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && binding.isCurrent && owner == _authController.session.stableUserId) {
                unawaited(_openNotificationPost(postId));
              }
            });
          },
        );
    _notificationOwnerUserId = _authController.session.stableUserId;
    final gateway = _pushMessagingGateway;
    if (gateway is PushMessagingLifecycle) {
      unawaited((gateway as PushMessagingLifecycle).start().catchError((_) {}));
    }
  }

  List<Widget> _buildScreens() => [
        HomeScreen(
          key: ValueKey('home-${_authController.session.stableUserId}'),
          isActive: _selectedIndex == 0 &&
              _composerRoute == null &&
              !_isHomeConnectionsOpen,
          loadSubscription: widget.loadSubscription,
          loadRecentPosts: widget.loadRecentPosts,
          loadDrafts: _loadHomeDrafts,
          loadConnections: widget.loadSocialConnections,
          loadScheduledPosts: widget.loadScheduledPosts == null
              ? null
              : _loadHomeScheduledPosts,
          onCreatePost: _openPostComposer,
          onResumeDraft: _resumeHomeDraft,
          onOpenConnections: () => unawaited(_openHomeConnections()),
          onOpenCalendar: () => _selectTab(3),
          onOpenNotifications: _openNotifications,
          onOpenProfile: () => _selectTab(5),
          onOpenLinkInBio: () => _selectTab(1),
          userName: _authController.session.displayName,
        ),
        LinkInBioScreen(
          key: ValueKey((_authController.session.stableUserId, _linkSessionGeneration)),
          onBack: () => _selectTab(0),
          embeddedInTab: true,
          isActive: _selectedIndex == 1,
        ),
        const SizedBox.shrink(),
        CalendarScreen(
          key: ValueKey('calendar-${_authController.session.stableUserId}'),
          ownerUserId: _authController.session.stableUserId,
          refreshToken: _calendarRefreshToken,
          isActive: _selectedIndex == 3 && _composerRoute == null,
          loadScheduledPosts: widget.loadScheduledPosts,
          loadCalendarPosts: widget.loadCalendarPosts,
          onAddPost: () => _selectTab(2),
          onAddPostForDate: (date) =>
              unawaited(_openPostComposer(initialScheduleDate: date)),
          onOpenCalendarPostDetail: _openCalendarPostDetail,
        ),
        // Do not start provider/statistics reads for an offstage dashboard.
        // Recreating it on entry also prevents an old owner's summary lingering.
        _selectedIndex == 4
            ? AnalyticsScreen(
                key: ValueKey((
                  'analytics',
                  _authController.session.stableUserId,
                  _linkSessionGeneration,
                )),
                showTitle: true,
              )
            : const SizedBox.shrink(),
        // Profile is the 5th nav tab per the design handoff (no pushed route).
        ProfileScreen(
          isActive: _selectedIndex == 5 && _composerRoute == null,
          loadSubscription: widget.loadSubscription,
          languageController: widget.languageController,
          themeController:
              widget.themeController ?? PostDeeThemeController.instance,
          onOpenTemplates: _openTemplates,
          onDeleteAccount: _handleDeleteAccount,
          isDeletingAccount: _isDeletingAccount,
          onSignOut: _authController.signOut,
          onSendEmailVerification: _authController.supportsEmailRecovery
              ? _authController.sendEmailVerification
              : null,
          onRefreshEmailVerification: _authController.supportsEmailRecovery
              ? _authController.refreshEmailVerification
              : null,
          runNativePhoneAuthOperation: _authController.runBoundNativeAuthOperation,
        ),
      ];

  @override
  void dispose() {
    unawaited(_pushMessagingGateway.dispose());
    _authController.removeListener(_handleComposerOwnerChanged);
    _authController.removeListener(_handleNotificationSessionChanged);
    _authController.dispose();
    super.dispose();
  }

  void _openNotifications() {
    unawaited(_openNotificationsAfterPermission());
  }

  Future<void> _openNotificationsAfterPermission() async {
    final binding = PostDeeAuthSessionStore.instance.captureSession();
    // Ask for notification permission only after the user taps the bell. This
    // gives the system prompt clear context instead of interrupting sign-in.
    final owner = _authController.session.stableUserId;
    try {
      await _pushMessagingGateway
          .initialize()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted && binding.isCurrent) {
        final languageCode = Localizations.of<PostDeeLocalizations>(
                    context, PostDeeLocalizations)
                ?.locale
                .languageCode ??
            'th';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageCode == 'th'
                  ? 'เชื่อมการแจ้งเตือนไม่สำเร็จ กรุณาลองอีกครั้ง'
                  : 'Could not connect to notifications. Please try again.')),
        );
      }
    }
    if (!mounted ||
        !binding.isCurrent ||
        !_authController.session.isSignedIn ||
        owner != _authController.session.stableUserId) {
      return;
    }
    final route = MaterialPageRoute<void>(
      builder: (context) => NotificationsScreen(
        onOpenPost: (postId) => unawaited(_openNotificationPost(postId)),
      ),
    );
    _notificationRoutes.add(route);
    await Navigator.of(context).push<void>(route);
    _notificationRoutes.remove(route);
  }

  Future<void> _openNotificationPost(String postId) async {
    if (!mounted ||
        !_authController.session.isSignedIn ||
        _authController.session.stableUserId == null) {
      return;
    }
    final route = MaterialPageRoute<void>(
      builder: (_) => PostDetailLoaderScreen(postId: postId),
    );
    _notificationRoutes.add(route);
    await Navigator.of(context).push<void>(route);
    _notificationRoutes.remove(route);
  }

  void _handleNotificationSessionChanged() {
    if (_notificationSession.isCurrent) return;
    _notificationSession = PostDeeAuthSessionStore.instance.captureSession();
    _linkSessionGeneration += 1;
    PostDeeNotificationCenter.instance.clear();
    for (final route in _notificationRoutes.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _notificationRoutes.clear();
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

  Future<List<PublishDraft>> _loadHomeDrafts() async {
    final owner = _authController.session.stableUserId;
    if (owner == null || !_authController.session.isSignedIn) return const [];
    final store =
        widget.uploaderDraftStore ?? await createPublishDraftStoreForSession();
    if (!mounted || owner != _authController.session.stableUserId) {
      return const [];
    }
    if (store == null) throw StateError('Draft store is unavailable.');
    final drafts = await store.listDrafts();
    if (!mounted || owner != _authController.session.stableUserId) {
      return const [];
    }
    return drafts.where((draft) => draft.ownerUserId == owner).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<PostSummaryResult>> _loadHomeScheduledPosts() async {
    final owner = _authController.session.stableUserId;
    if (owner == null || !_authController.session.isSignedIn) return const [];
    final posts = await widget.loadScheduledPosts!();
    if (!mounted || owner != _authController.session.stableUserId) {
      return const [];
    }
    return posts
        .where((post) => post.userId == null || post.userId == owner)
        .map((post) => PostSummaryResult(
              id: post.id,
              caption: post.caption,
              videoS3Key: post.videoS3Key,
              platforms: post.platforms,
              status: post.status,
              createdAt: post.createdAt,
              scheduledAt: post.scheduledAt,
              publishedAt: post.publishedAt,
              platformResults: post.platformResults,
            ))
        .toList();
  }

  Future<void> _resumeHomeDraft(PublishDraft draft) async {
    if (!mounted ||
        !_authController.session.isSignedIn ||
        draft.ownerUserId != _authController.session.stableUserId) {
      return;
    }
    await _openPostComposer(initialDraftId: draft.id);
  }

  Future<void> _openHomeConnections() async {
    if (!mounted ||
        _isHomeConnectionsOpen ||
        _composerRoute != null ||
        !_authController.session.isSignedIn) {
      return;
    }
    setState(() => _isHomeConnectionsOpen = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => const ConnectionsScreen(),
      ));
    } finally {
      if (mounted) setState(() => _isHomeConnectionsOpen = false);
    }
  }

  Future<void> _openPostComposer(
      {String? initialDraftId, DateTime? initialScheduleDate}) async {
    if (!mounted ||
        _composerRoute != null ||
        _isHomeConnectionsOpen ||
        !_authController.session.isSignedIn) {
      return;
    }

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
              initialDraftId: initialDraftId,
              initialScheduleDate: initialScheduleDate,
              loadSubscription: widget.loadSubscription,
              pickVideo: widget.pickVideo,
              createUpload: widget.createUpload,
              uploadVideoFile: widget.uploadVideoFile,
              prepareTikTokVideo: widget.prepareTikTokVideo,
              createPost: widget.createPost,
              checkPublishingReadiness: widget.checkPublishingReadiness,
              loadSocialConnections: widget.loadSocialConnections,
              loadSocialPublishingReadiness: widget.loadSocialPublishingReadiness,
              probePublishMedia: widget.probePublishMedia,
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
    setState(() {
      _composerRoute = route;
      _composerOwnerUserId = _authController.session.stableUserId;
    });
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (mounted && identical(_composerRoute, route)) {
        setState(() {
          _composerRoute = null;
          _composerOwnerUserId = null;
        });
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
    final owner = _authController.session.isSignedIn
        ? _authController.session.stableUserId
        : null;
    if (owner != _notificationOwnerUserId) {
      _notificationOwnerUserId = owner;
      PostDeeNotificationCenter.instance.clear();
      Navigator.of(context).popUntil((route) => route.isFirst);
      _notificationRoutes.clear();
    }
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

  Future<void> _openCalendarPostDetail(CalendarPostResult post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PostDetailScreen(
          post: post,
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

    String deletionText(String thai, String english) =>
        (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                    ?.locale.languageCode ??
                'th') ==
            'th'
        ? thai
        : english;

    setState(() => _isDeletingAccount = true);
    // Permanently deletes the account via DELETE /account, then signs out so the
    // user lands back on the login gate. Only sign out after the delete succeeds.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final deletionSession = PostDeeAuthSessionStore.instance.captureSession();
    final addonPendingStore = SharedPreferencesAddonPendingStore();
    final apiClient = PostDeeApiClient(sessionBinding: deletionSession);
    final capturedOwnerUserId = _authController.session.stableUserId;
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
      deletionSession.ensureCurrent();
      if (!identityAlreadyDeleted) {
        await _authController.runBoundNativeAuthOperation(sessionBinding: deletionSession,
          operation: _accountAccessRevoker.revokeBeforeAccountDeletion);
      }
      deletionSession.ensureCurrent();
      await deleteAccount();
      deletionSession.ensureCurrent();
      try {
        final deleteLocalPublishDrafts = await localDraftDeleterFuture;
        deletionSession.ensureCurrent();
        await deleteLocalPublishDrafts?.call();
      } catch (_) {
        // The server account is already deleted. Continue signing out, but
        // tell the user how to remove any local files the OS would not delete.
        localDraftCleanupFailed = true;
      }

      if (capturedOwnerUserId != null) {
        try {
          await addonPendingStore.clearForDeletedAccount();
        } catch (_) {
          localDraftCleanupFailed = true;
        }
        try {
          await clearLinkInBioDraftForUser(capturedOwnerUserId);
        } catch (_) {
          localDraftCleanupFailed = true;
        }
        try {
          await const SharedPreferencesCaptionWritingStyleStore()
              .clearForDeletedAccount(capturedOwnerUserId);
        } catch (_) {
          localDraftCleanupFailed = true;
        }
        try {
          await const SharedPreferencesPlatformPublishDefaultsStore()
              .clearForDeletedAccount(capturedOwnerUserId);
        } catch (_) {
          localDraftCleanupFailed = true;
        }
      }

      if (!mounted || !deletionSession.isCurrent) {
        return;
      }

      navigator.popUntil((route) => route.isFirst);
      AuthSessionBinding? signedOutSession;
      try {
        final signOut = _authController.signOut(sessionBinding: deletionSession);
        signedOutSession = PostDeeAuthSessionStore.instance.captureSession();
        await signOut;
      } catch (_) {
        // The controller always clears the local session in a finally block.
      }
      if (!mounted || signedOutSession?.isCurrent != true) {
        return;
      }
      // The auth change swaps the signed-in Scaffold for the login Scaffold.
      // Wait until that frame is mounted so the success toast attaches to the
      // screen the user actually lands on instead of the Scaffold being removed.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || signedOutSession?.isCurrent != true) {
        return;
      }
      showPostDeeUndoToast(
        context,
        message: localDraftCleanupFailed
            ? deletionText(
                'ลบบัญชีแล้ว แต่ลบข้อมูลในเครื่องไม่ครบ กรุณาล้างข้อมูลแอป',
                'Account deleted, but some data remains on this device. Please clear app data.',
              )
            : deletionText('ลบบัญชีและออกจากระบบแล้ว',
                'Account deleted and signed out'),
      );
    } on AuthSessionChangedException {
      // A late deletion result must not sign out or navigate a later account.
    } on AccountAccessRevocationException catch (error) {
      if (!deletionSession.isCurrent || !mounted) return;
      final message = switch (error.message) {
        'Apple ไม่ส่งรหัสยืนยัน กรุณาลองลบบัญชีอีกครั้ง' => deletionText(
            error.message,
            'Apple did not return a verification code. Please try deleting your account again.',
          ),
        'ถอนสิทธิ์ Sign in with Apple ไม่สำเร็จ บัญชียังไม่ถูกลบ กรุณาลองใหม่' =>
          deletionText(
            error.message,
            'Could not revoke Sign in with Apple access. Your account has not been deleted. Please try again.',
          ),
        _ => error.message,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      if (!deletionSession.isCurrent || !mounted) return;
      final message = switch (error.code) {
        'ACCOUNT_DELETION_UNAVAILABLE' => deletionText(
            'ระบบลบบัญชียังไม่พร้อม กรุณาลองใหม่ภายหลัง',
            'Account deletion is unavailable. Please try again later.',
          ),
        'ACCOUNT_MEDIA_CLEANUP_UNAVAILABLE' => deletionText(
            'ระบบลบวิดีโอยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
            'Video deletion is unavailable. Please try again later.',
          ),
        'ACCOUNT_MEDIA_CLEANUP_FAILED' => deletionText(
            'ลบวิดีโอยังไม่สำเร็จ บัญชีของคุณยังอยู่ กรุณาลองใหม่',
            'Could not delete your videos. Your account still exists. Please try again.',
          ),
        'ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE' => deletionText(
            'ระบบถอนการเชื่อมต่อโซเชียลยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
            'Channel disconnection is unavailable. Please try again later.',
          ),
        'ACCOUNT_SOCIAL_CLEANUP_FAILED' => deletionText(
            'ถอนการเชื่อมต่อโซเชียลยังไม่ครบ บัญชียังไม่ถูกลบ กรุณาลองใหม่',
            'Could not disconnect all channels. Your account has not been deleted. Please try again.',
          ),
        'ACCOUNT_IDENTITY_DELETE_FAILED' => deletionText(
            'ลบข้อมูลแล้ว แต่ยังปิดการเข้าสู่ระบบไม่สำเร็จ กรุณากดลบบัญชีอีกครั้ง',
            'Your data was deleted, but sign-in access could not be closed. Please try deleting your account again.',
          ),
        'ACCOUNT_REAUTHENTICATION_REQUIRED' => deletionText(
            'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ จากนั้นลบบัญชีภายใน 5 นาที',
            'Sign out and sign in again, then delete your account within 5 minutes.',
          ),
        _ => error.message,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!deletionSession.isCurrent || !mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(deletionText('ลบบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง',
            'Could not delete your account. Please try again.'))),
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

class _PostDeeBottomNav extends StatefulWidget {
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
  static const _iconSize = 26.0;
  static const _iconBackgroundSize = 42.0;
  static const _labelHeight = 18.0;

  int? get _selectedSlot => switch (currentIndex) {
        0 => 0,
        3 => 1,
        1 => 3,
        5 => 4,
        _ => null,
      };

  @override
  State<_PostDeeBottomNav> createState() => _PostDeeBottomNavState();
}

class _PostDeeBottomNavState extends State<_PostDeeBottomNav>
    with WidgetsBindingObserver {
  late bool _resumed;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (mounted && resumed != _resumed) {
      setState(() => _resumed = resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = !_resumed ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context);
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
                child: SizedBox(
                  height: _PostDeeBottomNav._height,
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ReferenceNavButton(
                              slot: 0,
                              reduceMotion: reduceMotion,
                              label: widget.l10n.navigationHome,
                              icon: Icons.home_outlined,
                              selected: widget.currentIndex == 0,
                              onPressed: widget.onHome,
                            ),
                          ),
                          Expanded(
                            child: _ReferenceNavButton(
                              slot: 1,
                              reduceMotion: reduceMotion,
                              label: widget.l10n.captionTab,
                              icon: Icons.calendar_today_outlined,
                              iconSize: 22,
                              selected: widget.currentIndex == 3,
                              onPressed: widget.onCalendar,
                            ),
                          ),
                          Expanded(
                            child: _ReferenceCreateNavButton(
                              reduceMotion: reduceMotion,
                              label: widget.l10n.createPostTab,
                              selected: widget.currentIndex == 2,
                              onPressed: widget.onCreate,
                            ),
                          ),
                          Expanded(
                            child: _ReferenceNavButton(
                              slot: 3,
                              reduceMotion: reduceMotion,
                              label: widget.l10n.navigationStoreLink,
                              icon: Icons.link_outlined,
                              selected: widget.currentIndex == 1,
                              onPressed: widget.onLinkInBio,
                            ),
                          ),
                          Expanded(
                            child: _ReferenceNavButton(
                              slot: 4,
                              reduceMotion: reduceMotion,
                              label: widget.l10n.navigationAccount,
                              icon: Icons.person_outline_rounded,
                              selected: widget.currentIndex == 5,
                              onPressed: widget.onProfile,
                            ),
                          ),
                        ],
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: _RunningNavDot(
                              selectedSlot: widget._selectedSlot,
                              reduceMotion: reduceMotion,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningNavDot extends StatefulWidget {
  const _RunningNavDot({
    required this.selectedSlot,
    required this.reduceMotion,
  });

  final int? selectedSlot;
  final bool reduceMotion;

  @override
  State<_RunningNavDot> createState() => _RunningNavDotState();
}

class _RunningNavDotState extends State<_RunningNavDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late double _fromSlot = (widget.selectedSlot ?? 0).toDouble();
  late double _toSlot = _fromSlot;
  double _fromWidth = 4;

  double get _position =>
      _fromSlot +
      (_toSlot - _fromSlot) * Curves.easeInOutCubic.transform(_motion.value);

  double get _width {
    final progress = _motion.value;
    return progress < .5
        ? _fromWidth +
            (22 - _fromWidth) * Curves.easeOut.transform(progress * 2)
        : 22 - 18 * Curves.easeIn.transform((progress - .5) * 2);
  }

  @override
  void didUpdateWidget(_RunningNavDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSlot == widget.selectedSlot &&
        oldWidget.reduceMotion == widget.reduceMotion) {
      return;
    }
    final target = widget.selectedSlot;
    final animate = !widget.reduceMotion &&
        target != null &&
        oldWidget.selectedSlot != null &&
        oldWidget.selectedSlot != target;
    if (animate) {
      // A second tap starts from the current position and width, not the
      // previous destination, so rapid navigation never jumps backwards.
      _fromSlot = _position;
      _fromWidth = _width;
      _toSlot = target.toDouble();
      _motion.forward(from: 0);
    } else {
      _motion.stop();
      _fromSlot = _toSlot = (target ?? _toSlot).toDouble();
      _fromWidth = 4;
      _motion.value = 1;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedSlot == null) return const SizedBox.shrink();
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final slot = isRtl ? 4 - _position : _position;
          final center = constraints.maxWidth * (slot + .5) / 5;
          return Stack(
            children: [
              Positioned(
                left: center - _width / 2,
                // Align with the reserved 4 dp space beneath every label.
                bottom: 7,
                width: _width,
                height: 4,
                child: DecoratedBox(
                  key: const ValueKey('postdee-nav-selected-indicator'),
                  decoration: BoxDecoration(
                    color: AppTheme.navActive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReferenceNavButton extends StatefulWidget {
  const _ReferenceNavButton({
    required this.slot,
    required this.reduceMotion,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.iconSize = _PostDeeBottomNav._iconSize,
    this.isCreateAction = false,
    this.createScale = 1,
    this.onHighlightChanged,
  });

  final int slot;
  final bool reduceMotion;
  final String label;
  final IconData icon;
  final double iconSize;
  final bool selected;
  final VoidCallback onPressed;
  final bool isCreateAction;
  final double createScale;
  final ValueChanged<bool>? onHighlightChanged;

  @override
  State<_ReferenceNavButton> createState() => _ReferenceNavButtonState();
}

class _ReferenceNavButtonState extends State<_ReferenceNavButton>
    with TickerProviderStateMixin {
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.selected ? 1 : 0,
  );
  late final AnimationController _press =
      AnimationController.unbounded(vsync: this, value: 1);
  late final Listenable _feedback = Listenable.merge([_selection, _press]);
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // Initialize even for the center action, which renders its own feedback.
    // Creating a previously unused ticker during disposal is unsafe.
    _feedback;
  }

  @override
  void didUpdateWidget(_ReferenceNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _selection.stop();
      _selection.value = widget.selected ? 1 : 0;
      _press.stop();
      _press.value = 1;
    } else if (!widget.isCreateAction &&
        oldWidget.selected != widget.selected) {
      _selection.animateTo(
        widget.selected ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _highlightChanged(bool highlighted) {
    if (_disposed || !mounted) return;
    if (!widget.isCreateAction && !widget.reduceMotion) {
      _press.animateTo(
        highlighted ? .9 : 1,
        duration: Duration(milliseconds: highlighted ? 80 : 180),
        curve: highlighted ? Curves.easeOut : Curves.easeOutBack,
      );
    }
    widget.onHighlightChanged?.call(highlighted);
  }

  @override
  void dispose() {
    _disposed = true;
    _selection.dispose();
    _press.dispose();
    super.dispose();
  }

  Widget _animatedIcon() {
    return AnimatedBuilder(
      animation: _feedback,
      builder: (context, _) {
        final progress = _selection.value;
        return Transform.scale(
          key: ValueKey('postdee-nav-icon-feedback-${widget.slot}'),
          scale: _press.value,
          transformHitTests: false,
          child: Transform.translate(
            key: ValueKey('postdee-nav-icon-lift-${widget.slot}'),
            offset: Offset(0, -2 * progress),
            transformHitTests: false,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: _PostDeeBottomNav._iconBackgroundSize,
                  child: DecoratedBox(
                    key: ValueKey('postdee-nav-icon-halo-${widget.slot}'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.navActive
                          .withValues(alpha: .12 * progress),
                    ),
                  ),
                ),
                Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: Color.lerp(
                      AppTheme.textSecondary, AppTheme.navActive, progress),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: widget.label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: _highlightChanged,
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
                        child: widget.isCreateAction
                            ? Transform.translate(
                                offset: const Offset(0, -7),
                                transformHitTests: false,
                                child: Transform.scale(
                                  scale: widget.createScale,
                                  transformHitTests: false,
                                  child: Center(
                                    child: SizedBox.square(
                                      dimension:
                                          _PostDeeBottomNav._iconBackgroundSize,
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                            'postdee-nav-create-surface'),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.accent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Icon(
                                            widget.icon,
                                            color: Colors.white,
                                            size: widget.iconSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : _animatedIcon(),
                      ),
                      const SizedBox(height: 1),
                      if (widget.isCreateAction)
                        const SizedBox(height: _PostDeeBottomNav._labelHeight)
                      else
                        _ReferenceNavLabel(
                            label: widget.label, selected: widget.selected),
                      const SizedBox(height: 3),
                      const SizedBox(width: 4, height: 4),
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

class _ReferenceCreateNavButton extends StatefulWidget {
  const _ReferenceCreateNavButton({
    required this.reduceMotion,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final bool reduceMotion;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_ReferenceCreateNavButton> createState() =>
      _ReferenceCreateNavButtonState();
}

class _ReferenceCreateNavButtonState extends State<_ReferenceCreateNavButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press =
      AnimationController.unbounded(vsync: this, value: 1);
  bool _disposed = false;

  @override
  void didUpdateWidget(_ReferenceCreateNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _press.stop();
      _press.value = 1;
    }
  }

  void _highlightChanged(bool highlighted) {
    if (_disposed || !mounted || widget.reduceMotion) return;
    _press.animateTo(
      highlighted ? .9 : 1,
      duration: Duration(milliseconds: highlighted ? 80 : 180),
      curve: highlighted ? Curves.easeOut : Curves.easeOutBack,
    );
  }

  void _onPressed() {
    if (_disposed || !mounted) return;
    if (!widget.reduceMotion) {
      _press.value = .9;
      _highlightChanged(false);
    }
    widget.onPressed();
  }

  @override
  void dispose() {
    _disposed = true;
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _press,
      builder: (context, _) => _ReferenceNavButton(
        slot: 2,
        reduceMotion: widget.reduceMotion,
        label: widget.label,
        icon: Icons.ios_share_outlined,
        selected: widget.selected,
        onPressed: _onPressed,
        isCreateAction: true,
        createScale: _press.value,
        onHighlightChanged: _highlightChanged,
      ),
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
        height: _PostDeeBottomNav._labelHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? AppTheme.navActive : AppTheme.textSecondary,
              fontSize: 12,
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
            ? localizeAuthMessage(context, setupMessage)
            : isThai
                ? l10n.loginDefaultHelper
                : 'Sign in with Google or email to get started.';
    final heroTitle =
        isThai ? 'ลงครั้งเดียว ขายได้ทุกที่' : 'Post once. Sell everywhere.';
    final heroSubtitle = isThai
        ? 'โพสต์วิดีโอเดียวไป TikTok, Shorts,\nReels และ Facebook พร้อมกัน'
        : 'Post one video to TikTok, Shorts,\nReels and Facebook at once.';
    final requirement = isThai
        ? 'เชื่อมต่อบัญชีเพียงครั้งเดียว ปลอดภัย ไม่เก็บรหัสผ่านของคุณ'
        : 'Connect your account once. Sign in securely. PostDee does not store your password.';
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
                              localizeAuthMessage(
                                  context, controller.errorMessage!),
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
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: TextButton(
                                key: const ValueKey('login-terms'),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: AppTheme.accentCyanInk,
                                  textStyle: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => const LegalDocumentScreen(
                                            document: PostDeeLegalDocuments
                                                .termsOfService,
                                          )),
                                ),
                                child: Text(isThai
                                    ? 'เงื่อนไขการใช้บริการ'
                                    : 'Terms of Service'),
                              ),
                            ),
                          ],
                        ),
                        TextSpan(text: isThai ? '\nและ' : '\nand '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: TextButton(
                            key: const ValueKey('login-privacy'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: AppTheme.accentCyanInk,
                              textStyle: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => const LegalDocumentScreen(
                                        document:
                                            PostDeeLegalDocuments.privacyPolicy,
                                      )),
                            ),
                            child: Text(isThai
                                ? 'นโยบายความเป็นส่วนตัว'
                                : 'Privacy Policy'),
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
  String? _recoveryMessage;

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

  Future<void> _resetPassword() async {
    setState(() {
      _isSubmitting = true;
      _validationMessage = null;
      _recoveryMessage = null;
    });
    final success =
        await widget.controller.resetEmailPassword(_emailController.text);
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      if (success) {
        _recoveryMessage =
            'หากอีเมลนี้มีบัญชี คุณจะได้รับลิงก์ตั้งรหัสผ่าน กรุณาตรวจสอบกล่องอีเมลและจดหมายขยะ';
      } else {
        _validationMessage = widget.controller.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isThai = PostDeeLocalizations.of(context).locale.languageCode == 'th';
    String text(String thai, String english) => isThai ? thai : english;
    final title = _createAccount
        ? text('สร้างบัญชีด้วยอีเมล', 'Create an account with email')
        : text('เข้าสู่ระบบด้วยอีเมล', 'Sign in with email');
    final submitLabel = _createAccount
        ? text('สร้างบัญชี', 'Create account')
        : text('เข้าสู่ระบบ', 'Sign in');

    return AlertDialog(
      key: const ValueKey('email-sign-in-form'),
      scrollable: true,
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
              decoration: InputDecoration(
                label: Text(text('อีเมล', 'Email')),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_isSubmitting,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                label: Text(text('รหัสผ่าน', 'Password')),
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                localizeAuthMessage(context, _validationMessage!),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (_recoveryMessage != null) ...[
              const SizedBox(height: 12),
              Text(localizeAuthMessage(context, _recoveryMessage!),
                  style: const TextStyle(fontSize: 12)),
            ],
            if (!_createAccount && widget.controller.supportsEmailRecovery)
              TextButton(
                key: const ValueKey('email-forgot-password'),
                onPressed: _isSubmitting ? null : _resetPassword,
                child: Text(text('ลืมรหัสผ่าน?', 'Forgot password?')),
              ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _createAccount = !_createAccount),
              child: Text(
                _createAccount
                    ? text('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ',
                        'Already have an account? Sign in')
                    : text('ยังไม่มีบัญชี? สร้างบัญชีใหม่',
                        'New to PostDee? Create an account'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(text('ยกเลิก', 'Cancel')),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(_isSubmitting
              ? text('กำลังดำเนินการ...', 'Please wait...')
              : submitLabel),
        ),
      ],
    );
  }
}
