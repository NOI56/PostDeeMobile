import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';

void main() {
  testWidgets('shows only paid benefits that are available now',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'basic-user',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ลายน้ำอัตโนมัติ'), findsOneWidget);
    expect(find.text('AI ตัดต่อ 200 นาที/เดือน'), findsOneWidget);
    expect(find.textContaining('ตัดคลิปเป็น EP'), findsNothing);
    expect(find.textContaining('เรดาร์แฮชแท็ก'), findsNothing);
    expect(find.textContaining('แจ้งเตือนไวรัล'), findsNothing);
    expect(find.textContaining('ทีมและผู้ช่วย'), findsNothing);
  });
}
