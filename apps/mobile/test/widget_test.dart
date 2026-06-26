import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/app.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';

void main() {
  tearDown(() {
    AppTheme.applyThemeMode(ThemeMode.dark);
  });

  testWidgets('renders PostDee app smoke test', (tester) async {
    await tester.pumpWidget(const PostDeeApp());

    expect(find.bySemanticsLabel('PostDee logo'), findsOneWidget);
  });

  testWidgets('uses the dark logo asset in dark mode', (tester) async {
    final themeController = PostDeeThemeController();
    addTearDown(themeController.dispose);

    await tester.pumpWidget(PostDeeApp(themeController: themeController));

    expect(
      _postDeeLogoAssetName(tester),
      'assets/images/brand/postdee_logo_dark.png',
    );
  });

  testWidgets('uses the original logo asset in light mode', (tester) async {
    final themeController = PostDeeThemeController(
      initialMode: ThemeMode.light,
    );
    addTearDown(themeController.dispose);

    await tester.pumpWidget(PostDeeApp(themeController: themeController));

    expect(
      _postDeeLogoAssetName(tester),
      'assets/images/brand/postdee_logo.png',
    );
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
}

String _postDeeLogoAssetName(WidgetTester tester) {
  final logo = find.bySemanticsLabel('PostDee logo');
  final image = tester.widget<Image>(
    find.descendant(of: logo, matching: find.byType(Image)).first,
  );
  final assetImage = image.image as AssetImage;

  return assetImage.assetName;
}

Size _pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  return Size(
    data.getUint32(16).toDouble(),
    data.getUint32(20).toDouble(),
  );
}
