import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

void main() {
  test('startProSubscription verifies Android purchase token with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_pro_monthly',
          purchaseToken: 'android-purchase-token',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request);
      },
    );

    final result = await service.startProSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'ANDROID',
      'productId': 'postdee_pro_monthly',
      'purchaseToken': 'android-purchase-token',
    });
    expect(result.subscription.isPro, isTrue);
  });

  test('startProSubscription uses RevenueCat without store verify when enabled',
      () async {
    var verifyCalls = 0;
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_pro_monthly',
          purchaseToken: 'android-purchase-token',
        ),
      ),
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      verifyPurchase: (_) async {
        verifyCalls += 1;
        throw StateError('store verify should not be called');
      },
      loadSubscription: () async => _subscription(plan: 'PRO'),
    );

    final result = await service.startProSubscription();

    expect(revenueCatGateway.purchasedProductId, 'postdee_pro_monthly');
    expect(verifyCalls, 0);
    expect(result.purchase.provider, 'revenuecat');
    expect(result.subscription.isPro, isTrue);
  });

  test('startStarterSubscription polls until RevenueCat webhook entitlement',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: loadCalls < 3 ? 'BASIC' : 'STARTER');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    final result = await service.startStarterSubscription();

    expect(result.subscription.isStarter, isTrue);
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('startStarterSubscription stops polling when entitlement never arrives',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: 'BASIC');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    await expectLater(
      service.startStarterSubscription(),
      throwsA(isA<StoreSubscriptionException>()),
    );
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('RevenueCat entitlement polling retries transient backend failures',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async {
        loadCalls += 1;
        if (loadCalls == 1) {
          throw const ApiException('Backend is waking up', statusCode: 503);
        }
        return _subscription(plan: loadCalls == 2 ? 'BASIC' : 'PRO');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    final result = await service.startProSubscription();

    expect(result.subscription.isPro, isTrue);
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('RevenueCat entitlement polling does not retry authentication errors',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async {
        loadCalls += 1;
        throw const ApiException('Unauthorized', statusCode: 401);
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    await expectLater(
      service.startProSubscription(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(loadCalls, 1);
    expect(waitCalls, 0);
  });

  test('restoreSubscription restores once and accepts the active paid plan',
      () async {
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    var resyncCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      resyncRevenueCatSubscription: () async {
        resyncCalls += 1;
        return 'STARTER';
      },
      loadSubscription: () async => _subscription(plan: 'STARTER'),
    );

    final result = await service.restoreSubscription();

    expect(revenueCatGateway.restoreCalls, 1);
    expect(resyncCalls, 1);
    expect(result.purchase.productId, 'postdee_starter_monthly');
    expect(result.subscription.isStarter, isTrue);
  });

  test('restoreSubscription stops immediately when no purchase is available',
      () async {
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    var loadCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      resyncRevenueCatSubscription: () async => 'BASIC',
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: 'BASIC');
      },
    );

    await expectLater(
      service.restoreSubscription(),
      throwsA(
        isA<StoreSubscriptionException>().having(
          (error) => error.message,
          'message',
          'ไม่พบรายการสมาชิกที่กู้คืนได้ในบัญชีนี้',
        ),
      ),
    );
    expect(revenueCatGateway.restoreCalls, 1);
    expect(loadCalls, 0);
  });

  final restoreResyncErrorCases = <({
    String? code,
    int statusCode,
    String expectedMessage,
  })>[
    (
      code: 'REVENUECAT_RESYNC_NOT_CONFIGURED',
      statusCode: 501,
      expectedMessage: 'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง',
    ),
    (
      code: 'REVENUECAT_ENTITLEMENT_NOT_MAPPED',
      statusCode: 409,
      expectedMessage:
          'พบรายการสมาชิกแล้ว แต่แพ็กเกจยังเชื่อมกับระบบไม่ถูกต้อง กรุณาติดต่อทีม PostDee',
    ),
    (
      code: 'REVENUECAT_RESYNC_FAILED',
      statusCode: 502,
      expectedMessage: 'เชื่อมต่อระบบสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    ),
    (
      code: null,
      statusCode: 501,
      expectedMessage: 'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง',
    ),
  ];

  for (final errorCase in restoreResyncErrorCases) {
    test(
        'restoreSubscription explains RevenueCat resync error '
        '${errorCase.code ?? errorCase.statusCode}', () async {
      final revenueCatGateway = FakeRevenueCatBillingGateway();
      var loadCalls = 0;
      final service = StoreSubscriptionService(
        revenueCatGateway: revenueCatGateway,
        useRevenueCat: true,
        resyncRevenueCatSubscription: () async => throw ApiException(
          'Backend RevenueCat resync failed',
          statusCode: errorCase.statusCode,
          code: errorCase.code,
        ),
        loadSubscription: () async {
          loadCalls += 1;
          return _subscription(plan: 'BASIC');
        },
      );

      await expectLater(
        service.restoreSubscription(),
        throwsA(
          isA<StoreSubscriptionException>().having(
            (error) => error.message,
            'message',
            errorCase.expectedMessage,
          ),
        ),
      );
      expect(revenueCatGateway.restoreCalls, 1);
      expect(loadCalls, 0);
    });
  }

  test('restoreProSubscription verifies iOS transaction id with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        restorePayload: const StorePurchasePayload.ios(
          productId: 'postdee_pro_monthly',
          transactionId: 'ios-transaction-id',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request);
      },
    );

    final result = await service.restoreProSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'IOS',
      'productId': 'postdee_pro_monthly',
      'transactionId': 'ios-transaction-id',
    });
    expect(result.subscription.isPro, isTrue);
  });

  test('startStarterSubscription verifies the Starter product with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_starter_monthly',
          purchaseToken: 'android-starter-purchase-token',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request, plan: 'STARTER');
      },
    );

    final result = await service.startStarterSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'ANDROID',
      'productId': 'postdee_starter_monthly',
      'purchaseToken': 'android-starter-purchase-token',
    });
    expect(result.subscription.isStarter, isTrue);
  });

  test(
      'restoreStarterSubscription verifies the Starter transaction with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        restorePayload: const StorePurchasePayload.ios(
          productId: 'postdee_starter_monthly',
          transactionId: 'ios-starter-transaction-id',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request, plan: 'STARTER');
      },
    );

    final result = await service.restoreStarterSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'IOS',
      'productId': 'postdee_starter_monthly',
      'transactionId': 'ios-starter-transaction-id',
    });
    expect(result.subscription.isStarter, isTrue);
  });

  test('startProSubscription fails before backend verify when store is offline',
      () async {
    var verifyCalls = 0;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(available: false),
      verifyPurchase: (_) async {
        verifyCalls += 1;
        throw StateError('verify should not be called');
      },
    );

    await expectLater(
      service.startProSubscription(),
      throwsA(isA<StoreSubscriptionException>()),
    );
    expect(verifyCalls, 0);
  });
}

