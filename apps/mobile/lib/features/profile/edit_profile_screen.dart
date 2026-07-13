import 'package:flutter/material.dart';

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
  String? _errorMessage;

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
      setState(() => _errorMessage = 'กรอกชื่อที่ต้องการให้แสดง');
      return;
    }

    Navigator.of(context).pop(
      ProfileDraft(
        displayName: displayName,
        storeName: storeName,
        accountEmail: widget.initialDraft.accountEmail,
      ),
    );
  }

  void _showAvatarNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ระบบอัปโหลดรูปโปรไฟล์กำลังเตรียมเชื่อมต่อกับบัญชีจริง'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _displayNameController.text.trim().isEmpty
        ? 'P'
        : _displayNameController.text.trim().characters.first.toUpperCase();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'แก้ไขโปรไฟล์',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                    child: const Text('เปลี่ยนรูปโปรไฟล์'),
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
                    const _FieldLabel('ชื่อที่แสดง'),
                    const SizedBox(height: 6),
                    _ProfileTextField(
                      key: const ValueKey('edit-profile-display-name'),
                      controller: _displayNameController,
                      hintText: 'เช่น มีนา',
                      onChanged: (_) => setState(() => _errorMessage = null),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('ชื่อร้าน'),
                    const SizedBox(height: 6),
                    _ProfileTextField(
                      key: const ValueKey('edit-profile-store-name'),
                      controller: _storeNameController,
                      hintText: 'เช่น ร้านมีนาขายดี',
                      prefixIcon: Icons.storefront_outlined,
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('อีเมล'),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
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
                            child: Text(
                              widget.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: widget.emailVerified
                                  ? AppTheme.mint
                                  : AppTheme.glass,
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
                                Text(
                                  widget.emailVerified
                                      ? 'ยืนยันแล้ว'
                                      : 'อีเมลยังไม่ยืนยัน',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: widget.emailVerified
                                        ? AppTheme.accentCyanInk
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
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
                      'บันทึกเฉพาะในอุปกรณ์นี้',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'ชื่อร้านจะแสดงบนหน้าโปรไฟล์ลิงก์ (Link in Bio) และในโพสต์ของคุณ',
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
                label: const Text('บันทึก'),
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
