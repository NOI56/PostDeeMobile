import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/platforms/social_platform_logo.dart';
import 'package:postdee_mobile/features/uploader/platform_settings_scaffold.dart';

void main() {
  Future<void> open(WidgetTester tester,
      {required Widget content,
      VoidCallback? onSave,
      String? validationMessage,
      double keyboard = 0,
      double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => PlatformSettingsScaffold(
                            platform: SocialPlatform.tiktok,
                            displayName: 'บัญชีทดสอบ',
                            onSave: onSave,
                            validationMessage: validationMessage,
                            child: content)),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'short settings shrink to content with shared identity and cancel',
      (tester) async {
    await open(tester, content: const Text('ส่งเป็นร่าง'), onSave: () {});
    expect(
        tester
            .getSize(
                find.byKey(const ValueKey('uploader-platform-settings-sheet')))
            .height,
        lessThan(400));
    expect(find.byType(SocialPlatformLogo), findsOneWidget);
    expect(find.text('บัญชีทดสอบ'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('uploader-platform-settings-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uploader-platform-settings-sheet')),
        findsNothing);
  });

  testWidgets(
      'long settings scroll above visible footer with keyboard and large text',
      (tester) async {
    var saved = false;
    await open(tester,
        keyboard: 220,
        textScale: 1.5,
        onSave: () => saved = true,
        content: Column(
            children: List.generate(
                20,
                (index) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('ตัวเลือก $index')))));
    expect(tester.takeException(), isNull);
    final save = find.byKey(const ValueKey('uploader-platform-settings-save'));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(420));
    await tester.tap(save);
    expect(saved, isTrue);
    await tester.drag(find.byKey(const ValueKey('platform-settings-scroll')),
        const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('ตัวเลือก 19').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled save keeps validation explanation visible',
      (tester) async {
    await open(tester,
        content: const Text('ตัวเลือก'),
        validationMessage: 'เลือกผู้ชมก่อนบันทึก');
    expect(find.text('เลือกผู้ชมก่อนบันทึก'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('uploader-platform-settings-save')))
            .onPressed,
        isNull);
  });
}
