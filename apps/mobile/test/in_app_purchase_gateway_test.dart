import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _productId = 'postdee_pro_monthly';

PurchaseDetails _purchase({
  PurchaseStatus status = PurchaseStatus.purchased,
  String purchaseId = 'transaction-1',
}) =>
    PurchaseDetails(
      purchaseID: purchaseId,
      productID: _productId,
      verificationData: PurchaseVerificationData(
          localVerificationData: 'receipt',
          serverVerificationData: 'receipt',
          source: 'mock-store'),
      transactionDate: '1',
      status: status,
    )..pendingCompletePurchase = true;

class _NativeStore implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  int buyCalls = 0;
  int completeCalls = 0;
  int restoreCalls = 0;
  int acknowledgementFailures = 0;
  Completer<void>? acknowledgement;
  void Function()? onRestore;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
          Set<String> identifiers) async =>
      ProductDetailsResponse(
          productDetails: identifiers
              .map((id) => ProductDetails(
                  id: id,
                  title: id,
                  description: '',
                  price: '฿299',
                  rawPrice: 299,
                  currencyCode: 'THB'))
              .toList(),
          notFoundIDs: []);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls += 1;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls += 1;
    if (acknowledgementFailures > 0) {
      acknowledgementFailures -= 1;
      throw StateError('acknowledgement offline');
    }
    await acknowledgement?.future;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls += 1;
    onRestore?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a hanging acknowledgement does not hide an available receipt',
      () async {
    final store = _NativeStore()..acknowledgement = Completer<void>();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(
        store: store, acknowledgementTimeout: const Duration(milliseconds: 10));
    final result = gateway.buySubscription(_productId);
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    expect((await result).purchaseToken, 'receipt');
    expect(gateway.hasPendingAcknowledgement, isTrue);
    final retry = gateway.reconcilePendingPurchase();
    await Future<void>.delayed(Duration.zero);
    expect(store.completeCalls, 1);
    await expectLater(gateway.buySubscription(_productId),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    store.acknowledgement!.complete();
    await retry;
    expect(gateway.hasPendingAcknowledgement, isFalse);
    expect(store.completeCalls, 1);
  });

  test('receipt confirmation retry retains an unfinished acknowledgement',
      () async {
    final store = _NativeStore()..acknowledgementFailures = 1;
    addTearDown(store.events.close);
    var verifications = 0;
    final service = StoreSubscriptionService(
      gateway: InAppPurchaseStoreBillingGateway(store: store),
      useRevenueCat: false,
      verifyPurchase: (request) async {
        verifications += 1;
        if (verifications == 1) throw StateError('verification offline');
        return StoreSubscriptionVerificationResult(
          purchase: StorePurchaseResult(
              provider: 'mock-store',
              platform: request.platform,
              productId: request.productId,
              verifiedAt: DateTime(2026),
              purchaseToken: request.purchaseToken),
          subscription: const SubscriptionStatusResult(
              userId: 'seller',
              plan: 'PRO',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true),
        );
      },
    );
    final buy = service.startProSubscription();
    final failedConfirmation = expectLater(
        buy, throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    await failedConfirmation;
    expect(service.hasPendingStoreAcknowledgement, isTrue);
    expect(
        (await service.retryPendingConfirmation()).subscription.isPro, isTrue);
    expect(service.hasPendingConfirmation, isTrue);
    expect(verifications, 2);
    expect(store.completeCalls, 1);
    await service.retryPendingConfirmation();
    expect(service.hasPendingConfirmation, isFalse);
    expect(verifications, 2);
    expect(store.completeCalls, 2);
    expect(store.buyCalls, 1);
  });

  test(
      'verified receipt keeps an acknowledgement retry without verifying twice',
      () async {
    final store = _NativeStore()..acknowledgementFailures = 1;
    addTearDown(store.events.close);
    var verifications = 0;
    final service = StoreSubscriptionService(
      gateway: InAppPurchaseStoreBillingGateway(store: store),
      useRevenueCat: false,
      verifyPurchase: (request) async {
        verifications += 1;
        return StoreSubscriptionVerificationResult(
          purchase: StorePurchaseResult(
              provider: 'mock-store',
              platform: request.platform,
              productId: request.productId,
              verifiedAt: DateTime(2026),
              purchaseToken: request.purchaseToken),
          subscription: const SubscriptionStatusResult(
              userId: 'seller',
              plan: 'PRO',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true),
        );
      },
    );
    final buy = service.startProSubscription();
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    expect((await buy).subscription.isPro, isTrue);
    expect(service.hasPendingConfirmation, isTrue);
    expect(service.hasPendingStoreAcknowledgement, isTrue);
    expect(store.completeCalls, 1);
    expect(
        (await service.retryPendingConfirmation()).subscription.isPro, isTrue);
    expect(service.hasPendingConfirmation, isFalse);
    expect(service.hasPendingStoreAcknowledgement, isFalse);
    expect(store.completeCalls, 2);
    expect(store.buyCalls, 1);
    expect(verifications, 1);
  });

  test('terminal cancellation releases a native operation for a later attempt',
      () async {
    final store = _NativeStore();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(store: store);
    final original = gateway.buySubscription(_productId);
    final cancellation =
        expectLater(original, throwsA(isA<StoreSubscriptionException>()));
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase(status: PurchaseStatus.canceled)]);
    await cancellation;
    final retry = gateway.buySubscription(_productId);
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    await retry;
    expect(store.buyCalls, 2);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('native purchase stays subscribed after its former deadline', () async {
    final store = _NativeStore();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(
        store: store, purchaseTimeout: const Duration(milliseconds: 10));
    final result = gateway.buySubscription(_productId);
    var settled = false;
    result.then<void>((_) => settled = true,
        onError: (Object _, StackTrace __) => settled = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(settled, isFalse);
    expect(store.events.hasListener, isTrue);
    await expectLater(gateway.buySubscription(_productId),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    store.events.add([_purchase()]);
    expect((await result).purchaseToken, 'receipt');
    expect(store.buyCalls, 1);
  });

  test('duplicate terminal events acknowledge one transaction once', () async {
    final store = _NativeStore()..acknowledgement = Completer<void>();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(store: store);
    final result = gateway.buySubscription(_productId);
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    store.events.add([_purchase()]);
    await Future<void>.delayed(Duration.zero);
    expect(store.completeCalls, 1);
    store.acknowledgement!.complete();
    expect((await result).productId, _productId);
  });

  test('stream transport error keeps the unknown purchase pending', () async {
    final store = _NativeStore();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(store: store);
    final result = gateway.buySubscription(_productId);
    var settled = false;
    result.then<void>((_) => settled = true,
        onError: (Object _, StackTrace __) => settled = true);
    await Future<void>.delayed(Duration.zero);
    store.events.addError(StateError('transport offline'));
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    await expectLater(gateway.buySubscription(_productId),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    store.events.add([_purchase()]);
    await result;
    expect(store.buyCalls, 1);
  });

  test('acknowledgement failure preserves a receipt for verification and retry',
      () async {
    final store = _NativeStore()..acknowledgementFailures = 1;
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(store: store);
    final result = gateway.buySubscription(_productId);
    await Future<void>.delayed(Duration.zero);
    store.events.add([_purchase()]);
    expect((await result).purchaseToken, 'receipt');
    await expectLater(gateway.buySubscription(_productId),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    await gateway.reconcilePendingPurchase();
    expect(store.completeCalls, 2);
    expect(store.restoreCalls, 1);
    expect(store.buyCalls, 1);
  });

  test('explicit restore reconciles the same pending purchase', () async {
    final store = _NativeStore();
    addTearDown(store.events.close);
    final gateway = InAppPurchaseStoreBillingGateway(store: store);
    final result = gateway.buySubscription(_productId);
    await Future<void>.delayed(Duration.zero);
    store.onRestore =
        () => store.events.add([_purchase(status: PurchaseStatus.restored)]);
    final restored = gateway.restoreSubscription(_productId);
    expect((await restored).purchaseToken, 'receipt');
    expect((await result).purchaseToken, 'receipt');
    expect(store.buyCalls, 1);
    expect(store.restoreCalls, 1);
  });

  test(
      'service recheck restores and verifies the original native purchase once',
      () async {
    final store = _NativeStore();
    addTearDown(store.events.close);
    var verifications = 0;
    final service = StoreSubscriptionService(
      gateway: InAppPurchaseStoreBillingGateway(store: store),
      useRevenueCat: false,
      storeOperationTimeout: const Duration(milliseconds: 20),
      verifyPurchase: (request) async {
        verifications += 1;
        return StoreSubscriptionVerificationResult(
          purchase: StorePurchaseResult(
              provider: 'mock-store',
              platform: request.platform,
              productId: request.productId,
              verifiedAt: DateTime(2026),
              purchaseToken: request.purchaseToken),
          subscription: const SubscriptionStatusResult(
              userId: 'seller',
              plan: 'PRO',
              status: 'ACTIVE',
              canSchedule: true,
              canUseAiCaptions: true,
              canUseAnalytics: true),
        );
      },
    );
    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    store.onRestore =
        () => store.events.add([_purchase(status: PurchaseStatus.restored)]);
    final result = await service.retryPendingConfirmation();
    expect(result.subscription.isPro, isTrue);
    expect(store.buyCalls, 1);
    expect(store.restoreCalls, 1);
    expect(verifications, 1);
  });
}
