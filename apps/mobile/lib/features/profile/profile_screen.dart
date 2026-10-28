import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/localization/language_controller.dart';
import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../auth/phone_verification_screen.dart';
import '../auth/phone_verification_service.dart' show BoundPhoneAuthOperation;
import '../billing/paywall_screen.dart';
import '../legal/legal_document_screen.dart';
import '../platforms/connections_screen.dart';
import '../shared/postdee_undo_toast.dart';
import '../support/support_chat_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_draft_store.dart';
import 'profile_ui_motion.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.languageController,
    required this.themeController,
    required this.onOpenTemplates,
    required this.onDeleteAccount,
    this.onSignOut,
    this.isActive = true,
    this.loadSubscription,
    this.runNativePhoneAuthOperation,
    this.apiClient,
    this.launchConnectUrl,
    this.onManageSubscription,
    this.launchSubscriptionManagement,
    this.isDeletingAccount = false,
    this.profileDraftStore = const SharedPreferencesProfileDraftStore(),
    this.verifyPhone,
    this.onSendEmailVerification,
    this.onRefreshEmailVerification,
    this.onOpenSupportChat,
    super.key,
  });

  final PostDeeLanguageController languageController;
  final PostDeeThemeController themeController;
  final VoidCallback onOpenTemplates;
  final VoidCallback onDeleteAccount;
  final VoidCallback? onSignOut;
  final bool isActive;
  final PaywallSubscriptionLoader? loadSubscription;
  final BoundPhoneAuthOperation? runNativePhoneAuthOperation;
  final PostDeeApiClient? apiClient;
  final ConnectUrlLauncher? launchConnectUrl;
  final Future<void> Function()? onManageSubscription;
  final Future<bool> Function(Uri)? launchSubscriptionManagement;
  final bool isDeletingAccount;
  final ProfileDraftStore profileDraftStore;
  final Future<AuthSession?> Function(BuildContext context)? verifyPhone;
  final Future<bool> Function()? onSendEmailVerification;
  final Future<bool> Function()? onRefreshEmailVerification;

  /// Opens the support chat; defaults to pushing [SupportChatScreen].
  final VoidCallback? onOpenSupportChat;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();

  int? _connectedCount;
  var _isConnectedCountLoading = true;
  Object? _connectedCountLoadError;
  SubscriptionStatusResult? _subscription;
  var _isSubscriptionLoading = true;
  Object? _subscriptionLoadError;
  ProfileDraft? _profileDraft;
  var _connectedCountLoadGeneration = 0;
  var _subscriptionLoadGeneration = 0;
  var _profileDraftLoadGeneration = 0;
  String? _accountScope;
  bool _isEmailActionBusy = false;

  String _text(String thai, String english) =>
      _profileText(context, thai, english);

  String? get _currentAccountScope {
    final session = PostDeeAuthSessionStore.instance.session;
    if (!session.isSignedIn) return null;
    return session.stableUserId ?? session.email?.trim().toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountScope = _currentAccountScope;
    PostDeeAuthSessionStore.instance.addListener(_handleSessionChanged);
    _loadConnectedCount();
    _loadSubscription();
    _loadProfileDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PostDeeAuthSessionStore.instance.removeListener(_handleSessionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _loadSubscription();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _loadSubscription();
    }
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final scope = _currentAccountScope;
    if (scope != _accountScope) {
      _accountScope = scope;
      _profileDraftLoadGeneration += 1;
      _connectedCountLoadGeneration += 1;
      _subscriptionLoadGeneration += 1;
      setState(() {
        _profileDraft = null;
        _subscription = null;
        _connectedCount = null;
        _isEmailActionBusy = false;
      });
      if (scope != null) {
        _loadProfileDraft();
        _loadConnectedCount();
        _loadSubscription();
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _loadProfileDraft() async {
    final generation = ++_profileDraftLoadGeneration;
    final scope = _currentAccountScope;
    final draft = await widget.profileDraftStore.load();
    if (!mounted ||
        draft == null ||
        generation != _profileDraftLoadGeneration ||
        scope != _currentAccountScope) {
      return;
    }

    final session = PostDeeAuthSessionStore.instance.session;
    final sessionEmail = session.email?.trim().toLowerCase() ?? '';
    if (draft.accountUserId.isNotEmpty) {
      if (draft.accountUserId != session.stableUserId) return;
    } else if (draft.accountEmail.isEmpty ||
        sessionEmail.isEmpty ||
        draft.accountEmail != sessionEmail) {
      return;
    }

    setState(() => _profileDraft = draft);
    if (draft.displayName.isNotEmpty) {
      PostDeeAuthSessionStore.instance.updateDisplayName(draft.displayName);
    }
  }

  Future<void> _loadConnectedCount() async {
    final loadGeneration = ++_connectedCountLoadGeneration;
    setState(() {
      _isConnectedCountLoading = true;
      _connectedCountLoadError = null;
    });

    try {
      final results = await _apiClient.listSocialConnections();
      if (!mounted || loadGeneration != _connectedCountLoadGeneration) return;
      final statuses = {for (final result in results) result.platform: result};
      setState(() {
        _connectedCount = connectablePlatforms
            .where(
                (platform) => statuses[platform.apiValue]?.connected ?? false)
            .length;
        _isConnectedCountLoading = false;
        _connectedCountLoadError = null;
      });
    } catch (error) {
      if (!mounted || loadGeneration != _connectedCountLoadGeneration) return;
      setState(() {
        _isConnectedCountLoading = false;
        _connectedCountLoadError = error;
      });
    }
  }

  Future<void> _openSubscriptionManagement() async {
    final binding = PostDeeAuthSessionStore.instance.captureSession();
    final platform = Theme.of(context).platform;
    final store = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                _profileText(sheetContext, 'เลือกร้านค้าที่สมัคร',
                    'Choose your subscription store'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(_profileText(
                sheetContext,
                'เลือกตามร้านค้าที่เคยชำระเงิน แม้ตอนนี้จะใช้เครื่องคนละระบบ '
                    'คุณตรวจสอบรายการได้ก่อนยกเลิกสมาชิก',
                'Choose the store you paid through, even if you now use a different device. You can review your subscription before canceling it.')),
            const SizedBox(height: 12),
            for (final choice in [
              (
                id: 'google-play',
                name: 'Google Play',
                current: platform == TargetPlatform.android
              ),
              (
                id: 'app-store',
                name: 'App Store',
                current: platform == TargetPlatform.iOS
              ),
            ])
              ListTile(
                key: ValueKey('manage-subscription-${choice.id}'),
                title: Text(choice.name),
                subtitle: choice.current
                    ? Text(_profileText(sheetContext, 'ร้านค้าบนเครื่องนี้',
                        'Store on this device'))
                    : null,
                trailing: const Icon(Icons.open_in_new),
                onTap: () => Navigator.of(sheetContext).pop(choice.id),
              ),
            TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(_profileText(sheetContext, 'กลับไป', 'Back'))),
          ],
        )),
      ),
    );
    if (!mounted || !binding.isCurrent || store == null) return;
    final uri = Uri.parse(store == 'app-store'
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions');
    var launched = false;

    try {
      launched = await (widget.launchSubscriptionManagement?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      launched = false;
    }

    if (!launched && mounted && binding.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
              'เปิดหน้าจัดการสมาชิกไม่ได้ กรุณาเปิดจาก App Store หรือ Google Play',
              'Could not open subscription management. Open it from the App Store or Google Play.')),
        ),
      );
    }
  }

  Future<void> _loadSubscription() async {
    final loadGeneration = ++_subscriptionLoadGeneration;

    setState(() {
      _isSubscriptionLoading = true;
      _subscriptionLoadError = null;
    });

    try {
      final loader =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      final subscription = await loader();
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) return;
      setState(() {
        _subscription = subscription;
        _isSubscriptionLoading = false;
        _subscriptionLoadError = null;
      });
    } on SocketException catch (error) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) return;
      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionLoadError = error;
      });
    } catch (error) {
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) return;
      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionLoadError = error;
      });
    }
  }

  Future<void> _openPaywall() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PaywallScreen(
          onAddonPurchased: () { if (mounted) _loadSubscription(); },
          loadSubscription:
              widget.loadSubscription ?? _apiClient.loadCurrentSubscription,
        ),
      ),
    );

    if (mounted) {
      await _loadSubscription();
    }
  }

  void _updateConnectedCount(int count) {
    if (!mounted) return;
    _connectedCountLoadGeneration += 1;
    if (count == _connectedCount &&
        !_isConnectedCountLoading &&
        _connectedCountLoadError == null) {
      return;
    }
    setState(() {
      _connectedCount = count;
      _isConnectedCountLoading = false;
      _connectedCountLoadError = null;
    });
  }

  Future<void> _openConnections() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ConnectionsScreen(
          apiClient: widget.apiClient,
          launchConnectUrl: widget.launchConnectUrl,
          onConnectionsChanged: _updateConnectedCount,
        ),
      ),
    );
    if (mounted) await _loadConnectedCount();
  }

  Future<void> _openEditProfile() async {
    final scope = _currentAccountScope;
    final session = PostDeeAuthSessionStore.instance.session;
    final email = session.email?.trim() ?? '';
    final savedDraft = _profileDraft;
    final previous = ProfileDraft(
      displayName: savedDraft?.displayName ?? session.displayLabel,
      storeName: savedDraft?.storeName ?? '',
      accountEmail: email.toLowerCase(),
      accountUserId: session.stableUserId ?? '',
    );
    final updated = await Navigator.of(context).push<ProfileDraft>(
      MaterialPageRoute<ProfileDraft>(
        builder: (context) => EditProfileScreen(
          initialDraft: previous,
          email: email.isEmpty
              ? _text('ยังไม่ได้เชื่อมอีเมล', 'Email not connected')
              : email,
          emailVerified: session.emailVerified,
        ),
      ),
    );

    if (updated == null || !mounted || scope != _currentAccountScope) return;

    await widget.profileDraftStore.save(updated);
    if (!mounted || scope != _currentAccountScope) return;

    setState(() => _profileDraft = updated);
    PostDeeAuthSessionStore.instance.updateDisplayName(updated.displayName);

    showPostDeeUndoToast(
      context,
      message: _text('บันทึกโปรไฟล์แล้ว', 'Profile saved'),
      undoLabel: _text('เลิกทำ', 'Undo'),
      onUndo: () async {
        if (scope != _currentAccountScope) return;
        if (previous.displayName.isEmpty && previous.storeName.isEmpty) {
          await widget.profileDraftStore.clear();
        } else {
          await widget.profileDraftStore.save(previous);
        }
        if (!mounted || scope != _currentAccountScope) return;
        setState(() => _profileDraft = previous);
        PostDeeAuthSessionStore.instance
            .updateDisplayName(previous.displayName);
      },
    );
  }

  Future<void> _verifyPhone() async {
    final owner = _currentAccountScope;
    final binding = PostDeeAuthSessionStore.instance.captureSession();
    final session = widget.verifyPhone != null
        ? await widget.verifyPhone!(context)
        : await Navigator.of(context).push<AuthSession>(
            MaterialPageRoute<AuthSession>(
                builder: (_) => PhoneVerificationScreen(
                      runNativeAuthOperation: widget.runNativePhoneAuthOperation,
                      onVerified: (verified) {
                        if (binding.isCurrent && _currentAccountScope == owner &&
                            verified.stableUserId ==
                                PostDeeAuthSessionStore
                                    .instance.session.stableUserId) {
                          PostDeeAuthSessionStore.instance.updateCredentials(verified);
                        }
                      },
                    )),
          );
    if (!mounted || !binding.isCurrent || owner != _currentAccountScope) return;
    if (session != null &&
        session.stableUserId ==
            PostDeeAuthSessionStore.instance.session.stableUserId) {
      PostDeeAuthSessionStore.instance.updateCredentials(session);
    }
    await _loadSubscription();
  }

  Future<void> _emailAction({required bool refresh}) async {
    if (_isEmailActionBusy) return;
    final owner = _currentAccountScope;
    setState(() => _isEmailActionBusy = true);
    final action = refresh
        ? widget.onRefreshEmailVerification
        : widget.onSendEmailVerification;
    var success = false;
    try {
      success = await action?.call() ?? false;
    } catch (_) {}
    if (!mounted || owner != _currentAccountScope) return;
    setState(() => _isEmailActionBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
      !success
          ? _text('ดำเนินการไม่สำเร็จ กรุณาลองใหม่',
              'Could not complete this action. Please try again.')
          : refresh
              ? (PostDeeAuthSessionStore.instance.session.emailVerified
                  ? _text('ยืนยันอีเมลแล้ว', 'Email verified')
                  : _text('อีเมลยังไม่ยืนยัน กรุณาเปิดลิงก์ในอีเมลก่อน',
                      'Your email is not verified yet. Open the link in your email first.'))
              : _text('ส่งลิงก์ยืนยันแล้ว กรุณาตรวจสอบกล่องอีเมลและจดหมายขยะ',
                  'Verification link sent. Check your inbox and spam folder.'),
    )));
  }

  String? get _currentTierId {
    final plan = _subscription?.plan.toUpperCase();
    return switch (plan) {
      'PRO' => 'pro',
      'STARTER' => 'starter',
      'BASIC' || 'FREE' => 'free',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = PostDeeAuthSessionStore.instance.session;
    final savedDisplayName = _profileDraft?.displayName.trim();
    final accountName = savedDisplayName != null && savedDisplayName.isNotEmpty
        ? savedDisplayName
        : session.isSignedIn
            ? session.displayLabel
            : _text('ยังไม่ได้เชื่อมบัญชี', 'Account not connected');
    final accountEmail = session.email?.trim();
    final accountDetail = accountEmail == null || accountEmail.isEmpty
        ? _text('เชื่อมอีเมลก่อนใช้งานจริง',
            'Connect your email before using live features.')
        : accountEmail;
    final phoneVerified = _subscription?.phoneVerified ?? false;
    final connectedLabel = _isConnectedCountLoading
        ? _text('กำลังโหลดช่องทาง...', 'Loading channels...')
        : _connectedCountLoadError != null
            ? _text('โหลดข้อมูลช่องทางไม่สำเร็จ', 'Could not load channels')
            : _text(
                '${_connectedCount!}/${connectablePlatforms.length} เชื่อมต่อ',
                '${_connectedCount!}/${connectablePlatforms.length} connected');

    return AccountUiMotionScope(
      enabled: widget.isActive,
      child: Builder(
        builder: (motionContext) => AccountUiEntrance(
          key: const ValueKey('profile-content-motion'),
          isActive: widget.isActive,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, AppTheme.navOverlap),
            children: [
              Text(
                _text('บัญชีและโปรไฟล์', 'Account and profile'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _text('จัดการบัญชีและการตั้งค่า',
                    'Manage your account and settings'),
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              _ProfileSection(
                title: _text('บัญชีของฉัน', 'My account'),
                children: [
                  _ProfileHeaderCard(
                    name: accountName,
                    email: accountDetail,
                    hasEmail: accountEmail != null && accountEmail.isNotEmpty,
                    emailVerified: session.emailVerified,
                    onEdit: _openEditProfile,
                  ),
                  if (!session.emailVerified &&
                      accountEmail != null &&
                      accountEmail.isNotEmpty &&
                      widget.onSendEmailVerification != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      children: [
                        AccountUiPress(
                          enabled: !_isEmailActionBusy,
                          child: TextButton(
                            key: const ValueKey(
                                'profile-send-email-verification'),
                            onPressed: _isEmailActionBusy
                                ? null
                                : () => _emailAction(refresh: false),
                            child: Text(_text(
                                'ส่งอีเมลยืนยัน', 'Send verification email')),
                          ),
                        ),
                        AccountUiPress(
                          enabled: !_isEmailActionBusy,
                          child: TextButton(
                            key: const ValueKey(
                                'profile-refresh-email-verification'),
                            onPressed: _isEmailActionBusy
                                ? null
                                : () => _emailAction(refresh: true),
                            child: Text(_text(
                                'ตรวจสอบการยืนยัน', 'Check verification')),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _ProfileMenuCard(
                    rows: [
                      _ProfileMenuRow(
                        icon: Icons.phone_outlined,
                        label: _text('ยืนยันเบอร์โทร', 'Verify phone number'),
                        trailing: _isSubscriptionLoading &&
                                _subscription == null
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : _subscriptionLoadError != null &&
                                    _subscription == null
                                ? Text(
                                    _text('โหลดไม่สำเร็จ', 'Could not load'),
                                    style: TextStyle(
                                        color: AppTheme.textSecondary),
                                  )
                                : _subscription == null
                                    ? null
                                    : _StatusPill(
                                        label: phoneVerified
                                            ? _text('ยืนยันแล้ว', 'Verified')
                                            : _text(
                                                'ยังไม่ยืนยัน', 'Not verified'),
                                        background: phoneVerified
                                            ? AppTheme.mint
                                            : AppTheme.glassDeep,
                                        foreground: phoneVerified
                                            ? AppTheme.accentCyanInk
                                            : AppTheme.textSecondary,
                                      ),
                        onTap: _verifyPhone,
                      ),
                    ],
                  ),
                ],
              ),
              _ProfileSection(
                title: _text('ช่องทางและเครื่องมือ', 'Channels and tools'),
                children: [
                  _ProfileMenuCard(
                    rows: [
                      _ProfileMenuRow(
                        key: const ValueKey('profile-connections-row'),
                        icon: Icons.hub_outlined,
                        label: _text('เชื่อมต่อช่องทาง', 'Connect channels'),
                        detail: connectedLabel,
                        onTap: _openConnections,
                      ),
                    ],
                  ),
                  if (_connectedCountLoadError != null) ...[
                    const SizedBox(height: 10),
                    _ProfileDataStatusCard(
                      key: const ValueKey('profile-connections-error'),
                      message: _text('โหลดข้อมูลช่องทางไม่สำเร็จ',
                          'Could not load channels'),
                      retryKey: const ValueKey('profile-retry-connections'),
                      onRetry: _loadConnectedCount,
                    ),
                  ],
                ],
              ),
              _ProfileSection(
                title: _text('แพ็กเกจของฉัน', 'My plan'),
                children: [
                  if (_isSubscriptionLoading)
                    _ProfileDataStatusCard(
                      key: const ValueKey('profile-subscription-loading'),
                      message:
                          _text('กำลังโหลดข้อมูลแพ็กเกจ...', 'Loading plan...'),
                      isLoading: true,
                    )
                  else if (_subscriptionLoadError != null)
                    _ProfileDataStatusCard(
                      key: const ValueKey('profile-subscription-error'),
                      message: _text(
                          'โหลดข้อมูลแพ็กเกจไม่สำเร็จ', 'Could not load plan'),
                      retryKey: const ValueKey('profile-retry-subscription'),
                      onRetry: _loadSubscription,
                    )
                  else if (_subscription != null)
                    _CurrentPlanCard(
                      key: ValueKey(
                          'profile-plan-${_currentTierId ?? 'unknown'}'),
                      subscription: _subscription!,
                    ),
                  const SizedBox(height: 10),
                  _ProfileMenuCard(
                    rows: [
                      _ProfileMenuRow(
                        key: const ValueKey('profile-view-plans'),
                        icon: Icons.workspace_premium_outlined,
                        label: _text('ดูแพ็กเกจทั้งหมด', 'View all plans'),
                        onTap: _openPaywall,
                      ),
                      _ProfileMenuRow(
                        icon: Icons.credit_card_outlined,
                        label: _text('จัดการสมาชิก', 'Manage subscription'),
                        onTap: widget.onManageSubscription ??
                            _openSubscriptionManagement,
                      ),
                    ],
                  ),
                ],
              ),
              _ProfileSection(
                title: _text('ตั้งค่าและช่วยเหลือ', 'Settings and help'),
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      widget.languageController,
                      widget.themeController,
                    ]),
                    builder: (context, _) {
                      final l10n = PostDeeLocalizations.of(context);
                      final locale = widget.languageController.locale ??
                          Localizations.localeOf(context);
                      return _ProfileMenuCard(
                        rows: [
                          _ProfileMenuRow(
                            key: const ValueKey('profile-language-row'),
                            icon: Icons.language_outlined,
                            label: l10n.profileLanguageTitle,
                            trailing: Text(
                              locale.languageCode == 'en'
                                  ? l10n.languageEnglish
                                  : l10n.languageThai,
                            ),
                            onTap: () => _chooseLanguage(motionContext),
                          ),
                          _ProfileMenuRow(
                            key: const ValueKey('profile-theme-row'),
                            icon: Icons.contrast_outlined,
                            label: _profileText(
                                context, 'โหมดการแสดงผล', 'Display mode'),
                            trailing: Text(
                              widget.themeController.isLightMode
                                  ? _profileText(context, 'สว่าง', 'Light')
                                  : _profileText(context, 'มืด', 'Dark'),
                            ),
                            onTap: () => _chooseTheme(motionContext),
                          ),
                          _ProfileMenuRow(
                            icon: Icons.security_outlined,
                            label: _profileText(
                                context, 'ความปลอดภัย', 'Security'),
                            onTap: () => _openLegal(context, _securityInfo),
                          ),
                          _ProfileMenuRow(
                            key: const ValueKey('profile-support-chat-row'),
                            icon: Icons.chat_bubble_outline,
                            label: _profileText(
                                context, 'แชทกับทีมงาน', 'Chat with the team'),
                            onTap: widget.onOpenSupportChat ??
                                () => _openSupportChat(context),
                          ),
                          _ProfileMenuRow(
                            icon: Icons.help_outline,
                            label: _profileText(context, 'ช่วยเหลือ', 'Help'),
                            onTap: () => _openLegal(context, _helpInfo),
                          ),
                          _ProfileMenuRow(
                            icon: Icons.privacy_tip_outlined,
                            label: _profileText(context,
                                'นโยบายความเป็นส่วนตัว', 'Privacy policy'),
                            onTap: () => _openLegal(
                              context,
                              PostDeeLegalDocuments.privacyPolicy,
                            ),
                          ),
                          _ProfileMenuRow(
                            icon: Icons.description_outlined,
                            label: _profileText(context, 'ข้อกำหนดการใช้งาน',
                                'Terms of service'),
                            onTap: () => _openLegal(
                              context,
                              PostDeeLegalDocuments.termsOfService,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (widget.onSignOut != null) ...[
                _ProfileMenuCard(
                  rows: [
                    _ProfileMenuRow(
                      icon: Icons.logout,
                      label: _text('ออกจากระบบ', 'Sign out'),
                      onTap: widget.onSignOut,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              _DeleteAccountButton(
                onDeleteAccount: widget.onDeleteAccount,
                onManageSubscription:
                    widget.onManageSubscription ?? _openSubscriptionManagement,
                isDeleting: widget.isDeletingAccount,
                subscription:
                    _subscriptionLoadError == null && !_isSubscriptionLoading
                        ? _subscription
                        : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLanguage(BuildContext motionContext) async {
    final locale = await _showSettingChoices<Locale>(
      motionContext,
      titleBuilder: (sheetContext) =>
          PostDeeLocalizations.of(sheetContext).profileLanguageTitle,
      current:
          widget.languageController.locale ?? Localizations.localeOf(context),
      choicesBuilder: (sheetContext) {
        final l10n = PostDeeLocalizations.of(sheetContext);
        return [
          (value: const Locale('th'), label: l10n.languageThai),
          (value: const Locale('en'), label: l10n.languageEnglish),
        ];
      },
    );
    if (locale != null && mounted) widget.languageController.setLocale(locale);
  }

  Future<void> _chooseTheme(BuildContext motionContext) async {
    final mode = await _showSettingChoices<ThemeMode>(
      motionContext,
      titleBuilder: (sheetContext) =>
          _profileText(sheetContext, 'โหมดการแสดงผล', 'Display mode'),
      current: widget.themeController.themeMode,
      choicesBuilder: (sheetContext) => [
        (
          value: ThemeMode.light,
          label: _profileText(sheetContext, 'สว่าง', 'Light')
        ),
        (
          value: ThemeMode.dark,
          label: _profileText(sheetContext, 'มืด', 'Dark')
        ),
      ],
    );
    if (mode != null && mounted) {
      await widget.themeController.setThemeMode(mode);
    }
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ProfileDataStatusCard extends StatelessWidget {
  const _ProfileDataStatusCard({
    super.key,
    required this.message,
    this.isLoading = false,
    this.retryKey,
    this.onRetry,
  });

  final String message;
  final bool isLoading;
  final Key? retryKey;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              if (isLoading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 4),
            AccountUiPress(
              child: TextButton(
                key: retryKey,
                onPressed: onRetry,
                child: Text(_profileText(context, 'ลองใหม่', 'Try again')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.name,
    required this.email,
    required this.hasEmail,
    required this.emailVerified,
    required this.onEdit,
  });

  final String name;
  final String email;
  final bool hasEmail;
  final bool emailVerified;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initial =
        name.trim().isEmpty ? 'P' : name.trim().characters.first.toUpperCase();

    return AccountUiPress(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Semantics(
          button: true,
          label: _profileText(context, 'แก้ไขโปรไฟล์', 'Edit profile'),
          child: InkWell(
            key: const ValueKey('profile-edit-button'),
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentCyanInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          emailVerified
                              ? _profileText(
                                  context, 'ยืนยันอีเมลแล้ว', 'Email verified')
                              : hasEmail
                                  ? _profileText(context, 'อีเมลยังไม่ยืนยัน',
                                      'Email not verified')
                                  : _profileText(context, 'ยังไม่เชื่อมอีเมล',
                                      'Email not connected'),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _profileText(context, 'แก้ไขโปรไฟล์', 'Edit profile'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentCyanInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 20, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.55;

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({required this.rows});

  final List<_ProfileMenuRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i += 1) ...[
            if (i > 0)
              Divider(height: 1, indent: 50, color: AppTheme.borderSoft),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.icon,
    required this.label,
    this.detail,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stackValue = MediaQuery.textScalerOf(context).scale(14) > 18;
    final value = trailing == null
        ? null
        : DefaultTextStyle(
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            child: trailing!,
          );
    return AccountUiPress(
      enabled: onTap != null,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
            child: Row(
              children: [
                Icon(icon, size: 21, color: AppTheme.textSecondary),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail!,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      if (stackValue && value != null) ...[
                        const SizedBox(height: 6),
                        value,
                      ],
                    ],
                  ),
                ),
                if (!stackValue && value != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.32,
                    ),
                    child: value,
                  ),
                ],
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.subscription, super.key});

  final SubscriptionStatusResult subscription;

  @override
  Widget build(BuildContext context) {
    final plan = subscription.plan.toUpperCase();
    final name = switch (plan) {
      'BASIC' || 'FREE' => _profileText(context, 'ฟรี', 'Free'),
      'STARTER' => 'Starter',
      'PRO' => 'Pro',
      _ => _profileText(context, 'ไม่รู้จักแพ็กเกจนี้', 'Unknown plan'),
    };
    final isPaid = plan == 'STARTER' || plan == 'PRO';
    final status = switch (subscription.status.toUpperCase()) {
      'ACTIVE' => _profileText(context, 'ใช้งานอยู่', 'Active'),
      'INACTIVE' => _profileText(context, 'ยังไม่เปิดใช้งาน', 'Inactive'),
      'EXPIRED' => _profileText(context, 'หมดอายุ', 'Expired'),
      'CANCELED' ||
      'CANCELLED' =>
        _profileText(context, 'ยกเลิกแล้ว', 'Canceled'),
      _ => _profileText(context, 'ตรวจสอบสถานะในหน้าจัดการสมาชิก',
          'Check status in Manage subscription'),
    };
    final remaining = subscription.remainingPostsThisMonth;
    final limit = subscription.monthlyPostLimit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.workspace_premium_outlined,
              size: 24,
              color: AppTheme.accentCyanInk,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileText(context, 'แพ็กเกจปัจจุบัน', 'Current plan'),
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (isPaid) ...[
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                if (remaining != null && limit != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _profileText(
                        context,
                        'เหลือโพสต์ $remaining / $limit หน่วยเดือนนี้',
                        '$remaining / $limit post units left this month'),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                if (subscription.addonPostUnits > 0 ||
                    subscription.addonAiCaptions > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                      _profileText(
                          context,
                          'เครดิตซื้อเพิ่มคงเหลือ: โพสต์ ${subscription.addonPostUnits} หน่วย · AI ${subscription.addonAiCaptions} เครดิต',
                          'Purchased credits remaining: ${subscription.addonPostUnits} post units · ${subscription.addonAiCaptions} AI caption credits'),
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                      isPaid
                          ? _profileText(
                              context,
                              'เครดิตซื้อเพิ่มไม่หมดอายุ · ใช้โควตารายเดือนก่อน',
                              'Purchased credits do not expire · Monthly quota is used first')
                          : _profileText(
                              context,
                              'เครดิตยังอยู่ ใช้ได้เมื่อสมัคร Starter หรือ Pro',
                              'Your credits are retained and become usable with Starter or Pro'),
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  if (isPaid && subscription.availablePostUnits != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        _profileText(
                            context,
                            'โพสต์ได้รวม ${subscription.availablePostUnits} หน่วย',
                            'Total available: ${subscription.availablePostUnits} post units'),
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ],
                if (subscription.monthlyQuotaResetsAt case final reset?) ...[
                  const SizedBox(height: 4),
                  Text(
                      _profileText(
                          context,
                          'โควตารายเดือนเริ่มรอบใหม่ ${_quotaResetLabel(reset)} (เวลาท้องถิ่น)',
                          'Monthly quota resets on ${_quotaResetLabel(reset, languageCode: 'en')} (local time)'),
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _quotaResetLabel(DateTime value, {String languageCode = 'th'}) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} ${languageCode == 'th' ? 'เวลา' : 'at'} $hour:$minute';
}

void _openSupportChat(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const SupportChatScreen()),
  );
}

void _openLegal(BuildContext context, LegalDocument document) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => LegalDocumentScreen(document: document),
    ),
  );
}

const _securityInfo = LegalDocument(
  title: 'ความปลอดภัย',
  body: 'PostDee ดูแลความปลอดภัยของบัญชีและข้อมูลของคุณ\n\n'
      '- การเข้าสู่ระบบด้วยอีเมลหรือ Google จัดการผ่าน Firebase Authentication '
      'และแอปไม่เก็บรหัสผ่านของคุณ\n'
      '- โทเคนการเชื่อมต่อบัญชีโซเชียลถูกเก็บอย่างปลอดภัยบนเซิร์ฟเวอร์\n'
      '- คีย์ลับของระบบ AI อยู่ฝั่งเซิร์ฟเวอร์เท่านั้น ไม่อยู่ในแอป\n\n'
      'หากพบกิจกรรมที่น่าสงสัย ติดต่อ postdee.support@gmail.com',
);

const _helpInfo = LegalDocument(
  title: 'ช่วยเหลือ',
  body: 'ต้องการความช่วยเหลือใช่ไหม?\n\n'
      'เริ่มต้นใช้งาน\n'
      '1. เลือกคลิปวิดีโอแนวตั้ง 9:16\n'
      '2. เลือกแพลตฟอร์มที่จะโพสต์\n'
      '3. โพสต์ทันที หรือ ตั้งเวลาไว้ในปฏิทิน\n\n'
      'คำถามที่พบบ่อย\n'
      '- โควตาโพสต์ฟรีคิดอย่างไร? แพ็กเกจ Basic ได้ 3 หน่วยต่อเดือนหลังยืนยันเบอร์\n'
      '  1 ช่องทางใช้ 1 หน่วย เช่น 1 คลิปลง 3 ช่องทาง ใช้ 3 หน่วย\n'
      '- ตั้งเวลาโพสต์ได้ไหม? Starter ล่วงหน้าได้ 14 วัน และ Pro 30 วัน\n\n'
      'ติดต่อทีมงาน: กดแชทกับทีมงานในหน้าบัญชี หรืออีเมล postdee.support@gmail.com',
);

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({
    required this.onDeleteAccount,
    required this.onManageSubscription,
    required this.isDeleting,
    this.subscription,
  });

  final VoidCallback onDeleteAccount;
  final Future<void> Function() onManageSubscription;
  final bool isDeleting;
  final SubscriptionStatusResult? subscription;

  Future<void> _confirm(BuildContext context) async {
    final binding = PostDeeAuthSessionStore.instance.captureSession();
    final originTicker = TickerMode.getValuesNotifier(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0A120E).withValues(alpha: 0.5),
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => AccountUiOriginScope(
        originTicker: originTicker,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Container(
            key: const ValueKey('delete-account-confirm-sheet'),
            padding: const EdgeInsets.all(22),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
            ),
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x550A120E),
                  blurRadius: 50,
                  spreadRadius: -16,
                  offset: Offset(0, 24),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      size: 28,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _profileText(sheetContext, 'ก่อนลบบัญชี',
                        'Before deleting your account'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _profileText(
                        sheetContext,
                        'ระบบจะลบข้อมูลบัญชีที่อยู่บนบริการของ PostDee อย่างถาวร '
                            'ฉบับร่างและไฟล์ในเครื่องนี้ รวมถึงสำเนาสำรองของระบบ '
                            'อาจยังคงอยู่ หากต้องการลบ ให้ลบฉบับร่างก่อนลบบัญชี '
                            'หรือล้างข้อมูลแอปและจัดการข้อมูลสำรองแยกต่างหาก',
                        'Your account data on PostDee services will be permanently deleted. Drafts and files on this device, including system backups, may remain. To remove them, delete drafts before deleting your account, or clear app data and manage backups separately.'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subscription != null &&
                            (subscription!.addonPostUnits > 0 ||
                                subscription!.addonAiCaptions > 0)
                        ? _profileText(
                            sheetContext,
                            'คุณมีเครดิตซื้อเพิ่มคงเหลือ: โพสต์ ${subscription!.addonPostUnits} หน่วย · AI ${subscription!.addonAiCaptions} เครดิต '
                                'หลังลบบัญชีจะใช้เครดิตเหล่านี้ไม่ได้ กรุณาตรวจสอบก่อนยืนยัน',
                            'You have purchased credits remaining: ${subscription!.addonPostUnits} post units · ${subscription!.addonAiCaptions} AI caption credits. These credits cannot be used after account deletion. Review them before confirming.')
                        : _profileText(
                            sheetContext,
                            'หากมีเครดิตซื้อเพิ่มคงเหลือ หลังลบบัญชีจะใช้เครดิตเหล่านี้ไม่ได้ '
                                'กรุณาตรวจสอบยอดก่อนยืนยัน',
                            'Any purchased credits remaining cannot be used after account deletion. Check your balance before confirming.'),
                    style: TextStyle(
                        fontSize: 13, height: 1.5, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF2C66D)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: Color(0xFF9A6700),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _profileText(
                                sheetContext,
                                'การลบบัญชี PostDee ไม่ได้ยกเลิกแพ็กเกจ Starter/Pro '
                                    'ที่ซื้อผ่าน App Store หรือ Google Play หากไม่ต้องการให้ต่ออายุ '
                                    'กรุณายกเลิกสมาชิกในร้านค้าก่อนลบบัญชี',
                                'Deleting your PostDee account does not cancel Starter/Pro subscriptions purchased through the App Store or Google Play. To stop renewal, cancel your subscription in the store before deleting your account.'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Color(0xFF6B4F00),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      minHeight: 46,
                    ),
                    child: AccountUiPress(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await onManageSubscription();
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(_profileText(sheetContext, 'จัดการสมาชิก',
                            'Manage subscription')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentCyanInk,
                          side: BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 50),
                          child: AccountUiPress(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textPrimary,
                                side: BorderSide(color: AppTheme.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(_profileText(
                                  sheetContext, 'ยกเลิก', 'Cancel')),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 50),
                          child: AccountUiPress(
                            enabled: !isDeleting,
                            child: FilledButton(
                              onPressed: isDeleting
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: isDeleting
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(_profileText(
                                      sheetContext,
                                      'ลบบัญชีถาวร',
                                      'Delete account permanently')),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true && context.mounted && binding.isCurrent) {
      onDeleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFEF4444);

    return AccountUiPress(
      enabled: !isDeleting,
      child: Semantics(
        button: true,
        label: _profileText(context, 'ลบบัญชี', 'Delete account'),
        child: OutlinedButton.icon(
          onPressed: isDeleting ? null : () => _confirm(context),
          icon: const Icon(Icons.delete_outline, color: errorColor, size: 19),
          label: Text(
            _profileText(context, 'ลบบัญชี', 'Delete account'),
            style: const TextStyle(
              color: errorColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: errorColor.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showSettingChoices<T>(
  BuildContext context, {
  required String Function(BuildContext) titleBuilder,
  required T current,
  required List<({T value, String label})> Function(BuildContext)
      choicesBuilder,
}) {
  final originTicker = TickerMode.getValuesNotifier(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.glass,
    builder: (context) => AccountUiOriginScope(
      originTicker: originTicker,
      child: AccountUiEntrance(
        key: const ValueKey('profile-setting-motion'),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: SingleChildScrollView(
              key: const ValueKey('profile-setting-sheet'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleBuilder(context),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        AccountUiPress(
                          child: IconButton(
                            tooltip: _profileText(context, 'ปิด', 'Close'),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final choice in choicesBuilder(context))
                    AccountUiPress(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        selected: choice.value == current,
                        selectedColor: AppTheme.accentCyanInk,
                        title: Text(choice.label),
                        trailing: choice.value == current
                            ? Icon(Icons.check, color: AppTheme.accentCyanInk)
                            : null,
                        onTap: () => Navigator.pop(context, choice.value),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _profileText(BuildContext context, String thai, String english) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                    ?.locale
                    .languageCode ??
                'th') ==
            'th'
        ? thai
        : english;
