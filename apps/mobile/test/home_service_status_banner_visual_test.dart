import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/home/home_service_status_banner.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('home-service-status-visual-capture');

Future<void> _capture(WidgetTester tester, String fileName) async {
  expect(tester.takeException(), isNull);
  if (_captureDirectory.isEmpty) return;
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/$fileName.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'real-font service notices in ${dark ? 'dark narrow large-text' : 'light'} Home width',
        (tester) async {
      tester.view.physicalSize =
          dark ? const Size(320, 700) : const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousTheme =
          AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
      addTearDown(() => AppTheme.applyThemeMode(previousTheme));
      AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      await tester.runAsync(() async {
        final fonts = FontLoader('Anuphan');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(
              rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
        }
        await fonts.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        locale: const Locale('th'),
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(dark ? 1.7 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: _captureKey,
              child: ColoredBox(
                color: AppTheme.ink,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: HomeServiceStatusBanner(
                    isActive: true,
                    now: () => DateTime(2026, 10, 28, 15),
                    loadStatus: () async => [
                      ServiceIncidentResult(
                        id: 'tiktok',
                        title: 'TikTok ส่งคลิปช้ากว่าปกติ',
                        message:
                            'ทีมงานพบสาเหตุแล้วและกำลังแก้ไข\nโพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำ',
                        platforms: const ['TIKTOK', 'INSTAGRAM_REELS'],
                        stage: 'IDENTIFIED',
                        updatedAt: DateTime(2026, 10, 28, 14, 5),
                      ),
                      ServiceIncidentResult(
                        id: 'login',
                        title: 'เข้าสู่ระบบช้าในบางเครือข่าย',
                        message: 'แก้ไขแล้ว กำลังติดตามผลอีกสักระยะ',
                        platforms: const [],
                        stage: 'MONITORING',
                        updatedAt: DateTime(2026, 10, 27, 22, 40),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('TikTok ส่งคลิปช้ากว่าปกติ'), findsOneWidget);
      expect(find.text('ทั้งแอป · อัปเดต 27/10 22:40 น.'), findsOneWidget);
      await _capture(
          tester, 'home-service-status-${dark ? 'dark-large' : 'light'}');
    });
  }
}
