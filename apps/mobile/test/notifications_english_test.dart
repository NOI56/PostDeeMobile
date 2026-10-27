import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/notifications/notifications_screen.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

PostDeeNotification _notification({
  String title = 'Post result received',
  String body = 'Review the result in your post history.',
  DateTime? receivedAt,
  String? postId = 'english-notification-post',
}) =>
    PostDeeNotification(
        title: title,
        body: body,
        receivedAt: receivedAt ?? DateTime.now(),
        postId: postId);

Widget _app(
  NotificationsScreen notifications, {
  Locale locale = const Locale('en'),
  double scale = 1,
  bool dark = false,
}) {
  AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return MaterialApp(
    locale: locale,
    supportedLocales: PostDeeLocalizations.supportedLocales,
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: notifications,
  );
}

void _expectEnglish(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? text.textSpan?.toPlainText() ?? '',
        isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
  }
  expect(tester.takeException(), isNull);
}

void _expectReadable(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.dark));

  testWidgets(
      'English notifications translates title, session notice and empty state',
      (tester) async {
    await tester.pumpWidget(
        _app(NotificationsScreen(center: PostDeeNotificationCenter())));
    await tester.pumpAndSettle();
    for (final label in [
      'Notifications',
      'Received on this device during this session',
      'View all posts',
      'No notifications',
      'Post delivery results received on this device will appear here.',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    _expectEnglish(tester);
  });

  testWidgets(
      'English live notification exposes mark-all and singular elapsed time',
      (tester) async {
    final center = PostDeeNotificationCenter()
      ..add(_notification(
          receivedAt:
              DateTime.now().subtract(const Duration(minutes: 1, seconds: 5))));
    await tester.pumpWidget(_app(NotificationsScreen(center: center)));
    await tester.pumpAndSettle();
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('1 minute ago'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets('English future receipt retains Just now behavior',
      (tester) async {
    final center = PostDeeNotificationCenter()
      ..add(_notification(
          receivedAt: DateTime.now().add(const Duration(days: 1))));
    await tester.pumpWidget(_app(NotificationsScreen(center: center)));
    await tester.pumpAndSettle();
    expect(find.text('Just now'), findsOneWidget);
    _expectEnglish(tester);
  });

  for (final elapsed in const [
    (age: Duration(seconds: 45), label: 'Just now'),
    (age: Duration(minutes: 2, seconds: 5), label: '2 minutes ago'),
    (age: Duration(hours: 1, seconds: 5), label: '1 hour ago'),
    (age: Duration(hours: 2, seconds: 5), label: '2 hours ago'),
    (age: Duration(days: 1, seconds: 5), label: '1 day ago'),
    (age: Duration(days: 2, seconds: 5), label: '2 days ago'),
    (age: Duration(minutes: 59, seconds: 30), label: '59 minutes ago'),
    (age: Duration(hours: 23, minutes: 59, seconds: 30), label: '23 hours ago'),
  ]) {
    testWidgets('English elapsed receipt renders ${elapsed.label}',
        (tester) async {
      final source = _notification(
          receivedAt: DateTime.now().subtract(elapsed.age).toUtc());
      final center = PostDeeNotificationCenter()..add(source);
      await tester.pumpWidget(_app(NotificationsScreen(center: center)));
      await tester.pumpAndSettle();
      expect(find.text(elapsed.label), findsOneWidget);
      expect(center.items.single, same(source));
      _expectEnglish(tester);
    });
  }

  testWidgets('live arrivals retain newest-first order and open one exact post',
      (tester) async {
    final first = _notification(title: 'First receipt', postId: 'first-post');
    final newest =
        _notification(title: 'Newest receipt', postId: 'exact-post-42');
    final center = PostDeeNotificationCenter()..add(first);
    final opened = <String>[];
    await tester.pumpWidget(
        _app(NotificationsScreen(center: center, onOpenPost: opened.add)));
    await tester.pumpAndSettle();
    center.add(newest);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Newest receipt')).dy,
        lessThan(tester.getTopLeft(find.text('First receipt')).dy));
    await _tap(tester, find.text('Newest receipt'));
    expect(opened, ['exact-post-42']);
    expect(center.isUnread(newest), isFalse);
    expect(center.isUnread(first), isTrue);
    expect(center.items[0], same(newest));
    expect(center.items[1], same(first));
    _expectEnglish(tester);
  });

  testWidgets('English mark-all reads existing items without opening any posts',
      (tester) async {
    final first = _notification(title: 'First receipt');
    final second = _notification(title: 'Second receipt');
    final center = PostDeeNotificationCenter()
      ..add(first)
      ..add(second);
    final opened = <String>[];
    var historyOpens = 0;
    await tester.pumpWidget(_app(NotificationsScreen(
        center: center,
        onOpenPost: opened.add,
        onOpenAllPosts: () => historyOpens++)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Mark all as read'));
    expect(center.hasUnread, isFalse);
    expect(center.isUnread(first), isFalse);
    expect(center.isUnread(second), isFalse);
    expect(center.items[0], same(second));
    expect(center.items[1], same(first));
    expect(opened, isEmpty);
    expect(historyOpens, 0);
    expect(find.text('Mark all as read'), findsNothing);
    final later = _notification(
        title: 'Later receipt',
        receivedAt: DateTime.now().add(const Duration(seconds: 1)));
    center.add(later);
    await tester.pumpAndSettle();
    expect(center.isUnread(later), isTrue);
    expect(find.text('Mark all as read'), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'locale changes preserve source identity, ordering and read markers',
      (tester) async {
    final read = _notification(
        title: 'Read result',
        receivedAt: DateTime.now().subtract(const Duration(hours: 2)));
    final unread = _notification(title: 'Unread result');
    final center = PostDeeNotificationCenter()
      ..add(read)
      ..add(unread)
      ..markRead(read);
    var changes = 0;
    center.addListener(() => changes++);
    final opened = <String>[];
    final screen = NotificationsScreen(center: center, onOpenPost: opened.add);
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(find.text('2 ชม.ก่อน'), findsOneWidget);
    await tester.pumpWidget(_app(screen));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('2 hours ago'), findsOneWidget);
    expect(center.items[0], same(unread));
    expect(center.items[1], same(read));
    expect(center.isUnread(read), isFalse);
    expect(center.isUnread(unread), isTrue);
    expect(changes, 0);
    expect(opened, isEmpty);
    _expectEnglish(tester);
    await tester.pumpWidget(_app(screen, locale: const Locale('th')));
    await tester.pumpAndSettle();
    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(center.isUnread(unread), isTrue);
    expect(changes, 0);
  });

  testWidgets('a post notification without an open handler remains unread',
      (tester) async {
    final source = _notification();
    final center = PostDeeNotificationCenter()..add(source);
    await tester.pumpWidget(_app(NotificationsScreen(center: center)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text(source.title));
    expect(center.isUnread(source), isTrue);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    _expectEnglish(tester);
  });

  testWidgets(
      'a non-post notification does not navigate or change its read state',
      (tester) async {
    final source = _notification(postId: null);
    final center = PostDeeNotificationCenter()..add(source);
    final opened = <String>[];
    await tester.pumpWidget(
        _app(NotificationsScreen(center: center, onOpenPost: opened.add)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text(source.title));
    expect(opened, isEmpty);
    expect(center.isUnread(source), isTrue);
    _expectEnglish(tester);
  });

  testWidgets(
      'English View all posts invokes its callback once without marking read',
      (tester) async {
    final source = _notification();
    final center = PostDeeNotificationCenter()..add(source);
    var opens = 0;
    final openedPosts = <String>[];
    await tester.pumpWidget(_app(NotificationsScreen(
        center: center,
        onOpenPost: openedPosts.add,
        onOpenAllPosts: () => opens++)));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('notifications-open-posts')));
    expect(opens, 1);
    expect(openedPosts, isEmpty);
    expect(center.isUnread(source), isTrue);
    _expectEnglish(tester);
  });

  testWidgets('explicit item override preserves raw Thai title, body and time',
      (tester) async {
    final source = _notification(title: 'Hidden center source');
    final center = PostDeeNotificationCenter()..add(source);
    final opened = <String>[];
    final screen =
        NotificationsScreen(center: center, onOpenPost: opened.add, items: [
      NotificationItem(
        icon: Icons.info_outline,
        color: Colors.blue,
        title: 'ข้อความที่ระบุเอง',
        body: 'เนื้อหาภาษาไทยของผู้ใช้',
        time: 'เวลาที่กำหนดเอง CUSTOM_TIME',
        isUnread: true,
        postId: 'explicit-item-id',
        sourceNotification: source,
      )
    ]);
    for (final locale in [const Locale('th'), const Locale('en')]) {
      await tester.pumpWidget(_app(screen, locale: locale));
      await tester.pumpAndSettle();
      expect(find.text('ข้อความที่ระบุเอง'), findsOneWidget);
      expect(find.text('เนื้อหาภาษาไทยของผู้ใช้'), findsOneWidget);
      expect(find.text('เวลาที่กำหนดเอง CUSTOM_TIME'), findsOneWidget);
      expect(find.text('Hidden center source'), findsNothing);
      expect(find.text('Mark all as read'), findsNothing);
    }
    await _tap(tester, find.text('ข้อความที่ระบุเอง'));
    expect(opened, ['explicit-item-id']);
    expect(center.isUnread(source), isTrue);
    expect(center.items.single, same(source));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clearing live history removes old content and retains later arrivals',
      (tester) async {
    final old = _notification(title: 'Previous account receipt');
    final center = PostDeeNotificationCenter()
      ..add(old)
      ..markRead(old);
    await tester.pumpWidget(_app(NotificationsScreen(center: center)));
    await tester.pumpAndSettle();
    center.clear();
    await tester.pumpAndSettle();
    expect(find.text('Previous account receipt'), findsNothing);
    expect(find.text('No notifications'), findsOneWidget);
    expect(center.items, isEmpty);
    final latest = _notification(title: 'Current account receipt');
    center.add(latest);
    await tester.pumpAndSettle();
    expect(find.text('Current account receipt'), findsOneWidget);
    expect(find.text('No notifications'), findsNothing);
    expect(center.items.single, same(latest));
    expect(center.isUnread(latest), isTrue);
    _expectEnglish(tester);
  });

  testWidgets('idle notifications schedule no refresh or automatic motion',
      (tester) async {
    final source = _notification();
    final center = PostDeeNotificationCenter()..add(source);
    final opened = <String>[];
    await tester.pumpWidget(
        _app(NotificationsScreen(center: center, onOpenPost: opened.add)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(days: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(opened, isEmpty);
    expect(center.items.single, same(source));
    expect(center.isUnread(source), isTrue);
    _expectEnglish(tester);
  });

  testWidgets('plain MaterialApp retains historical Thai notification fallback',
      (tester) async {
    final center = PostDeeNotificationCenter()
      ..add(_notification(
          receivedAt:
              DateTime.now().subtract(const Duration(minutes: 1, seconds: 5))));
    await tester
        .pumpWidget(MaterialApp(home: NotificationsScreen(center: center)));
    await tester.pumpAndSettle();
    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(find.text('อ่านทั้งหมด'), findsOneWidget);
    expect(find.text('ดูโพสต์ทั้งหมด'), findsOneWidget);
    expect(find.text('1 นาทีก่อน'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English empty notifications fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opens = 0;
      await tester.pumpWidget(_app(
          NotificationsScreen(
              center: PostDeeNotificationCenter(),
              onOpenAllPosts: () => opens++),
          scale: 2,
          dark: dark));
      await tester.pumpAndSettle();
      for (final label in [
        'Notifications',
        'Received on this device during this session',
        'View all posts',
        'No notifications',
        'Post delivery results received on this device will appear here.',
      ]) {
        _expectReadable(tester, label);
      }
      await _tap(tester, find.text('View all posts'));
      expect(opens, 1);
      _expectEnglish(tester);
    });

    testWidgets(
        'English live notification actions fit 320dp 2x ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = 'A long notification title describing the delivery result';
      final source = _notification(
          title: title,
          receivedAt:
              DateTime.now().subtract(const Duration(days: 123, minutes: 10)));
      final center = PostDeeNotificationCenter()..add(source);
      final opened = <String>[];
      var historyOpens = 0;
      await tester.pumpWidget(_app(
          NotificationsScreen(
              center: center,
              onOpenPost: opened.add,
              onOpenAllPosts: () => historyOpens++),
          scale: 2,
          dark: dark));
      await tester.pumpAndSettle();
      for (final label in [
        'Notifications',
        'Mark all as read',
        '123 days ago',
        title,
      ]) {
        _expectReadable(tester, label);
      }
      await _tap(tester, find.text('Mark all as read'));
      expect(center.hasUnread, isFalse);
      expect(opened, isEmpty);
      await _tap(tester, find.text(title));
      expect(opened, ['english-notification-post']);
      await _tap(tester, find.text('View all posts'));
      expect(historyOpens, 1);
      _expectEnglish(tester);
    });
  }
}
