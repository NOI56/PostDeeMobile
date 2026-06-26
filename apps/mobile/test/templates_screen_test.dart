import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/templates/templates_screen.dart';

void main() {
  testWidgets('loads and creates saved templates in the refreshed Thai UI',
      (tester) async {
    final loadCompleter = Completer<List<TextTemplateResult>>();
    final createdTemplates = <Map<String, String>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemplatesScreen(
            loadTemplates: () => loadCompleter.future,
            createTemplate: ({required body, required title}) async {
              createdTemplates.add({
                'title': title,
                'body': body,
              });

              return TextTemplateResult(
                id: 'created-template',
                title: title,
                body: body,
                createdAt: DateTime.parse('2026-06-03T00:00:00.000Z'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('เทมเพลต'), findsOneWidget);
    expect(find.text('จัดการแคปชั่นที่ใช้บ่อย'), findsOneWidget);
    expect(find.text('ชื่อเทมเพลต'), findsOneWidget);
    expect(find.text('เนื้อหาเทมเพลต'), findsOneWidget);
    expect(find.text('ยังไม่มีเทมเพลตที่โหลด'), findsOneWidget);
    expect(find.text('Template title'), findsNothing);
    expect(find.text('Save template'), findsNothing);

    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pump();

    expect(find.text('กำลังโหลดเทมเพลต...'), findsOneWidget);

    loadCompleter.complete([
      TextTemplateResult(
        id: 'template-1',
        title: 'Affiliate disclosure',
        body: 'This post may contain affiliate links.',
        createdAt: DateTime.parse('2026-06-03T00:00:00.000Z'),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Affiliate disclosure'), findsOneWidget);
    expect(find.text('This post may contain affiliate links.'), findsOneWidget);

    await tester.enterText(
        find.bySemanticsLabel('ชื่อเทมเพลต'), 'ข้อมูลติดต่อ');
    await tester.enterText(
        find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'Line: @postdee');
    await tester.tap(find.text('บันทึกเทมเพลต'));
    await tester.pumpAndSettle();

    expect(createdTemplates, [
      {
        'title': 'ข้อมูลติดต่อ',
        'body': 'Line: @postdee',
      }
    ]);
    expect(find.text('ข้อมูลติดต่อ'), findsOneWidget);
    expect(find.text('Line: @postdee'), findsOneWidget);
  });
}
