import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';
import 'auth_controller.dart';

typedef PhoneVerificationCodeSender = Future<PhoneVerificationStartResult>
    Function(String phoneNumber);
typedef PhoneVerificationCodeConfirmer = Future<AuthSession> Function({
  required String verificationId,
  required String smsCode,
});
typedef BoundPhoneAuthOperation = Future<void> Function({
  required AuthSessionBinding sessionBinding,
  required Future<void> Function() operation,
});

/// Accepts Thai mobile numbers or an international number with a country code.
/// This validates the input format; the SMS provider verifies the actual number.
String? normalizePhoneVerificationNumber(String input) {
  final compact = input.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^0[689][0-9]{8}$').hasMatch(compact)) {
    return '+66${compact.substring(1)}';
  }
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(compact)) return null;
  if (compact.startsWith('+66') &&
      !RegExp(r'^\+66[689][0-9]{8}$').hasMatch(compact)) {
    return null;
  }
  return compact;
}

String _phoneProviderErrorMessage(firebase_auth.FirebaseAuthException error) =>
    switch (error.code) {
      'invalid-phone-number' =>
        'ตรวจสอบเบอร์โทรมือถือและรหัสประเทศ เช่น 0812345678 หรือ +66812345678',
      'invalid-verification-code' ||
      'invalid-verification-id' =>
        'รหัส OTP ไม่ถูกต้อง กรุณากรอกรหัสล่าสุดจาก SMS อีกครั้ง',
      'session-expired' ||
      'code-expired' =>
        'รหัส OTP หมดอายุแล้ว กรุณากดส่งรหัสอีกครั้ง',
      'too-many-requests' => 'ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่',
      'quota-exceeded' => 'ระบบส่ง SMS ไม่พร้อมชั่วคราว กรุณาลองใหม่ภายหลัง',
      'network-request-failed' =>
        'เชื่อมต่อไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
      'credential-already-in-use' ||
      'phone-number-already-exists' =>
        'เบอร์นี้ใช้กับบัญชีอื่นแล้ว กรุณาใช้เบอร์อื่นหรือเข้าสู่บัญชีเดิม',
      _ => 'ยืนยันเบอร์โทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    };

abstract class FirebasePhoneAuthUser {
  String get uid;
  String? get email;
  String? get displayName;
  bool get emailVerified;

  Future<void> linkWithCredential(firebase_auth.PhoneAuthCredential credential);
  Future<void> reload();
  Future<String?> getIdToken(bool forceRefresh);
}

abstract class FirebasePhoneAuthAdapter {
  FirebasePhoneAuthUser? get currentUser;

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Duration timeout,
    required firebase_auth.PhoneVerificationCompleted verificationCompleted,
    required firebase_auth.PhoneVerificationFailed verificationFailed,
    required firebase_auth.PhoneCodeSent codeSent,
    required firebase_auth.PhoneCodeAutoRetrievalTimeout
        codeAutoRetrievalTimeout,
    int? forceResendingToken,
  });
}

class _FirebasePhoneAuthUser implements FirebasePhoneAuthUser {
  const _FirebasePhoneAuthUser(this._user);

  final firebase_auth.User _user;

  @override
  String get uid => _user.uid;
  @override
  String? get email => _user.email;
  @override
  String? get displayName => _user.displayName;
  @override
  bool get emailVerified => _user.emailVerified;

  @override
  Future<void> linkWithCredential(
    firebase_auth.PhoneAuthCredential credential,
  ) async {
    await _user.linkWithCredential(credential);
  }

  @override
  Future<void> reload() => _user.reload();

  @override
  Future<String?> getIdToken(bool forceRefresh) =>
      _user.getIdToken(forceRefresh);
}

class _FirebasePhoneAuthAdapter implements FirebasePhoneAuthAdapter {
  const _FirebasePhoneAuthAdapter(this._auth);

  final firebase_auth.FirebaseAuth _auth;

  @override
  FirebasePhoneAuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _FirebasePhoneAuthUser(user);
  }

  @override
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Duration timeout,
    required firebase_auth.PhoneVerificationCompleted verificationCompleted,
    required firebase_auth.PhoneVerificationFailed verificationFailed,
    required firebase_auth.PhoneCodeSent codeSent,
    required firebase_auth.PhoneCodeAutoRetrievalTimeout
        codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) =>
      _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
        forceResendingToken: forceResendingToken,
      );
}

