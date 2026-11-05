import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreferenceStore implements PostDeeLanguagePreferenceStore {
  Locale? value;
  bool failRead = false;
  bool failWrite = false;
  Completer<Locale?>? loadGate;
  Completer<void>? firstWriteGate;
  final saved = <Locale>[];

  @override
  Future<Locale?> loadLocale() async {
    if (failRead) throw StateError('Preference read failed');
    return loadGate == null ? value : await loadGate!.future;
  }

  @override
  Future<void> saveLocale(Locale locale) async {
    saved.add(locale);
    if (saved.length == 1) await firstWriteGate?.future;
    if (failWrite) throw StateError('Preference write failed');
    value = locale;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final phoneLanguage in ['th', 'en', 'ja']) {
    test('uses $phoneLanguage phone preferences on first launch', () async {
      final controller = PostDeeLanguageController(
        preferenceStore: const SharedPreferencesLanguagePreferenceStore(),
      );
      addTearDown(controller.dispose);

      await controller.loadSavedLocale(
        preferredLocales: [Locale(phoneLanguage)],
      );

      expect(controller.locale, Locale(phoneLanguage == 'th' ? 'th' : 'en'));
    });
  }

  test('uses English when the phone has no preferred locales', () async {
    final controller = PostDeeLanguageController();
    addTearDown(controller.dispose);

    await controller.loadSavedLocale(preferredLocales: const []);

    expect(controller.locale, const Locale('en'));
  });

  for (final preferredLocales in [
    const [Locale('ja'), Locale('th', 'TH'), Locale('en', 'US')],
    const [Locale('ja'), Locale('en', 'GB'), Locale('th', 'TH')],
  ]) {
    test('uses the first supported regional locale in $preferredLocales',
        () async {
      final controller = PostDeeLanguageController();
      addTearDown(controller.dispose);

      await controller.loadSavedLocale(preferredLocales: preferredLocales);

      expect(controller.locale, Locale(preferredLocales[1].languageCode));
    });
  }

  test('reads the actual phone preferred-language list by default', () async {
    binding.platformDispatcher.localesTestValue = const [
      Locale('ja'),
      Locale('en', 'AU'),
      Locale('th'),
    ];
    addTearDown(binding.platformDispatcher.clearLocalesTestValue);
    final controller = PostDeeLanguageController();
    addTearDown(controller.dispose);

    await controller.loadSavedLocale();

    expect(controller.locale, const Locale('en'));
  });

  for (final savedLanguage in ['th', 'en']) {
    test('saved $savedLanguage choice overrides phone preferences', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesLanguagePreferenceStore.localeKey: savedLanguage,
      });
      final controller = PostDeeLanguageController(
        preferenceStore: const SharedPreferencesLanguagePreferenceStore(),
      );
      addTearDown(controller.dispose);

      await controller.loadSavedLocale(
        preferredLocales: [Locale(savedLanguage == 'th' ? 'en' : 'th')],
      );

      expect(controller.locale, Locale(savedLanguage));
    });
  }

  test('ignores an unsupported saved preference', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesLanguagePreferenceStore.localeKey: 'ja',
    });
    final controller = PostDeeLanguageController(
      preferenceStore: const SharedPreferencesLanguagePreferenceStore(),
    );
    addTearDown(controller.dispose);

    await controller.loadSavedLocale(preferredLocales: const [Locale('th')]);

    expect(controller.locale, const Locale('th'));
  });

  test('saves a normalized choice and restores it on the next launch',
      () async {
    const store = SharedPreferencesLanguagePreferenceStore();
    final controller = PostDeeLanguageController(preferenceStore: store);
    final restarted = PostDeeLanguageController(preferenceStore: store);
    addTearDown(controller.dispose);
    addTearDown(restarted.dispose);

    await controller.setLocale(const Locale('en', 'US'));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SharedPreferencesLanguagePreferenceStore.localeKey),
      'en',
    );
    await restarted.loadSavedLocale(preferredLocales: const [Locale('th')]);

    expect(restarted.locale, const Locale('en'));
  });

  test('explicitly choosing the detected locale still saves the choice',
      () async {
    final store = _PreferenceStore();
    final controller = PostDeeLanguageController(preferenceStore: store);
    addTearDown(controller.dispose);
    await controller.loadSavedLocale(preferredLocales: const [Locale('en')]);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setLocale(const Locale('en'));

    expect(store.saved, const [Locale('en')]);
    expect(notifications, 0);
  });

  test('ignores unsupported choices without saving them', () async {
    final store = _PreferenceStore();
    final controller = PostDeeLanguageController(preferenceStore: store);
    addTearDown(controller.dispose);

    await controller.setLocale(const Locale('ja'));

    expect(controller.locale, const Locale('th'));
    expect(store.saved, isEmpty);
  });

  test('read errors fall back to phone preferences without throwing', () async {
    final controller = PostDeeLanguageController(
      preferenceStore: _PreferenceStore()..failRead = true,
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.loadSavedLocale(preferredLocales: const [Locale('en')]),
      completes,
    );

    expect(controller.locale, const Locale('en'));
  });

  test('malformed stored values cannot block startup', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesLanguagePreferenceStore.localeKey: 42,
    });
    final controller = PostDeeLanguageController(
      preferenceStore: const SharedPreferencesLanguagePreferenceStore(),
    );
    addTearDown(controller.dispose);

    await controller.loadSavedLocale(preferredLocales: const [Locale('en')]);

    expect(controller.locale, const Locale('en'));
  });

  test('write errors do not prevent the immediate language switch', () async {
    final controller = PostDeeLanguageController(
      preferenceStore: _PreferenceStore()..failWrite = true,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final saving = controller.setLocale(const Locale('en'));
    expect(controller.locale, const Locale('en'));
    expect(notifications, 1);
    await expectLater(saving, completes);
  });

  test('rapid choices are saved in order so the last choice wins', () async {
    final gate = Completer<void>();
    final store = _PreferenceStore()..firstWriteGate = gate;
    final controller = PostDeeLanguageController(preferenceStore: store);
    addTearDown(controller.dispose);

    final firstSave = controller.setLocale(const Locale('en'));
    final lastSave = controller.setLocale(const Locale('th'));
    expect(controller.locale, const Locale('th'));
    await Future<void>.delayed(Duration.zero);
    expect(store.saved, const [Locale('en')]);
    gate.complete();
    await Future.wait([firstSave, lastSave]);

    expect(store.saved, const [Locale('en'), Locale('th')]);
    expect(store.value, const Locale('th'));
  });

  test('a late preference load cannot overwrite an explicit selection',
      () async {
    final gate = Completer<Locale?>();
    final store = _PreferenceStore()..loadGate = gate;
    final controller = PostDeeLanguageController(preferenceStore: store);
    addTearDown(controller.dispose);

    final loading = controller.loadSavedLocale(
      preferredLocales: const [Locale('th')],
    );
    await controller.setLocale(const Locale('en'));
    gate.complete(const Locale('th'));
    await loading;

    expect(controller.locale, const Locale('en'));
  });
}