StoreSubscriptionVerificationResult _verifiedSubscription(
  VerifyStorePurchaseRequest request, {
  String plan = 'PRO',
}) =>
    StoreSubscriptionVerificationResult(
      purchase: StorePurchaseResult(
        provider: 'store',
        platform: request.platform,
        productId: request.productId,
        verifiedAt: DateTime.parse('2026-06-04T00:00:00.000Z'),
        purchaseToken: request.purchaseToken,
        transactionId: request.transactionId,
      ),
      subscription: SubscriptionStatusResult(
        userId: 'seller-store',
        plan: plan,
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: plan == 'PRO',
        canUseAiAudioReview: false,
        canUseAiVideoReview: false,
      ),
    );

SubscriptionStatusResult _subscription({
  required String plan,
}) =>
    SubscriptionStatusResult(
      userId: 'seller-revenuecat',
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
      canUseAiAudioReview: false,
      canUseAiVideoReview: false,
    );

class FakeStoreBillingGateway implements StoreBillingGateway {
  const FakeStoreBillingGateway({
    this.available = true,
    this.purchasePayload,
    this.restorePayload,
  });

  final bool available;

  final StorePurchasePayload? purchasePayload;
  final StorePurchasePayload? restorePayload;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      productIds
          .map(
            (productId) => StoreProductInfo(
              id: productId,
              title: 'PostDee Pro',
              description: 'Monthly Pro subscription',
              price: '299 THB',
            ),
          )
          .toList();

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async =>
      purchasePayload ??
      StorePurchasePayload.android(
        productId: productId,
        purchaseToken: 'android-purchase-token',
      );

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async =>
      restorePayload ??
      StorePurchasePayload.ios(
        productId: productId,
        transactionId: 'ios-transaction-id',
      );
}

class FakeRevenueCatBillingGateway implements RevenueCatBillingGateway {
  FakeRevenueCatBillingGateway({this.available = true});

  final bool available;
  String? purchasedProductId;
  var restoreCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      productIds
          .map(
            (productId) => StoreProductInfo(
              id: productId,
              title: 'PostDee RevenueCat',
              description: 'RevenueCat subscription',
              price: 'Test Store',
            ),
          )
          .toList();

  @override
  Future<void> buySubscription(String productId) async {
    purchasedProductId = productId;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls += 1;
  }
}
