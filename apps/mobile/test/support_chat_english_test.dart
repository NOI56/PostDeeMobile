import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/support/support_chat_screen.dart';

final _now = DateTime(2026, 10, 30, 14, 0, 30);
const _loadFallback = 'Could not load the chat. Please try again.';
const _sendFallback = 'Could not send the message. Tap it to retry.';
const _handoffFallback =
    'Could not send your request to the team. Please try again.';
const _limitMessage =
    'You have reached the daily message limit. Wait for the team to reply.';
const _unavailable =
    'PostDee is temporarily unavailable. Please try again later.';
const _offline =
    'Cannot connect to PostDee. Check your internet connection and try again.';
const _timeout = 'The request took too long. Please try again.';
const _auth = 'Please sign in again and retry.';
const _rate = 'Too many requests. Wait a moment and try again.';

class _Chat {
  final messages = <SupportMessageResult>[];
  final incidents = <ServiceIncidentResult>[];
  final loadCursors = <String?>[];
  final sent = <({String id, String body})>[];
  Object? loadError;
  Object? sendError;
  Object? handoffError;
  Completer<SupportChatResult>? initialGate;
  Completer<SupportChatResult>? pollGate;
  Completer<SupportMessageResult>? sendGate;
  Completer<void>? handoffGate;
  bool botAvailable = false;
  bool botEnabled = true;
  bool teamRequested = false;
  int teamRequests = 0;
  int statusReads = 0;

  SupportMessageResult message(String sender, String body,
      {String? id, DateTime? createdAt}) {
    final message = SupportMessageResult(
      id: id ?? 'server-${messages.length}',
      sender: sender,
      body: body,
      createdAt: createdAt ??
          _now
              .subtract(const Duration(minutes: 2))
              .add(Duration(seconds: messages.length)),
    );
    messages.add(message);
    return message;
  }

  SupportChatResult snapshot({String? after}) => SupportChatResult(
        messages: List.of(messages.skip(after == null ? 0 : int.parse(after))),
        cursor: '${messages.length}',
        threadStatus: messages.isEmpty ? null : 'WAITING_TEAM',
        botAvailable: botAvailable,
        botEnabled: botEnabled,
        teamRequested: teamRequested,
      );

  Future<SupportChatResult> load({String? after}) async {
    loadCursors.add(after);
    if (loadError != null) throw loadError!;
    if (after == null && initialGate != null) return initialGate!.future;
    if (after != null && pollGate != null) return pollGate!.future;
    return snapshot(after: after);
  }

  Future<List<ServiceIncidentResult>> loadStatus() async {
    statusReads++;
    return List.of(incidents);
  }

  Future<SupportMessageResult> send(
      {required String id, required String body}) async {
    sent.add((id: id, body: body));
    if (sendError != null) throw sendError!;
    if (sendGate != null) return sendGate!.future;
    return messages.where((message) => message.id == id).firstOrNull ??
        message('MEMBER', body, id: id, createdAt: _now);
  }

  Future<void> requestTeam() async {
    teamRequests++;
    if (handoffError != null) throw handoffError!;
    if (handoffGate != null) await handoffGate!.future;
    teamRequested = true;
  }
}

