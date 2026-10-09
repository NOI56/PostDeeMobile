import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

void main() {
  testWidgets('uses actual store prices instead of fixed Thai prices', (tester) async {
    tester.view.physicalSize = const Size(393, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(
      loadSubscription: () async => _subscription(plan: 'BASIC'),
      service: StoreSubscriptionService(gateway: _PricedStoreBillingGateway(),
        useRevenueCat: false))));
    await tester.pumpAndSettle();
    expect(find.text('€5.49/เดือน'), findsOneWidget);
    expect(find.text('€8.49/เดือน'), findsOneWidget);
    expect(find.text('199 ฿/เดือน'), findsNothing);
    expect(find.text('299 ฿/เดือน'), findsNothing);
  });

  testWidgets('shows each paid plan scheduling window', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PaywallScreen(
            loadSubscription: () async => _subscription(plan: 'BASIC'))));
    await tester.pumpAndSettle();
    final starter = find.text('ตั้งเวลาล่วงหน้า 14 วัน + ปฏิทิน + เทมเพลต');
    await tester.scrollUntilVisible(starter, 300,
        scrollable: find.byType(Scrollable).first);
    expect(starter, findsOneWidget);
    final pro = find.text('ตั้งเวลาล่วงหน้า 30 วัน');
    await tester.scrollUntilVisible(pro, 300,
        scrollable: find.byType(Scrollable).first);
    expect(pro, findsOneWidget);
  });

  testWidgets(
      'default paywall service retains pending purchase across reopening',
      (tester) async {
    tester.view.physicalSize = const Size(393, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessionStore = PostDeeAuthSessionStore(
        initialSession: AuthSession.authenticated(
            userId: 'paywall-user', idToken: 'token'));
    final gateway = _FakeStoreBillingGateway();
    var backendAvailable = false;
    final cache = StoreSubscriptionSessionCache(
      sessionStore: sessionStore,
      createService: () => StoreSubscriptionService(
        gateway: gateway,
        useRevenueCat: false,
        verifyPurchase: (request) async {
          if (!backendAvailable) {
            throw const ApiException('Unavailable', statusCode: 503);
          }
          return _verifiedSubscription(request, plan: 'PRO');
        },
      ),
    );
    addTearDown(cache.dispose);
    await expectLater(cache.service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));

    Future<void> openPaywall() async {
      await tester.pumpWidget(MaterialApp(
          home: PaywallScreen(
        sessionCache: cache,
        loadSubscription: () async => _subscription(plan: 'BASIC'),
      )));
      await tester.pumpAndSettle();
    }

    await openPaywall();
    expect(find.byKey(const ValueKey('paywall-purchase-awaiting-confirmation')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await openPaywall();
    expect(find.byKey(const ValueKey('paywall-purchase-awaiting-confirmation')),
        findsOneWidget);
    backendAvailable = true;
    await tester.tap(find.byKey(const ValueKey('paywall-retry-purchase')));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันการซื้อสำเร็จ'), findsOneWidget);
    expect(gateway.purchaseCalls, 1);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
        'pending purchase safely rechecks without buying at ${textScale}x text',
        (tester) async {
      tester.view.physicalSize = const Size(393, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gateway = _FakeStoreBillingGateway();
      var backendAvailable = false;
      var verifiedCallbacks = 0;
      var verifyCalls = 0;
      final service = StoreSubscriptionService(
        gateway: gateway,
        useRevenueCat: false,
        verifyPurchase: (request) async {
          verifyCalls += 1;
          if (!backendAvailable) {
            throw const ApiException('Service Suspended', statusCode: 503);
          }
          return _verifiedSubscription(request, plan: 'PRO');
        },
      );
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: PaywallScreen(
          service: service,
          loadSubscription: () async => _subscription(plan: 'BASIC'),
          onSubscribed: (_) => verifiedCallbacks += 1,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('สมัคร Pro'), 400,
          scrollable: find.byType(Scrollable));
      await tester.ensureVisible(find.text('สมัคร Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สมัคร Pro'));
      await tester.pumpAndSettle();

      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('สมัครไม่สำเร็จ ลองใหม่อีกครั้ง'), findsNothing);
      expect(
          find.byKey(const ValueKey('paywall-purchase-awaiting-confirmation')),
          findsOneWidget);
      expect(verifiedCallbacks, 0);
      await tester.scrollUntilVisible(find.text('สมัคร Starter'), 400,
          scrollable: find.byType(Scrollable));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'สมัคร Starter'))
              .onPressed,
          isNull);
      await tester.scrollUntilVisible(find.text('สมัคร Pro'), 400,
          scrollable: find.byType(Scrollable));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'สมัคร Pro'))
              .onPressed,
          isNull);

      final retry = find.byKey(const ValueKey('paywall-retry-purchase'));
      await tester.scrollUntilVisible(retry, -400,
          scrollable: find.byType(Scrollable));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(service.hasPendingConfirmation, isTrue);
      expect(verifiedCallbacks, 0);
      expect(gateway.purchaseCalls, 1);
      backendAvailable = true;
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text('ยืนยันการซื้อสำเร็จ'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('paywall-purchase-awaiting-confirmation')),
          findsNothing);
      expect(verifiedCallbacks, 1);
      expect(verifyCalls, 3);
      expect(gateway.purchaseCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.text('AI ตัดต่อ 200 นาที/เดือน'), findsNothing);
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
      gateway: _FakeStoreBillingGateway(),
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

    await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'กู้คืนการซื้อ'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'กู้คืนการซื้อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กู้คืนการซื้อ'));
    await tester.pumpAndSettle();

    expect(revenueCatGateway.restoreCalls, 1);
    expect(find.text('กู้คืนการซื้อสำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.text('สมัคร Pro'), findsNothing);
  });

  testWidgets('disables purchases until the current plan is loaded',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialSubscription = Completer<SubscriptionStatusResult>();
    final service = StoreSubscriptionService(
      gateway: _FakeStoreBillingGateway(),
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
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'สมัคร Pro'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('สมัคร Pro'));
    await tester.pump();
    expect(find.text('กำลังดำเนินการสั่งซื้อ...'), findsNothing);
    expect(find.text('กำลังตรวจสอบแพ็กเกจปัจจุบัน...'), findsOneWidget);

    initialSubscription.complete(_subscription(plan: 'BASIC'));
    await tester.pumpAndSettle();

    expect(find.text('แพ็กเกจปัจจุบัน'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'สมัคร Pro'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('blocks purchase after a plan error and still offers retry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var loadCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: _FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async => _subscription(plan: 'PRO'),
      resyncRevenueCatSubscription: () async => 'PRO',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          service: service,
          loadSubscription: () async {
            loadCalls += 1;
            if (loadCalls == 1) throw Exception('subscription unavailable');
            return _subscription(plan: 'BASIC');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'โหลดแพ็กเกจปัจจุบันไม่สำเร็จ กรุณาลองใหม่ก่อนสมัคร หรือกู้คืนการซื้อเดิม',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('สมัคร Pro'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'สมัคร Pro'),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(find.text('กู้คืนการซื้อ'), 300,
        scrollable: find.byType(Scrollable));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'กู้คืนการซื้อ'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('paywall-retry-subscription')), -300,
        scrollable: find.byType(Scrollable));
    await tester.ensureVisible(
      find.byKey(const ValueKey('paywall-retry-subscription')),
    );
    await tester.tap(
      find.byKey(const ValueKey('paywall-retry-subscription')),
    );
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.textContaining('โหลดแพ็กเกจปัจจุบันไม่สำเร็จ'), findsNothing);
    await tester.ensureVisible(find.text('สมัคร Pro'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'สมัคร Pro'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'keeps loading error and retry states usable at 393dp with 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialSubscription = Completer<SubscriptionStatusResult>();
    var loadCalls = 0;
    addTearDown(() {
      if (!initialSubscription.isCompleted) {
        initialSubscription.complete(_subscription(plan: 'BASIC'));
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: PaywallScreen(
          loadSubscription: () {
            loadCalls += 1;
            return loadCalls == 1
                ? initialSubscription.future
                : Future.value(_subscription(plan: 'BASIC'));
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('กำลังตรวจสอบแพ็กเกจปัจจุบัน...'), findsOneWidget);
    expect(tester.takeException(), isNull);

    initialSubscription.completeError(Exception('subscription unavailable'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('โหลดแพ็กเกจปัจจุบันไม่สำเร็จ'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('สมัคร Pro'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'สมัคร Pro'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('paywall-retry-subscription')),
      -300,
      scrollable: find.byType(Scrollable),
    );
    final retryButton = find.byKey(
      const ValueKey('paywall-retry-subscription'),
    );
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.text('แพ็กเกจปัจจุบัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks back navigation while a purchase is pending',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final purchase = Completer<StoreSubscriptionVerificationResult>();
    final service = StoreSubscriptionService(
      gateway: _FakeStoreBillingGateway(),
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

class _PricedStoreBillingGateway extends _FakeStoreBillingGateway {
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      productIds.map((id) => StoreProductInfo(id: id, title: id, description: '',
        price: id.contains('starter') ? '€5.49' : '€8.49')).toList();
}

class _FakeStoreBillingGateway implements StoreBillingGateway {
  var purchaseCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async {
    purchaseCalls += 1;
    return StorePurchasePayload.android(
      productId: productId,
      purchaseToken: 'paywall-purchase-token',
    );
  }

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
