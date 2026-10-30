import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/features/notifications/notifications_screen.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

// Exact title/body pairs emitted by publishNotifier.ts. The stored payloads
// remain in their received language; only the screen presentation changes.
const _messages = [
  (
    thaiTitle: 'ส่งคลิปสำเร็จ',
    thaiBody: 'ระบบส่งคลิปไปยังช่องทางที่เลือกเรียบร้อยแล้ว แตะเพื่อดูผลลัพธ์',
    englishTitle: 'Video delivered',
    englishBody:
        'Your video was sent to the selected channels. Tap to view the result.',
  ),
  (
    thaiTitle: 'ส่งคลิปสำเร็จบางช่องทาง',
    thaiBody: 'บางช่องทางส่งคลิปไม่สำเร็จ แตะเพื่อดูรายละเอียด',
    englishTitle: 'Video partially delivered',
    englishBody:
        'Your video could not be sent to some channels. Tap for details.',
  ),
  (
    thaiTitle: 'ส่งคลิปไม่สำเร็จ',
    thaiBody: 'ส่งคลิปไปยังช่องทางที่เลือกไม่สำเร็จ แตะเพื่อดูรายละเอียด',
    englishTitle: 'Video delivery failed',
    englishBody:
        'Your video could not be sent to the selected channels. Tap for details.',
  ),
];

class _RecordingCenter extends PostDeeNotificationCenter {
  final marked = <PostDeeNotification>[];
  var markAllCalls = 0;

  @override
  void markRead(PostDeeNotification notification) {
    marked.add(notification);
    super.markRead(notification);
  }

  @override
  void markAllRead() {
    markAllCalls++;
    super.markAllRead();
  }
}

Widget _app(NotificationsScreen screen, {String languageCode = 'en'}) =>
    MaterialApp(
      locale: Locale(languageCode),
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: PostDeeLocalizations.supportedLocales,
      home: screen,
    );

