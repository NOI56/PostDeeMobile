import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;

import '../../core/config/app_config.dart';
import '../../core/network/postdee_api_client.dart';

typedef StorePurchaseVerifier = Future<StoreSubscriptionVerificationResult>
    Function(VerifyStorePurchaseRequest request);
typedef SubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef SubscriptionWait = Future<void> Function(Duration duration);
typedef RevenueCatSubscriptionResync = Future<String> Function();

Future<void> _defaultSubscriptionWait(Duration duration) =>
    Future<void>.delayed(duration);

class StoreSubscriptionException implements Exception {
  const StoreSubscriptionException(this.message);

  final String message;

  @override
  String toString() => 'StoreSubscriptionException: $message';
}

class StoreProductInfo {
  const StoreProductInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
}

class StorePurchasePayload {
  const StorePurchasePayload({
    required this.platform,
    required this.productId,
    this.purchaseToken,
    this.transactionId,
  });

  const StorePurchasePayload.android({
    required String productId,
    required String purchaseToken,
  }) : this(
          platform: 'ANDROID',
          productId: productId,
          purchaseToken: purchaseToken,
        );

  const StorePurchasePayload.ios({
    required String productId,
    required String transactionId,
  }) : this(
          platform: 'IOS',
          productId: productId,
          transactionId: transactionId,
        );

  final String platform;
  final String productId;
  final String? purchaseToken;
  final String? transactionId;
}

abstract class StoreBillingGateway {
  Future<bool> isAvailable();
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds);
  Future<StorePurchasePayload> buySubscription(String productId);
  Future<StorePurchasePayload> restoreSubscription(String productId);
}

abstract class RevenueCatBillingGateway {
  Future<bool> isAvailable();
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds);
  Future<void> buySubscription(String productId);
  Future<void> restorePurchases();
}

class StoreSubscriptionService {
  StoreSubscriptionService({
    StoreBillingGateway? gateway,
    RevenueCatBillingGateway? revenueCatGateway,
    StorePurchaseVerifier? verifyPurchase,
    SubscriptionLoader? loadSubscription,
    bool useRevenueCat = AppConfig.enableRevenueCatBilling,
    this.productId = AppConfig.storeProMonthlyProductId,
    this.starterProductId = AppConfig.storeStarterMonthlyProductId,
    int revenueCatEntitlementPollAttempts = 16,
    Duration revenueCatEntitlementPollInterval = const Duration(seconds: 1),
    SubscriptionWait? revenueCatEntitlementWait,
    RevenueCatSubscriptionResync? resyncRevenueCatSubscription,
  })  : assert(revenueCatEntitlementPollAttempts > 0),
        _revenueCatEntitlementPollAttempts = revenueCatEntitlementPollAttempts,
        _revenueCatEntitlementPollInterval = revenueCatEntitlementPollInterval,
        _revenueCatEntitlementWait =
            revenueCatEntitlementWait ?? _defaultSubscriptionWait,
        _resyncRevenueCatSubscription = resyncRevenueCatSubscription ??
            PostDeeApiClient().resyncRevenueCatSubscription,
        _gateway = gateway ??
            (useRevenueCat
                ? const _UnavailableStoreBillingGateway()
                : InAppPurchaseStoreBillingGateway()),
        _revenueCatGateway = useRevenueCat
            ? revenueCatGateway ?? createRevenueCatBillingGatewayFromConfig()
            : null,
        _loadSubscription =
            loadSubscription ?? PostDeeApiClient().loadCurrentSubscription,
        _verifyPurchase =
            verifyPurchase ?? PostDeeApiClient().verifyStoreSubscription;

  final StoreBillingGateway _gateway;
  final RevenueCatBillingGateway? _revenueCatGateway;
  final StorePurchaseVerifier _verifyPurchase;
  final SubscriptionLoader _loadSubscription;
  final int _revenueCatEntitlementPollAttempts;
  final Duration _revenueCatEntitlementPollInterval;
  final SubscriptionWait _revenueCatEntitlementWait;
  final RevenueCatSubscriptionResync _resyncRevenueCatSubscription;
  final String productId;
  final String starterProductId;

  bool get supportsUnifiedRestore => _revenueCatGateway != null;

