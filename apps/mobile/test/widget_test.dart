import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/app.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/splash/postdee_splash_screen.dart';

void main() {
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('renders PostDee app smoke test', (tester) async {
    _signInForShell();

    await tester.pumpWidget(const PostDeeApp());
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('postdee-reference-bottom-nav')),
      findsOneWidget,
    );
  });

  testWidgets('uses dark theme mode when requested', (tester) async {
    _signInForShell();
    final themeController = PostDeeThemeController(
      initialMode: ThemeMode.dark,
    );
    addTearDown(themeController.dispose);

    await tester.pumpWidget(PostDeeApp(themeController: themeController));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(AppTheme.isLightMode, isFalse);
  });

  testWidgets('uses light theme mode when requested', (tester) async {
    _signInForShell();
    final themeController = PostDeeThemeController(
      initialMode: ThemeMode.light,
    );
    addTearDown(themeController.dispose);

    await tester.pumpWidget(PostDeeApp(themeController: themeController));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(AppTheme.isLightMode, isTrue);
  });

  test('keeps dark and light logo image canvases the same size', () {
    final lightLogoSize = _pngSize(
      File('assets/images/brand/postdee_logo.png').readAsBytesSync(),
    );
    final darkLogoSize = _pngSize(
      File('assets/images/brand/postdee_logo_dark.png').readAsBytesSync(),
    );

    expect(darkLogoSize, lightLogoSize);
  });

  testWidgets('uses the current PostDee brand mark on the splash screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PostDeeSplashGate(
          minimumDuration: Duration(minutes: 1),
          child: SizedBox.shrink(),
        ),
      ),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('postdee-splash-mark')),
    );

    expect(
      (image.image as AssetImage).assetName,
      'assets/images/brand/postdee_mark.png',
    );
  });
}

void _signInForShell() {
  PostDeeAuthSessionStore.instance.signIn(
    const AuthSession(
      idToken: 'firebase-id-token',
      email: 'seller@example.com',
      displayName: 'PostDee Seller',
    ),
  );
}

Size _pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  return Size(
    data.getUint32(16).toDouble(),
    data.getUint32(20).toDouble(),
  );
}
