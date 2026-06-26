import 'package:flutter/material.dart';

import 'postdee_localizations.dart';

class PostDeeLanguageController extends ChangeNotifier {
  PostDeeLanguageController({Locale? initialLocale})
      : _locale = _normalizeLocale(initialLocale) ?? const Locale('th');

  static final instance = PostDeeLanguageController();

  Locale? _locale;

  Locale? get locale => _locale;

  void setLocale(Locale locale) {
    final nextLocale = _normalizeLocale(locale);

    if (nextLocale == null || nextLocale == _locale) {
      return;
    }

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