  Future<StoreProductInfo?> loadStarterProduct() async {
    final products = await _queryProducts({starterProductId});

    return products
        .where((product) => product.id == starterProductId)
        .firstOrNull;
  }

  Future<StoreProductInfo?> loadProProduct() async {
    final products = await _queryProducts({productId});

    return products.where((product) => product.id == productId).firstOrNull;
  }

  Future<StoreSubscriptionVerificationResult> startStarterSubscription() async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _startRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: starterProductId,
        expectedPlan: 'STARTER',
      );
    }

    await _ensureStoreAvailable();
    final payload = await _gateway.buySubscription(starterProductId);

    return _verifyPayload(payload, starterProductId);
  }

  Future<StoreSubscriptionVerificationResult> startProSubscription() async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _startRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: productId,
        expectedPlan: 'PRO',
      );
    }

    await _ensureStoreAvailable();
    final payload = await _gateway.buySubscription(productId);

    return _verifyPayload(payload, productId);
  }

  Future<StoreSubscriptionVerificationResult>
      restoreStarterSubscription() async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _restoreRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: starterProductId,
        expectedPlan: 'STARTER',
      );
    }

    await _ensureStoreAvailable();
    final payload = await _gateway.restoreSubscription(starterProductId);

    return _verifyPayload(payload, starterProductId);
  }

  Future<StoreSubscriptionVerificationResult> restoreProSubscription() async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _restoreRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: productId,
        expectedPlan: 'PRO',
      );
    }

    await _ensureStoreAvailable();
    final payload = await _gateway.restoreSubscription(productId);

    return _verifyPayload(payload, productId);
  }

  Future<StoreSubscriptionVerificationResult> restoreSubscription() async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway == null) {
      throw const StoreSubscriptionException(
        'Restoring purchases is not available with the current billing setup.',
      );
    }

    await _ensureRevenueCatAvailable(revenueCatGateway);
    await revenueCatGateway.restorePurchases();
    final resyncedPlan = await _resyncRevenueCatForRestore();
    final expectedProductsByPlan = {
      'STARTER': starterProductId,
      'PRO': productId,
    };
    _ensureRestorablePlan(resyncedPlan, expectedProductsByPlan.keys);

    return _readRevenueCatSubscription(
      expectedProductsByPlan: expectedProductsByPlan,
      operation: 'restore',
    );
  }

  Future<void> _ensureStoreAvailable() async {
    if (!await _gateway.isAvailable()) {
      throw const StoreSubscriptionException(
        'Store purchases are not available on this device.',
      );
    }
  }

  Future<List<StoreProductInfo>> _queryProducts(Set<String> productIds) async {
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      await _ensureRevenueCatAvailable(revenueCatGateway);
      return revenueCatGateway.queryProducts(productIds);
    }

    await _ensureStoreAvailable();
    return _gateway.queryProducts(productIds);
  }

  Future<void> _ensureRevenueCatAvailable(
    RevenueCatBillingGateway gateway,
  ) async {
    if (!await gateway.isAvailable()) {
      throw const StoreSubscriptionException(
        'Store purchases are not available on this device.',
      );
    }
  }

  Future<StoreSubscriptionVerificationResult> _startRevenueCatSubscription({
    required RevenueCatBillingGateway gateway,
    required String productId,
    required String expectedPlan,
  }) async {
    await _ensureRevenueCatAvailable(gateway);
    await gateway.buySubscription(productId);

    return _readRevenueCatSubscription(
      expectedProductsByPlan: {expectedPlan: productId},
      operation: 'purchase',
    );
  }

  Future<StoreSubscriptionVerificationResult> _restoreRevenueCatSubscription({
    required RevenueCatBillingGateway gateway,
    required String productId,
    required String expectedPlan,
  }) async {
    await _ensureRevenueCatAvailable(gateway);
    await gateway.restorePurchases();
    final resyncedPlan = await _resyncRevenueCatForRestore();
    _ensureRestorablePlan(resyncedPlan, {expectedPlan});

    return _readRevenueCatSubscription(
      expectedProductsByPlan: {expectedPlan: productId},
      operation: 'restore',
    );
  }

  Future<String> _resyncRevenueCatForRestore() async {
    try {
      return await _resyncRevenueCatSubscription();
    } on ApiException catch (error) {
      final code = error.code;
      final statusCode = error.statusCode;

      if (code == 'REVENUECAT_RESYNC_NOT_CONFIGURED' ||
          (code == null && statusCode == HttpStatus.notImplemented)) {
        throw const StoreSubscriptionException(
          'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง',
        );
      }

      if (code == 'REVENUECAT_ENTITLEMENT_NOT_MAPPED' ||
          (code == null && statusCode == HttpStatus.conflict)) {
        throw const StoreSubscriptionException(
          'พบรายการสมาชิกแล้ว แต่แพ็กเกจยังเชื่อมกับระบบไม่ถูกต้อง กรุณาติดต่อทีม PostDee',
        );
      }

      if (code == 'REVENUECAT_RESYNC_FAILED' ||
          (code == null && statusCode == HttpStatus.badGateway)) {
        throw const StoreSubscriptionException(
          'เชื่อมต่อระบบสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
        );
      }

      throw const StoreSubscriptionException(
        'กู้คืนการซื้อไม่สำเร็จ ลองใหม่อีกครั้ง',
      );
    }
  }

  void _ensureRestorablePlan(String plan, Iterable<String> expectedPlans) {
    final normalizedPlan = plan.toUpperCase();
    if (expectedPlans.any((expected) => expected == normalizedPlan)) {
      return;
    }

    throw const StoreSubscriptionException(
      'ไม่พบรายการสมาชิกที่กู้คืนได้ในบัญชีนี้',
    );
  }

  Future<StoreSubscriptionVerificationResult> _readRevenueCatSubscription({
    required Map<String, String> expectedProductsByPlan,
    required String operation,
  }) async {
    for (var attempt = 0;
        attempt < _revenueCatEntitlementPollAttempts;
        attempt += 1) {
      late final SubscriptionStatusResult subscription;

      try {
        subscription = await _loadSubscription();
      } catch (error) {
        final hasAnotherAttempt =
            attempt + 1 < _revenueCatEntitlementPollAttempts;
        if (!hasAnotherAttempt || !_isRetryableSubscriptionLoadError(error)) {
          rethrow;
        }

        await _revenueCatEntitlementWait(
          _revenueCatEntitlementPollInterval,
        );
        continue;
      }

      final productId = expectedProductsByPlan[subscription.plan.toUpperCase()];

      if (productId != null) {
        return StoreSubscriptionVerificationResult(
          purchase: StorePurchaseResult(
            provider: 'revenuecat',
            platform: 'REVENUECAT',
            productId: productId,
            verifiedAt: DateTime.now(),
          ),
          subscription: subscription,
        );
      }

      if (attempt + 1 < _revenueCatEntitlementPollAttempts) {
        await _revenueCatEntitlementWait(
          _revenueCatEntitlementPollInterval,
        );
      }
    }

    final expectedPlans = expectedProductsByPlan.keys.join(' or ');
    throw StoreSubscriptionException(
      'RevenueCat $operation completed, but PostDee has not received the '
      '$expectedPlans entitlement yet. Please try again in a moment.',
    );
  }

  bool _isRetryableSubscriptionLoadError(Object error) {
    if (error is ApiException) {
      final statusCode = error.statusCode;
      return statusCode == HttpStatus.requestTimeout ||
          statusCode == HttpStatus.tooManyRequests ||
          (statusCode != null && statusCode >= 500 && statusCode < 600);
    }

    return error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TimeoutException;
  }

  Future<StoreSubscriptionVerificationResult> _verifyPayload(
    StorePurchasePayload payload,
    String expectedProductId,
  ) {
    if (payload.productId != expectedProductId) {
      throw StoreSubscriptionException(
        'Store returned an unexpected product: ${payload.productId}',
      );
    }

    if (payload.platform == 'ANDROID') {
      final purchaseToken = payload.purchaseToken;

      if (purchaseToken == null || purchaseToken.isEmpty) {
        throw const StoreSubscriptionException(
          'Android purchase is missing a purchase token.',
        );
      }

      return _verifyPurchase(
        VerifyStorePurchaseRequest.android(
          productId: payload.productId,
          purchaseToken: purchaseToken,
        ),
      );
    }

    if (payload.platform == 'IOS') {
      final transactionId = payload.transactionId;

      if (transactionId == null || transactionId.isEmpty) {
        throw const StoreSubscriptionException(
          'iOS purchase is missing a transaction id.',
        );
      }

      return _verifyPurchase(
        VerifyStorePurchaseRequest.ios(
          productId: payload.productId,
          transactionId: transactionId,
        ),
      );
    }

    throw StoreSubscriptionException(
      'Unsupported store platform: ${payload.platform}',
    );
  }
}

