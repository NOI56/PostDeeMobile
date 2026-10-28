import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/support/support_chat_screen.dart';

class _FakeChat {
  final messages = <SupportMessageResult>[];
  final loadCursors = <String?>[];
  final sentIds = <String>[];
  Object? loadError;
  Object? sendError;
  var failSends = 0;
  var _minute = 0;

  SupportMessageResult message(String sender, String body, {String? id}) {
    final result = SupportMessageResult(
      id: id ?? 'server-${messages.length}',
      sender: sender,
      body: body,
      createdAt: DateTime(2026, 10, 28, 14, _minute++),
    );
    messages.add(result);
    return result;
  }

  Future<SupportChatResult> load({String? after}) async {
    loadCursors.add(after);
    if (loadError != null) throw loadError!;
    final start = after == null ? 0 : int.parse(after);
    return SupportChatResult(
      messages: messages.sublist(start),
      cursor: '${messages.length}',
      threadStatus: messages.isEmpty ? null : 'WAITING_TEAM',
    );
  }

  Future<SupportMessageResult> send(
      {required String id, required String body}) async {
    sentIds.add(id);
    if (failSends > 0) {
      failSends--;
      throw sendError ?? const ApiException('offline', statusCode: 503);
    }
    final existing = messages.where((m) => m.id == id);
    return existing.isNotEmpty ? existing.first : message('MEMBER', body, id: id);
  }
}

Widget _app(_FakeChat chat, {Duration poll = const Duration(seconds: 5)}) {
  var next = 0;
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('th'),
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: SupportChatScreen(
      loadChat: chat.load,
      sendMessage: chat.send,
      loadServiceStatus: () async => const [],
      pollInterval: poll,
      newMessageId: () => 'client-${next++}',
      now: () => DateTime(2026, 10, 28, 15),
    ),
  );
}

void main() {
  test('newSupportMessageId makes random version-4 UUIDs', () {
    final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final first = newSupportMessageId();
    expect(first, matches(pattern));
    expect(newSupportMessageId(), isNot(first));
  });

  testWidgets('shows the conversation with team replies labeled',
      (tester) async {
    final chat = _FakeChat()
      ..message('MEMBER', 'โพสต์ TikTok ไม่ขึ้น')
      ..message('TEAM', 'ทีมงานกำลังตรวจสอบให้');
    await tester.pumpWidget(_app(chat));
    await tester.pumpAndSettle();

    expect(find.text('แชทกับทีมงาน'), findsOneWidget);
    expect(find.text('โพสต์ TikTok ไม่ขึ้น'), findsOneWidget);
    expect(find.text('ทีมงานกำลังตรวจสอบให้'), findsOneWidget);
    expect(find.text('ทีมงาน PostDee'), findsOneWidget);
    expect(find.text('14:01 น.'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-chat-empty')), findsNothing);
  });

  testWidgets('sends with one id and retries that same id after a failure',
      (tester) async {
    final chat = _FakeChat()..failSends = 1;
    await tester.pumpWidget(_app(chat));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-chat-empty')), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('support-chat-send')))
            .onPressed,
        isNull);

    await tester.enterText(
        find.byKey(const ValueKey('support-chat-input')), '  ช่วยดูโพสต์ให้หน่อย  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('ส่งไม่สำเร็จ · แตะเพื่อส่งอีกครั้ง'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-chat-send-error')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('support-chat-input'))).controller!.text, isEmpty);

    await tester.tap(find.text('ช่วยดูโพสต์ให้หน่อย'));
    await tester.pumpAndSettle();
    expect(chat.sentIds, ['client-0', 'client-0']);
    expect(find.text('ส่งไม่สำเร็จ · แตะเพื่อส่งอีกครั้ง'), findsNothing);
    expect(find.byKey(const ValueKey('support-message-client-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-chat-send-error')), findsNothing);
  });

  testWidgets('a failed message can be removed instead of retried',
      (tester) async {
    final chat = _FakeChat()..failSends = 1;
    await tester.pumpWidget(_app(chat));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('support-chat-input')), 'ส่งไม่ออก');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ลบข้อความนี้'));
    await tester.pumpAndSettle();
    expect(find.text('ส่งไม่ออก'), findsNothing);
    expect(chat.sentIds, ['client-0']);
  });

  testWidgets('polls only for newer messages and shows new team replies',
      (tester) async {
    final chat = _FakeChat()..message('MEMBER', 'สวัสดีครับ');
    await tester.pumpWidget(_app(chat, poll: const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(chat.loadCursors, [null]);

    chat.message('TEAM', 'ทีมงานรับเรื่องแล้วครับ');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(chat.loadCursors, [null, '1']);
    expect(find.text('ทีมงานรับเรื่องแล้วครับ'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(chat.loadCursors.last, '2');
    expect(find.text('ทีมงานรับเรื่องแล้วครับ'), findsOneWidget);

    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    final pausedReads = chat.loadCursors.length;
    await tester.pump(const Duration(seconds: 3));
    expect(chat.loadCursors.length, pausedReads);
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(chat.loadCursors.length, pausedReads + 1);
  });

  testWidgets('explains the daily message limit', (tester) async {
    final chat = _FakeChat()
      ..failSends = 1
      ..sendError = const ApiException('limit',
          statusCode: 429, code: 'SUPPORT_MESSAGE_LIMIT');
    await tester.pumpWidget(_app(chat));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('support-chat-input')), 'อีกข้อความ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('support-chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('วันนี้ส่งข้อความครบจำนวนแล้ว รอทีมงานตอบกลับก่อน'),
        findsOneWidget);
  });

  testWidgets('offers a retry when the chat cannot load', (tester) async {
    final chat = _FakeChat()
      ..message('TEAM', 'คำตอบเดิม')
      ..loadError = const ApiException('down', statusCode: 503);
    await tester.pumpWidget(_app(chat));
    await tester.pumpAndSettle();
    expect(find.text('คำตอบเดิม'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);

    chat.loadError = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('คำตอบเดิม'), findsOneWidget);
  });
}