class PhoneVerificationStartResult {
  const PhoneVerificationStartResult.codeSent({
    required this.verificationId,
  }) : autoVerifiedSession = null;

  const PhoneVerificationStartResult.autoVerified({
    required AuthSession session,
  })  : verificationId = '',
        autoVerifiedSession = session;

  final String verificationId;
  final AuthSession? autoVerifiedSession;

  bool get isAutoVerified => autoVerifiedSession != null;
}

class FirebasePhoneVerificationGateway {
  FirebasePhoneVerificationGateway({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebasePhoneAuthAdapter? phoneAuthAdapter,
    PostDeeAuthSessionStore? sessionStore,
    BoundPhoneAuthOperation? runNativeAuthOperation,
    this.timeout = const Duration(seconds: 60),
  })  : _phoneAuth = phoneAuthAdapter ??
            _FirebasePhoneAuthAdapter(
              firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
            ),
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _runNativeAuthOperation = runNativeAuthOperation;

  final FirebasePhoneAuthAdapter _phoneAuth;
  final PostDeeAuthSessionStore _sessionStore;
  final BoundPhoneAuthOperation? _runNativeAuthOperation;
  final Duration timeout;
  _PhoneVerificationRequest? _request;

  Future<PhoneVerificationStartResult> sendCode(String phoneNumber) {
    final previous = _request;
    final resendToken = previous != null &&
            !previous.cancelled &&
            !previous.consumed &&
            previous.phoneNumber == phoneNumber &&
            previous.sessionBinding.isCurrent &&
            previous.userId == _sessionStore.session.userId &&
            previous.userId == _phoneAuth.currentUser?.uid
        ? previous.resendToken
        : null;
    cancelVerification();
    try {
      if (_runNativeAuthOperation == null) {
        throw const AuthUnavailableException(
          'Phone verification requires the shared authentication queue.',
        );
      }
      final user = _phoneAuth.currentUser;
      if (user == null || !_sessionStore.session.isSignedIn) {
        throw const AuthUnavailableException(
          'Sign in before verifying a phone number.',
        );
      }
      final request = _PhoneVerificationRequest(
        user: user,
        sessionBinding: _sessionStore.captureSession(),
        phoneNumber: phoneNumber,
      );
      _request = request;
      _ensureCurrent(request);
      unawaited(_startVerification(request, forceResendingToken: resendToken));
      return request.completer.future;
    } catch (error, stackTrace) {
      _request?.cancelled = true;
      _request = null;
      return Future<PhoneVerificationStartResult>.error(error, stackTrace);
    }
  }

  Future<void> _startVerification(
    _PhoneVerificationRequest request, {
    int? forceResendingToken,
  }) async {
    try {
      _ensureCurrent(request);
      await _phoneAuth.verifyPhoneNumber(
        phoneNumber: request.phoneNumber,
        timeout: timeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (credential) async {
          // Claim the callback before awaiting native work. codeSent/timeout and
          // completed/failed/cancelled requests cannot start another credential.
          if (request.autoClosed || request.completer.isCompleted) return;
          request.autoClosed = true;
          request.linking = true;
          try {
            final session = await _linkPhoneCredential(request, credential);
            _ensureCurrent(request);
            request.consumed = true;
            if (!request.completer.isCompleted) {
              request.completer.complete(
                PhoneVerificationStartResult.autoVerified(session: session),
              );
            }
          } catch (error, stackTrace) {
            _failStart(request, error, stackTrace);
          } finally {
            request.linking = false;
          }
        },
        verificationFailed: (error) {
          if (request.autoClosed || request.completer.isCompleted) return;
          _failStart(
            request,
            AuthUnavailableException(
              _phoneProviderErrorMessage(error),
            ),
            StackTrace.current,
          );
        },
        codeSent: (verificationId, resendToken) =>
            _completeWithSms(request, verificationId, resendToken: resendToken),
        codeAutoRetrievalTimeout: (verificationId) =>
            _completeWithSms(request, verificationId),
      );
    } on firebase_auth.FirebaseAuthException catch (error, stackTrace) {
      _failStart(
          request,
          AuthUnavailableException(_phoneProviderErrorMessage(error)),
          stackTrace);
    } catch (error, stackTrace) {
      _failStart(request, error, stackTrace);
    }
  }

