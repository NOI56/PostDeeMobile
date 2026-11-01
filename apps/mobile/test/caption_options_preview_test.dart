import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/platform_caption_fields.dart';

const _captureDirectory = String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR');
const _captureKey = ValueKey('caption-options-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final language in ['th', 'en']) {
    for (final dark in [false, true]) {
      testWidgets('$language shared choices fit narrow large-text ${dark ? 'dark' : 'light'} screens',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        addTearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
        await tester.runAsync(() async {
          final fonts = FontLoader('Anuphan');
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
            fonts.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
          }
          await fonts.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        });
        String? selected;
        await tester.pumpWidget(RepaintBoundary(key: _captureKey, child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          locale: Locale(language),
          supportedLocales: PostDeeLocalizations.supportedLocales,
          localizationsDelegates: const [
            PostDeeLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(builder: (context) => Scaffold(body: FilledButton(
            onPressed: () async {
              selected = await showModalBottomSheet<String>(
                context: context, isScrollControlled: true, useSafeArea: true,
                builder: (_) => const CaptionOptionsPreviewSheet(
                  captions: ['สินค้าจริงในคลิป อ่านรายละเอียดก่อนสั่งซื้อ', 'another user caption', 'ตัวเลือกยาวสำหรับทดสอบการแสดงผลบนหน้าจอเล็ก'],
                ),
              );
            },
            child: const Text('open'),
          ))),
        )));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text(language == 'en' ? 'Choose a caption' : 'เลือกแคปชั่นที่ชอบ'), findsOneWidget);
        final option = find.byKey(const ValueKey('uploader-shared-ai-option-1'));
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        await _capture(tester, dark ? 'ui-dark' : 'ui-light');
        final apply = find.byKey(const ValueKey('uploader-shared-ai-apply'));
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(selected, 'another user caption');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
