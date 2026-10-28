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
import 'package:postdee_mobile/features/support/support_chat_screen.dart';

const _captureDirectory =
    String.fromEnvironment('POSTDEE_UI_CAPTURE_DIR', defaultValue: '');
const _captureKey = ValueKey('support-chat-visual-capture');

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
        'real-font support chat in ${dark ? 'dark narrow large-text' : 'light'} phone width',
        (tester) async {
      tester.view.physicalSize =
          dark ? const Size(320, 760) : const Size(400, 820);
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

      final messages = [
        SupportMessageResult(
            id: 'm1',
            sender: 'MEMBER',
            body: 'โพสต์ลง TikTok เมื่อเช้าขึ้นว่าส่งไม่สำเร็จ ต้องทำยังไงครับ',
            createdAt: DateTime(2026, 10, 28, 9, 12)),
        SupportMessageResult(
            id: 'm2',
            sender: 'TEAM',
            body:
                'สวัสดีครับ ตอนนี้ TikTok ขัดข้องชั่วคราว\nโพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำครับ',
            createdAt: DateTime(2026, 10, 28, 9, 20)),
        SupportMessageResult(
            id: 'm3',
            sender: 'BOT',
            body: 'ถ้าคลิปขึ้นว่าส่งไม่สำเร็จ ลองตรวจบน TikTok ก่อนส่งซ้ำนะคะ จะได้ไม่โพสต์ซ้ำ',
            createdAt: DateTime(2026, 10, 28, 9, 21)),
      ];
      await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
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
                .copyWith(textScaler: TextScaler.linear(dark ? 1.5 : 1)),
            child: child!,
          ),
          home: SupportChatScreen(
            now: () => DateTime(2026, 10, 28, 15),
            loadChat: ({String? after}) async =>
                SupportChatResult(
                    messages: after == null ? messages : const [], cursor: '3', botAvailable: true),
            sendMessage: ({required String id, required String body}) async =>
                throw const ApiException('offline', statusCode: 503),
            loadServiceStatus: () async => [
              ServiceIncidentResult(
                id: 'tiktok',
                title: 'TikTok ส่งคลิปช้ากว่าปกติ',
                message: 'โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ',
                platforms: const ['TIKTOK'],
                stage: 'IDENTIFIED',
                updatedAt: DateTime(2026, 10, 28, 9, 5),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('support-chat-input')), 'ตอนนี้ลองใหม่ได้ยังครับ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('support-chat-send')));
      await tester.pumpAndSettle();
      expect(find.text('ส่งไม่สำเร็จ · แตะเพื่อส่งอีกครั้ง'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _capture(tester, 'support-chat-${dark ? 'dark-large' : 'light'}');
    });
  }
}
