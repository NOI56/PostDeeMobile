import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/auth_session.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.storeName,
    this.accountEmail = '',
    this.accountUserId = '',
  });

  final String displayName;
  final String storeName;
  final String accountEmail;
  final String accountUserId;
}

abstract interface class ProfileDraftStore {
  Future<ProfileDraft?> load();

  Future<void> save(ProfileDraft draft);

  Future<void> clear();
}

class SharedPreferencesProfileDraftStore implements ProfileDraftStore {
  const SharedPreferencesProfileDraftStore({
    SharedPreferences? preferences,
    PostDeeAuthSessionStore? sessionStore,
  })  : _preferences = preferences,
        _sessionStore = sessionStore;

  static const _displayNameKey = 'postdee.profile.display_name';
  static const _storeNameKey = 'postdee.profile.store_name';
  static const _accountEmailKey = 'postdee.profile.account_email';
  static const _legacyOwnerUserIdKey = 'postdee.profile.legacy_owner_uid';

  final SharedPreferences? _preferences;
  final PostDeeAuthSessionStore? _sessionStore;
  AuthSession get _session =>
      (_sessionStore ?? PostDeeAuthSessionStore.instance).session;
  String _key(String base, String uid) => '$base.${Uri.encodeComponent(uid)}';

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<ProfileDraft?> load() async {
    final session = _session;
    final uid = session.stableUserId;
    if (!session.isSignedIn || uid == null) return null;
    final preferences = await _activePreferences;
    final displayName =
        preferences.getString(_key(_displayNameKey, uid))?.trim() ?? '';
    final storeName =
        preferences.getString(_key(_storeNameKey, uid))?.trim() ?? '';
    final accountEmail = preferences
            .getString(_key(_accountEmailKey, uid))
            ?.trim()
            .toLowerCase() ??
        '';

    if (displayName.isEmpty && storeName.isEmpty) {
      final legacyEmail =
          preferences.getString(_accountEmailKey)?.trim().toLowerCase() ?? '';
      final sessionEmail = session.email?.trim().toLowerCase() ?? '';
      final legacyOwner = preferences.getString(_legacyOwnerUserIdKey);
      if (legacyEmail.isEmpty ||
          sessionEmail.isEmpty ||
          legacyEmail != sessionEmail ||
          _session.stableUserId != uid ||
          (legacyOwner != null && legacyOwner != uid)) {
        return null;
      }
      final legacyName = preferences.getString(_displayNameKey)?.trim() ?? '';
      final legacyStore = preferences.getString(_storeNameKey)?.trim() ?? '';
      if (legacyName.isEmpty && legacyStore.isEmpty) return null;
      final migrated = ProfileDraft(
          displayName: legacyName,
          storeName: legacyStore,
          accountEmail: legacyEmail,
          accountUserId: uid);
      await save(migrated);
      await preferences.setString(_legacyOwnerUserIdKey, uid);
      // Preserve the legacy values until their owner has migrated. Matching
      // email is required and no other account may claim an unnamed draft.
      return migrated;
    }

    return ProfileDraft(
      displayName: displayName,
      storeName: storeName,
      accountEmail: accountEmail,
      accountUserId: uid,
    );
  }

  @override
  Future<void> save(ProfileDraft draft) async {
    final uid = _session.stableUserId;
    if (!_session.isSignedIn || uid == null || draft.accountUserId != uid) {
      return;
    }
    final preferences = await _activePreferences;
    await preferences.setString(
        _key(_displayNameKey, uid), draft.displayName.trim());
    await preferences.setString(
        _key(_storeNameKey, uid), draft.storeName.trim());
    await preferences.setString(
      _key(_accountEmailKey, uid),
      draft.accountEmail.trim().toLowerCase(),
    );
  }

  @override
  Future<void> clear() async {
    final uid = _session.stableUserId;
    if (!_session.isSignedIn || uid == null) return;
    final preferences = await _activePreferences;
    await preferences.remove(_key(_displayNameKey, uid));
    await preferences.remove(_key(_storeNameKey, uid));
    await preferences.remove(_key(_accountEmailKey, uid));
  }
}