  Future<AuthSession> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final request = _request;
    if (request == null ||
        request.verificationId != verificationId ||
        request.linking ||
        request.consumed) {
      throw const AuthSessionChangedException();
    }
    _ensureCurrent(request);
    request.linking = true;
    try {
      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final session = await _linkPhoneCredential(request, credential);
      _ensureCurrent(request);
      request.consumed = true;
      return session;
    } finally {
      request.linking = false;
    }
  }

  void cancelVerification() {
    final request = _request;
    _request = null;
    if (request == null) return;
    request.cancelled = true;
    request.autoClosed = true;
    if (!request.completer.isCompleted) {
      request.completer.completeError(const AuthSessionChangedException());
    }
  }

  void _completeWithSms(
    _PhoneVerificationRequest request,
    String verificationId, {
    int? resendToken,
  }) {
    if (request.autoClosed || request.completer.isCompleted) return;
    try {
      _ensureCurrent(request);
      request.autoClosed = true;
      request.verificationId = verificationId;
      request.resendToken = resendToken;
      request.completer.complete(
        PhoneVerificationStartResult.codeSent(verificationId: verificationId),
      );
    } catch (error, stackTrace) {
      _failStart(request, error, stackTrace);
    }
  }

  void _failStart(
    _PhoneVerificationRequest request,
    Object error,
    StackTrace stackTrace,
  ) {
    if (request.completer.isCompleted) return;
    request.cancelled = true;
    request.autoClosed = true;
    request.completer.completeError(error, stackTrace);
  }

  void _ensureCurrent(_PhoneVerificationRequest request) {
    request.sessionBinding.ensureCurrent();
    final sessionUid = _sessionStore.session.userId;
    if (request.cancelled ||
        !identical(_request, request) ||
        request.user.uid != request.userId ||
        _phoneAuth.currentUser?.uid != request.userId ||
        sessionUid != request.userId) {
      throw const AuthSessionChangedException();
    }
  }

  Future<AuthSession> _linkPhoneCredential(
    _PhoneVerificationRequest request,
    firebase_auth.PhoneAuthCredential credential,
  ) async {
    _ensureCurrent(request);
    late final AuthSession session;
    // FlutterFire's native User methods dispatch against native currentUser.
    // The shared controller queue prevents a later app login/logout from racing
    // that dispatch; a captured Dart User alone does not provide this guarantee.
    await _runNativeAuthOperation!(
      sessionBinding: request.sessionBinding,
      operation: () async {
        _ensureCurrent(request);
        final user = request.user;
        try {
          await user.linkWithCredential(credential);
        } on firebase_auth.FirebaseAuthException catch (error) {
          _ensureCurrent(request);
          if (error.code != 'provider-already-linked') {
            throw AuthUnavailableException(
              _phoneProviderErrorMessage(error),
            );
          }
        }
        _ensureCurrent(request);
        await user.reload();
        _ensureCurrent(request);
        final idToken = (await user.getIdToken(true))?.trim();
        _ensureCurrent(request);

        if (idToken == null || idToken.isEmpty) {
          throw const AuthUnavailableException(
            'Firebase Auth did not return a refreshed ID token.',
          );
        }

        session = AuthSession.authenticated(
          userId: request.userId,
          idToken: idToken,
          email: user.email,
          displayName: user.displayName,
          emailVerified: user.emailVerified,
        );
      },
    );
    _ensureCurrent(request);
    return session;
  }
}

class _PhoneVerificationRequest {
  _PhoneVerificationRequest({
    required this.user,
    required this.sessionBinding,
    required this.phoneNumber,
  }) : userId = user.uid;

  final FirebasePhoneAuthUser user;
  final String userId;
  final AuthSessionBinding sessionBinding;
  final String phoneNumber;
  final completer = Completer<PhoneVerificationStartResult>();
  String? verificationId;
  int? resendToken;
  bool cancelled = false;
  bool autoClosed = false;
  bool linking = false;
  bool consumed = false;
}
