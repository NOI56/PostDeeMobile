import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('a mock binding without a UID cannot inherit the global principal', () async {
    final global = PostDeeAuthSessionStore.instance;
    addTearDown(global.clear);
    global.signIn(const AuthSession(userId: 'global-b', idToken: 'local-mock-id-token'));
    final custom = PostDeeAuthSessionStore(initialSession: const AuthSession(idToken: 'local-mock-id-token'));
    await expectLater(PostDeeApiAuthHeaders(sessionBinding: custom.captureSession(), mockUserId: 'global-b', enableFirebaseAuth: false, allowLocalMockAuth: true).load(), throwsA(isA<ApiException>()));
  });

  test('local mock headers use the binding owner instead of the global account', () async {
    final global = PostDeeAuthSessionStore.instance;
    addTearDown(global.clear);
    global.signIn(const AuthSession(userId: 'global-b', idToken: 'local-mock-id-token'));
    final custom = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'custom-a', idToken: 'local-mock-id-token'));
    final headers = await PostDeeApiAuthHeaders(sessionBinding: custom.captureSession(), mockUserId: 'custom-a', enableFirebaseAuth: false, allowLocalMockAuth: true).load();
    expect(headers['x-postdee-user-id'], 'custom-a');
  });

  test('bound mock headers reject configuration for a different global owner', () async {
    final global = PostDeeAuthSessionStore.instance;
    addTearDown(global.clear);
    global.signIn(const AuthSession(userId: 'global-b', idToken: 'local-mock-id-token'));
    final custom = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'custom-a', idToken: 'local-mock-id-token'));
    await expectLater(PostDeeApiAuthHeaders(sessionBinding: custom.captureSession(), mockUserId: 'global-b', enableFirebaseAuth: false, allowLocalMockAuth: true).load(), throwsA(isA<ApiException>()));
  });

  test('explicit local mock auth sends its configured stable API principal', () async {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'demo-owner', idToken: 'local-mock-id-token'));
    final headers = await PostDeeApiAuthHeaders(sessionStore: store, mockUserId: 'demo-owner', enableFirebaseAuth: false, allowLocalMockAuth: true).load();
    expect(headers['x-postdee-user-id'], 'demo-owner');
  });

  test('Firebase token never receives a development principal header', () async {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'firebase-owner', idToken: 'real-token'));
    final headers = await PostDeeApiAuthHeaders(sessionStore: store, mockUserId: 'demo-owner', enableFirebaseAuth: true, allowLocalMockAuth: true).load();
    expect(headers.containsKey('x-postdee-user-id'), isFalse);
  });

  test('explicit mock auth without matching configuration fails closed', () async {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'demo-owner', idToken: 'local-mock-id-token'));
    await expectLater(PostDeeApiAuthHeaders(sessionStore: store, mockUserId: '', enableFirebaseAuth: false, allowLocalMockAuth: true).load(), throwsA(isA<ApiException>()));
  });

  test('credential updates retain the binding only for its existing UID', () {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'a', idToken: 'a'));
    final binding = store.captureSession();
    store.updateCredentials(const AuthSession(userId: 'a', idToken: 'fresh-a', emailVerified: true));
    expect(binding.isCurrent, isTrue);
    expect(store.session.emailVerified, isTrue);
    expect(() => store.updateCredentials(const AuthSession(userId: 'b', idToken: 'b')), throwsA(isA<AuthSessionChangedException>()));
    expect(store.session.userId, 'a');
  });

  test('bound headers reject a delayed token after an account transition', () async {
    final token = Completer<String?>();
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'a', idToken: 'a'));
    final headers = PostDeeApiAuthHeaders(sessionBinding: store.captureSession(), authTokenProvider: () => token.future);
    final loaded = headers.load();
    final rejected = expectLater(loaded, throwsA(isA<AuthSessionChangedException>()));
    store.signIn(const AuthSession(userId: 'b', idToken: 'b'));
    token.complete('token-a');
    await rejected;
  });

  test('session binding survives profile edits but not another sign-in', () {
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(
      userId: 'a', idToken: 'token-a',
    ));
    final binding = store.captureSession();
    store.updateDisplayName('Updated');
    expect(binding.isCurrent, isTrue);
    store.signIn(store.session);
    expect(binding.isCurrent, isFalse);
    expect(binding.ensureCurrent, throwsA(isA<AuthSessionChangedException>()));
  });

  test('binding rejects a token refresh after signing out and back in', () async {
    final refresh = Completer<AuthCredentialSnapshot?>();
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(
      userId: 'a', idToken: 'token-a',
    ))..setAuthCredentialRefresher(() => refresh.future);
    final token = store.captureSession().currentIdToken();
    final rejected = expectLater(token, throwsA(isA<AuthSessionChangedException>()));
    store.signOut();
    store.signIn(const AuthSession(userId: 'a', idToken: 'new-token-a'));
    refresh.complete(const AuthCredentialSnapshot(userId: 'a', idToken: 'old-refresh'));
    await rejected;
  });

  test('failed token refresh never falls back to a later account', () async {
    final refresh = Completer<String?>();
    final store = PostDeeAuthSessionStore(initialSession: const AuthSession(
      userId: 'a', idToken: 'token-a',
    ))..setIdTokenRefresher(() => refresh.future);
    final token = store.currentIdToken();
    final rejected = expectLater(token, throwsA(isA<AuthSessionChangedException>()));
    store.signIn(const AuthSession(userId: 'b', idToken: 'token-b'));
    refresh.completeError(StateError('refresh failed'));
    await rejected;
  });

  test('authenticated session keeps a normalized stable user id', () {
    final session = AuthSession.authenticated(
      userId: '  firebase-user-123  ',
      idToken: '  firebase-id-token  ',
      email: 'seller@example.com',
    );

    expect(session.userId, 'firebase-user-123');
    expect(session.idToken, 'firebase-id-token');
    expect(session.hasStableUserId, isTrue);
  });

  test('authenticated session rejects a missing stable user id', () {
    expect(
      () => AuthSession.authenticated(
        userId: '   ',
        idToken: 'firebase-id-token',
      ),
      throwsArgumentError,
    );
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

  test('credential refresher accepts a token only for the same stable user',
      () async {
    final store = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase-user-a',
        idToken: 'cached-token-a',
      ),
    )..setAuthCredentialRefresher(
        () async => const AuthCredentialSnapshot(
          userId: 'firebase-user-a',
          idToken: 'fresh-token-a',
        ),
      );

    expect(await store.currentIdToken(), 'fresh-token-a');
  });

  test('credential refresher fails closed when Firebase switched users',
      () async {
    final store = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase-user-a',
        idToken: 'cached-token-a',
      ),
    )..setAuthCredentialRefresher(
        () async => const AuthCredentialSnapshot(
          userId: 'firebase-user-b',
          idToken: 'fresh-token-b',
        ),
      );

    await expectLater(
      store.currentIdToken(),
      throwsA(isA<AuthSessionChangedException>()),
    );
  });

  test('credential refresher may reuse the cache only after confirming the uid',
      () async {
    final store = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase-user-a',
        idToken: 'cached-token-a',
      ),
    )..setAuthCredentialRefresher(
        () async => const AuthCredentialSnapshot(
          userId: 'firebase-user-a',
        ),
      );

    expect(await store.currentIdToken(), 'cached-token-a');
  });

  test('API headers stop instead of sending another Firebase user token',
      () async {
    final store = PostDeeAuthSessionStore(
      initialSession: AuthSession.authenticated(
        userId: 'firebase-user-a',
        idToken: 'cached-token-a',
      ),
    )..setAuthCredentialRefresher(
        () async => const AuthCredentialSnapshot(
          userId: 'firebase-user-b',
          idToken: 'fresh-token-b',
        ),
      );

    await expectLater(
      PostDeeApiAuthHeaders(
        sessionStore: store,
        mockUserId: '',
        mockSubscriptionPlan: '',
      ).load(),
      throwsA(isA<AuthSessionChangedException>()),
    );
  });

  test('updating the display name preserves real email verification', () {
    final store = PostDeeAuthSessionStore(
      initialSession: const AuthSession(
        userId: 'firebase-user-123',
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'Old name',
        emailVerified: true,
      ),
    );

    store.updateDisplayName('New name');

    expect(store.session.displayName, 'New name');
    expect(store.session.emailVerified, isTrue);
    expect(store.session.userId, 'firebase-user-123');
  });
}
