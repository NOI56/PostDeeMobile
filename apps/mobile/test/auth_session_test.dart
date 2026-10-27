import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('display-name updates preserve the stable UID and session binding', () {
    final store = PostDeeAuthSessionStore(
      initialSession: const AuthSession(
        userId: 'dummy-firebase-uid',
        idToken: 'dummy-token',
        email: 'seller@example.invalid',
      ),
    );
    final binding = store.captureSession();
    store.updateDisplayName('ร้านใหม่');

    expect(store.session.userId, 'dummy-firebase-uid');
    expect(binding.isCurrent, isTrue);
  });

  test(
      'PostDeeApiAuthHeaders uses the shared signed-in session token by default',
      () async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    addTearDown(sessionStore.clear);

    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );

    final headers = await PostDeeApiAuthHeaders(
      mockUserId: 'local-dev-user',
      mockSubscriptionPlan: 'PRO',
    ).load();

    expect(headers, {
      'Accept': 'application/json',
      'x-postdee-subscription-plan': 'PRO',
      'Authorization': 'Bearer firebase-id-token',
    });
  });

  test('currentIdToken returns a fresh token from the refresher when set',
      () async {
    final store = PostDeeAuthSessionStore()
      ..signIn(const AuthSession(idToken: 'stale-cached-token'))
      ..setIdTokenRefresher(() async => 'fresh-token');

    expect(await store.currentIdToken(), 'fresh-token');
  });

  test(
      'currentIdToken falls back to the cached token when refresher returns null',
      () async {
    final store = PostDeeAuthSessionStore()
      ..signIn(const AuthSession(idToken: 'cached-token'))
      ..setIdTokenRefresher(() async => null);

    expect(await store.currentIdToken(), 'cached-token');
  });

  test('currentIdToken falls back to the cached token when refresher throws',
      () async {
    final store = PostDeeAuthSessionStore()
      ..signIn(const AuthSession(idToken: 'cached-token'))
      ..setIdTokenRefresher(() async {
        throw Exception('network down');
      });

    expect(await store.currentIdToken(), 'cached-token');
  });

  test('currentIdToken is null when signed out with no refresher', () async {
    final store = PostDeeAuthSessionStore();

    expect(await store.currentIdToken(), isNull);
  });

  for (final outcome in ['fresh token', 'null token', 'refresh failure']) {
    test('bound token rejects a changed session after $outcome', () async {
      final token = Completer<String?>();
      final store = PostDeeAuthSessionStore(
        initialSession: const AuthSession(idToken: 'account-a-token'),
      )..setIdTokenRefresher(() => token.future);
      final binding = store.captureSession();
      final expectation = expectLater(
        binding.currentIdToken(),
        throwsA(isA<AuthSessionChangedException>()),
      );

      store.signOut();
      store.signIn(const AuthSession(idToken: 'account-b-token'));
      if (outcome == 'refresh failure') {
        token.completeError(StateError('refresh failed'));
      } else {
        token.complete(outcome == 'fresh token' ? 'account-b-token' : null);
      }

      await expectation;
      expect(store.session.idToken, 'account-b-token');
    });
  }

  test('bound token rejects a session changed before token loading', () async {
    var refreshCalls = 0;
    final store = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    )..setIdTokenRefresher(() async {
        refreshCalls += 1;
        return 'account-b-token';
      });
    final binding = store.captureSession();
    store.signIn(const AuthSession(idToken: 'account-b-token'));

    await expectLater(
      binding.currentIdToken(),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(refreshCalls, 0);
  });

  test('name edits and token refresh preserve a session binding', () async {
    final store = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'cached-token'),
    )..setIdTokenRefresher(() async => 'refreshed-token');
    final binding = store.captureSession();

    store.updateDisplayName('New name');

    expect(await binding.currentIdToken(), 'refreshed-token');
    expect(binding.isCurrent, isTrue);
  });

  test('explicit sign-in again requires a new session binding', () {
    const account = AuthSession(idToken: 'same-account-token');
    final store = PostDeeAuthSessionStore(initialSession: account);
    final binding = store.captureSession();

    store.signIn(account);

    expect(binding.isCurrent, isFalse);
  });

  test('updating the display name preserves real email verification', () {
    final store = PostDeeAuthSessionStore(
      initialSession: const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'Old name',
        emailVerified: true,
      ),
    );

    store.updateDisplayName('New name');

    expect(store.session.displayName, 'New name');
    expect(store.session.emailVerified, isTrue);
  });
}