PostDeeNotification _notification(String title, String body,
        {String postId = 'owned-post'}) =>
    PostDeeNotification(
      title: title,
      body: body,
      postId: postId,
      receivedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

void main() {
  for (final message in _messages) {
    testWidgets(
        'English presentation translates exact pair ${message.englishTitle}',
        (tester) async {
      final notification = _notification(message.thaiTitle, message.thaiBody);
      final center = _RecordingCenter()..add(notification);
      await tester.pumpWidget(_app(NotificationsScreen(center: center)));
      await tester.pumpAndSettle();
      expect(find.text(message.englishTitle), findsOneWidget);
      expect(find.text(message.englishBody), findsOneWidget);
      expect(find.text(message.thaiTitle), findsNothing);
      expect(find.text(message.thaiBody), findsNothing);
      expect(center.items.single, same(notification));
      expect(notification.title, message.thaiTitle);
      expect(notification.body, message.thaiBody);
      expect(center.isUnread(notification), isTrue);
      expect(center.marked, isEmpty);
      expect(center.markAllCalls, 0);
      expect(find.textContaining('Published'), findsNothing);
      expect(find.textContaining('publicly'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Thai presentation keeps received pair ${message.englishTitle}',
        (tester) async {
      final notification = _notification(message.thaiTitle, message.thaiBody);
      final center = _RecordingCenter()..add(notification);
      await tester.pumpWidget(
          _app(NotificationsScreen(center: center), languageCode: 'th'));
      await tester.pumpAndSettle();
      expect(find.text(message.thaiTitle), findsOneWidget);
      expect(find.text(message.thaiBody), findsOneWidget);
      expect(find.text(message.englishTitle), findsNothing);
      expect(center.items.single, same(notification));
      expect(center.marked, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (var titleIndex = 0; titleIndex < _messages.length; titleIndex++) {
    for (var bodyIndex = 0; bodyIndex < _messages.length; bodyIndex++) {
      if (titleIndex == bodyIndex) continue;
      testWidgets(
          'English preserves mismatched title $titleIndex/body $bodyIndex',
          (tester) async {
        final title = _messages[titleIndex].thaiTitle;
        final body = _messages[bodyIndex].thaiBody;
        final notification = _notification(title, body);
        final center = _RecordingCenter()..add(notification);
        await tester.pumpWidget(_app(NotificationsScreen(center: center)));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(center.items.single, same(notification));
        expect(center.marked, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final content in [
    (title: 'ข้อความจากผู้ขาย', body: 'ข้อความที่กำหนดเอง'),
    (title: _messages[0].thaiTitle, body: 'ข้อความที่กำหนดเอง'),
    (title: 'หัวข้อที่กำหนดเอง', body: _messages[0].thaiBody),
    (title: '${_messages[0].thaiTitle} ', body: _messages[0].thaiBody),
    (title: _messages[0].thaiTitle, body: '${_messages[0].thaiBody}.'),
    (title: _messages[0].englishTitle, body: _messages[0].englishBody),
  ]) {
    testWidgets(
        'English preserves unknown received copy ${content.title}/${content.body}',
        (tester) async {
      final center = PostDeeNotificationCenter()
        ..add(_notification(content.title, content.body));
      await tester.pumpWidget(_app(NotificationsScreen(center: center)));
      await tester.pumpAndSettle();
      expect(find.text(content.title), findsOneWidget);
      expect(find.text(content.body), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'explicit NotificationItem override is not translated or marked read',
      (tester) async {
    final message = _messages.first;
    final source = _notification(message.thaiTitle, message.thaiBody);
    final center = _RecordingCenter()..add(source);
    String? opened;
    await tester.pumpWidget(_app(NotificationsScreen(
      center: center,
      items: [
        NotificationItem(
          icon: Icons.notifications_none,
          color: Colors.blue,
          title: message.thaiTitle,
          body: message.thaiBody,
          time: 'Caller time',
          isUnread: true,
          postId: 'explicit-post',
          sourceNotification: source,
        ),
      ],
      onOpenPost: (id) => opened = id,
    )));
    await tester.pumpAndSettle();
    expect(find.text(message.thaiTitle), findsOneWidget);
    expect(find.text(message.thaiBody), findsOneWidget);
    expect(find.text('Caller time'), findsOneWidget);
    expect(find.text(message.englishTitle), findsNothing);
    await tester.tap(find.text(message.thaiTitle));
    await tester.pump();
    expect(opened, 'explicit-post');
    expect(center.marked, isEmpty);
    expect(center.isUnread(source), isTrue);
  });

  testWidgets('TH EN TH switch keeps payload identity and read state until tap',
      (tester) async {
    final first = _notification(_messages[0].thaiTitle, _messages[0].thaiBody,
        postId: 'selected-post');
    final second = _notification(_messages[2].thaiTitle, _messages[2].thaiBody,
        postId: 'keep-unread');
    final center = _RecordingCenter()
      ..add(second)
      ..add(first);
    var notifications = 0;
    center.addListener(() => notifications++);
    final opened = <String>[];
    final screen = NotificationsScreen(
      key: const ValueKey('stable-notifications'),
      center: center,
      onOpenPost: opened.add,
    );
    for (final code in ['th', 'en', 'th']) {
      await tester.pumpWidget(_app(screen, languageCode: code));
      await tester.pumpAndSettle();
      expect(
          find.text(code == 'th'
              ? _messages[0].thaiTitle
              : _messages[0].englishTitle),
          findsOneWidget);
      expect(center.items[0], same(first));
      expect(center.items[1], same(second));
      expect(center.isUnread(first), isTrue);
      expect(center.isUnread(second), isTrue);
      expect(center.marked, isEmpty);
      expect(center.markAllCalls, 0);
      expect(notifications, 0);
      expect(opened, isEmpty);
    }
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_messages[0].englishTitle));
    await tester.pump();
    expect(opened, ['selected-post']);
    expect(center.marked.single, same(first));
    expect(center.isUnread(first), isFalse);
    expect(center.isUnread(second), isTrue);
    expect(center.items[0], same(first));
    expect(first.title, _messages[0].thaiTitle);
    expect(first.body, _messages[0].thaiBody);
    expect(notifications, 1);
    for (final code in ['th', 'en']) {
      await tester.pumpWidget(_app(screen, languageCode: code));
      await tester.pumpAndSettle();
      expect(center.isUnread(first), isFalse);
      expect(center.isUnread(second), isTrue);
      expect(center.marked, hasLength(1));
      expect(center.marked.single, same(first));
      expect(center.markAllCalls, 0);
      expect(notifications, 1);
      expect(opened, ['selected-post']);
    }
    expect(tester.takeException(), isNull);
  });
}
