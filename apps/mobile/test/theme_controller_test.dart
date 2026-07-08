import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  tearDown(() {
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  test('defaults to the Claude light theme when no preference exists', () {
    final controller = PostDeeThemeController(
      preferenceStore: const SharedPreferencesThemePreferenceStore(),
    );
    addTearDown(controller.dispose);

    expect(controller.themeMode, ThemeMode.light);
    expect(AppTheme.isLightMode, isTrue);
  });
  test('loads a saved light theme from local preferences', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesThemePreferenceStore.themeModeKey: 'light',
    });
    final controller = PostDeeThemeController(
      preferenceStore: const SharedPreferencesThemePreferenceStore(),
    );
    addTearDown(controller.dispose);

    await controller.loadSavedThemeMode();

    expect(controller.themeMode, ThemeMode.light);
    expect(AppTheme.isLightMode, isTrue);
  });

  test('saves the selected theme mode to local preferences', () async {
    final controller = PostDeeThemeController(
      preferenceStore: const SharedPreferencesThemePreferenceStore(),
    );
    addTearDown(controller.dispose);

    await controller.setThemeMode(ThemeMode.dark);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        SharedPreferencesThemePreferenceStore.themeModeKey,
      ),
      'dark',
    );
  });
}
