import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/firebase_session_restorer.dart';

void main() {
  const restored = AuthSession(userId: 'old-user', idToken: 'old-token');

  test('startup survives a failed persisted token refresh', () async {
    final store = PostDeeAuthSessionStore();
    await restoreFirebaseSession(
      sessionStore: store,
      readSession: () async => throw StateError('offline'),
    );
    expect(store.session.isSignedIn, isFalse);
  });

  testWidgets('startup stops waiting and ignores a late restore',
      (tester) async {
    final store = PostDeeAuthSessionStore();
    final pending = Completer<AuthSession?>();
    final restore = restoreFirebaseSession(
      sessionStore: store,
      readSession: () => pending.future,
      timeout: const Duration(seconds: 2),
    );
    await tester.pump(const Duration(seconds: 3));
    await restore;
    pending.complete(restored);
    await tester.pump();
    expect(store.session.isSignedIn, isFalse);
  });

  test('restore cannot replace a newer sign-in or logout', () async {
    final store = PostDeeAuthSessionStore();
    final pending = Completer<AuthSession?>();
    final restore = restoreFirebaseSession(
      sessionStore: store,
      readSession: () => pending.future,
    );
    store.signIn(const AuthSession(userId: 'new-user', idToken: 'new-token'));
    store.clear();
    pending.complete(restored);
    await restore;
    expect(store.session.isSignedIn, isFalse);
  });
}