class _Fixture {
  _Fixture(
      {Locale locale = const Locale('en'), this.poll = const Duration(days: 1)})
      : language = ValueNotifier(locale);
  final ValueNotifier<Locale> language;
  final Duration poll;
  final chat = _Chat();
  int nextId = 0;

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) => MaterialApp(
        locale: locale,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        home: SupportChatScreen(
          key: const ValueKey('english-support-chat'),
          loadChat: chat.load,
          sendMessage: chat.send,
          requestTeam: chat.requestTeam,
          loadServiceStatus: chat.loadStatus,
          pollInterval: poll,
          newMessageId: () => 'client-${nextId++}',
          now: () => _now,
        ),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> locale(WidgetTester tester, String code) async {
    language.value = Locale(code);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    language.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
TextEditingController _composer(WidgetTester tester) =>
    tester.widget<TextField>(_key('support-chat-input')).controller!;
String _sendError(WidgetTester tester) =>
    tester.widget<Text>(_key('support-chat-send-error')).data!;

void _expectEnglishChrome(WidgetTester tester) {
  expect(find.text('Chat with the team'), findsOneWidget);
  expect(
      tester.widget<TextField>(_key('support-chat-input')).decoration!.hintText,
      'Message the team');
  expect(find.byTooltip('Send'), findsOneWidget);
}

Future<void> _sendText(WidgetTester tester, String body) async {
  await tester.enterText(_key('support-chat-input'), body);
  await tester.pump();
  await tester.tap(_key('support-chat-send'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppTheme.applyThemeMode(ThemeMode.light));
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('load generic failure is English and can retry', (tester) async {
    final f = _Fixture();
    f.chat.loadError = StateError('private load details');
    await f.mount(tester);
    _expectEnglishChrome(tester);
    expect(find.text(_loadFallback), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('private load details'), findsNothing);
    expect(
        tester.widget<IconButton>(_key('support-chat-send')).onPressed, isNull);
    f.chat.loadError = null;
    f.chat.message('TEAM', 'ทีมงานตอบกลับตามเดิม');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(f.chat.loadCursors, [null, null]);
    expect(find.text(_loadFallback), findsNothing);
    expect(find.text('ทีมงานตอบกลับตามเดิม'), findsOneWidget);
    expect(find.text('PostDee team'), findsOneWidget);
    await f.close(tester);
  });

  final loadFailures = <({String name, Object error, String message})>[
    (
      name: 'unavailable',
      error: const ApiException('private 503', statusCode: 503),
      message: _unavailable
    ),
    (
      name: 'offline',
      error: const SocketException('private host'),
      message: _offline
    ),
    (
      name: 'timeout',
      error: TimeoutException('private deadline'),
      message: _timeout
    ),
    (
      name: 'auth',
      error: const ApiException('private token', statusCode: 401),
      message: _auth
    ),
    (
      name: 'rate limit',
      error: const ApiException('private rate', statusCode: 429),
      message: _rate
    ),
  ];
  for (final failure in loadFailures) {
    testWidgets(
        'load ${failure.name} failure uses English API guidance and Retry',
        (tester) async {
      final f = _Fixture();
      f.chat.loadError = failure.error;
      await f.mount(tester);
      _expectEnglishChrome(tester);
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('private '), findsNothing);
      f.chat.loadError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Have a problem or question? Tell the team.'),
          findsOneWidget);
      expect(find.text(failure.message), findsNothing);
      await f.close(tester);
    });
  }

  testWidgets(
      'English loading and empty chat keep the text-only composer usable',
      (tester) async {
    final f = _Fixture();
    final gate = Completer<SupportChatResult>();
    f.chat.initialGate = gate;
    await f.mount(tester, settle: false);
    _expectEnglishChrome(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .semanticsLabel,
        'Loading chat');
    expect(
        tester.widget<IconButton>(_key('support-chat-send')).onPressed, isNull);
    final input = tester.widget<TextField>(_key('support-chat-input'));
    expect(input.maxLength, 1000);
    expect(input.maxLines, 5);
    gate.complete(f.chat.snapshot());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Have a problem or question? Tell the team.'),
        findsOneWidget);
    expect(
        find.textContaining('The PostDee team replies here and notifies you.'),
        findsOneWidget);
    expect(
        find.textContaining('Never send passwords, OTP codes or card details.'),
        findsOneWidget);
    await tester.enterText(_key('support-chat-input'), '   ');
    await tester.pump();
    expect(
        tester.widget<IconButton>(_key('support-chat-send')).onPressed, isNull);
    expect(f.chat.sent, isEmpty);
    await f.close(tester);
  });

  testWidgets(
      'English chat preserves raw member, team, bot and service-incident content',
      (tester) async {
    final f = _Fixture();
    f.chat
      ..botAvailable = true
      ..message('MEMBER', 'โพสต์ TikTok ไม่ขึ้น')
      ..message('TEAM', 'ส่งข้อความไม่สำเร็จ แตะข้อความเพื่อส่งอีกครั้ง')
      ..message('BOT', 'ขอคุยกับทีมงาน');
    f.chat.incidents.add(ServiceIncidentResult(
      id: 'thai-notice',
      title: 'ระบบ TikTok ยังมีปัญหา',
      message: 'กำลังแก้ไข กรุณารอก่อน',
      platforms: const ['TIKTOK'],
      stage: 'IDENTIFIED',
      updatedAt: _now.subtract(const Duration(minutes: 5)),
    ));
    await f.mount(tester);
    _expectEnglishChrome(tester);
    for (final value in [
      'โพสต์ TikTok ไม่ขึ้น',
      'ส่งข้อความไม่สำเร็จ แตะข้อความเพื่อส่งอีกครั้ง',
      'ขอคุยกับทีมงาน',
      'ระบบ TikTok ยังมีปัญหา',
      'กำลังแก้ไข กรุณารอก่อน'
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('PostDee team'), findsOneWidget);
    expect(find.text('Dot · AI helper'), findsOneWidget);
    expect(find.text('AI answer · 13:58'), findsOneWidget);
    expect(find.text('Cause found · fixing'), findsOneWidget);
    expect(find.text('Affects TikTok · updated 13:55'), findsOneWidget);
    expect(find.textContaining('Dot, the AI helper'), findsOneWidget);
    expect(find.textContaining('AI can be wrong'), findsOneWidget);
    await f.locale(tester, 'th');
    expect(find.text('Dot · ผู้ช่วย AI'), findsOneWidget);
    expect(find.text('พบสาเหตุแล้ว · กำลังแก้ไข'), findsOneWidget);
    expect(find.text('ระบบ TikTok ยังมีปัญหา'), findsOneWidget);
    expect(find.text('ขอคุยกับทีมงาน'), findsWidgets);
    await f.locale(tester, 'en');
    _expectEnglishChrome(tester);
    expect(f.chat.loadCursors, [null]);
    expect(f.chat.statusReads, 1);
    expect(find.text('ขอคุยกับทีมงาน'), findsOneWidget);
    await f.close(tester);
  });

  testWidgets(
      'English history formats a previous-day timestamp without Thai suffix',
      (tester) async {
    final f = _Fixture();
    f.chat.message('TEAM', 'คำตอบเมื่อวาน',
        createdAt: DateTime(2026, 10, 29, 13, 5));
    await f.mount(tester);
    expect(find.text('29/10 13:05'), findsOneWidget);
    await f.locale(tester, 'th');
    expect(find.text('29/10 13:05 น.'), findsOneWidget);
    expect(find.text('คำตอบเมื่อวาน'), findsOneWidget);
    await f.close(tester);
  });

  for (final flags in [
    (available: false, enabled: true),
    (available: true, enabled: false)
  ]) {
    testWidgets(
        'English disabled Dot controls preserve old bot history ${flags.available}/${flags.enabled}',
        (tester) async {
      final f = _Fixture();
      f.chat
        ..botAvailable = flags.available
        ..botEnabled = flags.enabled
        ..message('BOT', 'คำตอบเก่าจาก Dot');
      await f.mount(tester);
      expect(find.text('Dot · AI helper'), findsOneWidget);
      expect(find.text('คำตอบเก่าจาก Dot'), findsOneWidget);
      expect(
          find.textContaining('The PostDee team replies here'), findsOneWidget);
      expect(_key('support-chat-handoff'), findsNothing);
      expect(_key('support-bot-typing'), findsNothing);
      expect(_key('support-chat-handed-off'), findsNothing);
      await f.close(tester);
    });
  }

  testWidgets('English Dot typing ends when its raw reply arrives by polling',
      (tester) async {
    final f = _Fixture(poll: const Duration(seconds: 1));
    f.chat.botAvailable = true;
    await f.mount(tester);
    await _sendText(tester, 'ส่งไม่ได้ค่ะ');
    expect(find.text('Dot is typing…'), findsOneWidget);
    expect(find.text('ส่งไม่ได้ค่ะ'), findsOneWidget);
    f.chat.message('BOT', 'ลองส่งใหม่อีกครั้งได้ค่ะ',
        createdAt: _now.add(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('ลองส่งใหม่อีกครั้งได้ค่ะ'), findsOneWidget);
    expect(find.text('Dot is typing…'), findsNothing);
    expect(find.text('Talk to the team'), findsOneWidget);
    await f.close(tester);
  });

  testWidgets(
      'English team-requested state keeps Dot available without another handoff',
      (tester) async {
    final f = _Fixture();
    f.chat
      ..botAvailable = true
      ..teamRequested = true
      ..message('BOT', 'ทีมงานจะเข้ามาดูต่อ');
    await f.mount(tester);
    expect(find.textContaining('The team has been told and will reply here.'),
        findsOneWidget);
    expect(find.textContaining('Meanwhile you can keep asking Dot.'),
        findsOneWidget);
    expect(find.textContaining('Dot, the AI helper'), findsOneWidget);
    expect(_key('support-chat-handoff'), findsNothing);
    expect(f.chat.teamRequests, 0);
    await f.close(tester);
  });

  final sendFailures = <({String name, Object error, String message})>[
    (
      name: 'generic',
      error: StateError('private send details'),
      message: _sendFallback
    ),
    (
      name: 'daily limit',
      error: const ApiException('private limit',
          statusCode: 429, code: 'SUPPORT_MESSAGE_LIMIT'),
      message: _limitMessage
    ),
    (
      name: 'unavailable',
      error: const ApiException('private 503', statusCode: 503),
      message: _unavailable
    ),
  ];
  for (final failure in sendFailures) {
    testWidgets(
        'send ${failure.name} failure is English and retains the same id and body on retry',
        (tester) async {
      final f = _Fixture();
      f.chat.sendError = failure.error;
      await f.mount(tester);
      await _sendText(tester, '  ช่วยดูข้อความให้หน่อย  ');
      expect(_sendError(tester), failure.message);
      expect(find.text('Not sent · tap to retry'), findsOneWidget);
      expect(find.byTooltip('Remove this message'), findsOneWidget);
      expect(f.chat.sent, [(id: 'client-0', body: 'ช่วยดูข้อความให้หน่อย')]);
      expect(_composer(tester).text, isEmpty);
      await tester.enterText(_key('support-chat-input'), 'ร่างข้อความถัดไป');
      await tester.pump();
      f.chat.sendError = null;
      await tester.tap(find.text('ช่วยดูข้อความให้หน่อย'));
      await tester.pumpAndSettle();
      expect(f.chat.sent, [
        (id: 'client-0', body: 'ช่วยดูข้อความให้หน่อย'),
        (id: 'client-0', body: 'ช่วยดูข้อความให้หน่อย'),
      ]);
      expect(_key('support-pending-client-0'), findsNothing);
      expect(_key('support-message-client-0'), findsOneWidget);
      expect(find.text('ช่วยดูข้อความให้หน่อย'), findsOneWidget);
      expect(_key('support-chat-send-error'), findsNothing);
      expect(_composer(tester).text, 'ร่างข้อความถัดไป');
      await f.close(tester);
    });
  }

  testWidgets(
      'English failed message can be discarded without sending another request',
      (tester) async {
    final f = _Fixture();
    f.chat.sendError = StateError('private send details');
    await f.mount(tester);
    await _sendText(tester, 'ส่งไม่ออก');
    expect(_sendError(tester), _sendFallback);
    await tester.tap(find.byTooltip('Remove this message'));
    await tester.pumpAndSettle();
    expect(find.text('ส่งไม่ออก'), findsNothing);
    expect(_key('support-chat-send-error'), findsNothing);
    expect(find.text('Have a problem or question? Tell the team.'),
        findsOneWidget);
    expect(f.chat.sent, [(id: 'client-0', body: 'ส่งไม่ออก')]);
    await f.close(tester);
  });

  testWidgets(
      'load failure re-localizes immediately and preserves an unsent composer draft',
      (tester) async {
    final f = _Fixture();
    f.chat.loadError = StateError('private load details');
    await f.mount(tester);
    await tester.enterText(_key('support-chat-input'), 'ร่างก่อนโหลดใหม่');
    await tester.pump();
    final controller = _composer(tester);
    expect(find.text(_loadFallback), findsOneWidget);
    await f.locale(tester, 'th');
    expect(find.text('โหลดแชทไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(_composer(tester), same(controller));
    expect(controller.text, 'ร่างก่อนโหลดใหม่');
    await f.locale(tester, 'en');
    expect(find.text(_loadFallback), findsOneWidget);
    expect(controller.text, 'ร่างก่อนโหลดใหม่');
    expect(f.chat.loadCursors, [null]);
    await f.close(tester);
  });

  testWidgets(
      'Thai API validation stays useful in Thai and becomes safe English guidance',
      (tester) async {
    final f = _Fixture();
    f.chat.loadError =
        const ApiException('ข้อความตรวจสอบจากเซิร์ฟเวอร์', statusCode: 400);
    await f.mount(tester);
    expect(find.text(_loadFallback), findsOneWidget);
    expect(find.text('ข้อความตรวจสอบจากเซิร์ฟเวอร์'), findsNothing);
    await f.locale(tester, 'th');
    expect(find.text('ข้อความตรวจสอบจากเซิร์ฟเวอร์'), findsOneWidget);
    await f.locale(tester, 'en');
    expect(find.text(_loadFallback), findsOneWidget);
    expect(find.text('ข้อความตรวจสอบจากเซิร์ฟเวอร์'), findsNothing);
    await f.close(tester);
  });

  for (final limited in [false, true]) {
    testWidgets(
        'failed send re-localizes without changing its id, raw body or next draft limit=$limited',
        (tester) async {
      final f = _Fixture();
      f.chat.sendError = limited
          ? const ApiException('private limit',
              statusCode: 429, code: 'SUPPORT_MESSAGE_LIMIT')
          : StateError('private send details');
      await f.mount(tester);
      await _sendText(tester, 'ข้อความจริงไม่ต้องแปล');
      await tester.enterText(_key('support-chat-input'), 'ร่างใหม่ยังไม่ส่ง');
      await tester.pump();
      final controller = _composer(tester);
      expect(_sendError(tester), limited ? _limitMessage : _sendFallback);
      await f.locale(tester, 'th');
      expect(
          _sendError(tester),
          limited
              ? 'วันนี้ส่งข้อความครบจำนวนแล้ว รอทีมงานตอบกลับก่อน'
              : 'ส่งข้อความไม่สำเร็จ แตะข้อความเพื่อส่งอีกครั้ง');
      expect(find.text('ส่งไม่สำเร็จ · แตะเพื่อส่งอีกครั้ง'), findsOneWidget);
      expect(find.byTooltip('ลบข้อความนี้'), findsOneWidget);
      expect(_composer(tester), same(controller));
      expect(controller.text, 'ร่างใหม่ยังไม่ส่ง');
      expect(find.text('ข้อความจริงไม่ต้องแปล'), findsOneWidget);
      await f.locale(tester, 'en');
      expect(_sendError(tester), limited ? _limitMessage : _sendFallback);
      expect(find.text('Not sent · tap to retry'), findsOneWidget);
      expect(find.byTooltip('Remove this message'), findsOneWidget);
      expect(f.chat.sent, [(id: 'client-0', body: 'ข้อความจริงไม่ต้องแปล')]);
      expect(controller.text, 'ร่างใหม่ยังไม่ส่ง');
      await f.close(tester);
    });
  }

  testWidgets(
      'an in-flight send survives language changes and merges its late acknowledgement once',
      (tester) async {
    final f = _Fixture();
    final gate = Completer<SupportMessageResult>();
    f.chat.sendGate = gate;
    await f.mount(tester);
    await _sendText(tester, 'ข้อความกำลังส่ง');
    expect(find.text('Sending…'), findsOneWidget);
    await tester.enterText(_key('support-chat-input'), 'ร่างใหม่');
    await tester.pump();
    final controller = _composer(tester);
    await f.locale(tester, 'th');
    expect(find.text('กำลังส่ง…'), findsOneWidget);
    expect(find.text('ข้อความกำลังส่ง'), findsOneWidget);
    expect(controller.text, 'ร่างใหม่');
    await f.locale(tester, 'en');
    expect(find.text('Sending…'), findsOneWidget);
    expect(_composer(tester), same(controller));
    gate.complete(f.chat
        .message('MEMBER', 'ข้อความกำลังส่ง', id: 'client-0', createdAt: _now));
    await tester.pumpAndSettle();
    expect(find.text('Sending…'), findsNothing);
    expect(_key('support-message-client-0'), findsOneWidget);
    expect(find.text('ข้อความกำลังส่ง'), findsOneWidget);
    expect(controller.text, 'ร่างใหม่');
    expect(f.chat.sent, [(id: 'client-0', body: 'ข้อความกำลังส่ง')]);
    await f.close(tester);
  });

  testWidgets(
      'handoff failure is English, follows locale and can retry without losing the draft',
      (tester) async {
    final f = _Fixture();
    f.chat
      ..botAvailable = true
      ..handoffError = StateError('private handoff details')
      ..message('BOT', 'คำตอบจากบอต');
    await f.mount(tester);
    await tester.enterText(_key('support-chat-input'), 'ร่างรอทีมงาน');
    await tester.pump();
    await tester.tap(_key('support-chat-handoff'));
    await tester.pumpAndSettle();
    expect(_sendError(tester), _handoffFallback);
    expect(f.chat.teamRequests, 1);
    await f.locale(tester, 'th');
    expect(_sendError(tester), 'ส่งต่อให้ทีมงานไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    expect(_composer(tester).text, 'ร่างรอทีมงาน');
    await f.locale(tester, 'en');
    expect(_sendError(tester), _handoffFallback);
    f.chat.handoffError = null;
    await tester.tap(_key('support-chat-handoff'));
    await tester.pumpAndSettle();
    expect(f.chat.teamRequests, 2);
    expect(_key('support-chat-send-error'), findsNothing);
    expect(find.textContaining('The team has been told'), findsOneWidget);
    expect(_key('support-chat-handoff'), findsNothing);
    expect(_composer(tester).text, 'ร่างรอทีมงาน');
    await f.close(tester);
  });

  testWidgets(
      'handoff busy state rejects duplicate taps and stays disabled across locale changes',
      (tester) async {
    final f = _Fixture();
    final gate = Completer<void>();
    f.chat
      ..botAvailable = true
      ..handoffGate = gate
      ..message('BOT', 'คำตอบเดิม');
    await f.mount(tester);
    await tester.tap(_key('support-chat-handoff'));
    await tester.tap(_key('support-chat-handoff'));
    await tester.pumpAndSettle();
    expect(f.chat.teamRequests, 1);
    expect(
        tester.widget<OutlinedButton>(_key('support-chat-handoff')).onPressed,
        isNull);
    await f.locale(tester, 'th');
    expect(
        tester.widget<OutlinedButton>(_key('support-chat-handoff')).onPressed,
        isNull);
    expect(f.chat.teamRequests, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await f.locale(tester, 'en');
    expect(find.textContaining('The team has been told'), findsOneWidget);
    expect(_key('support-chat-handoff'), findsNothing);
    expect(f.chat.teamRequests, 1);
    await f.close(tester);
  });

  testWidgets(
      'polling keeps the cursor before a send and deduplicates the acknowledgement',
      (tester) async {
    // Editing pumps can include caret frames; keep the poll tick outside them.
    final f = _Fixture(poll: const Duration(seconds: 10));
    await f.mount(tester);
    expect(f.chat.loadCursors, [null]);
    await _sendText(tester, 'ข้อความสมาชิก');
    f.chat.message('TEAM', 'คำตอบทีมงาน',
        createdAt: _now.add(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(f.chat.loadCursors, [null, '0']);
    expect(find.text('ข้อความสมาชิก'), findsOneWidget);
    expect(find.text('คำตอบทีมงาน'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(f.chat.loadCursors.last, '2');
    expect(find.text('คำตอบทีมงาน'), findsOneWidget);
    await f.close(tester);
  });

  testWidgets('missed polls stay quiet and a later English-chat poll recovers',
      (tester) async {
    final f = _Fixture(poll: const Duration(seconds: 1));
    f.chat.message('MEMBER', 'ข้อความเดิม');
    await f.mount(tester);
    f.chat.loadError = StateError('private poll details');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('ข้อความเดิม'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text(_loadFallback), findsNothing);
    f.chat.loadError = null;
    f.chat.message('TEAM', 'กลับมาตอบแล้ว');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('กลับมาตอบแล้ว'), findsOneWidget);
    _expectEnglishChrome(tester);
    await f.close(tester);
  });

  testWidgets(
      'polling pauses in background, resumes once and stops after disposal',
      (tester) async {
    final f = _Fixture(poll: const Duration(seconds: 1));
    await f.mount(tester);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    final pausedReads = f.chat.loadCursors.length;
    await tester.pump(const Duration(seconds: 3));
    expect(f.chat.loadCursors.length, pausedReads);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(f.chat.loadCursors.length, pausedReads + 1);
    await f.close(tester);
    final disposedReads = f.chat.loadCursors.length;
    await tester.pump(const Duration(seconds: 3));
    expect(f.chat.loadCursors.length, disposedReads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late initial load completion is ignored after disposal',
      (tester) async {
    final f = _Fixture();
    final gate = Completer<SupportChatResult>();
    f.chat.initialGate = gate;
    await f.mount(tester, settle: false);
    await f.close(tester);
    gate.complete(f.chat.snapshot());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.chat.loadCursors, [null]);
    expect(f.chat.statusReads, 0);
  });

  testWidgets('late send completion is ignored after disposal', (tester) async {
    final f = _Fixture();
    final gate = Completer<SupportMessageResult>();
    f.chat.sendGate = gate;
    await f.mount(tester);
    await _sendText(tester, 'ส่งค้างอยู่');
    await f.close(tester);
    gate.complete(f.chat
        .message('MEMBER', 'ส่งค้างอยู่', id: 'client-0', createdAt: _now));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.chat.sent, [(id: 'client-0', body: 'ส่งค้างอยู่')]);
  });

  testWidgets('late handoff completion is ignored after disposal',
      (tester) async {
    final f = _Fixture();
    final gate = Completer<void>();
    f.chat
      ..botAvailable = true
      ..handoffGate = gate
      ..message('BOT', 'คำตอบจากบอต');
    await f.mount(tester);
    await tester.tap(_key('support-chat-handoff'));
    await tester.pumpAndSettle();
    await f.close(tester);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.chat.teamRequests, 1);
  });

  testWidgets('late poll completion is ignored after disposal', (tester) async {
    final f = _Fixture(poll: const Duration(seconds: 1));
    final gate = Completer<SupportChatResult>();
    await f.mount(tester);
    f.chat.pollGate = gate;
    await tester.pump(const Duration(seconds: 1));
    await f.close(tester);
    gate.complete(f.chat.snapshot(after: '0'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.chat.loadCursors, [null, '0']);
  });
}
