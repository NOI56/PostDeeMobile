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
import '../billing/paywall_screen.dart';
import '../legal/legal_document_screen.dart';
import '../platforms/connections_screen.dart';
import '../shared/postdee_undo_toast.dart';
import 'edit_profile_screen.dart';
import 'profile_draft_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.languageController,
    required this.themeController,
    required this.onOpenTemplates,
    required this.onDeleteAccount,
    this.onSignOut,
    this.apiClient,
    this.launchConnectUrl,
    this.onManageSubscription,
    this.isDeletingAccount = false,
    this.profileDraftStore = const SharedPreferencesProfileDraftStore(),
    super.key,
  });

  final PostDeeLanguageController languageController;
  final PostDeeThemeController themeController;
  final VoidCallback onOpenTemplates;
  final VoidCallback onDeleteAccount;
  final VoidCallback? onSignOut;
  final PostDeeApiClient? apiClient;
  final ConnectUrlLauncher? launchConnectUrl;
  final Future<void> Function()? onManageSubscription;
  final bool isDeletingAccount;
  final ProfileDraftStore profileDraftStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadConnectedCount();
    _loadSubscription();
    _loadProfileDraft();
  }

  Future<void> _loadProfileDraft() async {
    final draft = await widget.profileDraftStore.load();
    if (!mounted || draft == null) return;

    final sessionEmail =
        PostDeeAuthSessionStore.instance.session.email?.trim().toLowerCase() ??
            '';
    if (draft.accountEmail.isNotEmpty &&
        sessionEmail.isNotEmpty &&
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
    final uri = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );
    var launched = false;

    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'เปิดหน้าจัดการสมาชิกไม่ได้ กรุณาเปิดจาก App Store หรือ Google Play'),
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
      final subscription = await _apiClient.loadCurrentSubscription();
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
          loadSubscription: _apiClient.loadCurrentSubscription,
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
    final session = PostDeeAuthSessionStore.instance.session;
    final email = session.email?.trim() ?? '';
    final savedDraft = _profileDraft;
    final previous = ProfileDraft(
      displayName: savedDraft?.displayName ?? session.displayLabel,
      storeName: savedDraft?.storeName ?? '',
      accountEmail: email.toLowerCase(),
    );
    final updated = await Navigator.of(context).push<ProfileDraft>(
      MaterialPageRoute<ProfileDraft>(
        builder: (context) => EditProfileScreen(
          initialDraft: previous,
          email: email.isEmpty ? 'ยังไม่ได้เชื่อมอีเมล' : email,
          emailVerified: session.emailVerified,
        ),
      ),
    );

    if (updated == null || !mounted) return;

    await widget.profileDraftStore.save(updated);
    if (!mounted) return;

    setState(() => _profileDraft = updated);
    PostDeeAuthSessionStore.instance.updateDisplayName(updated.displayName);

    showPostDeeUndoToast(
      context,
      message: 'บันทึกโปรไฟล์แล้ว',
      onUndo: () async {
        if (previous.displayName.isEmpty && previous.storeName.isEmpty) {
          await widget.profileDraftStore.clear();
        } else {
          await widget.profileDraftStore.save(previous);
        }
        if (!mounted) return;
        setState(() => _profileDraft = previous);
        PostDeeAuthSessionStore.instance
            .updateDisplayName(previous.displayName);
      },
    );
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
            : 'ยังไม่ได้เชื่อมบัญชี';
    final accountEmail = session.email?.trim();
    final accountDetail = accountEmail == null || accountEmail.isEmpty
        ? 'เชื่อมอีเมลก่อนใช้งานจริง'
        : accountEmail;
    final phoneVerified = _subscription?.phoneVerified ?? false;
    final connectedLabel = _isConnectedCountLoading
        ? 'กำลังโหลดช่องทาง...'
        : _connectedCountLoadError != null
            ? 'โหลดข้อมูลช่องทางไม่สำเร็จ'
            : '${_connectedCount!}/${connectablePlatforms.length} เชื่อมต่อ';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, AppTheme.navOverlap),
      children: [
        Text(
          'บัญชีและโปรไฟล์',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'จัดการบัญชีและการตั้งค่า',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        _ProfileSection(
          title: 'บัญชีของฉัน',
          children: [
            _ProfileHeaderCard(
              name: accountName,
              email: accountDetail,
              hasEmail: accountEmail != null && accountEmail.isNotEmpty,
              emailVerified: session.emailVerified,
              onEdit: _openEditProfile,
            ),
            const SizedBox(height: 10),
            _ProfileMenuCard(
              rows: [
                _ProfileMenuRow(
                  icon: Icons.phone_outlined,
                  label: 'ยืนยันเบอร์โทร',
                  trailing: _isSubscriptionLoading && _subscription == null
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _subscriptionLoadError != null && _subscription == null
                          ? Text(
                              'โหลดไม่สำเร็จ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            )
                          : _subscription == null
                              ? null
                              : _StatusPill(
                                  label: phoneVerified
                                      ? 'ยืนยันแล้ว'
                                      : 'ยังไม่ยืนยัน',
                                  background: phoneVerified
                                      ? AppTheme.mint
                                      : AppTheme.glassDeep,
                                  foreground: phoneVerified
                                      ? AppTheme.accentCyanInk
                                      : AppTheme.textSecondary,
                                ),
                  onTap: () => _openPhoneVerification(context),
                ),
              ],
            ),
          ],
        ),
        _ProfileSection(
          title: 'ช่องทางและเครื่องมือ',
          children: [
            _ProfileMenuCard(
              rows: [
                _ProfileMenuRow(
                  key: const ValueKey('profile-connections-row'),
                  icon: Icons.hub_outlined,
                  label: 'เชื่อมต่อช่องทาง',
                  detail: connectedLabel,
                  onTap: _openConnections,
                ),
              ],
            ),
            if (_connectedCountLoadError != null) ...[
              const SizedBox(height: 10),
              _ProfileDataStatusCard(
                key: const ValueKey('profile-connections-error'),
                message: 'โหลดข้อมูลช่องทางไม่สำเร็จ',
                retryKey: const ValueKey('profile-retry-connections'),
                onRetry: _loadConnectedCount,
              ),
            ],
          ],
        ),
        _ProfileSection(
          title: 'แพ็กเกจของฉัน',
          children: [
            if (_isSubscriptionLoading)
              const _ProfileDataStatusCard(
                key: ValueKey('profile-subscription-loading'),
                message: 'กำลังโหลดข้อมูลแพ็กเกจ...',
                isLoading: true,
              )
            else if (_subscriptionLoadError != null)
              _ProfileDataStatusCard(
                key: const ValueKey('profile-subscription-error'),
                message: 'โหลดข้อมูลแพ็กเกจไม่สำเร็จ',
                retryKey: const ValueKey('profile-retry-subscription'),
                onRetry: _loadSubscription,
              )
            else if (_subscription != null)
              _CurrentPlanCard(
                key: ValueKey('profile-plan-${_currentTierId ?? 'unknown'}'),
                subscription: _subscription!,
              ),
            const SizedBox(height: 10),
            _ProfileMenuCard(
              rows: [
                _ProfileMenuRow(
                  key: const ValueKey('profile-view-plans'),
                  icon: Icons.workspace_premium_outlined,
                  label: 'ดูแพ็กเกจทั้งหมด',
                  onTap: _openPaywall,
                ),
                _ProfileMenuRow(
                  icon: Icons.credit_card_outlined,
                  label: 'จัดการสมาชิก',
                  onTap: widget.onManageSubscription ??
                      _openSubscriptionManagement,
                ),
              ],
            ),
          ],
        ),
        _ProfileSection(
          title: 'ตั้งค่าและช่วยเหลือ',
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
                      onTap: _chooseLanguage,
                    ),
                    _ProfileMenuRow(
                      key: const ValueKey('profile-theme-row'),
                      icon: Icons.contrast_outlined,
                      label: 'โหมดการแสดงผล',
                      trailing: Text(
                        widget.themeController.isLightMode ? 'สว่าง' : 'มืด',
                      ),
                      onTap: _chooseTheme,
                    ),
                    _ProfileMenuRow(
                      icon: Icons.security_outlined,
                      label: 'ความปลอดภัย',
                      onTap: () => _openLegal(context, _securityInfo),
                    ),
                    _ProfileMenuRow(
                      icon: Icons.help_outline,
                      label: 'ช่วยเหลือ',
                      onTap: () => _openLegal(context, _helpInfo),
                    ),
                    _ProfileMenuRow(
                      icon: Icons.privacy_tip_outlined,
                      label: 'นโยบายความเป็นส่วนตัว',
                      onTap: () => _openLegal(
                        context,
                        PostDeeLegalDocuments.privacyPolicy,
                      ),
                    ),
                    _ProfileMenuRow(
                      icon: Icons.description_outlined,
                      label: 'ข้อกำหนดการใช้งาน',
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
                label: 'ออกจากระบบ',
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
        ),
      ],
    );
  }

  Future<void> _chooseLanguage() async {
    final l10n = PostDeeLocalizations.of(context);
    final locale = await _showSettingChoices<Locale>(
      context,
      title: l10n.profileLanguageTitle,
      current:
          widget.languageController.locale ?? Localizations.localeOf(context),
      choices: [
        (value: const Locale('th'), label: l10n.languageThai),
        (value: const Locale('en'), label: l10n.languageEnglish),
      ],
    );
    if (locale != null && mounted) widget.languageController.setLocale(locale);
  }

  Future<void> _chooseTheme() async {
    final mode = await _showSettingChoices<ThemeMode>(
      context,
      title: 'โหมดการแสดงผล',
      current: widget.themeController.themeMode,
      choices: [
        (value: ThemeMode.light, label: 'สว่าง'),
        (value: ThemeMode.dark, label: 'มืด'),
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
      child: Row(
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
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: retryKey,
              onPressed: onRetry,
              child: const Text('ลองใหม่'),
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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Semantics(
        button: true,
        label: 'แก้ไขโปรไฟล์',
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        emailVerified
                            ? 'ยืนยันอีเมลแล้ว'
                            : hasEmail
                                ? 'อีเมลยังไม่ยืนยัน'
                                : 'ยังไม่เชื่อมอีเมล',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'แก้ไขโปรไฟล์',
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
                Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
              ],
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
    return Semantics(
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
      'BASIC' || 'FREE' => 'ฟรี',
      'STARTER' => 'Starter',
      'PRO' => 'Pro',
      _ => 'ไม่รู้จักแพ็กเกจนี้',
    };
    final isPaid = plan == 'STARTER' || plan == 'PRO';
    final status = switch (subscription.status.toUpperCase()) {
      'ACTIVE' => 'ใช้งานอยู่',
      'INACTIVE' => 'ยังไม่เปิดใช้งาน',
      'EXPIRED' => 'หมดอายุ',
      'CANCELED' || 'CANCELLED' => 'ยกเลิกแล้ว',
      _ => 'ตรวจสอบสถานะในหน้าจัดการสมาชิก',
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
                  'แพ็กเกจปัจจุบัน',
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
                    'เหลือโพสต์ $remaining / $limit หน่วยเดือนนี้',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
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

void _openLegal(BuildContext context, LegalDocument document) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => LegalDocumentScreen(document: document),
    ),
  );
}

void _openPhoneVerification(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const PhoneVerificationScreen(),
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
      'หากพบกิจกรรมที่น่าสงสัย ติดต่อ support@postdee.app',
);

const _helpInfo = LegalDocument(
  title: 'ช่วยเหลือ',
  body: 'ต้องการความช่วยเหลือใช่ไหม?\n\n'
      'เริ่มต้นใช้งาน\n'
      '1. เลือกคลิปวิดีโอแนวตั้ง 9:16\n'
      '2. เลือกแพลตฟอร์มที่จะโพสต์\n'
      '3. โพสต์ทันที หรือ ตั้งเวลาไว้ในปฏิทิน\n\n'
      'คำถามที่พบบ่อย\n'
      '- โพสต์ฟรีได้กี่ครั้ง? แพ็กเกจ Basic โพสต์ฟรีได้ 3 ครั้งต่อเดือนหลังยืนยันเบอร์\n'
      '- ตั้งเวลาโพสต์ได้ไหม? ได้ในแพ็กเกจ Starter และ Pro\n\n'
      'ติดต่อทีมงาน: support@postdee.app',
);

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({
    required this.onDeleteAccount,
    required this.onManageSubscription,
    required this.isDeleting,
  });

  final VoidCallback onDeleteAccount;
  final Future<void> Function() onManageSubscription;
  final bool isDeleting;

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0A120E).withValues(alpha: 0.5),
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
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
                  'ก่อนลบบัญชี',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ระบบจะลบข้อมูลบัญชีที่อยู่บนบริการของ PostDee อย่างถาวร '
                  'ฉบับร่างและไฟล์ในเครื่องนี้ รวมถึงสำเนาสำรองของระบบ '
                  'อาจยังคงอยู่ หากต้องการลบ ให้ลบฉบับร่างก่อนลบบัญชี '
                  'หรือล้างข้อมูลแอปและจัดการข้อมูลสำรองแยกต่างหาก',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF2C66D)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: Color(0xFF9A6700),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'การลบบัญชี PostDee ไม่ได้ยกเลิกแพ็กเกจ Starter/Pro '
                          'ที่ซื้อผ่าน App Store หรือ Google Play หากไม่ต้องการให้ต่ออายุ '
                          'กรุณายกเลิกสมาชิกในร้านค้าก่อนลบบัญชี',
                          style: TextStyle(
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
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await onManageSubscription();
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('จัดการสมาชิก'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyanInk,
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
                          child: const Text('ยกเลิก'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 50),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('ลบบัญชีถาวร'),
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
    );

    if (confirmed == true) {
      onDeleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFEF4444);

    return Semantics(
      button: true,
      label: 'ลบบัญชี',
      child: OutlinedButton.icon(
        onPressed: isDeleting ? null : () => _confirm(context),
        icon: const Icon(Icons.delete_outline, color: errorColor, size: 19),
        label: const Text(
          'ลบบัญชี',
          style: TextStyle(
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
    );
  }
}

Future<T?> _showSettingChoices<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<({T value, String label})> choices,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.glass,
    builder: (context) => SafeArea(
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
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'ปิด',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              for (final choice in choices)
                ListTile(
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}
