import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/shared/growth_tool_detail_sheet.dart';
import 'package:postdee_mobile/features/shared/growth_tool_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _detail = GrowthToolDetail(
  id: 'test_tool',
  title: 'เครื่องมือทดสอบ',
  description: 'ตั้งค่าตัวอย่างสำหรับทดสอบการบันทึก',
  status: 'ทดสอบ',
  icon: Icons.auto_awesome,
  color: AppTheme.accent,
  settings: [
    GrowthToolSettingOption(
      id: 'first',
      label: 'ตั้งค่าแรก',
    ),
    GrowthToolSettingOption(
      id: 'second',
      label: 'ตั้งค่าที่สอง',
    ),
  ],
);

const _prototypeDetail = GrowthToolDetail(
  id: 'prototype_tool',
  title: 'เครื่องมือที่กำลังพัฒนา',
  description: 'เลือกตัวเลือกไว้ล่วงหน้าได้',
  status: 'เร็ว ๆ นี้',
  icon: Icons.science_outlined,
  color: AppTheme.accent,
  prototypeOnly: true,
  settings: [
    GrowthToolSettingOption(
      id: 'first',
      label: 'ตั้งค่าแรก',
    ),
  ],
);

Widget _testApp([GrowthToolDetail detail = _detail]) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return Center(
            child: TextButton(
              onPressed: () => showGrowthToolDetailSheet(context, detail),
              child: const Text('เปิดรายละเอียด'),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves growth tool settings locally and reloads them',
      (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.text('เปิดรายละเอียด'));
    await tester.pumpAndSettle();

    expect(find.text('บันทึกการตั้งค่า'), findsOneWidget);
    expect(find.text('ยังไม่เปิดใช้งาน'), findsOneWidget);
    expect(find.byKey(const ValueKey('growth-tool-real-status-note')),
        findsOneWidget);
    expect(find.text('ยังไม่เชื่อมระบบจริง'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('growth-tool-enabled-switch')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('growth-tool-option-test_tool-second')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();

    expect(find.text('บันทึกการตั้งค่าแล้ว'), findsOneWidget);

    await tester.tap(find.text('เปิดรายละเอียด'));
    await tester.pumpAndSettle();

    expect(find.text('เปิดใช้งานแล้ว'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('growth-tool-option-test_tool-first')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('growth-tool-option-test_tool-second')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('prototype tools save a disabled local draft honestly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesGrowthToolSettingsStore.enabledKey('prototype_tool'):
          true,
      SharedPreferencesGrowthToolSettingsStore.enabledOptionsKey(
        'prototype_tool',
      ): ['first'],
    });

    await tester.pumpWidget(_testApp(_prototypeDetail));
    await tester.tap(find.text('เปิดรายละเอียด'));
    await tester.pumpAndSettle();

    expect(find.text('เร็ว ๆ นี้'), findsWidgets);
    expect(find.text('แบบร่างในเครื่อง'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('growth-tool-enabled-switch')),
      findsNothing,
    );
    expect(find.text('บันทึกแบบร่าง'), findsOneWidget);

    await tester.tap(find.text('บันทึกแบบร่าง'));
    await tester.pumpAndSettle();

    expect(
      find.text('บันทึกแบบร่างไว้ในเครื่องแล้ว ยังไม่ได้เปิดใช้งานฟีเจอร์'),
      findsOneWidget,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(
        SharedPreferencesGrowthToolSettingsStore.enabledKey('prototype_tool'),
      ),
      isFalse,
    );
  });
}
