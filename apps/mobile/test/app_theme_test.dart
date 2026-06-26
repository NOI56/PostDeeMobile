import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';

void main() {
  setUp(() {
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  tearDown(() {
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  test('uses a Thai-friendly font stack', () {
    final theme = AppTheme.dark;
    final bodyStyle = theme.textTheme.bodyMedium;

    expect(bodyStyle?.fontFamily, 'Prompt');
    expect(bodyStyle?.fontFamilyFallback, contains('Noto Sans Thai'));
  });

  test('keeps panels on a quiet dark surface', () {
    expect(
      AppTheme.panelGradient.colors,
      const [
        Color(0xFF0E131D),
        Color(0xFF080B12),
      ],
    );
  });

  test('switches shared theme colors to the light palette', () {
    AppTheme.applyThemeMode(ThemeMode.light);

    expect(AppTheme.isLightMode, isTrue);
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.pitchBlack, const Color(0xFFF7F8FC));
    expect(
      AppTheme.panelGradient.colors,
      const [
        Color(0xFFFFFFFF),
        Color(0xFFF3F6FB),
      ],
    );
  });

  test('bundles Prompt font assets for consistent Thai rendering', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('family: Prompt'));
    expect(
      File('assets/fonts/prompt/Prompt-Regular.ttf').existsSync(),
      isTrue,
    );
    expect(File('assets/fonts/prompt/Prompt-Bold.ttf').existsSync(), isTrue);
  });
}
