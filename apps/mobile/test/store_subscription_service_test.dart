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

  test('startStarterSubscription waits for RevenueCat webhook entitlement',
      () async {
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      loadSubscription: () async => _subscription(plan: 'BASIC'),
    );

    await expectLater(
      service.startStarterSubscription(),
      throwsA(isA<StoreSubscriptionException>()),
    );
  });

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
