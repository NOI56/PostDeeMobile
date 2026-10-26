import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/templates/templates_screen.dart';

void main() {
  testWidgets('keeps newly typed text when an older save completes',
      (tester) async {
    final saved = Completer<TextTemplateResult>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TemplatesScreen(
      loadTemplates: () async => [],
      createTemplate: ({required title, required body}) => saved.future,
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่างแรก');
    await tester.enterText(
        find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความแรก');
    await tester.tap(find.text('บันทึกเทมเพลต'));
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่างถัดไป');
    await tester.enterText(
        find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความใหม่');
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'รีเฟรชเทมเพลต'))
            .onPressed,
        isNull);
    saved.complete(TextTemplateResult(
        id: 'first',
        title: 'ร่างแรก',
        body: 'ข้อความแรก',
        createdAt: DateTime.utc(2026, 10, 9)));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'ร่างถัดไป');
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'ข้อความใหม่');
    expect(find.text('ข้อความแรก'), findsOneWidget);
  });

  testWidgets('cannot create while an older list load is unfinished',
      (tester) async {
    final loaded = Completer<List<TextTemplateResult>>();
    var creates = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TemplatesScreen(
      loadTemplates: () => loaded.future,
      createTemplate: ({required title, required body}) async {
        creates++;
        return TextTemplateResult(
            id: 'new',
            title: title,
            body: body,
            createdAt: DateTime.utc(2026, 10, 9));
      },
    ))));
    await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่าง');
    await tester.enterText(find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความ');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'บันทึกเทมเพลต'))
            .onPressed,
        isNull);
    expect(creates, 0);
    loaded.complete([]);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
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
    expect(find.text('ยังไม่มีเทมเพลตที่บันทึกไว้'), findsNothing);
    expect(find.text('Template title'), findsNothing);
    expect(find.text('Save template'), findsNothing);

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

  testWidgets(
      'loads on entry and refreshes an existing list without losing a draft',
      (tester) async {
    var loads = 0;
    await _openTemplates(tester, loadTemplates: () async {
      loads++;
      return [_template('saved', 'แคปชั่นที่บันทึกไว้')];
    });
    expect(loads, 1);
    expect(find.text('แคปชั่นที่บันทึกไว้'), findsOneWidget);
    await _enterDraft(tester);
    await tester.tap(find.text('รีเฟรชเทมเพลต'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(_title(tester), 'ร่าง');
    expect(_body(tester), 'ข้อความร่าง');
  });

  testWidgets(
      'offers a retry instead of an empty list after an initial failure',
      (tester) async {
    var loads = 0;
    await _openTemplates(tester, loadTemplates: () async {
      if (loads++ == 0) throw StateError('network');
      return [_template('saved', 'โหลดได้แล้ว')];
    });
    expect(
        find.text('โหลดเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.text('ยังไม่มีเทมเพลตที่บันทึกไว้'), findsNothing);
    await tester.tap(find.text('รีเฟรชเทมเพลต'));
    await tester.pumpAndSettle();
    expect(find.text('โหลดได้แล้ว'), findsOneWidget);
    expect(
        find.text('โหลดเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'), findsNothing);
  });

  for (final back in ['system', 'app-bar']) {
    testWidgets('$back back lets the seller keep or explicitly discard a draft',
        (tester) async {
      await _openTemplates(tester);
      await _enterDraft(tester);
      await _back(tester, back);
      expect(find.text('ยังไม่ได้บันทึกเทมเพลต'), findsOneWidget);
      await tester.tap(find.text('แก้ต่อ'));
      await tester.pumpAndSettle();
      expect(_title(tester), 'ร่าง');
      expect(_body(tester), 'ข้อความร่าง');
      await _back(tester, back);
      await tester.tap(find.text('ออกโดยไม่บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('เปิดเทมเพลต'), findsOneWidget);
      expect(find.byType(TemplatesScreen), findsNothing);
    });
  }

  testWidgets('saves a draft before leaving and does not ask again when clean',
      (tester) async {
    final creates = <String>[];
    await _openTemplates(tester,
        createTemplate: ({required title, required body}) async {
      creates.add('$title:$body');
      return _template('saved', title, body);
    });
    await _enterDraft(tester);
    await _back(tester, 'app-bar');
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();
    expect(creates, ['ร่าง:ข้อความร่าง']);
    expect(find.byType(TemplatesScreen), findsNothing);
    await tester.tap(find.text('เปิดเทมเพลต'));
    await tester.pumpAndSettle();
    await _back(tester, 'system');
    expect(find.text('ยังไม่ได้บันทึกเทมเพลต'), findsNothing);
    expect(find.byType(TemplatesScreen), findsNothing);
  });

  testWidgets('failed save on exit keeps the draft and the route open',
      (tester) async {
    await _openTemplates(tester,
        createTemplate: ({required title, required body}) async {
      throw StateError('private technical error');
    });
    await _enterDraft(tester);
    await _back(tester, 'system');
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsOneWidget);
    expect(_title(tester), 'ร่าง');
    expect(_body(tester), 'ข้อความร่าง');
    expect(find.text('บันทึกเทมเพลตไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'),
        findsOneWidget);
    expect(find.textContaining('private technical'), findsNothing);
  });

  testWidgets('incomplete draft cannot be silently lost by save and exit',
      (tester) async {
    var creates = 0;
    await _openTemplates(tester,
        createTemplate: ({required title, required body}) async {
      creates++;
      return _template('saved', title, body);
    });
    await tester.enterText(
        find.bySemanticsLabel('ชื่อเทมเพลต'), 'ยังพิมพ์ไม่ครบ');
    await _back(tester, 'system');
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();
    expect(creates, 0);
    expect(_title(tester), 'ยังพิมพ์ไม่ครบ');
    expect(find.text('กรอกชื่อและเนื้อหาเทมเพลตก่อนบันทึก'), findsOneWidget);
  });

  testWidgets('a newer draft typed during save and exit remains open',
      (tester) async {
    final saved = Completer<TextTemplateResult>();
    await _openTemplates(tester,
        createTemplate: ({required title, required body}) => saved.future);
    await _enterDraft(tester);
    await _back(tester, 'system');
    await tester.tap(find.text('บันทึกแล้วออก'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ร่างถัดไป');
    await _back(tester, 'app-bar');
    expect(find.text('ยังไม่ได้บันทึกเทมเพลต'), findsNothing);
    saved.complete(_template('saved', 'ร่าง', 'ข้อความร่าง'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsOneWidget);
    expect(_body(tester), 'ร่างถัดไป');
  });

  for (final transition in [
    'sign-out',
    'different-owner',
    'fresh-same-owner'
  ]) {
    testWidgets('late template load is ignored after $transition',
        (tester) async {
      final sessions = PostDeeAuthSessionStore.instance;
      sessions.signIn(const AuthSession(userId: 'seller-a', idToken: 'a'));
      addTearDown(sessions.clear);
      final loaded = Completer<List<TextTemplateResult>>();
      await _openTemplates(tester, loadTemplates: () => loaded.future);
      await _enterDraft(tester);
      if (transition == 'sign-out') {
        sessions.clear();
      } else {
        sessions.signIn(AuthSession(
            userId: transition == 'different-owner' ? 'seller-b' : 'seller-a',
            idToken: 'new'));
      }
      loaded.complete([_template('private', 'ข้อมูลบัญชีเดิม')]);
      await tester.pumpAndSettle();
      expect(find.text('ข้อมูลบัญชีเดิม'), findsNothing);
      expect(_title(tester), isEmpty);
      expect(_body(tester), isEmpty);
      expect(find.text('บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าเทมเพลตใหม่'),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'บันทึกเทมเพลต'))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'account change clears loaded templates and closes only its draft dialog',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(userId: 'seller-a', idToken: 'a'));
    addTearDown(sessions.clear);
    await _openTemplates(tester,
        loadTemplates: () async => [_template('private', 'ข้อมูลบัญชีเดิม')]);
    await _enterDraft(tester);
    await _back(tester, 'app-bar');
    sessions.signIn(const AuthSession(userId: 'seller-b', idToken: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้บันทึกเทมเพลต'), findsNothing);
    expect(find.text('ข้อมูลบัญชีเดิม'), findsNothing);
    expect(_title(tester), isEmpty);
    await _back(tester, 'system');
    expect(find.text('เปิดเทมเพลต'), findsOneWidget);
  });

  testWidgets(
      'late save cannot insert an old account template after account change',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(userId: 'seller-a', idToken: 'a'));
    addTearDown(sessions.clear);
    final saved = Completer<TextTemplateResult>();
    await _openTemplates(tester,
        createTemplate: ({required title, required body}) => saved.future);
    await _enterDraft(tester);
    await tester.tap(find.text('บันทึกเทมเพลต'));
    await tester.pump();
    sessions.signIn(const AuthSession(userId: 'seller-b', idToken: 'b'));
    saved.complete(_template('private', 'ข้อมูลบัญชีเดิม'));
    await tester.pumpAndSettle();
    expect(find.text('ข้อมูลบัญชีเดิม'), findsNothing);
    expect(_title(tester), isEmpty);
    expect(_body(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account change dismisses its draft dialog without popping a newer route',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.signIn(const AuthSession(userId: 'seller-a', idToken: 'a'));
    addTearDown(sessions.clear);
    await _openTemplates(tester);
    await _enterDraft(tester);
    await _back(tester, 'app-bar');
    unawaited(showDialog<void>(
      context: tester.element(find.byType(AlertDialog)),
      builder: (_) => const AlertDialog(title: Text('หน้าต่างอื่น')),
    ));
    await tester.pumpAndSettle();
    sessions.signIn(const AuthSession(userId: 'seller-b', idToken: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('หน้าต่างอื่น'), findsOneWidget);
    expect(
        find.text('ยังไม่ได้บันทึกเทมเพลต', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late load failure after leaving does not update the disposed screen',
      (tester) async {
    final loaded = Completer<List<TextTemplateResult>>();
    await _openTemplates(tester, loadTemplates: () => loaded.future);
    await _back(tester, 'system');
    loaded.completeError(StateError('late network failure'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

TextTemplateResult _template(String id, String title,
        [String body = 'ข้อความที่บันทึก']) =>
    TextTemplateResult(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime.utc(2026, 10, 26));

Future<void> _openTemplates(
  WidgetTester tester, {
  TemplateLoader? loadTemplates,
  TemplateCreator? createTemplate,
}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: Center(
                    child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                        appBar: AppBar(
                                            title: const Text('จัดการเทมเพลต')),
                                        body: TemplatesScreen(
                                            loadTemplates:
                                                loadTemplates ?? () async => [],
                                            createTemplate: createTemplate),
                                      )),
                            ),
                        child: const Text('เปิดเทมเพลต'))),
              ))));
  await tester.tap(find.text('เปิดเทมเพลต'));
  await tester.pumpAndSettle();
}

Future<void> _enterDraft(WidgetTester tester) async {
  await tester.enterText(find.bySemanticsLabel('ชื่อเทมเพลต'), 'ร่าง');
  await tester.enterText(
      find.bySemanticsLabel('เนื้อหาเทมเพลต'), 'ข้อความร่าง');
}

Future<void> _back(WidgetTester tester, String source) async {
  await tester.pump();
  if (source == 'system') {
    await tester.binding.handlePopRoute();
  } else {
    await tester.tap(find.byType(BackButton));
  }
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

String _body(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;
