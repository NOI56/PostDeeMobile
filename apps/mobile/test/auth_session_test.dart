import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
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

  test('currentIdToken falls back to the cached token when refresher returns null',
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
}