RevenueCatBillingGateway? createRevenueCatBillingGatewayFromConfig() {
  if (!AppConfig.enableRevenueCatBilling) {
    return null;
  }

  return PurchasesRevenueCatBillingGateway(
    apiKey: AppConfig.revenueCatApiKey,
    androidApiKey: AppConfig.revenueCatAndroidApiKey,
    iosApiKey: AppConfig.revenueCatIosApiKey,
  );
}

class PurchasesRevenueCatBillingGateway implements RevenueCatBillingGateway {
  PurchasesRevenueCatBillingGateway({
    required this.apiKey,
    required this.androidApiKey,
    required this.iosApiKey,
    this.appUserIdProvider,
  });

  final String apiKey;
  final String androidApiKey;
  final String iosApiKey;
  final Future<String?> Function()? appUserIdProvider;

  @override
  Future<bool> isAvailable() async {
    await _ensureConfigured();
    return purchases.Purchases.canMakePayments();
  }

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async {
    await _ensureConfigured();
    final products = await purchases.Purchases.getProducts(productIds.toList());

    return products
        .map(
          (product) => StoreProductInfo(
            id: product.identifier,
            title: product.title,
            description: product.description,
            price: product.priceString,
          ),
        )
        .toList();
  }

  @override
  Future<void> buySubscription(String productId) async {
    await _ensureConfigured();
    final product = await _loadProduct(productId);

    try {
      await purchases.Purchases.purchase(
        purchases.PurchaseParams.storeProduct(product),
      );
    } on PlatformException catch (error) {
      throw StoreSubscriptionException(
        error.message ?? 'RevenueCat purchase failed.',
      );
    }
  }

