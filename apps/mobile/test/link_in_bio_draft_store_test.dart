import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

LinkInBioDraft _draft(String marker) => LinkInBioDraft(
      storeName: marker,
      slug: marker,
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {'recommended_product'},
      customLinks: [
        LinkInBioCustomLink(
          id: marker,
          title: marker,
          url: 'https://example.invalid/$marker',
        ),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('drafts are isolated by UID even when emails match', () async {
    final sessions = PostDeeAuthSessionStore();
    final store = SharedPreferencesLinkInBioDraftStore(sessionStore: sessions);
    sessions.signIn(const AuthSession(
      userId: 'A', idToken: 'token-A', email: 'same@example.invalid',
    ));
    await store.saveDraft(_draft('only-A'));
    sessions.signIn(const AuthSession(
      userId: 'B', idToken: 'token-B', email: 'same@example.invalid',
    ));
    expect(await store.loadDraft(), isNull);
    await store.saveDraft(_draft('only-B'));
    sessions.signIn(const AuthSession(userId: 'A', idToken: 'new-token-A'));
    expect((await store.loadDraft())?.customLinks.single.title, 'only-A');
  });

  test('unowned legacy preferences are never assigned to a signed-in account',
      () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesLinkInBioDraftStore.storeNameKey: 'legacy-private-shop',
      SharedPreferencesLinkInBioDraftStore.slugKey: 'legacy-private-slug',
    });
    final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(userId: 'B', idToken: 'token-B'),
    );
    final store = SharedPreferencesLinkInBioDraftStore(sessionStore: sessions);
    expect(await store.loadDraft(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SharedPreferencesLinkInBioDraftStore.storeNameKey),
        'legacy-private-shop');
  });

  test('signed-out and unidentified sessions cannot persist a draft', () async {
    final sessions = PostDeeAuthSessionStore();
    final store = SharedPreferencesLinkInBioDraftStore(sessionStore: sessions);
    expect(await store.loadDraft(), isNull);
    await expectLater(store.saveDraft(_draft('signed-out')),
        throwsA(isA<StateError>()));
    sessions.signIn(const AuthSession(idToken: 'token-without-uid'));
    expect(await store.loadDraft(), isNull);
    await expectLater(store.saveDraft(_draft('unknown-owner')),
        throwsA(isA<StateError>()));
  });

  test('a save waiting for preferences cannot write for a later session',
      () async {
    final pendingPreferences = Completer<SharedPreferences>();
    final prefs = await SharedPreferences.getInstance();
    final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(userId: 'A', idToken: 'token-A'),
    );
    final store = SharedPreferencesLinkInBioDraftStore(
      sessionStore: sessions,
      preferencesLoader: () => pendingPreferences.future,
    );
    final outcome = expectLater(store.saveDraft(_draft('late-A')),
        throwsA(isA<AuthSessionChangedException>()));
    sessions.signIn(const AuthSession(userId: 'B', idToken: 'token-B'));
    pendingPreferences.complete(prefs);
    await outcome;
    expect(prefs.getKeys(), isEmpty);
  });
}
