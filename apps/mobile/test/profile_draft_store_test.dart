import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/profile/profile_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const owner = AuthSession(
      userId: 'owner', idToken: 'token', email: 'owner@example.com');
  const other = AuthSession(userId: 'other', idToken: 'token');

  test('profile drafts stay with their UID on a shared device', () async {
    SharedPreferences.setMockInitialValues({});
    final session = PostDeeAuthSessionStore(initialSession: owner);
    final store = SharedPreferencesProfileDraftStore(sessionStore: session);
    await store.save(const ProfileDraft(
        displayName: 'Owner name',
        storeName: 'Owner shop',
        accountUserId: 'owner'));
    session.signIn(other);
    expect(await store.load(), isNull);
    await store.save(const ProfileDraft(
        displayName: 'Other name', storeName: '', accountUserId: 'other'));
    session.signIn(owner);
    expect((await store.load())?.displayName, 'Owner name');
  });

  test('legacy profile is migrated only for its matching nonempty email',
      () async {
    SharedPreferences.setMockInitialValues({
      'postdee.profile.display_name': 'Legacy owner',
      'postdee.profile.store_name': 'Legacy shop',
      'postdee.profile.account_email': 'owner@example.com',
    });
    final session = PostDeeAuthSessionStore(initialSession: other);
    final store = SharedPreferencesProfileDraftStore(sessionStore: session);
    expect(await store.load(), isNull);
    session.signIn(owner);
    expect((await store.load())?.accountUserId, 'owner');
    session.signIn(other);
    expect(await store.load(), isNull);
    session.signIn(owner);
    expect((await store.load())?.displayName, 'Legacy owner');
  });

  test('late save from an old profile editor cannot target the new UID',
      () async {
    SharedPreferences.setMockInitialValues({});
    final session = PostDeeAuthSessionStore(initialSession: other);
    final store = SharedPreferencesProfileDraftStore(sessionStore: session);
    await store.save(const ProfileDraft(
        displayName: 'Old', storeName: '', accountUserId: 'owner'));
    expect(await store.load(), isNull);
  });
}
