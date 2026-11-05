import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'postdee_localizations.dart';

abstract class PostDeeLanguagePreferenceStore {
  Future<Locale?> loadLocale();

  Future<void> saveLocale(Locale locale);
}

class SharedPreferencesLanguagePreferenceStore
    implements PostDeeLanguagePreferenceStore {
  const SharedPreferencesLanguagePreferenceStore(
      {SharedPreferences? preferences})
      : _preferences = preferences;

  static const localeKey = 'postdee_language';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<Locale?> loadLocale() async {
    final preferences = await _activePreferences;

    return switch (preferences.getString(localeKey)) {
      'th' => const Locale('th'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  @override
  Future<void> saveLocale(Locale locale) async {
    final preferences = await _activePreferences;

    await preferences.setString(localeKey, locale.languageCode);
  }
}

class PostDeeLanguageController extends ChangeNotifier {
  PostDeeLanguageController({
    Locale? initialLocale,
    PostDeeLanguagePreferenceStore? preferenceStore,
  })  : _locale = _normalizeLocale(initialLocale) ?? const Locale('th'),
        _preferenceStore = preferenceStore;

  static final instance = PostDeeLanguageController(
    preferenceStore: const SharedPreferencesLanguagePreferenceStore(),
  );

  Locale? _locale;
  final PostDeeLanguagePreferenceStore? _preferenceStore;
  Future<void> _pendingSave = Future<void>.value();
  var _selectionVersion = 0;

  Locale? get locale => _locale;

  Future<void> loadSavedLocale({List<Locale>? preferredLocales}) async {
    final selectionVersion = _selectionVersion;
    Locale? savedLocale;
    try {
      savedLocale = await _preferenceStore?.loadLocale();
    } catch (_) {
      // Local preference failures must never prevent the app from opening.
    }

    if (_selectionVersion != selectionVersion) return;

    final locales =
        preferredLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
    final nextLocale = _normalizeLocale(savedLocale) ??
        locales.map(_normalizeLocale).whereType<Locale>().firstOrNull ??
        const Locale('en');
    _applyLocale(nextLocale);
  }

  Future<void> setLocale(Locale locale) {
    final nextLocale = _normalizeLocale(locale);

    if (nextLocale == null) {
      return Future<void>.value();
    }

    _selectionVersion++;
    _applyLocale(nextLocale);
    // Persist an explicit choice even when it matches the detected language.
    // Serialize writes so a slower earlier save cannot win a rapid switch.
    _pendingSave = _pendingSave.then((_) async {
      try {
        await _preferenceStore?.saveLocale(nextLocale);
      } catch (_) {
        // Keep the selected language usable if local storage is unavailable.
      }
    });
    return _pendingSave;
  }

  void _applyLocale(Locale nextLocale) {
    if (nextLocale == _locale) return;

    _locale = nextLocale;
    notifyListeners();
  }

  bool isSelected(Locale locale) {
    return _locale?.languageCode == locale.languageCode;
  }

  static Locale? _normalizeLocale(Locale? locale) {
    if (locale == null) {
      return null;
    }

    return switch (locale.languageCode) {
      'th' => const Locale('th'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  static bool isSupported(Locale locale) {
    return PostDeeLocalizations.supportedLocales.any(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
    );
  }
}
