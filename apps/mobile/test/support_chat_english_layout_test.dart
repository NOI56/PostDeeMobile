import 'dart:async';
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

const _loadFailure = 'Could not load the chat. Please try again.';
const _sendFailure = 'Could not send the message. Tap it to retry.';
const _memberBody = 'ข้อความต้นฉบับจากสมาชิก';
const _teamBody = 'ข้อความต้นฉบับจากทีมงาน';
const _botBody = 'ข้อความต้นฉบับจาก Dot';
const _pendingBody = 'ข้อความทดสอบที่ยังส่งไม่สำเร็จ';

class _Fixture {
  _Fixture({this.dark = false, this.scale = 1});

  final bool dark;
  final double scale;
  final boundary = GlobalKey();
  final keyboardInset = ValueNotifier<double>(0);
  Object? loadError;
  Object? sendError;
  Object? handoffError;
  Completer<SupportChatResult>? loading;
  Completer<void>? handoff;
  bool bot = false;
  int handoffs = 0;
  int sends = 0;
  final messages = <SupportMessageResult>[];

  void addHistory() {
    bot = true;
    for (final entry in [
      ('MEMBER', _memberBody),
      ('TEAM', _teamBody),
      ('BOT', _botBody),
    ]) {
      messages.add(SupportMessageResult(
        id: 'history-${messages.length}',
        sender: entry.$1,
        body: entry.$2,
        createdAt: DateTime(2026, 10, 28, 14, messages.length),
      ));
    }
  }

  Future<SupportChatResult> load({String? after}) async {
    if (loadError != null) throw loadError!;
    if (loading != null) return loading!.future;
    return SupportChatResult(
      messages: after == null ? List.of(messages) : const [],
      cursor: '${messages.length}',
      botAvailable: bot,
    );
  }

  Future<SupportMessageResult> send({
    required String id,
    required String body,
  }) async {
    sends++;
    if (sendError != null) throw sendError!;
    return SupportMessageResult(
      id: id,
      sender: 'MEMBER',
      body: body,
      createdAt: DateTime(2026, 10, 28, 14, 3),
    );
  }

  Future<void> requestTeam() async {
    handoffs++;
    if (handoffError != null) throw handoffError!;
    if (handoff != null) await handoff!.future;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: keyboardInset,
        builder: (context, inset, _) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: inset),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
      home: Builder(
          builder: (context) => Scaffold(
                body: Center(
                    child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SupportChatScreen(
                      loadChat: load,
                      sendMessage: send,
                      requestTeam: requestTeam,
                      loadServiceStatus: () async => const [],
                      pollInterval: const Duration(days: 1),
                      newMessageId: () => 'layout-message',
                      now: () => DateTime(2026, 10, 28, 15),
                    ),
                  )),
                  child: const Text('Open support chat'),
                )),
              )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open support chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (loading == null) await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['POSTDEE_SUPPORT_ENGLISH_PREVIEW_DIR'];
    if (output == null || output.isEmpty) return;
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    keyboardInset.dispose();
  }
}

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final fonts = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await fonts.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  _fontsLoaded = true;
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _chatScroll => find.descendant(
    of: _key('support-chat-list'), matching: find.byType(Scrollable));

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(_chatScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 180,
        scrollable: _chatScroll, maxScrolls: 60);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void _readable(WidgetTester tester, Finder target) {
  expect(target, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: target, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5));
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(-.5));
  expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width + .5));
}

void _action(WidgetTester tester, Finder target) {
  expect(target.hitTestable(), findsOneWidget);
  final size = tester.getSize(target);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
  final rect = tester.getRect(target);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
}

