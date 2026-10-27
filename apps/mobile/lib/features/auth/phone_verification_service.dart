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
    required firebase_auth.PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
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
    required firebase_auth.PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
  }) =>
      _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
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
      );
      _request = request;
      _ensureCurrent(request);
      unawaited(_startVerification(request, phoneNumber));
      return request.completer.future;
    } catch (error, stackTrace) {
      _request?.cancelled = true;
      _request = null;
      return Future<PhoneVerificationStartResult>.error(error, stackTrace);
    }
  }

  Future<void> _startVerification(
    _PhoneVerificationRequest request,
    String phoneNumber,
  ) async {
    try {
      _ensureCurrent(request);
      await _phoneAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
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
              error.message ?? 'Phone verification failed: ${error.code}',
            ),
            StackTrace.current,
          );
        },
        codeSent: (verificationId, resendToken) =>
            _completeWithSms(request, verificationId),
        codeAutoRetrievalTimeout: (verificationId) =>
            _completeWithSms(request, verificationId),
      );
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
    String verificationId,
  ) {
    if (request.autoClosed || request.completer.isCompleted) return;
    try {
      _ensureCurrent(request);
      request.autoClosed = true;
      request.verificationId = verificationId;
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
        (sessionUid != null && sessionUid != request.userId)) {
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
              error.message ?? 'Could not link phone number: ${error.code}',
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

        session = AuthSession(
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
  }) : userId = user.uid;

  final FirebasePhoneAuthUser user;
  final String userId;
  final AuthSessionBinding sessionBinding;
  final completer = Completer<PhoneVerificationStartResult>();
  String? verificationId;
  bool cancelled = false;
  bool autoClosed = false;
  bool linking = false;
  bool consumed = false;
}
