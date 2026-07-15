import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

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

  testWidgets('marks a verified plan as current immediately after purchase',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = StoreSubscriptionService(
      gateway: const _FakeStoreBillingGateway(),
      useRevenueCat: false,
      verifyPurchase: (request) async =>
          _verifiedSubscription(request, plan: 'PRO'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          service: service,
          loadSubscription: () async => _subscription(plan: 'BASIC'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('สมัคร Pro'));
    await tester.tap(find.text('สมัคร Pro'));
    await tester.pumpAndSettle();

    expect(find.text('สมัคร Pro สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();

    expect(find.text('สมัคร Pro'), findsNothing);
    expect(find.text('สมัคร Starter'), findsOneWidget);
  });

  testWidgets('restores a previous Pro purchase and refreshes the current plan',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final revenueCatGateway = _FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      resyncRevenueCatSubscription: () async => 'PRO',
      loadSubscription: () async => _subscription(plan: 'PRO'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          service: service,
          loadSubscription: () async => _subscription(plan: 'BASIC'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('กู้คืนการซื้อ'));
    await tester.tap(find.text('กู้คืนการซื้อ'));
    await tester.pumpAndSettle();

    expect(revenueCatGateway.restoreCalls, 1);
    expect(find.text('กู้คืนการซื้อสำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.text('สมัคร Pro'), findsNothing);
  });

  testWidgets('ignores an initial Basic response that finishes after purchase',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialSubscription = Completer<SubscriptionStatusResult>();
    final service = StoreSubscriptionService(
      gateway: const _FakeStoreBillingGateway(),
      useRevenueCat: false,
      verifyPurchase: (request) async =>
          _verifiedSubscription(request, plan: 'PRO'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          service: service,
          loadSubscription: () => initialSubscription.future,
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('สมัคร Pro'));
    await tester.tap(find.text('สมัคร Pro'));
    await tester.pumpAndSettle();
    expect(find.text('สมัคร Pro สำเร็จ'), findsOneWidget);

    initialSubscription.complete(_subscription(plan: 'BASIC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();

    expect(find.text('สมัคร Pro'), findsNothing);
  });

  testWidgets('blocks back navigation while a purchase is pending',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final purchase = Completer<StoreSubscriptionVerificationResult>();
    final service = StoreSubscriptionService(
      gateway: const _FakeStoreBillingGateway(),
      useRevenueCat: false,
      verifyPurchase: (_) => purchase.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          service: service,
          loadSubscription: () async => _subscription(plan: 'BASIC'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('สมัคร Pro'));
    await tester.tap(find.text('สมัคร Pro'));
    await tester.pump();
    expect(find.text('กำลังดำเนินการสั่งซื้อ...'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('กำลังดำเนินการสั่งซื้อ...'), findsOneWidget);

    purchase.complete(
      _verifiedSubscription(
        const VerifyStorePurchaseRequest.android(
          productId: 'postdee_pro_monthly',
          purchaseToken: 'pending-purchase-token',
        ),
        plan: 'PRO',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('สมัคร Pro สำเร็จ'), findsOneWidget);
  });
}

StoreSubscriptionVerificationResult _verifiedSubscription(
  VerifyStorePurchaseRequest request, {
  required String plan,
}) =>
    StoreSubscriptionVerificationResult(
      purchase: StorePurchaseResult(
        provider: 'store',
        platform: request.platform,
        productId: request.productId,
        verifiedAt: DateTime.parse('2026-07-15T00:00:00.000Z'),
        purchaseToken: request.purchaseToken,
        transactionId: request.transactionId,
      ),
      subscription: _subscription(plan: plan),
    );

SubscriptionStatusResult _subscription({required String plan}) =>
    SubscriptionStatusResult(
      userId: 'paywall-user',
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
    );

class _FakeStoreBillingGateway implements StoreBillingGateway {
  const _FakeStoreBillingGateway();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async =>
      StorePurchasePayload.android(
        productId: productId,
        purchaseToken: 'paywall-purchase-token',
      );

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async =>
      StorePurchasePayload.android(
        productId: productId,
        purchaseToken: 'paywall-restore-token',
      );
}

class _FakeRevenueCatBillingGateway implements RevenueCatBillingGateway {
  var restoreCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<void> buySubscription(String productId) async {}

  @override
  Future<void> restorePurchases() async => restoreCalls += 1;
}
