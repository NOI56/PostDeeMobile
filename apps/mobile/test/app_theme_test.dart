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

    // Anuphan is the handoff design font; Prompt stays bundled as fallback.
    expect(bodyStyle?.fontFamily, 'Anuphan');
    expect(bodyStyle?.fontFamilyFallback, contains('Prompt'));
    expect(bodyStyle?.fontFamilyFallback, contains('Noto Sans Thai'));
  });

  test('uses the Claude quiet dark surfaces', () {
    expect(
      AppTheme.panelGradient.colors,
      const [
        Color(0xFF19221D),
        Color(0xFF212C25),
      ],
    );
  });

  test('switches shared theme colors to the Claude mint palette', () {
    AppTheme.applyThemeMode(ThemeMode.light);

    expect(AppTheme.isLightMode, isTrue);
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.pitchBlack, const Color(0xFFF2F5F2));
    expect(AppTheme.textPrimary, const Color(0xFF15211A));
    expect(AppTheme.navActive, const Color(0xFF0E9F6E));
    expect(
      AppTheme.panelGradient.colors,
      const [
        Color(0xFFFFFFFF),
        Color(0xFFF2F7F3),
      ],
    );
  });

  test('bundles Anuphan font assets for consistent Thai rendering', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('family: Anuphan'));
    expect(
      File('assets/fonts/anuphan/Anuphan-Regular.ttf').existsSync(),
      isTrue,
    );
    expect(File('assets/fonts/anuphan/Anuphan-Bold.ttf').existsSync(), isTrue);
  });

  test('bundles the Thai mark-safe Bai Jamjuree font and its license', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('family: Bai Jamjuree'));
    expect(
      File('assets/fonts/baijamjuree/BaiJamjuree-Bold.ttf').existsSync(),
      isTrue,
    );
    expect(File('assets/fonts/baijamjuree/OFL.txt').existsSync(), isTrue);
    expect(pubspec, contains('family: PostDee Subtitle Thai'));
    expect(pubspec, contains('family: PostDee Subtitle Anuphan'));
    expect(pubspec, contains('family: PostDee Subtitle Prompt'));
    for (final asset in [
      'PostDeeSubtitleThai-Bold.ttf',
      'PostDeeSubtitleAnuphan-Regular.ttf',
      'PostDeeSubtitleAnuphan-Medium.ttf',
      'PostDeeSubtitleAnuphan-SemiBold.ttf',
      'PostDeeSubtitleAnuphan-Bold.ttf',
      'PostDeeSubtitlePrompt-Regular.ttf',
      'PostDeeSubtitlePrompt-Medium.ttf',
      'PostDeeSubtitlePrompt-SemiBold.ttf',
      'PostDeeSubtitlePrompt-Bold.ttf',
      'PostDeeSubtitlePrompt-ExtraBold.ttf',
      'PostDeeSubtitlePrompt-Black.ttf',
    ]) {
      expect(
        File('assets/fonts/postdee_subtitle/$asset').existsSync(),
        isTrue,
        reason: '$asset must be bundled for mark-safe subtitle rendering',
      );
      expect(pubspec, contains('assets/fonts/postdee_subtitle/$asset'));
    }
    expect(File('assets/fonts/postdee_subtitle/OFL.txt').existsSync(), isTrue);
  });
}
