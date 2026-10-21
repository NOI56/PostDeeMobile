import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/notifications/notifications_screen.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

void main() {
  testWidgets('opening one notification marks only that item as read',
      (tester) async {
    final read = PostDeeNotification(
        title: 'First result',
        body: 'Open this',
        receivedAt: DateTime.now(),
        postId: 'first');
    final unread = PostDeeNotification(
        title: 'Second result',
        body: 'Keep this unread',
        receivedAt: DateTime.now(),
        postId: 'second');
    final center = PostDeeNotificationCenter()
      ..add(read)
      ..add(unread);
    await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(center: center, onOpenPost: (_) {})));
    await tester.tap(find.text('First result'));
    await tester.pump();
    expect(center.isUnread(read), isFalse);
    expect(center.isUnread(unread), isTrue);
    expect(center.hasUnread, isTrue);
  });

  testWidgets('empty notification history offers the actual post history',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
            center: PostDeeNotificationCenter(),
            onOpenPost: (_) {},
            onOpenAllPosts: () => opened = true)));
    await tester.tap(find.byKey(const ValueKey('notifications-open-posts')));
    expect(opened, isTrue);
  });

  testWidgets('notification tap opens its post', (tester) async {
    String? openedPost;
    final center = PostDeeNotificationCenter()
      ..add(PostDeeNotification(
          title: 'Done',
          body: 'Tap',
          receivedAt: DateTime.now(),
          postId: 'post-1'));
    await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(
      center: center,
      onOpenPost: (id) => openedPost = id,
    )));
    await tester.tap(find.text('Done'));
    expect(openedPost, 'post-1');
  });
  testWidgets('shows an empty state instead of sample notifications by default',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(center: PostDeeNotificationCenter()),
      ),
    );

    expect(find.text('รายการที่ได้รับบนอุปกรณ์นี้ในรอบการใช้งานนี้'),
        findsOneWidget);
    expect(
      find.text('เมื่อได้รับผลการเผยแพร่โพสต์บนอุปกรณ์นี้ จะแสดงที่นี่'),
      findsOneWidget,
    );
    expect(find.textContaining('คลิปมาแรง'), findsNothing);
    expect(find.textContaining('คิวตั้งเวลา'), findsNothing);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.trending_up), findsNothing);
    expect(find.byIcon(Icons.schedule), findsNothing);
  });

  testWidgets('shows notifications received from the center', (tester) async {
    final center = PostDeeNotificationCenter()
      ..add(PostDeeNotification(
        title: 'โพสต์เผยแพร่แล้ว',
        body: 'ลงครบทุกแพลตฟอร์ม',
        receivedAt: DateTime.now(),
      ));

    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(center: center)),
    );

    expect(find.text('โพสต์เผยแพร่แล้ว'), findsOneWidget);
    expect(find.text('ลงครบทุกแพลตฟอร์ม'), findsOneWidget);
    expect(find.text('รายการที่ได้รับบนอุปกรณ์นี้ในรอบการใช้งานนี้'),
        findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
  });

  testWidgets('updates live when a new notification arrives', (tester) async {
    final center = PostDeeNotificationCenter();

    await tester.pumpWidget(
      MaterialApp(home: NotificationsScreen(center: center)),
    );

    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    center.add(PostDeeNotification(
      title: 'คลิปมาแรง',
      body: 'ยอดวิวกำลังพุ่ง',
      receivedAt: DateTime.now(),
    ));
    await tester.pump();

    expect(find.text('คลิปมาแรง'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
  });
}
