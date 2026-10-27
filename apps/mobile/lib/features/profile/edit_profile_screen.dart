import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'profile_draft_store.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialDraft,
    required this.email,
    required this.emailVerified,
  });

  final ProfileDraft initialDraft;
  final String email;
  final bool emailVerified;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _displayNameController =
      TextEditingController(text: widget.initialDraft.displayName);
  late final TextEditingController _storeNameController =
      TextEditingController(text: widget.initialDraft.storeName);
  bool _isDisplayNameMissing = false;

  String _text(String thai, String english) =>
      (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
                      ?.locale
                      .languageCode ??
                  'th') ==
              'th'
          ? thai
          : english;

  @override
  void dispose() {
    _displayNameController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  void _save() {
    final displayName = _displayNameController.text.trim();
    final storeName = _storeNameController.text.trim();

    if (displayName.isEmpty) {
      setState(() => _isDisplayNameMissing = true);
      return;
    }

    Navigator.of(context).pop(
      ProfileDraft(
        displayName: displayName,
        storeName: storeName,
        accountEmail: widget.initialDraft.accountEmail,
        accountUserId: widget.initialDraft.accountUserId,
      ),
    );
  }

  void _showAvatarNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_text(
            'ระบบอัปโหลดรูปโปรไฟล์กำลังเตรียมเชื่อมต่อกับบัญชีจริง',
            'Profile photo uploads are not available yet.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _displayNameController.text.trim().isEmpty
        ? 'P'
        : _displayNameController.text.trim().characters.first.toUpperCase();
    final emailLabel = switch (widget.email) {
      '' ||
      'ยังไม่ได้เชื่อมอีเมล' ||
      'Email not connected' =>
        _text('ยังไม่ได้เชื่อมอีเมล', 'Email not connected'),
      _ => widget.email,
    };
    final titleScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stackEmailStatus = MediaQuery.textScalerOf(context).scale(14) > 18 ||
        MediaQuery.sizeOf(context).width < 360;
    final emailStatus = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: widget.emailVerified ? AppTheme.mint : AppTheme.glass,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.emailVerified
                ? Icons.verified_rounded
                : Icons.info_outline_rounded,
            size: 13,
            color: widget.emailVerified
                ? AppTheme.accentCyanInk
                : AppTheme.textMuted,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              widget.emailVerified
                  ? _text('ยืนยันแล้ว', 'Verified')
                  : _text('อีเมลยังไม่ยืนยัน', 'Email not verified'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: widget.emailVerified
                    ? AppTheme.accentCyanInk
                    : AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * (titleScale < 1 ? 1 : titleScale),
        title: Text(
          _text('แก้ไขโปรไฟล์', 'Edit profile'),
          maxLines: 2,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF34D399), Color(0xFF0E9F6E)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.5),
                              blurRadius: 22,
                              spreadRadius: -8,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Material(
                          color: AppTheme.accent,
                          shape: CircleBorder(
                            side: BorderSide(
                              color: AppTheme.pitchBlack,
                              width: 3,
                            ),
                          ),
                          child: Semantics(
                            button: true,
                            label: _text(
                                'เปลี่ยนรูปโปรไฟล์', 'Change profile photo'),
                            child: InkWell(
                              key: const ValueKey('edit-profile-avatar'),
                              customBorder: const CircleBorder(),
                              onTap: _showAvatarNotice,
                              child: const SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.photo_camera_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  TextButton(
                    onPressed: _showAvatarNotice,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentCyanInk,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                        _text('เปลี่ยนรูปโปรไฟล์', 'Change profile photo')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppTheme.glass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF122018).withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(_text('ชื่อที่แสดง', 'Display name')),
                    const SizedBox(height: 6),
                    _ProfileTextField(
                      key: const ValueKey('edit-profile-display-name'),
                      controller: _displayNameController,
                      hintText: _text('เช่น มีนา', 'e.g. Mina'),
                      onChanged: (_) =>
                          setState(() => _isDisplayNameMissing = false),
                    ),
                    const SizedBox(height: 14),
                    _FieldLabel(_text('ชื่อร้าน', 'Store name')),
                    const SizedBox(height: 6),
                    _ProfileTextField(
                      key: const ValueKey('edit-profile-store-name'),
                      controller: _storeNameController,
                      hintText: _text('เช่น ร้านมีนาขายดี', 'e.g. Mina Shop'),
                      prefixIcon: Icons.storefront_outlined,
                    ),
                    const SizedBox(height: 14),
                    _FieldLabel(_text('อีเมล', 'Email')),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.glassDeep,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mail_outline_rounded,
                              size: 20, color: AppTheme.textMuted),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  emailLabel,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                if (stackEmailStatus) ...[
                                  const SizedBox(height: 6),
                                  emailStatus,
                                ],
                              ],
                            ),
                          ),
                          if (!stackEmailStatus) ...[
                            const SizedBox(width: 8),
                            emailStatus,
                          ],
                        ],
                      ),
                    ),
                    if (_isDisplayNameMissing) ...[
                      const SizedBox(height: 10),
                      Text(
                        _text('กรอกชื่อที่ต้องการให้แสดง',
                            'Enter a display name'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('บันทึกเฉพาะในอุปกรณ์นี้',
                          'Saved on this device only'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _text(
                          'ชื่อที่แก้จะใช้เฉพาะในเครื่องนี้ และยังไม่ซิงก์กับบัญชีหรืออุปกรณ์อื่น',
                          'Name changes are saved only on this device and are not synced with your account or other devices.'),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('edit-profile-save'),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: Text(_text('บันทึก', 'Save')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.prefixIcon,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: AppTheme.textMuted),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, size: 20, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.pitchBlack,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}
