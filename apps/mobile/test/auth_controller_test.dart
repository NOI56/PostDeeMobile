import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';

class _FailingGoogleGateway implements GoogleAuthGateway {
  @override
  Future<AuthSession> signIn() async => AuthSession.unauthenticated;

  @override
  Future<void> signOut() async => throw StateError('native sign-out failed');
}

void main() {
  test('clears the local session even when native sign-out fails', () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'deleted-user-token'),
    );
    final controller = PostDeeAuthController(
      googleAuthGateway: _FailingGoogleGateway(),
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);

    await expectLater(controller.signOut(), throwsStateError);

    expect(sessionStore.session.isSignedIn, isFalse);
  });
}