void _phone(WidgetTester tester, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize =
      scale == 1 ? const Size(390, 844) : const Size(320, 740);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
          'English support error and transcript fit ${scale}x ${dark ? 'dark' : 'light'}',
          (tester) async {
        _phone(tester, scale);
        final f = _Fixture(dark: dark, scale: scale)
          ..loadError = StateError('fake load failure');
        await f.open(tester);
        expect(find.text('Chat with the team'), findsOneWidget);
        expect(find.text(_loadFailure), findsOneWidget);
        _readable(tester, find.text(_loadFailure));
        _action(tester, find.widgetWithText(TextButton, 'Retry'));
        _action(tester, find.byType(BackButton));
        await f.capture(
            tester, 'support-error-${dark ? 'dark' : 'light'}-${scale}x');
        final errorViewport = find
            .ancestor(
              of: find.text(_loadFailure),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        final errorScroll = find
            .descendant(
              of: errorViewport,
              matching: find.byType(Scrollable),
            )
            .first;
        final errorPosition =
            tester.state<ScrollableState>(errorScroll).position;
        errorPosition.jumpTo(errorPosition.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text(_loadFailure)).bottom,
            lessThanOrEqualTo(tester.getRect(errorViewport).bottom));
        _action(tester, find.widgetWithText(TextButton, 'Retry'));
        await f.capture(tester,
            'support-error-bottom-${dark ? 'dark' : 'light'}-${scale}x');

        f.loadError = null;
        f.addHistory();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        for (final text in [
          _memberBody,
          _teamBody,
          _botBody,
          'PostDee team',
          'Dot · AI helper'
        ]) {
          await _reveal(tester, find.text(text));
          _readable(tester, find.text(text));
        }
        await _reveal(tester, _key('support-chat-handoff'));
        _readable(tester, find.text('Talk to the team'));
        _action(tester, _key('support-chat-handoff'));
        await f.capture(
            tester, 'support-history-${dark ? 'dark' : 'light'}-${scale}x');

        f.sendError = StateError('fake send failure');
        await tester.enterText(_key('support-chat-input'), _pendingBody);
        await tester.pumpAndSettle();
        _action(tester, _key('support-chat-send'));
        await tester.tap(_key('support-chat-send'));
        await tester.pumpAndSettle();
        expect(find.text(_sendFailure), findsOneWidget);
        _readable(tester, find.text(_sendFailure));
        await _reveal(tester, _key('support-pending-layout-message'));
        _readable(tester, find.text('Not sent · tap to retry'));
        _action(
          tester,
          find
              .ancestor(
                of: find.byTooltip('Remove this message'),
                matching: find.byType(IconButton),
              )
              .first,
        );
        await f.capture(
            tester, 'support-pending-${dark ? 'dark' : 'light'}-${scale}x');

        await tester.enterText(_key('support-chat-input'), 'draft');
        f.keyboardInset.value = 220;
        await tester.pumpAndSettle();
        _readable(tester, find.text(_sendFailure));
        _action(tester, _key('support-chat-send'));
        _action(tester, find.byType(BackButton));
        expect(
            tester
                .widget<TextField>(_key('support-chat-input'))
                .controller!
                .text,
            'draft');
        final composerRect = tester.getRect(_key('support-chat-input'));
        expect(composerRect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height - 220));
        expect(tester.takeException(), isNull);
        await f.capture(
            tester, 'support-keyboard-${dark ? 'dark' : 'light'}-${scale}x');
        f.keyboardInset.value = 0;
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(SupportChatScreen), findsNothing);
        expect(f.sends, 1);
        await f.close(tester);
      });
    }
  }

  testWidgets('English support loading remains visible without enabling Send',
      (tester) async {
    _phone(tester, 3);
    final f = _Fixture(scale: 3)..loading = Completer<SupportChatResult>();
    await f.open(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester.widget<IconButton>(_key('support-chat-send')).onPressed, isNull);
    _action(tester, find.byType(BackButton));
    expect(tester.takeException(), isNull);
    await f.capture(tester, 'support-loading-light-3.0x');
    f.loading!.complete(const SupportChatResult(messages: []));
    await tester.pumpAndSettle();
    await f.close(tester);
  });

  testWidgets(
      'English support preserves a full-height draft above the keyboard at 3x',
      (tester) async {
    _phone(tester, 3);
    final f = _Fixture(scale: 3)..sendError = StateError('fake send failure');
    await f.open(tester);
    await tester.enterText(_key('support-chat-input'), _pendingBody);
    await tester.pumpAndSettle();
    await tester.tap(_key('support-chat-send'));
    await tester.pumpAndSettle();
    expect(find.text(_sendFailure), findsOneWidget);
    final draft = List.filled(35, 'long draft text ').join();
    await tester.enterText(_key('support-chat-input'), draft);
    f.keyboardInset.value = 220;
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_key('support-chat-input'));
    expect(field.controller!.text, draft);
    expect(field.maxLines, 5);
    expect(tester.takeException(), isNull);
    _action(tester, _key('support-chat-send'));
    expect(tester.getRect(_key('support-chat-send')).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 220));
    await f.capture(tester, 'support-keyboard-full-draft-light-3.0x');
    expect(f.sends, 1);
    await f.close(tester);
  });

  testWidgets(
      'English support actions expose readable semantics and remain usable',
      (tester) async {
    _phone(tester, 1);
    final semantics = tester.ensureSemantics();
    final f = _Fixture()..loadError = StateError('fake load failure');
    try {
      await f.open(tester);
      expect(find.bySemanticsLabel('Chat with the team'), findsOneWidget);
      expect(find.bySemanticsLabel(_loadFailure), findsOneWidget);
      expect(find.bySemanticsLabel('Retry').hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('Back').hitTestable(), findsOneWidget);
      f.loadError = null;
      await tester.tap(find.bySemanticsLabel('Retry'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Message the team'), findsOneWidget);
      expect(tester.widget<IconButton>(_key('support-chat-send')).onPressed,
          isNull);
      f.sendError = StateError('fake send failure');
      await tester.enterText(_key('support-chat-input'), _pendingBody);
      await tester.pumpAndSettle();
      final sendSemantics =
          tester.getSemantics(_key('support-chat-send')).getSemanticsData();
      expect(sendSemantics.tooltip, 'Send');
      expect(sendSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.tap(_key('support-chat-send'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(_sendFailure), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Not sent.*tap to retry')),
          findsWidgets);
      final discardButton = find
          .ancestor(
            of: find.byTooltip('Remove this message'),
            matching: find.byType(IconButton),
          )
          .first;
      final discardSemantics =
          tester.getSemantics(discardButton).getSemanticsData();
      expect(discardSemantics.tooltip, 'Remove this message');
      expect(discardSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.tap(discardButton);
      await tester.pumpAndSettle();
      expect(find.text(_pendingBody), findsNothing);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SupportChatScreen), findsNothing);
      await f.close(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'English handoff stays reachable and exposes its busy state at 3x',
      (tester) async {
    _phone(tester, 3);
    final f = _Fixture(dark: true, scale: 3)
      ..addHistory()
      ..handoff = Completer<void>();
    await f.open(tester);
    await _reveal(tester, _key('support-chat-handoff'));
    _action(tester, _key('support-chat-handoff'));
    await tester.tap(_key('support-chat-handoff'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<OutlinedButton>(_key('support-chat-handoff')).onPressed,
        isNull);
    expect(f.handoffs, 1);
    await f.capture(tester, 'support-handoff-dark-3.0x');
    f.handoff!.complete();
    await tester.pumpAndSettle();
    await _reveal(tester, _key('support-chat-handed-off'));
    _readable(tester, _key('support-chat-handed-off'));
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
}