  @override
  Future<void> restorePurchases() async {
    await _ensureConfigured();

    try {
      await purchases.Purchases.restorePurchases();
    } on PlatformException catch (error) {
      throw StoreSubscriptionException(
        error.message ?? 'RevenueCat restore failed.',
      );
    }
  }

  Future<purchases.StoreProduct> _loadProduct(String productId) async {
    final products = await purchases.Purchases.getProducts([productId]);
    final matchingProducts =
        products.where((product) => product.identifier == productId);

    if (matchingProducts.isEmpty) {
      throw StoreSubscriptionException(
        'RevenueCat product was not found: $productId',
      );
    }

    return matchingProducts.first;
  }

  Future<void> _ensureConfigured() async {
    final selectedApiKey = _apiKeyForCurrentPlatform();

    if (selectedApiKey.isEmpty) {
      throw const StoreSubscriptionException(
        'RevenueCat SDK key is missing. Add REVENUECAT_API_KEY or a platform-specific RevenueCat key.',
      );
    }

    final appUserId = await _readAppUserId();

    if (appUserId == null || appUserId.isEmpty) {
      throw const StoreSubscriptionException(
        'Sign in with Firebase before starting RevenueCat purchases.',
      );
    }

    if (!await purchases.Purchases.isConfigured) {
      if (!kReleaseMode) {
        await purchases.Purchases.setLogLevel(purchases.LogLevel.debug);
      }

      final configuration = purchases.PurchasesConfiguration(selectedApiKey)
        ..appUserID = appUserId;
      await purchases.Purchases.configure(configuration);
      return;
    }

    final currentAppUserId = await purchases.Purchases.appUserID;

    if (currentAppUserId != appUserId) {
      await purchases.Purchases.logIn(appUserId);
    }
  }

  String _apiKeyForCurrentPlatform() {
    final platformKey = switch (defaultTargetPlatform) {
      TargetPlatform.android => androidApiKey,
      TargetPlatform.iOS => iosApiKey,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        '',
    };
    final selected = platformKey.trim();

    if (selected.isNotEmpty) {
      return selected;
    }

    return apiKey.trim();
  }

