import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/postdee_time_picker.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('wheel-time-visual-capture');

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'real-font looping time picker ${dark ? 'dark large text' : 'light'}',
        (tester) async {
      final size = dark ? const Size(320, 900) : const Size(430, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousTheme =
          AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
      addTearDown(() => AppTheme.applyThemeMode(previousTheme));
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      await tester.runAsync(() async {
        final font = FontLoader('Anuphan');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          font.addFont(
              rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
        }
        await font.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      TimeOfDay? result;
      await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(dark ? 1.7 : 1)),
            child: child!,
          ),
          home: Scaffold(body: Builder(builder: (context) {
            return Center(
                child: FilledButton(
              onPressed: () async {
                result = await showPostDeeTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 23, minute: 59),
                    date: DateTime(2026, 10, 24));
              },
              child: const Text('เลือกเวลาโพสต์'),
            ));
          })),
        ),
      ));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      for (final key in [
        'postdee-time-hour-picker',
        'postdee-time-minute-picker',
        'postdee-time-summary',
        'postdee-time-cancel',
        'postdee-time-confirm',
      ]) {
        final target = find.byKey(ValueKey(key));
        expect(target, findsOneWidget);
        final bounds = tester.getRect(target);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
      }
      expect(tester.takeException(), isNull);
      if (_captureDirectory.isNotEmpty) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory(_captureDirectory)
              ..createSync(recursive: true);
            await File(
                    '${directory.path}/wheel-${dark ? 'dark-large' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 23, minute: 59));
      expect(tester.takeException(), isNull);
    });
  }
}
