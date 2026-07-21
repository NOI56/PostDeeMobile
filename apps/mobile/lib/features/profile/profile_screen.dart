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
import '../link_in_bio/link_in_bio_screen.dart';
import '../platforms/connections_screen.dart';
import '../shared/postdee_card.dart';
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

  int _connectedCount = 0;
  SubscriptionStatusResult? _subscription;
  ProfileDraft? _profileDraft;
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
    try {
      final results = await _apiClient.listSocialConnections();
      if (!mounted) return;
      final statuses = {for (final result in results) result.platform: result};
      _updateConnectedCount(
        connectablePlatforms
            .where(
                (platform) => statuses[platform.apiValue]?.connected ?? false)
            .length,
      );
    } catch (_) {
      // Keep the pill at 0 connected if the status call fails.
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

    try {
      final subscription = await _apiClient.loadCurrentSubscription();
      if (!mounted || loadGeneration != _subscriptionLoadGeneration) return;
      setState(() => _subscription = subscription);
    } on SocketException {
      // Offline: keep the default free-tier display.
    } catch (_) {
      // Keep the default free-tier display if the plan call fails.
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
    if (!mounted || count == _connectedCount) return;
    setState(() => _connectedCount = count);
  }

  void _openConnections() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConnectionsScreen(
          apiClient: widget.apiClient,
          launchConnectUrl: widget.launchConnectUrl,
          onConnectionsChanged: _updateConnectedCount,
        ),
      ),
    );
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

  String get _currentTierId {
    final plan = _subscription?.plan.toUpperCase();
    return switch (plan) {
      'PRO' => 'pro',
      'STARTER' => 'starter',
      _ => 'free',
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, AppTheme.navOverlap),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'บัญชีและโปรไฟล์',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (widget.onSignOut != null)
              Semantics(
                button: true,
                label: 'ออกจากระบบ',
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onSignOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.glass,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout,
                              size: 17, color: AppTheme.textSecondary),
                          const SizedBox(width: 5),
                          Text(
                            'ออก',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        _ProfileHeaderCard(
          name: accountName,
          email: accountDetail,
          hasEmail: accountEmail != null && accountEmail.isNotEmpty,
          emailVerified: session.emailVerified,
          connectedLabel:
              '$_connectedCount/${connectablePlatforms.length} เชื่อมต่อ',
          onOpenConnections: _openConnections,
          onEdit: _openEditProfile,
        ),
        const SizedBox(height: 13),
        _ProfileMenuCard(
          rows: [
            _ProfileMenuRow(
              icon: Icons.hub_outlined,
              label: 'เชื่อมต่อช่องทาง',
              trailing: _StatusPill(
                label: '$_connectedCount/${connectablePlatforms.length}',
                background: AppTheme.glassDeep,
                foreground: AppTheme.textSecondary,
              ),
              onTap: _openConnections,
            ),
            _ProfileMenuRow(
              icon: Icons.smartphone,
              label: 'ยืนยันเบอร์โทร',
              trailing: _subscription == null
                  ? null
                  : _StatusPill(
                      label: phoneVerified ? 'ยืนยันแล้ว' : 'ยังไม่ยืนยัน',
                      background:
                          phoneVerified ? AppTheme.mint : AppTheme.glassDeep,
                      foreground: phoneVerified
                          ? AppTheme.accentCyanInk
                          : AppTheme.textSecondary,
                    ),
              onTap: () => _openPhoneVerification(context),
            ),
            _ProfileMenuRow(
              icon: Icons.text_snippet_outlined,
              label: 'เทมเพลตแคปชั่น',
              onTap: widget.onOpenTemplates,
            ),
            _ProfileMenuRow(
              icon: Icons.link,
              label: 'ลิงก์หน้าโปรไฟล์',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const LinkInBioScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _LanguagePickerCard(languageController: widget.languageController),
        const SizedBox(height: 13),
        _ThemeModeCard(themeController: widget.themeController),
        const SizedBox(height: 15),
        Row(
          children: [
            Icon(Icons.workspace_premium_outlined,
                size: 20, color: AppTheme.accentCyanInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'แพ็กเกจ PostDee',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              '1 ช่องทาง = 1 หน่วย',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final tier in _tiers) ...[
          _TierCard(
            key: ValueKey('profile-plan-${tier.id}'),
            tier: tier,
            isCurrent: tier.id == _currentTierId,
            onTap: _openPaywall,
          ),
          const SizedBox(height: 10),
        ],
        if (_subscription?.isPro ?? false) ...[
          const SizedBox(height: 3),
          _AiEditingQuotaCard(apiClient: _apiClient),
          const SizedBox(height: 13),
        ],
        _ProfileMenuCard(
          rows: [
            _ProfileMenuRow(
              icon: Icons.security,
              label: 'ความปลอดภัย',
              plainIcon: true,
              onTap: () => _openLegal(context, _securityInfo),
            ),
            _ProfileMenuRow(
              icon: Icons.help_outline,
              label: 'ช่วยเหลือ',
              plainIcon: true,
              onTap: () => _openLegal(context, _helpInfo),
            ),
            _ProfileMenuRow(
              icon: Icons.privacy_tip_outlined,
              label: 'นโยบายความเป็นส่วนตัว',
              plainIcon: true,
              onTap: () =>
                  _openLegal(context, PostDeeLegalDocuments.privacyPolicy),
            ),
            _ProfileMenuRow(
              icon: Icons.description_outlined,
              label: 'ข้อกำหนดการใช้งาน',
              plainIcon: true,
              onTap: () =>
                  _openLegal(context, PostDeeLegalDocuments.termsOfService),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _DeleteAccountButton(
          onDeleteAccount: widget.onDeleteAccount,
          onManageSubscription:
              widget.onManageSubscription ?? _openSubscriptionManagement,
          isDeleting: widget.isDeletingAccount,
        ),
      ],
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.name,
    required this.email,
    required this.hasEmail,
    required this.emailVerified,
    required this.connectedLabel,
    required this.onOpenConnections,
    required this.onEdit,
  });

  final String name;
  final String email;
  final bool hasEmail;
  final bool emailVerified;
  final String connectedLabel;
  final VoidCallback onOpenConnections;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initial =
        name.trim().isEmpty ? 'P' : name.trim().characters.first.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF34D399), Color(0xFF0E9F6E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _StatusPill(
                      label: emailVerified
                          ? 'ยืนยันอีเมลแล้ว'
                          : hasEmail
                              ? 'อีเมลยังไม่ยืนยัน'
                              : 'ยังไม่เชื่อมอีเมล',
                      icon: Icons.verified,
                      background: AppTheme.mint,
                      foreground: AppTheme.accentCyanInk,
                    ),
                    Semantics(
                      button: true,
                      label: connectedLabel,
                      child: GestureDetector(
                        key: const ValueKey('profile-connected-summary-pill'),
                        onTap: onOpenConnections,
                        child: _StatusPill(
                          label: connectedLabel,
                          icon: Icons.hub_outlined,
                          background: AppTheme.glassDeep,
                          foreground: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'แก้ไขโปรไฟล์',
            child: InkWell(
              key: const ValueKey('profile-edit-button'),
              borderRadius: BorderRadius.circular(11),
              onTap: onEdit,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.glassDeep,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Icon(
                  Icons.edit_outlined,
                  size: 19,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i += 1) ...[
            if (i > 0) Divider(height: 1, color: AppTheme.borderSoft),
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
    this.trailing,
    this.plainIcon = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  /// Legal/support rows show a bare muted icon instead of the mint icon box.
  final bool plainIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              if (plainIcon)
                Icon(icon, size: 20, color: AppTheme.textSecondary)
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.mint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: AppTheme.accentCyanInk),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierFeature {
  const _TierFeature(this.text, {this.included = true});

  final String text;

  /// Limitations render with a gray dash, never a green check — a hard rule
  /// from the design handoff README.
  final bool included;
}

class _TierData {
  const _TierData({
    required this.id,
    required this.name,
    required this.price,
    required this.features,
    this.badge,
  });

  final String id;
  final String name;
  final String price;
  final List<_TierFeature> features;
  final String? badge;
}

// Real tier prices from the design handoff (also used by the paywall).
const _tiers = [
  _TierData(
    id: 'free',
    name: 'ฟรี',
    price: '0 บาท',
    features: [
      _TierFeature('โพสต์ฟรี 3 หน่วย/เดือน'),
      _TierFeature('ต้องยืนยันเบอร์ก่อนโพสต์', included: false),
      _TierFeature('ไม่มี AI แคปชั่นจากคลิปจริง', included: false),
    ],
  ),
  _TierData(
    id: 'starter',
    name: 'Starter',
    price: '199 ฿/ด.',
    badge: 'แนะนำ',
    features: [
      _TierFeature('โพสต์หลายช่องทาง 120 หน่วย/เดือน'),
      _TierFeature('AI แคปชั่นจากเสียงคลิป 50 ครั้ง/เดือน'),
      _TierFeature('ตั้งเวลาโพสต์และปฏิทิน'),
    ],
  ),
  _TierData(
    id: 'pro',
    name: 'Pro',
    price: '299 ฿/ด.',
    features: [
      _TierFeature('ทุกอย่างใน Starter'),
      _TierFeature('โพสต์หลายช่องทาง 250 หน่วย/เดือน'),
      _TierFeature('AI แคปชั่นจากเสียง + ภาพ 120 ครั้ง/เดือน'),
      _TierFeature('AI ตัดต่อ 200 นาที/เดือน'),
    ],
  ),
];

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.isCurrent,
    required this.onTap,
    super.key,
  });

  final _TierData tier;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'แพ็กเกจ ${tier.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isCurrent ? AppTheme.sel : AppTheme.glass,
            borderRadius: BorderRadius.circular(18),
            border: isCurrent
                ? Border.all(color: AppTheme.accent, width: 2)
                : Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF122018).withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    tier.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (tier.badge != null) ...[
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 2),
                        child: Text(
                          tier.badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    tier.price,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tier.id == 'free'
                          ? AppTheme.textSecondary
                          : AppTheme.accentCyanInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              for (final feature in tier.features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          feature.included ? Icons.check_circle : Icons.remove,
                          size: 17,
                          color: feature.included
                              ? AppTheme.accentCyanInk
                              : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature.text,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent ? AppTheme.glassDeep : AppTheme.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isCurrent ? 'แพ็กเกจปัจจุบัน' : 'อัปเกรด',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color:
                        isCurrent ? AppTheme.textMuted : AppTheme.accentCyanInk,
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
                  'ระบบจะลบโปรไฟล์ โพสต์ วิดีโอ เทมเพลต การเชื่อมต่อโซเชียล '
                  'และประวัติการใช้งานของคุณอย่างถาวร ข้อมูลจะกู้คืนไม่ได้',
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

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({required this.themeController});

  final PostDeeThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final isLightMode = themeController.isLightMode;

        return _SettingCard(
          icon: Icons.dark_mode_outlined,
          title: 'โหมดการแสดงผล',
          subtitle: 'สลับหน้าตาแอประหว่างสว่างกับมืด',
          child: Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: 'สว่าง',
                  icon: Icons.light_mode_outlined,
                  isSelected: isLightMode,
                  onPressed: () => themeController.setLightMode(true),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ChoiceButton(
                  label: 'มืด',
                  icon: Icons.dark_mode_outlined,
                  isSelected: !isLightMode,
                  onPressed: () => themeController.setLightMode(false),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguagePickerCard extends StatelessWidget {
  const _LanguagePickerCard({required this.languageController});

  final PostDeeLanguageController languageController;

  @override
  Widget build(BuildContext context) {
    final l10n = PostDeeLocalizations.of(context);

    return AnimatedBuilder(
      animation: languageController,
      builder: (context, _) {
        final currentLocale =
            languageController.locale ?? Localizations.localeOf(context);

        return _SettingCard(
          icon: Icons.language,
          title: l10n.profileLanguageTitle,
          subtitle: l10n.profileLanguageDescription,
          child: Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: l10n.languageEnglish,
                  isSelected: currentLocale.languageCode == 'en',
                  onPressed: () =>
                      languageController.setLocale(const Locale('en')),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ChoiceButton(
                  label: l10n.languageThai,
                  isSelected: currentLocale.languageCode == 'th',
                  onPressed: () =>
                      languageController.setLocale(const Locale('th')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.accentCyanInk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? AppTheme.mint : AppTheme.glass,
          side: isSelected
              ? const BorderSide(color: AppTheme.accent, width: 1.5)
              : BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? AppTheme.accentCyanInk
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? AppTheme.accentCyanInk
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiEditingQuotaCard extends StatefulWidget {
  const _AiEditingQuotaCard({required this.apiClient});

  final PostDeeApiClient apiClient;

  @override
  State<_AiEditingQuotaCard> createState() => _AiEditingQuotaCardState();
}

class _AiEditingQuotaCardState extends State<_AiEditingQuotaCard> {
  int _limitMinutes = 200;
  int _usedMinutes = 0;
  final int _extraMinutes = 0;

  int get _remaining =>
      (_limitMinutes - _usedMinutes).clamp(0, _limitMinutes) + _extraMinutes;
  int get _total => _limitMinutes + _extraMinutes;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await widget.apiClient.fetchAiEditQuota();
      if (!mounted) return;
      setState(() {
        _limitMinutes = quota.limitMinutes;
        _usedMinutes = quota.usedMinutes;
      });
    } catch (_) {
      // Keep the default quota display if the API is unavailable.
    }
  }

  Future<void> _topUp() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ยังไม่ได้เปิดระบบซื้อนาทีตัดต่อจริงผ่าน RevenueCat'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final progress = _total == 0 ? 0.0 : _remaining / _total;

    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high,
                  color: AppTheme.accentCyanInk, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'โควต้าตัดต่อ AI',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const PostDeeSoftPill(label: 'Pro', color: AppTheme.accent),
            ],
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_remaining',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: AppTheme.spaceXs),
              Text(
                '/ $_total นาที',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.glassDeep,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'รีเซ็ตทุกเดือน · ใช้กับการถอดเสียงและเรนเดอร์ซับ',
            style: textTheme.labelSmall?.copyWith(color: AppTheme.textMuted),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          OutlinedButton.icon(
            onPressed: _topUp,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('เติม 120 นาที · 49 บาท'),
          ),
        ],
      ),
    );
  }
}