  Future<String?> _readAppUserId() async {
    final provided = await appUserIdProvider?.call();
    final appUserId =
        provided ?? firebase_auth.FirebaseAuth.instance.currentUser?.uid.trim();

    return appUserId == null || appUserId.isEmpty ? null : appUserId;
  }
}

class InAppPurchaseStoreBillingGateway implements StoreBillingGateway {
  InAppPurchaseStoreBillingGateway({
    InAppPurchase? store,
    this.purchaseTimeout = const Duration(minutes: 2),
  }) : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;
  final Duration purchaseTimeout;

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async {
    final response = await _store.queryProductDetails(productIds);

    if (response.error != null) {
      throw StoreSubscriptionException(response.error!.message);
    }

    return response.productDetails
        .map(
          (product) => StoreProductInfo(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
          ),
        )
        .toList();
  }

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async {
    return _runPurchaseFlow(
      productId: productId,
      startFlow: () async {
        final product = await _loadProduct(productId);
        final started = await _store.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product),
        );

        if (!started) {
          throw const StoreSubscriptionException(
            'Store purchase flow did not start.',
          );
        }
      },
      acceptedStatuses: const {PurchaseStatus.purchased},
    );
  }

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async {
    return _runPurchaseFlow(
      productId: productId,
      startFlow: () => _store.restorePurchases(),
      acceptedStatuses: const {
        PurchaseStatus.purchased,
        PurchaseStatus.restored,
      },
    );
  }

  Future<ProductDetails> _loadProduct(String productId) async {
    final response = await _store.queryProductDetails({productId});

    if (response.error != null) {
      throw StoreSubscriptionException(response.error!.message);
    }

    if (response.productDetails.isEmpty) {
      throw StoreSubscriptionException(
        'Store product was not found: $productId',
      );
    }

    return response.productDetails.first;
  }

  Future<StorePurchasePayload> _runPurchaseFlow({
    required String productId,
    required Future<void> Function() startFlow,
    required Set<PurchaseStatus> acceptedStatuses,
  }) async {
    final completer = Completer<StorePurchasePayload>();
    late final StreamSubscription<List<PurchaseDetails>> subscription;

    subscription = _store.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID != productId || completer.isCompleted) {
            continue;
          }

          if (acceptedStatuses.contains(purchase.status)) {
            try {
              if (purchase.pendingCompletePurchase) {
                await _store.completePurchase(purchase);
              }

              completer.complete(_payloadFromPurchase(purchase));
            } catch (error) {
              completer.completeError(
                StoreSubscriptionException(
                  'Could not complete store purchase: $error',
                ),
              );
            }
            continue;
          }

          if (purchase.status == PurchaseStatus.error) {
            completer.completeError(
              StoreSubscriptionException(
                purchase.error?.message ?? 'Store purchase failed.',
              ),
            );
            continue;
          }

          if (purchase.status == PurchaseStatus.canceled) {
            completer.completeError(
              const StoreSubscriptionException('Store purchase was canceled.'),
            );
          }
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(
            StoreSubscriptionException('Store purchase stream failed: $error'),
          );
        }
      },
    );

    try {
      await startFlow();
      return await completer.future.timeout(
        purchaseTimeout,
        onTimeout: () => throw const StoreSubscriptionException(
          'Timed out waiting for the store purchase update.',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  StorePurchasePayload _payloadFromPurchase(PurchaseDetails purchase) {
    final platform = _currentStorePlatform();
    final serverVerificationData =
        purchase.verificationData.serverVerificationData;

    if (platform == 'ANDROID') {
      return StorePurchasePayload.android(
        productId: purchase.productID,
        purchaseToken: serverVerificationData,
      );
    }

    return StorePurchasePayload.ios(
      productId: purchase.productID,
      transactionId: purchase.purchaseID ?? serverVerificationData,
    );
  }

  String _currentStorePlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ANDROID';
      case TargetPlatform.iOS:
        return 'IOS';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        throw const StoreSubscriptionException(
          'Store subscriptions are supported on iOS and Android only.',
        );
    }
  }
}

class _UnavailableStoreBillingGateway implements StoreBillingGateway {
  const _UnavailableStoreBillingGateway();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async {
    throw const StoreSubscriptionException(
      'Store purchases are not available on this device.',
    );
  }

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async {
    throw const StoreSubscriptionException(
      'Store purchases are not available on this device.',
    );
  }
}
