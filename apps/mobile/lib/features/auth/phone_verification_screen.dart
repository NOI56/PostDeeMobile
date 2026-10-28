import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/localization/postdee_localizations.dart';
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

    return AuthSession.authenticated(
      userId: localMockAuthUserId,
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
    this.sessionStore,
    this.runNativeAuthOperation,
    this.onVerified,
  });

  final PhoneVerificationCodeSender? sendCode;
  final PhoneVerificationCodeConfirmer? confirmCode;
  final bool enableFirebaseAuth;
  final bool allowLocalMockVerification;
  final FirebasePhoneVerificationGateway? firebasePhoneVerificationGateway;
  final PostDeeAuthSessionStore? sessionStore;
  final BoundPhoneAuthOperation? runNativeAuthOperation;
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
  String? _sentPhone;
  Timer? _resendTimer;
  int _resendSecondsRemaining = 0;
  bool _isLoading = false;
  String? _errorMessage;
  FirebasePhoneVerificationGateway? _firebasePhoneVerificationGateway;
  AuthSession? _verifiedSession;
  late final PostDeeAuthSessionStore _sessionStore;
  late final AuthSessionBinding _screenSession;
  var _operationGeneration = 0;

  String get _resendWaitInEnglish =>
      'wait $_resendSecondsRemaining ${_resendSecondsRemaining == 1 ? 'second' : 'seconds'}';

  @override
  void initState() {
    super.initState();
    _sessionStore = widget.sessionStore ?? PostDeeAuthSessionStore.instance;
    _screenSession = _sessionStore.captureSession();
    _sessionStore.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    _sessionStore.removeListener(_handleSessionChanged);
    _cancelVerification();
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  FirebasePhoneVerificationGateway get _activeFirebaseGateway =>
      widget.firebasePhoneVerificationGateway ??
      (_firebasePhoneVerificationGateway ??= FirebasePhoneVerificationGateway(
        sessionStore: _sessionStore,
        runNativeAuthOperation: widget.runNativeAuthOperation,
      ));

  void _cancelVerification({bool cancelGateway = true}) {
    _operationGeneration += 1;
    if (!cancelGateway) return;
    (widget.firebasePhoneVerificationGateway ??
            _firebasePhoneVerificationGateway)
        ?.cancelVerification();
  }

  void _handleSessionChanged() {
    if (_screenSession.isCurrent) return;
    _cancelVerification();
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _verificationId = '';
      _sentPhone = null;
      _resendSecondsRemaining = 0;
      _phoneController.clear();
      _codeController.clear();
      _step = _PhoneStep.enterPhone;
      _isLoading = false;
      _errorMessage = 'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้ายืนยันเบอร์อีกครั้ง';
    });
  }

  bool _isCurrentOperation(int generation) =>
      mounted && _screenSession.isCurrent && _operationGeneration == generation;

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

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendSecondsRemaining = 30;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_screenSession.isCurrent) {
        timer.cancel();
        return;
      }
      setState(() => _resendSecondsRemaining -= 1);
      if (_resendSecondsRemaining <= 0) timer.cancel();
    });
  }

  void _changePhone() {
    if (_isLoading) return;
    _cancelVerification();
    setState(() {
      _verificationId = '';
      _sentPhone = null;
      _codeController.clear();
      _errorMessage = null;
      _step = _PhoneStep.enterPhone;
    });
  }

  Future<void> _sendCode({bool isResend = false}) async {
    if (_isLoading || _resendSecondsRemaining > 0) return;
    if (!_screenSession.isCurrent) {
      _handleSessionChanged();
      return;
    }
    final phone = isResend
        ? _sentPhone
        : normalizePhoneVerificationNumber(_phoneController.text);

    if (phone == null) {
      setState(() => _errorMessage =
          'กรอกเบอร์โทรมือถือไทย 10 หลัก เช่น 0812345678 หรือเบอร์ต่างประเทศพร้อมรหัสประเทศ');
      return;
    }

    // Let the gateway retain its same-session resend token until sendCode claims
    // a new request; a changed number or disposed screen cancels it completely.
    _cancelVerification(cancelGateway: !isResend);
    final generation = _operationGeneration;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _verificationId = '';
      _codeController.clear();
      _sentPhone = phone;
      _phoneController.text = phone;
    });

    try {
      final result = await _sender(phone);

      if (!_isCurrentOperation(generation)) {
        return;
      }
      if (!_screenSession.isCurrent) {
        _showError('บัญชีเปลี่ยน กรุณาเปิดหน้ายืนยันเบอร์อีกครั้ง');
        return;
      }

      if (result.isAutoVerified) {
        _finish(result.autoVerifiedSession!);
        return;
      }

      setState(() {
        _verificationId = result.verificationId;
        _step = _PhoneStep.enterCode;
        _startResendCooldown();
      });
    } on AuthSessionChangedException {
      if (_isCurrentOperation(generation)) {
        _showError('คำขอยืนยันหมดอายุ กรุณาส่งรหัสอีกครั้ง');
      }
    } on AuthUnavailableException catch (error) {
      if (_isCurrentOperation(generation)) _showError(error.message);
    } catch (_) {
      if (_isCurrentOperation(generation)) _showError('ส่งรหัส OTP ไม่สำเร็จ');
    } finally {
      if (_isCurrentOperation(generation)) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmCode() async {
    if (_isLoading || _verificationId.isEmpty) return;
    if (!_screenSession.isCurrent) {
      _handleSessionChanged();
      return;
    }
    final generation = _operationGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await _confirmer(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );

      if (!_isCurrentOperation(generation)) {
        return;
      }

      _finish(session);
    } on AuthSessionChangedException {
      if (_isCurrentOperation(generation)) {
        _showError('คำขอยืนยันหมดอายุ กรุณาส่งรหัสอีกครั้ง');
      }
    } on AuthUnavailableException catch (error) {
      if (_isCurrentOperation(generation)) _showError(error.message);
    } catch (_) {
      if (_isCurrentOperation(generation)) _showError('ยืนยันรหัสไม่สำเร็จ');
    } finally {
      if (_isCurrentOperation(generation)) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _finish(AuthSession session) {
    _screenSession.ensureCurrent();
    final uid = _sessionStore.session.userId;
    if (uid != null && session.userId != null && uid != session.userId) {
      throw const AuthSessionChangedException();
    }
    _verifiedSession = session;
    _cancelVerification();
    _resendTimer?.cancel();
    if (mounted && _screenSession.isCurrent) {
      setState(() {
        _isLoading = false;
        _step = _PhoneStep.done;
      });
      widget.onVerified?.call(session);
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * (titleScale < 1 ? 1 : titleScale),
        title: const _PhoneVerificationText(
          'ยืนยันเบอร์โทร',
          maxLines: 3,
          softWrap: true,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.smartphone,
                size: 28,
                color: AppTheme.accentCyanInk,
              ),
            ),
          ),
          const SizedBox(height: 15),
          _PhoneVerificationText(
            'ยืนยันเบอร์เพื่อปลดล็อกโพสต์ฟรี',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 7),
          _PhoneVerificationText(
            'แพ็กเกจ Basic ต้องยืนยันเบอร์โทรก่อนใช้สิทธิ์โพสต์ฟรี 3 ครั้งต่อเดือน',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          TextField(
            key: const ValueKey('phone-verification-phone-field'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              label: const _PhoneVerificationText('เบอร์โทร', softWrap: true),
              hintText: _phoneVerificationText(context,
                  '0812345678 หรือ +66812345678', '0812345678 or +66812345678'),
              helper: Text(
                _phoneVerificationText(
                    context,
                    'ใส่เบอร์ไทย 10 หลัก หรือเบอร์ต่างประเทศพร้อม +รหัสประเทศ',
                    'Enter a 10-digit Thai mobile number, or an international number with +country code'),
                style: Theme.of(context).inputDecorationTheme.helperStyle ??
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
              ),
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            _PhoneVerificationText(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTheme.spaceLg),
          _GreenActionButton(
            key: const ValueKey('phone-verification-send-code'),
            label: _isLoading
                ? 'กำลังส่งรหัส...'
                : _resendSecondsRemaining > 0
                    ? _phoneVerificationText(
                        context,
                        'ส่งรหัส OTP (รอ $_resendSecondsRemaining วินาที)',
                        'Send OTP ($_resendWaitInEnglish)')
                    : 'ส่งรหัส OTP',
            icon: Icons.sms_outlined,
            onPressed: _isLoading || _resendSecondsRemaining > 0
                ? null
                : () => _sendCode(),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterCode(BuildContext context) {
    final showsDemoHint =
        !widget.enableFirebaseAuth && widget.allowLocalMockVerification;

    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneVerificationText(
            'กรอกรหัส OTP',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _phoneVerificationText(
                context,
                'ส่งรหัส 6 หลักไปที่ ${_phoneController.text.trim()}',
                'A 6-digit code was sent to ${_phoneController.text.trim()}'),
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          if (showsDemoHint) ...[
            const SizedBox(height: 13),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: AppTheme.accentCyanInk),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                                text: _phoneVerificationText(
                                    context,
                                    'โหมดทดสอบ: ใช้รหัส ',
                                    'Test mode: use code ')),
                            TextSpan(
                              text: DevMockPhoneVerification.demoCode,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spaceLg),
          TextField(
            key: const ValueKey('phone-verification-code-field'),
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              label: const _PhoneVerificationText('รหัส OTP', softWrap: true),
              hintText: '123456',
              counterText: '',
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            _PhoneVerificationText(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppTheme.spaceLg),
          _GreenActionButton(
            key: const ValueKey('phone-verification-confirm-code'),
            label: _isLoading ? 'กำลังยืนยัน...' : 'ยืนยัน',
            icon: Icons.verified_outlined,
            onPressed:
                _isLoading || _verificationId.isEmpty ? null : _confirmCode,
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey('phone-verification-resend-code'),
            onPressed: _isLoading || _resendSecondsRemaining > 0
                ? null
                : () => _sendCode(isResend: true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentCyanInk,
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: _PhoneVerificationText(_resendSecondsRemaining > 0
                ? _phoneVerificationText(
                    context,
                    'ส่งรหัสอีกครั้ง (รอ $_resendSecondsRemaining วินาที)',
                    'Resend code ($_resendWaitInEnglish)')
                : 'ส่งรหัสอีกครั้ง'),
          ),
          TextButton(
            key: const ValueKey('phone-verification-change-phone'),
            onPressed: _isLoading ? null : _changePhone,
            child: const _PhoneVerificationText('เปลี่ยนเบอร์'),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return PostDeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppTheme.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                size: 46,
                color: AppTheme.accentCyanInk,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PhoneVerificationText(
            'ยืนยันเบอร์เรียบร้อย',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _PhoneVerificationText(
            'ตอนนี้คุณใช้สิทธิ์โพสต์ฟรีของแพ็กเกจ Basic ได้แล้ว',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          _GreenActionButton(
            label: 'เสร็จสิ้น',
            icon: Icons.done,
            onPressed: () => Navigator.of(context).maybePop(_verifiedSession),
          ),
        ],
      ),
    );
  }
}

class _GreenActionButton extends StatelessWidget {
  const _GreenActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: _PhoneVerificationText(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PhoneVerificationText extends StatelessWidget {
  const _PhoneVerificationText(this.message,
      {this.style, this.textAlign, this.maxLines, this.softWrap});

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) => Text(
        _phoneVerificationMessage(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: softWrap,
      );
}

bool _phoneVerificationUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

String _phoneVerificationText(
        BuildContext context, String thai, String english) =>
    _phoneVerificationUsesThai(context) ? thai : english;

String _phoneVerificationMessage(BuildContext context, String message) =>
    _phoneVerificationUsesThai(context)
        ? message
        : _englishPhoneVerificationMessages[message] ?? message;

// Keep raw errors in state so app-owned messages follow the current locale.
// Provider behavior and unrecognized messages remain unchanged.
const _englishPhoneVerificationMessages = <String, String>{
  'ยืนยันเบอร์โทร': 'Verify phone number',
  'เบอร์โทร': 'Phone number',
  'รหัส OTP': 'OTP code',
  'ยืนยันเบอร์เพื่อปลดล็อกโพสต์ฟรี': 'Verify your phone to unlock free posting',
  'แพ็กเกจ Basic ต้องยืนยันเบอร์โทรก่อนใช้สิทธิ์โพสต์ฟรี 3 ครั้งต่อเดือน':
      'The Basic plan requires phone verification before you can use its 3 free post units per month.',
  'กำลังส่งรหัส...': 'Sending code...',
  'ส่งรหัส OTP': 'Send OTP',
  'กรอกรหัส OTP': 'Enter OTP',
  'กำลังยืนยัน...': 'Verifying...',
  'ยืนยัน': 'Verify',
  'ส่งรหัสอีกครั้ง': 'Resend code',
  'เปลี่ยนเบอร์': 'Change number',
  'ยืนยันเบอร์เรียบร้อย': 'Phone number verified',
  'ตอนนี้คุณใช้สิทธิ์โพสต์ฟรีของแพ็กเกจ Basic ได้แล้ว':
      "You can now use your Basic plan's free posting allowance.",
  'เสร็จสิ้น': 'Done',
  'กรอกเบอร์โทรมือถือไทย 10 หลัก เช่น 0812345678 หรือเบอร์ต่างประเทศพร้อมรหัสประเทศ':
      'Enter a 10-digit Thai mobile number, e.g. 0812345678, or an international number with its country code.',
  'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้ายืนยันเบอร์อีกครั้ง':
      'Your account has changed. Please reopen phone verification.',
  'บัญชีเปลี่ยน กรุณาเปิดหน้ายืนยันเบอร์อีกครั้ง':
      'Your account has changed. Please reopen phone verification.',
  'คำขอยืนยันหมดอายุ กรุณาส่งรหัสอีกครั้ง':
      'The verification request has expired. Please send a new code.',
  'ส่งรหัส OTP ไม่สำเร็จ': 'Could not send OTP.',
  'ยืนยันรหัสไม่สำเร็จ': 'Could not verify the code.',
  'รหัส OTP ไม่ถูกต้อง (โหมดทดสอบใช้ 123456)':
      'Invalid OTP (test mode uses 123456).',
  'ตรวจสอบเบอร์โทรมือถือและรหัสประเทศ เช่น 0812345678 หรือ +66812345678':
      'Check your mobile number and country code, e.g. 0812345678 or +66812345678.',
  'รหัส OTP ไม่ถูกต้อง กรุณากรอกรหัสล่าสุดจาก SMS อีกครั้ง':
      'Invalid OTP. Enter the latest code from your SMS.',
  'รหัส OTP หมดอายุแล้ว กรุณากดส่งรหัสอีกครั้ง':
      'Your OTP has expired. Please request a new code.',
  'ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่':
      'Too many requests. Please wait a moment and try again.',
  'ระบบส่ง SMS ไม่พร้อมชั่วคราว กรุณาลองใหม่ภายหลัง':
      'SMS delivery is temporarily unavailable. Please try again later.',
  'เชื่อมต่อไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่':
      'Could not connect. Check your internet connection and try again.',
  'เบอร์นี้ใช้กับบัญชีอื่นแล้ว กรุณาใช้เบอร์อื่นหรือเข้าสู่บัญชีเดิม':
      'This number is linked to another account. Use another number or sign in to the original account.',
  'ยืนยันเบอร์โทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง':
      'Could not verify your phone number. Please try again.',
};
