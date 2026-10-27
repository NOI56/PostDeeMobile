import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/templates/templates_screen.dart';

void main() {
  Future<void> pumpTemplates(
    WidgetTester tester, {
    required TemplateCreator createTemplate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemplatesScreen(
            loadTemplates: () async => const [],
            createTemplate: createTemplate,
          ),
        ),
      ),
    );
  }

  Future<void> saveTemplate(
    WidgetTester tester, {
    required String title,
    required String body,
  }) async {
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), title);
    await tester.enterText(find.bySemanticsLabel('เนื้อหาเทมเพลต'), body);
    await tester.tap(find.text('บันทึกเทมเพลต'));
    await tester.pumpAndSettle();
  }

  final savedTemplate = TextTemplateResult(
    id: 'template-1',
    title: 'ข้อมูลติดต่อ',
    body: 'Line: @postdee',
    createdAt: DateTime.parse('2026-10-27T00:00:00.000Z'),
  );

  Future<void> pumpLoadedTemplates(
    WidgetTester tester, {
    required TemplateDeleter deleteTemplate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemplatesScreen(
            loadTemplates: () async => [savedTemplate],
            createTemplate: ({required body, required title}) =>
                throw StateError('not used'),
            deleteTemplate: deleteTemplate,
          ),
        ),
      ),
    );
    await tester.tap(find.text('โหลดเทมเพลต'));
    await tester.pumpAndSettle();
  }

  Future<void> tapDelete(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('template-delete-template-1'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('deletes a saved template after confirmation', (tester) async {
    final deleted = <String>[];
    await pumpLoadedTemplates(tester, deleteTemplate: (id) async {
      deleted.add(id);
    });

    await tapDelete(tester);
    expect(find.text('ลบเทมเพลตนี้?'), findsOneWidget);
    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();

    expect(deleted, ['template-1']);
    expect(find.text('Line: @postdee'), findsNothing);
  });

  testWidgets('keeps the template when deletion is cancelled', (tester) async {
    final deleted = <String>[];
    await pumpLoadedTemplates(tester, deleteTemplate: (id) async {
      deleted.add(id);
    });

    await tapDelete(tester);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(deleted, isEmpty);
    expect(find.text('Line: @postdee'), findsOneWidget);
  });

  testWidgets('keeps the template and explains a failed deletion',
      (tester) async {
    await pumpLoadedTemplates(
      tester,
      deleteTemplate: (_) async => throw const ApiException('offline'),
    );

    await tapDelete(tester);
    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();

    expect(find.text('Line: @postdee'), findsOneWidget);
    expect(find.text('ลบเทมเพลตไม่สำเร็จ ลองใหม่อีกครั้ง'), findsOneWidget);
  });

  testWidgets('blocks a template body longer than a post caption',
      (tester) async {
    var creates = 0;
    await pumpTemplates(tester, createTemplate: ({required body, required title}) {
      creates++;
      throw StateError('should not be called');
    });

    await saveTemplate(tester, title: 'ยาวเกิน', body: 'ก' * 2201);

    expect(creates, 0);
    expect(
      find.text('เนื้อหาเทมเพลตต้องไม่เกิน 2,200 ตัวอักษร (ตอนนี้ 2,201)'),
      findsOneWidget,
    );
  });

  testWidgets('blocks a template title longer than 80 characters',
      (tester) async {
    var creates = 0;
    await pumpTemplates(tester, createTemplate: ({required body, required title}) {
      creates++;
      throw StateError('should not be called');
    });

    await saveTemplate(tester, title: 'ก' * 81, body: 'ข้อความ');

    expect(creates, 0);
    expect(find.text('ชื่อเทมเพลตต้องไม่เกิน 80 ตัวอักษร'), findsOneWidget);
  });

  testWidgets('explains the saved template limit in Thai', (tester) async {
    await pumpTemplates(
      tester,
      createTemplate: ({required body, required title}) async =>
          throw const ApiException(
        'Each account can save up to 30 templates',
        statusCode: 409,
        code: 'TEMPLATE_LIMIT_REACHED',
      ),
    );

    await saveTemplate(tester, title: 'อันที่ 31', body: 'ข้อความ');

    expect(
      find.text('บันทึกเทมเพลตได้สูงสุด 30 รายการแล้ว ลบอันที่ไม่ใช้ก่อนแล้วลองใหม่'),
      findsOneWidget,
    );
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
