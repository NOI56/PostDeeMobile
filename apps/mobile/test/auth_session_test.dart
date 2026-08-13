import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
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
