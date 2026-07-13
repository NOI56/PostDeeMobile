import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';

abstract class AccountAccessRevoker {
  Future<void> revokeBeforeAccountDeletion();
}

class NoopAccountAccessRevoker implements AccountAccessRevoker {
  const NoopAccountAccessRevoker();

  @override
  Future<void> revokeBeforeAccountDeletion() async {}
}

class AccountAccessRevocationException implements Exception {
  const AccountAccessRevocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FirebaseAccountAccessClient {
  bool get signedInWithApple;

  bool get supportsAppleTokenRevocation;

  Future<String?> requestAppleAuthorizationCode();

  Future<void> revokeAppleToken(String authorizationCode);
}

class FirebaseAccountAccessPackageClient
    implements FirebaseAccountAccessClient {
  FirebaseAccountAccessPackageClient({firebase_auth.FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  @override
  bool get signedInWithApple =>
      _firebaseAuth.currentUser?.providerData.any(
        (provider) => provider.providerId == 'apple.com',
      ) ??
      false;

  @override
  bool get supportsAppleTokenRevocation => Platform.isIOS || Platform.isMacOS;

  @override
  Future<String?> requestAppleAuthorizationCode() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      return null;
    }

    final provider = firebase_auth.AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final credential = await user.reauthenticateWithProvider(provider);
    await user.getIdToken(true);
    return credential.additionalUserInfo?.authorizationCode?.trim();
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) =>
      _firebaseAuth.revokeTokenWithAuthorizationCode(authorizationCode);
}

class FirebaseAccountAccessRevoker implements AccountAccessRevoker {
  const FirebaseAccountAccessRevoker(this._client);

  final FirebaseAccountAccessClient _client;

  @override
  Future<void> revokeBeforeAccountDeletion() async {
    if (!_client.signedInWithApple || !_client.supportsAppleTokenRevocation) {
      return;
    }

    final authorizationCode = await _client.requestAppleAuthorizationCode();

    if (authorizationCode == null || authorizationCode.isEmpty) {
      throw const AccountAccessRevocationException(
        'Apple ไม่ส่งรหัสยืนยัน กรุณาลองลบบัญชีอีกครั้ง',
      );
    }

    try {
      await _client.revokeAppleToken(authorizationCode);
    } catch (_) {
      throw const AccountAccessRevocationException(
        'ถอนสิทธิ์ Sign in with Apple ไม่สำเร็จ บัญชียังไม่ถูกลบ กรุณาลองใหม่',
      );
    }
  }
}

AccountAccessRevoker createAccountAccessRevokerFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
}) {
  if (!enableFirebaseAuth ||
      !(firebaseBootstrapResult?.isInitialized ?? false)) {
    return const NoopAccountAccessRevoker();
  }

  return FirebaseAccountAccessRevoker(
    FirebaseAccountAccessPackageClient(),
  );
}
