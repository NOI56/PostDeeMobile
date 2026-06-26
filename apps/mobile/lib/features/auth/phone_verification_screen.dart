import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import 'auth_controller.dart';
import 'phone_verification_service.dart';

/// Development gateway so the phone verification flow is usable on the emulator
/// without a real Firebase Phone Auth project. The demo OTP is 123456. Replace
/// with [FirebasePhoneVerificationGateway] once real credentials are wired.
class DevMockPhoneVerification {
  const DevMockPhoneVerification._();

  static const demoCode = '123456';

  static Future<PhoneVerificationStartResult> sendCode(
    String phoneNumber,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const PhoneVerificationStartResult.codeSent(
      verificationId: 'dev-mock-verification-id',
    );
  }

  static Future<AuthSession> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (smsCode.trim() != demoCode) {
      throw const AuthUnavailableException(
        'รหัส OTP ไม่ถูกต้อง (โหมดทดสอบใช้ 123456)',
      );
    }

    return const AuthSession(
      idToken: 'local-mock-id-token',
      email: 'demo@postdee.local',
      displayName: 'PostDee Demo',
    );
  }
}

enum _PhoneStep { enterPhone, enterCode, done }

class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({
    super.key,
    this.sendCode,
    this.confirmCode,
    this.enableFirebaseAuth = AppConfig.enableFirebaseAuth,
    this.allowLocalMockVerification = AppConfig.allowLocalMockAuth,
    this.firebasePhoneVerificationGateway,
    this.onVerified,
  });

  final PhoneVerificationCodeSender? sendCode;
  final PhoneVerificationCodeConfirmer? confirmCode;
  final bool enableFirebaseAuth;
  final bool allowLocalMockVerification;
  final FirebasePhoneVerificationGateway? firebasePhoneVerificationGateway;
  final ValueChanged<AuthSession>? onVerified;

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  _PhoneStep _step = _PhoneStep.enterPhone;
  String _verificationId = '';
  bool _isLoading = false;
  String? _errorMessage;
  FirebasePhoneVerificationGateway? _firebasePhoneVerificationGateway;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  FirebasePhoneVerificationGateway get _activeFirebaseGateway =>
      widget.firebasePhoneVerificationGateway ??
      (_firebasePhoneVerificationGateway ??=
          FirebasePhoneVerificationGateway());

  PhoneVerificationCodeSender get _sender {
    final sender = widget.sendCode;
    if (sender != null) {
      return sender;
    }

    if (!widget.enableFirebaseAuth) {
      return widget.allowLocalMockVerification
          ? DevMockPhoneVerification.sendCode
          : _sendUnavailableCode;
    }

    return _activeFirebaseGateway.sendCode;
  }

  PhoneVerificationCodeConfirmer get _confirmer {
    final confirmer = widget.confirmCode;
    if (confirmer != null) {
      return confirmer;
    }

    if (!widget.enableFirebaseAuth) {
      return widget.allowLocalMockVerification
          ? DevMockPhoneVerification.confirmCode
          : _confirmUnavailableCode;
    }

    return _activeFirebaseGateway.confirmCode;
  }

  Future<PhoneVerificationStartResult> _sendUnavailableCode(
    String phoneNumber,
  ) async {
    throw const AuthUnavailableException(
      'Firebase Auth is disabled. Enable Firebase Auth for phone verification.',
    );
  }

  Future<AuthSession> _confirmUnavailableCode({
    required String verificationId,
    required String smsCode,
  }) async {
    throw const AuthUnavailableException(
      'Firebase Auth is disabled. Enable Firebase Auth for phone verification.',
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();

    if (phone.length < 9) {
      setState(() => _errorMessage = 'กรอกเบอร์โทรให้ถูกต้อง');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _sender(phone);

      if (!mounted) {
        return;
      }

      if (result.isAutoVerified) {
        _finish(result.autoVerifiedSession!);
        return;
      }

      setState(() {
        _verificationId = result.verificationId;
        _step = _PhoneStep.enterCode;
      });
    } on AuthUnavailableException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('ส่งรหัส OTP ไม่สำเร็จ');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await _confirmer(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      _finish(session);
    } on AuthUnavailableException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('ยืนยันรหัสไม่สำเร็จ');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _finish(AuthSession session) {
    widget.onVerified?.call(session);
    setState(() => _step = _PhoneStep.done);
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ยืนยันเบอร์โทร',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: ListView(
            padding: AppTheme.screenPadding,
            children: [
              switch (_step) {
                _PhoneStep.enterPhone => _buildEnterPhone(context),
                _PhoneStep.enterCode => _buildEnterCode(context),
                _PhoneStep.done => _buildDone(context),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnterPhone(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      glowColor: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ยืนยันเบอร์เพื่อปลดล็อกโพสต์ฟรี',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'แพ็กเกจ Basic ต้องยืนยันเบอร์โทรก่อนใช้สิทธิ์โพสต์ฟรี 3 ครั้งต่อเดือน',
            style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          TextField(
            key: const ValueKey('phone-verification-phone-field'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
            ],
            decoration: const InputDecoration(
              labelText: 'เบอร์โทร',
              hintText: '+66XXXXXXXXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTheme.spaceLg),
          PostDeeGradientButton(
            key: const ValueKey('phone-verification-send-code'),
            label: _isLoading ? 'กำลังส่งรหัส...' : 'ส่งรหัส OTP',
            icon: Icons.sms_outlined,
            onPressed: _isLoading ? null : _sendCode,
          ),
        ],
      ),
    );
  }

  Widget _buildEnterCode(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      glowColor: AppTheme.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'กรอกรหัส OTP',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'ส่งรหัส 6 หลักไปที่ ${_phoneController.text.trim()}',
            style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          TextField(
            key: const ValueKey('phone-verification-code-field'),
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'รหัส OTP',
              hintText: '123456',
              counterText: '',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTheme.spaceLg),
          PostDeeGradientButton(
            key: const ValueKey('phone-verification-confirm-code'),
            label: _isLoading ? 'กำลังยืนยัน...' : 'ยืนยัน',
            icon: Icons.verified_outlined,
            onPressed: _isLoading ? null : _confirmCode,
          ),
          const SizedBox(height: AppTheme.spaceSm),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => setState(() => _step = _PhoneStep.enterPhone),
            child: const Text('เปลี่ยนเบอร์ / ส่งรหัสอีกครั้ง'),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PostDeeCard(
      glowColor: AppTheme.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle, color: AppTheme.successInk, size: 40),
          const SizedBox(height: AppTheme.spaceMd),
          Text(
            'ยืนยันเบอร์เรียบร้อย',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            'ตอนนี้คุณใช้สิทธิ์โพสต์ฟรีของแพ็กเกจ Basic ได้แล้ว',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          PostDeeGradientButton(
            label: 'เสร็จสิ้น',
            icon: Icons.done,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
