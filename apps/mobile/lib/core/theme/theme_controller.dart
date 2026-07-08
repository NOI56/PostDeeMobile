import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

abstract class PostDeeThemePreferenceStore {
  Future<ThemeMode?> loadThemeMode();

  Future<void> saveThemeMode(ThemeMode mode);
}

class SharedPreferencesThemePreferenceStore
    implements PostDeeThemePreferenceStore {
  const SharedPreferencesThemePreferenceStore({SharedPreferences? preferences})
      : _preferences = preferences;

  static const themeModeKey = 'postdee_theme_mode';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<ThemeMode?> loadThemeMode() async {
    final preferences = await _activePreferences;

    return switch (preferences.getString(themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    final preferences = await _activePreferences;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      _ => 'dark',
    };

    await preferences.setString(themeModeKey, value);
  }
}

class PostDeeThemeController extends ChangeNotifier {
  PostDeeThemeController({
    ThemeMode initialMode = ThemeMode.light,
    PostDeeThemePreferenceStore? preferenceStore,
  })  : _themeMode = initialMode,
        _preferenceStore = preferenceStore {
    AppTheme.applyThemeMode(_themeMode);
  }

  static final instance = PostDeeThemeController(
    preferenceStore: const SharedPreferencesThemePreferenceStore(),
  );

  ThemeMode _themeMode;
  final PostDeeThemePreferenceStore? _preferenceStore;

  ThemeMode get themeMode => _themeMode;

  bool get isLightMode => _themeMode == ThemeMode.light;

  Future<void> loadSavedThemeMode() async {
    final savedMode = await _preferenceStore?.loadThemeMode();

    if (savedMode == null) {
      return;
    }

    _applyThemeMode(savedMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final changed = _applyThemeMode(mode);

    if (!changed) {
      return;
    }

    await _preferenceStore?.saveThemeMode(mode);
  }

  Future<void> setLightMode(bool isLight) {
    return setThemeMode(isLight ? ThemeMode.light : ThemeMode.dark);
  }

  bool _applyThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return false;
    }

    _themeMode = mode;
    AppTheme.applyThemeMode(_themeMode);
    notifyListeners();

    return true;
  }
}
