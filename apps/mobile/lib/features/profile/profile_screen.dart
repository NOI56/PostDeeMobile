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
import '../notifications/notifications_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/postdee_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.languageController,
    required this.themeController,
    required this.onOpenTemplates,
    required this.onDeleteAccount,
    this.apiClient,
    this.launchConnectUrl,
    super.key,
  });

  final PostDeeLanguageController languageController;
  final PostDeeThemeController themeController;
  final VoidCallback onOpenTemplates;
  final VoidCallback onDeleteAccount;
  final PostDeeApiClient? apiClient;
  final Future<bool> Function(Uri uri)? launchConnectUrl;

  @override
  Widget build(BuildContext context) {
    final session = PostDeeAuthSessionStore.instance.session;
    final accountName =
        session.isSignedIn ? session.displayLabel : 'ยังไม่ได้เชื่อมบัญชี';
    final accountEmail = session.email?.trim();
    final accountDetail = accountEmail == null || accountEmail.isEmpty
        ? 'เชื่อมอีเมลก่อนใช้งานจริง'
        : accountEmail;
    final accountBadge =
        session.isSignedIn ? 'เชื่อมบัญชีแล้ว' : 'ยังไม่เชื่อมบัญชี';
    final emailPillLabel = accountEmail == null || accountEmail.isEmpty
        ? 'ยังไม่เชื่อมอีเมล'
        : 'เชื่อมอีเมลแล้ว';

    return ListView(
      padding: AppTheme.screenPadding,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'บัญชีและโปรไฟล์',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  accountBadge,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        PostDeeCard(
          glowColor: AppTheme.accentCyan,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentCyan],
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(AppTheme.spaceMd),
                  child: Icon(Icons.person, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สถานะบัญชี',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accountName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      accountDetail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ProfileSummaryPill(
                          icon: Icons.verified_user_outlined,
                          label: emailPillLabel,
                          color: AppTheme.accent,
                        ),
                        _ProfileSummaryPill(
                          icon: Icons.hub_outlined,
                          label: '0/4 เชื่อมต่อ',
                          color: AppTheme.accentCyanInk,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _LanguagePickerCard(languageController: languageController),
        const SizedBox(height: AppTheme.spaceLg),
        _ThemeModeCard(themeController: themeController),
        const SizedBox(height: AppTheme.spaceLg),
        const _PackageComparisonCard(),
        const SizedBox(height: AppTheme.spaceLg),
        const _AiEditingQuotaCard(),
        const SizedBox(height: AppTheme.spaceLg),
        Semantics(
          button: true,
          label: 'เปิดเทมเพลต',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenTemplates,
            child: PostDeeCard(
              glowColor: AppTheme.accentPink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'เทมเพลต',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onOpenTemplates,
                        icon: const Icon(Icons.text_snippet_outlined, size: 18),
                        label: const Text('เปิด'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    'จัดการแคปชั่นที่บันทึกไว้ได้จากที่นี่ ฟีเจอร์เดิมยังอยู่ครบ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _ConnectedPlatformsCard(
          apiClient: apiClient,
          launchConnectUrl: launchConnectUrl,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        PostDeeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileSettingRow(
                icon: Icons.verified_user_outlined,
                label: 'ยืนยันเบอร์โทร',
                onTap: () => _openPhoneVerification(context),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _ProfileSettingRow(
                icon: Icons.notifications_none,
                label: 'การแจ้งเตือน',
                onTap: () => _openNotifications(context),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _ProfileSettingRow(
                icon: Icons.security,
                label: 'ความปลอดภัย',
                onTap: () => _openLegal(context, _securityInfo),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _ProfileSettingRow(
                icon: Icons.help_outline,
                label: 'ช่วยเหลือ',
                onTap: () => _openLegal(context, _helpInfo),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        PostDeeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileSettingRow(
                icon: Icons.privacy_tip_outlined,
                label: 'นโยบายความเป็นส่วนตัว',
                onTap: () =>
                    _openLegal(context, PostDeeLegalDocuments.privacyPolicy),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              _ProfileSettingRow(
                icon: Icons.description_outlined,
                label: 'ข้อกำหนดการใช้งาน',
                onTap: () =>
                    _openLegal(context, PostDeeLegalDocuments.termsOfService),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        _DeleteAccountButton(onDeleteAccount: onDeleteAccount),
      ],
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

void _openNotifications(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const NotificationsScreen(),
    ),
  );
}

void _openPaywall(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const PaywallScreen(),
    ),
  );
}

const _securityInfo = LegalDocument(
  title: 'ความปลอดภัย',
  body: 'PostDee ดูแลความปลอดภัยของบัญชีและข้อมูลของคุณ\n\n'
      '- เข้าสู่ระบบผ่าน Google หรือ Apple เท่านั้น ไม่เก็บรหัสผ่านของคุณ\n'
      '- โทเคนการเชื่อมต่อบัญชีโซเชียลถูกเก็บอย่างปลอดภัยบนเซิร์ฟเวอร์\n'
      '- ผู้ช่วย/ทีมงานไม่เห็นรหัสผ่านหรือโทเคนของเจ้าของร้าน\n'
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
  const _DeleteAccountButton({required this.onDeleteAccount});

  final VoidCallback onDeleteAccount;

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบบัญชี'),
        content: const Text(
          'การลบบัญชีจะลบข้อมูลทั้งหมดของคุณออกอย่างถาวร '
          'และไม่สามารถกู้คืนได้ ต้องการดำเนินการต่อหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('ลบบัญชีถาวร'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDeleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return Semantics(
      button: true,
      label: 'ลบบัญชี',
      child: OutlinedButton.icon(
        onPressed: () => _confirm(context),
        icon: Icon(Icons.delete_outline, color: errorColor, size: 18),
        label: Text(
          'ลบบัญชี',
          style: TextStyle(color: errorColor, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: errorColor.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _PackageComparisonCard extends StatelessWidget {
  const _PackageComparisonCard();

  @override
  Widget build(BuildContext context) {
    return PostDeeCard(
      key: const ValueKey('profile-package-comparison'),
      glowColor: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: AppTheme.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'แพ็กเกจ PostDee',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              PostDeeSoftPill(
                label: 'ฟรี / 199 / 299',
                icon: Icons.compare_arrows,
                color: AppTheme.accentCyanInk,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'คิดโควต้าแบบ 1 ช่องทาง = 1 หน่วย เช่น ลง 4 ช่องทางใช้ 4 หน่วย',
          ),
          const SizedBox(height: AppTheme.spaceMd),
          _PlanCompareTile(
            key: ValueKey('profile-plan-free'),
            name: 'ฟรี',
            price: '0 บาท',
            color: AppTheme.textSecondary,
            lines: [
              'โพสต์ฟรี 3 หน่วย/เดือน',
              'ต้องยืนยันเบอร์ก่อนโพสต์',
              'ไม่มี AI แคปชั่นจากคลิปจริง',
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          _PlanCompareTile(
            key: ValueKey('profile-plan-starter'),
            name: 'Starter',
            price: '199 บาท/เดือน',
            color: AppTheme.accentPinkInk,
            lines: [
              'โพสต์หลายช่องทาง 120 หน่วย/เดือน',
              'AI แคปชั่นจากเสียงคลิป 50 ครั้ง/เดือน',
              'ตั้งเวลาโพสต์และปฏิทิน',
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),
          _PlanCompareTile(
            key: ValueKey('profile-plan-pro'),
            name: 'Pro',
            price: '299 บาท/เดือน',
            color: AppTheme.accentCyanInk,
            lines: [
              'โพสต์หลายช่องทาง 250 หน่วย/เดือน',
              'AI แคปชั่นจากเสียง + ภาพ 120 ครั้ง/เดือน',
              'วิเคราะห์, เรดาร์แฮชแท็ก, คอมเมนต์ AI',
            ],
          ),
          const SizedBox(height: AppTheme.spaceMd),
          const _PackageQuotaGrid(),
          const SizedBox(height: AppTheme.spaceMd),
          const _QuotaSummaryRow(
            key: ValueKey('profile-post-quota-summary'),
            icon: Icons.cloud_upload_outlined,
            label: 'โควต้าโพสต์',
            value: 'ฟรี 3 / Starter 120 / Pro 250 หน่วย',
          ),
          const SizedBox(height: AppTheme.spaceSm),
          const _QuotaSummaryRow(
            key: ValueKey('profile-ai-caption-quota-summary'),
            icon: Icons.auto_awesome,
            label: 'AI แคปชั่นจากคลิปจริง',
            value: 'Starter 50 / Pro 120 ครั้งต่อเดือน',
          ),
          const SizedBox(height: AppTheme.spaceSm),
          const _QuotaSummaryRow(
            key: ValueKey('profile-team-access-pro'),
            icon: Icons.groups_2_outlined,
            label: 'Team & Editor Access',
            value: 'อยู่ใน Pro 299: เชิญผู้ช่วยได้โดยไม่เห็นรหัสผ่าน',
          ),
          const SizedBox(height: AppTheme.spaceMd),
          PostDeeGradientButton(
            label: 'อัปเกรดแพ็กเกจ',
            icon: Icons.workspace_premium_outlined,
            onPressed: () => _openPaywall(context),
          ),
        ],
      ),
    );
  }
}

class _PlanCompareTile extends StatelessWidget {
  const _PlanCompareTile({
    required this.name,
    required this.price,
    required this.color,
    required this.lines,
    super.key,
  });

  final String name;
  final String price;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  price,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            for (final line in lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: color, size: 14),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.24,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ),
                ],
              ),
              if (line != lines.last) const SizedBox(height: 5),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackageQuotaGrid extends StatelessWidget {
  const _PackageQuotaGrid();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('profile-quota-grid'),
      spacing: 8,
      runSpacing: 8,
      children: [
        _QuotaMiniTile(
          key: const ValueKey('profile-plan-quota-free'),
          label: 'Free',
          posts: '3 โพสต์',
          ai: 'ไม่มี AI',
          color: AppTheme.textSecondary,
        ),
        _QuotaMiniTile(
          key: ValueKey('profile-plan-quota-starter'),
          label: '199 Starter',
          posts: '120 หน่วย',
          ai: 'AI 50 ครั้ง',
          color: AppTheme.accentPinkInk,
        ),
        _QuotaMiniTile(
          key: ValueKey('profile-plan-quota-pro'),
          label: '299 Pro',
          posts: '250 หน่วย',
          ai: 'AI 120 ครั้ง',
          color: AppTheme.accentCyanInk,
        ),
      ],
    );
  }
}

class _QuotaMiniTile extends StatelessWidget {
  const _QuotaMiniTile({
    required this.label,
    required this.posts,
    required this.ai,
    required this.color,
    super.key,
  });

  final String label;
  final String posts;
  final String ai;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.tileRadius),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                posts,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                ai,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotaSummaryRow extends StatelessWidget {
  const _QuotaSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accent, size: 18),
        const SizedBox(width: AppTheme.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.25,
                    ),
              ),
            ],
          ),
        ),
      ],
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

        return PostDeeCard(
          glowColor: isLightMode ? AppTheme.accentCyan : AppTheme.accentPink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isLightMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    color:
                        isLightMode ? AppTheme.accentCyan : AppTheme.accentPink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'โหมดการแสดงผล',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          'สลับหน้าตาแอประหว่างมืดกับสว่าง',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: _ThemeOptionButton(
                      label: 'มืด',
                      icon: Icons.dark_mode,
                      isSelected: !isLightMode,
                      onPressed: () => themeController.setLightMode(false),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: _ThemeOptionButton(
                      label: 'สว่าง',
                      icon: Icons.light_mode,
                      isSelected: isLightMode,
                      onPressed: () => themeController.setLightMode(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOptionButton extends StatelessWidget {
  const _ThemeOptionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 16,
        color: isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor:
            isSelected ? AppTheme.accent.withValues(alpha: 0.18) : null,
        side: BorderSide(
          color: isSelected ? AppTheme.accentCyan : AppTheme.border,
        ),
      ),
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

        return PostDeeCard(
          glowColor: AppTheme.accentCyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.language, color: AppTheme.accentCyanInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.profileLanguageTitle,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          l10n.profileLanguageDescription,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: _LanguageOptionButton(
                      label: l10n.languageEnglish,
                      isSelected: currentLocale.languageCode == 'en',
                      onPressed: () => languageController.setLocale(
                        const Locale('en'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: _LanguageOptionButton(
                      label: l10n.languageThai,
                      isSelected: currentLocale.languageCode == 'th',
                      onPressed: () => languageController.setLocale(
                        const Locale('th'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageOptionButton extends StatelessWidget {
  const _LanguageOptionButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            isSelected ? AppTheme.accent.withValues(alpha: 0.18) : null,
        side: BorderSide(
          color: isSelected ? AppTheme.accentCyan : AppTheme.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileSummaryPill extends StatelessWidget {
  const _ProfileSummaryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiEditingQuotaCard extends StatefulWidget {
  const _AiEditingQuotaCard();

  @override
  State<_AiEditingQuotaCard> createState() => _AiEditingQuotaCardState();
}

class _AiEditingQuotaCardState extends State<_AiEditingQuotaCard> {
  final _apiClient = PostDeeApiClient();
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
      final quota = await _apiClient.fetchAiEditQuota();
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
      glowColor: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high, color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'โควต้าตัดต่อ AI',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const PostDeeSoftPill(label: 'Pro', color: AppTheme.accentCyan),
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
                    ?.copyWith(fontWeight: FontWeight.w900),
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

typedef _ConnectUrlLauncher = Future<bool> Function(Uri uri);

/// Platforms PostPeer can connect a user account for. Shopee/Lazada are listed
/// in the app but not yet supported by the connect API, so they stay disabled.
const List<SocialPlatform> _connectablePlatforms = [
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
];

class _ConnectedPlatformsCard extends StatefulWidget {
  const _ConnectedPlatformsCard({this.apiClient, this.launchConnectUrl});

  final PostDeeApiClient? apiClient;
  final _ConnectUrlLauncher? launchConnectUrl;

  @override
  State<_ConnectedPlatformsCard> createState() =>
      _ConnectedPlatformsCardState();
}

class _ConnectedPlatformsCardState extends State<_ConnectedPlatformsCard> {
  late final PostDeeApiClient _apiClient =
      widget.apiClient ?? PostDeeApiClient();
  late final _ConnectUrlLauncher _launch = widget.launchConnectUrl ??
      ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  Map<String, SocialConnectionResult> _statuses = {};
  bool _loading = true;
  String? _busyPlatform;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final results = await _apiClient.listSocialConnections();
      if (!mounted) return;
      setState(() {
        _statuses = {for (final result in results) result.platform: result};
        _loading = false;
      });
    } catch (_) {
      // Keep platforms shown as disconnected if the status call fails.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  SocialConnectionResult? _statusFor(SocialPlatform platform) =>
      _statuses[platform.apiValue];

  int get _connectedCount => _connectablePlatforms
      .where((platform) => _statusFor(platform)?.connected ?? false)
      .length;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect(SocialPlatform platform) async {
    setState(() => _busyPlatform = platform.apiValue);
    try {
      final link =
          await _apiClient.createSocialConnectionLink(platform.apiValue);
      await _launch(link.connectUrl);
      await _loadConnections();
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('เชื่อมบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _busyPlatform = null);
    }
  }

  Future<void> _disconnect(SocialPlatform platform) async {
    setState(() => _busyPlatform = platform.apiValue);
    try {
      await _apiClient.disconnectSocialConnection(platform.apiValue);
      await _loadConnections();
    } catch (_) {
      _showMessage('ยกเลิกการเชื่อมไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _busyPlatform = null);
    }
  }

  ButtonStyle get _actionStyle => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        side: BorderSide(color: AppTheme.border.withValues(alpha: 0.5)),
      );

  Widget _buildAction(SocialPlatform platform) {
    if (!_connectablePlatforms.contains(platform)) {
      return OutlinedButton(
        key: ValueKey('profile-platform-soon-${platform.apiValue}'),
        onPressed: null,
        style: _actionStyle,
        child: const Text('เร็วๆ นี้'),
      );
    }

    if (_busyPlatform == platform.apiValue) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_statusFor(platform)?.connected ?? false) {
      return OutlinedButton(
        key: ValueKey('profile-platform-disconnect-${platform.apiValue}'),
        onPressed: () => _disconnect(platform),
        style: _actionStyle,
        child: const Text('ยกเลิก'),
      );
    }

    return OutlinedButton(
      key: ValueKey('profile-platform-connect-${platform.apiValue}'),
      onPressed: () => _connect(platform),
      style: _actionStyle,
      child: const Text('เชื่อม'),
    );
  }

  Widget _buildRow(BuildContext context, SocialPlatform platform) {
    final status = _statusFor(platform);
    final connected = status?.connected ?? false;
    final displayName = connected ? status?.displayName : null;

    return Row(
      children: [
        SocialPlatformLogo(platform: platform, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(platform.label)),
                  if (connected) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle,
                        size: 16, color: AppTheme.accent),
                  ],
                ],
              ),
              if (displayName != null && displayName.isNotEmpty)
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildAction(platform),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'แพลตฟอร์มที่เชื่อมต่อ',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '$_connectedCount/${_connectablePlatforms.length}',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'เชื่อมบัญชีโซเชียลของคุณผ่าน PostPeer เพื่อให้โพสต์ขึ้นบัญชีตัวเอง',
            style: textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          for (final platform in SocialPlatform.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildRow(context, platform),
            ),
        ],
      ),
    );
  }
}

class _ProfileSettingRow extends StatelessWidget {
  const _ProfileSettingRow({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      ],
    );

    if (onTap == null) {
      return row;
    }

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }
}
