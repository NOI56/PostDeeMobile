import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/notifications/notifications_screen.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

void main() {
  testWidgets('shows an empty state instead of sample notifications by default',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(center: PostDeeNotificationCenter()),
      ),
    );

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
