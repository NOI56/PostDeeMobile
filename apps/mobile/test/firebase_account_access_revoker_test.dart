import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/auth/firebase_account_access_revoker.dart';

class _FakeClient implements FirebaseAccountAccessClient {
  _FakeClient({
    required this.signedInWithApple,
    this.supportsAppleTokenRevocation = true,
    this.authorizationCode = 'apple-authorization-code',
  });

  @override
  final bool signedInWithApple;

  @override
  final bool supportsAppleTokenRevocation;

  final String? authorizationCode;
  int authorizationCodeCalls = 0;
  final List<String> revokedCodes = [];

  @override
  Future<String?> requestAppleAuthorizationCode() async {
    authorizationCodeCalls += 1;
    return authorizationCode;
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    revokedCodes.add(authorizationCode);
  }
}

void main() {
  test('does nothing when the current Firebase user did not sign in with Apple',
      () async {
    final client = _FakeClient(signedInWithApple: false);
    final revoker = FirebaseAccountAccessRevoker(client);

    await revoker.revokeBeforeAccountDeletion();

    expect(client.authorizationCodeCalls, 0);
    expect(client.revokedCodes, isEmpty);
  });

  test('reauthenticates and revokes Apple access before account deletion',
      () async {
    final client = _FakeClient(signedInWithApple: true);
    final revoker = FirebaseAccountAccessRevoker(client);

    await revoker.revokeBeforeAccountDeletion();

    expect(client.authorizationCodeCalls, 1);
    expect(client.revokedCodes, ['apple-authorization-code']);
  });

  test('blocks deletion when Apple does not return an authorization code',
      () async {
    final client = _FakeClient(
      signedInWithApple: true,
      authorizationCode: null,
    );
    final revoker = FirebaseAccountAccessRevoker(client);

    await expectLater(
      revoker.revokeBeforeAccountDeletion(),
      throwsA(isA<AccountAccessRevocationException>()),
    );
    expect(client.revokedCodes, isEmpty);
  });

  test('does not call an Apple-only API on unsupported platforms', () async {
    final client = _FakeClient(
      signedInWithApple: true,
      supportsAppleTokenRevocation: false,
    );
    final revoker = FirebaseAccountAccessRevoker(client);

    await revoker.revokeBeforeAccountDeletion();

    expect(client.authorizationCodeCalls, 0);
    expect(client.revokedCodes, isEmpty);
  });
}
