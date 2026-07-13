import 'package:shared_preferences/shared_preferences.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.storeName,
    this.accountEmail = '',
  });

  final String displayName;
  final String storeName;
  final String accountEmail;
}

abstract interface class ProfileDraftStore {
  Future<ProfileDraft?> load();

  Future<void> save(ProfileDraft draft);

  Future<void> clear();
}

class SharedPreferencesProfileDraftStore implements ProfileDraftStore {
  const SharedPreferencesProfileDraftStore({SharedPreferences? preferences})
      : _preferences = preferences;

  static const _displayNameKey = 'postdee.profile.display_name';
  static const _storeNameKey = 'postdee.profile.store_name';
  static const _accountEmailKey = 'postdee.profile.account_email';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<ProfileDraft?> load() async {
    final preferences = await _activePreferences;
    final displayName = preferences.getString(_displayNameKey)?.trim() ?? '';
    final storeName = preferences.getString(_storeNameKey)?.trim() ?? '';
    final accountEmail =
        preferences.getString(_accountEmailKey)?.trim().toLowerCase() ?? '';

    if (displayName.isEmpty && storeName.isEmpty) {
      return null;
    }

    return ProfileDraft(
      displayName: displayName,
      storeName: storeName,
      accountEmail: accountEmail,
    );
  }

  @override
  Future<void> save(ProfileDraft draft) async {
    final preferences = await _activePreferences;
    await preferences.setString(_displayNameKey, draft.displayName.trim());
    await preferences.setString(_storeNameKey, draft.storeName.trim());
    await preferences.setString(
      _accountEmailKey,
      draft.accountEmail.trim().toLowerCase(),
    );
  }

  @override
  Future<void> clear() async {
    final preferences = await _activePreferences;
    await preferences.remove(_displayNameKey);
    await preferences.remove(_storeNameKey);
    await preferences.remove(_accountEmailKey);
  }
}
