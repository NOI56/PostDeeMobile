import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/templates/templates_screen.dart';

void main() {
  testWidgets('keeps newly typed text when an older save completes',
      (tester) async {
    final saved = Completer<TextTemplateResult>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplatesScreen(
      createTemplate: ({required title, required body}) => saved.future,
    ))));
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่างแรก');
    await tester.enterText(find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความแรก');
    await tester.tap(find.text('บันทึกเทมเพลต'));
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่างถัดไป');
    await tester.enterText(find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความใหม่');
    expect(tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'โหลดเทมเพลต')).onPressed, isNull);
    saved.complete(TextTemplateResult(id: 'first', title: 'ร่างแรก',
      body: 'ข้อความแรก', createdAt: DateTime.utc(2026, 10, 9)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'ร่างถัดไป');
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'ข้อความใหม่');
    expect(find.text('ข้อความแรก'), findsOneWidget);
  });

  testWidgets('cannot create while an older list load is unfinished',
      (tester) async {
    final loaded = Completer<List<TextTemplateResult>>();
    var creates = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplatesScreen(
      loadTemplates: () => loaded.future,
      createTemplate: ({required title, required body}) async {
        creates++;
        return TextTemplateResult(id: 'new', title: title, body: body,
          createdAt: DateTime.utc(2026, 10, 9));
      },
    ))));
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่าง');
    await tester.enterText(find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความ');
    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pump();
    expect(tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'บันทึกเทมเพลต')).onPressed, isNull);
    expect(creates, 0);
    loaded.complete([]);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'ร่าง');
  });

  testWidgets(
      'does not expose a technical network error when loading templates',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TemplatesScreen(
      loadTemplates: () async =>
          throw StateError('private-host technical failure'),
    ))));
    await tester.ensureVisible(find.text('โหลดเทมเพลต'));
    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pumpAndSettle();
    expect(
        find.text('โหลดเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.textContaining('private-host'), findsNothing);
    expect(find.textContaining('Unexpected error'), findsNothing);
  });

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
