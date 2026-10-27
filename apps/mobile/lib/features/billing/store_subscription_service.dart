import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/network/postdee_api_client.dart';

typedef StorePurchaseVerifier = Future<StoreSubscriptionVerificationResult>
    Function(VerifyStorePurchaseRequest request);
typedef SubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef SubscriptionWait = Future<void> Function(Duration duration);
typedef RevenueCatSubscriptionResync = Future<String> Function();
typedef SubscriptionPurchasePreparation = Future<void> Function();
typedef BoundSubscriptionApiClientFactory = PostDeeApiClient Function(
    AuthSessionBinding sessionBinding);

PostDeeApiClient _createBoundSubscriptionApiClient(AuthSessionBinding binding) =>
    PostDeeApiClient(authHeaders: PostDeeApiAuthHeaders(sessionBinding: binding));

class _RevenueCatOperation {
  const _RevenueCatOperation({
    required this.binding,
    required this.userId,
    required this.prepare,
    required this.load,
    required this.resync,
  });
  final AuthSessionBinding binding;
  final String? userId;
  final SubscriptionPurchasePreparation prepare;
  final SubscriptionLoader load;
  final RevenueCatSubscriptionResync resync;
}

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
    SubscriptionPurchasePreparation? prepareSubscriptionPurchase,
    PostDeeAuthSessionStore? sessionStore,
    BoundSubscriptionApiClientFactory? apiClientFactory,
  })  : assert(revenueCatEntitlementPollAttempts > 0),
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _apiClientFactory = apiClientFactory ?? _createBoundSubscriptionApiClient,
        _revenueCatEntitlementPollAttempts = revenueCatEntitlementPollAttempts,
        _revenueCatEntitlementPollInterval = revenueCatEntitlementPollInterval,
        _revenueCatEntitlementWait =
            revenueCatEntitlementWait ?? _defaultSubscriptionWait,
        _resyncRevenueCatSubscription = resyncRevenueCatSubscription,
        _prepareSubscriptionPurchase = prepareSubscriptionPurchase,
        _gateway = gateway ??
            (useRevenueCat
                ? const _UnavailableStoreBillingGateway()
                : InAppPurchaseStoreBillingGateway()),
        _revenueCatGateway = useRevenueCat
            ? revenueCatGateway ??
                createRevenueCatBillingGatewayFromConfig(
                  sessionStore: sessionStore,
                )
            : null,
        _loadSubscription = loadSubscription,
        _verifyPurchase =
            verifyPurchase ?? PostDeeApiClient().verifyStoreSubscription;

  final StoreBillingGateway _gateway;
  final RevenueCatBillingGateway? _revenueCatGateway;
  final StorePurchaseVerifier _verifyPurchase;
  final SubscriptionLoader? _loadSubscription;
  final PostDeeAuthSessionStore _sessionStore;
  final BoundSubscriptionApiClientFactory _apiClientFactory;
  final int _revenueCatEntitlementPollAttempts;
  final Duration _revenueCatEntitlementPollInterval;
  final SubscriptionWait _revenueCatEntitlementWait;
  final RevenueCatSubscriptionResync? _resyncRevenueCatSubscription;
  final SubscriptionPurchasePreparation? _prepareSubscriptionPurchase;
  final String productId;
  final String starterProductId;

  bool get supportsUnifiedRestore => _revenueCatGateway != null;

  _RevenueCatOperation _captureRevenueCatOperation() {
    final binding = _sessionStore.captureSession();
    final userId = _sessionStore.session.userId;
    final api = _apiClientFactory(binding);
    return _RevenueCatOperation(
      binding: binding,
      userId: userId,
      prepare: _prepareSubscriptionPurchase ?? api.prepareSubscriptionPurchase,
      load: _loadSubscription ?? api.loadCurrentSubscription,
      resync: _resyncRevenueCatSubscription ?? api.resyncRevenueCatSubscription,
    );
  }

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

    final operation = _captureRevenueCatOperation();
    operation.binding.ensureCurrent();
    await _ensureRevenueCatAvailable(revenueCatGateway);
    operation.binding.ensureCurrent();
    await revenueCatGateway.restorePurchases();
    operation.binding.ensureCurrent();
    final resyncedPlan = await _resyncRevenueCatForRestore(operation);
    final expectedProductsByPlan = {
      'STARTER': starterProductId,
      'PRO': productId,
    };
    _ensureRestorablePlan(resyncedPlan, expectedProductsByPlan.keys);

    return _readRevenueCatSubscription(
      expectedProductsByPlan: expectedProductsByPlan,
      operation: 'restore',
      sessionOperation: operation,
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
      final binding = _sessionStore.captureSession();
      await _ensureRevenueCatAvailable(revenueCatGateway);
      binding.ensureCurrent();
      final products = await revenueCatGateway.queryProducts(productIds);
      binding.ensureCurrent();
      return products;
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
    final operation = _captureRevenueCatOperation();
    operation.binding.ensureCurrent();
    await _ensureRevenueCatAvailable(gateway);
    operation.binding.ensureCurrent();
    await _prepareRevenueCatPurchase(operation);
    operation.binding.ensureCurrent();
    await gateway.buySubscription(productId);
    operation.binding.ensureCurrent();

    return _readRevenueCatSubscription(
      expectedProductsByPlan: {expectedPlan: productId},
      operation: 'purchase',
      sessionOperation: operation,
    );
  }

  Future<void> _prepareRevenueCatPurchase(_RevenueCatOperation operation) async {
    try {
      operation.binding.ensureCurrent();
      await operation.prepare();
      operation.binding.ensureCurrent();
    } on ApiException catch (error) {
      operation.binding.ensureCurrent();
      if (error.code == 'PURCHASE_READINESS_UNSUPPORTED' ||
          error.statusCode == HttpStatus.notFound ||
          error.statusCode == HttpStatus.notImplemented) {
        throw const StoreSubscriptionException(
          'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง',
        );
      }
      rethrow;
    }
  }

  Future<StoreSubscriptionVerificationResult> _restoreRevenueCatSubscription({
    required RevenueCatBillingGateway gateway,
    required String productId,
    required String expectedPlan,
  }) async {
    final operation = _captureRevenueCatOperation();
    operation.binding.ensureCurrent();
    await _ensureRevenueCatAvailable(gateway);
    operation.binding.ensureCurrent();
    await gateway.restorePurchases();
    operation.binding.ensureCurrent();
    final resyncedPlan = await _resyncRevenueCatForRestore(operation);
    _ensureRestorablePlan(resyncedPlan, {expectedPlan});

    return _readRevenueCatSubscription(
      expectedProductsByPlan: {expectedPlan: productId},
      operation: 'restore',
      sessionOperation: operation,
    );
  }

  Future<String> _resyncRevenueCatForRestore(
    _RevenueCatOperation operation,
  ) async {
    try {
      operation.binding.ensureCurrent();
      final plan = await operation.resync();
      operation.binding.ensureCurrent();
      return plan;
    } on ApiException catch (error) {
      operation.binding.ensureCurrent();
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
    required _RevenueCatOperation sessionOperation,
  }) async {
    for (var attempt = 0;
        attempt < _revenueCatEntitlementPollAttempts;
        attempt += 1) {
      late final SubscriptionStatusResult subscription;
      sessionOperation.binding.ensureCurrent();

      try {
        subscription = await sessionOperation.load();
        sessionOperation.binding.ensureCurrent();
      } catch (error) {
        sessionOperation.binding.ensureCurrent();
        final hasAnotherAttempt =
            attempt + 1 < _revenueCatEntitlementPollAttempts;
        if (!hasAnotherAttempt || !_isRetryableSubscriptionLoadError(error)) {
          rethrow;
        }

        await _revenueCatEntitlementWait(
          _revenueCatEntitlementPollInterval,
        );
        sessionOperation.binding.ensureCurrent();
        continue;
      }

      final expectedUserId = sessionOperation.userId;
      if (expectedUserId != null &&
          expectedUserId.trim().isNotEmpty &&
          subscription.userId != expectedUserId) {
        throw const StoreSubscriptionException(
          'Subscription does not belong to the account that started this operation.',
        );
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
        sessionOperation.binding.ensureCurrent();
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

RevenueCatBillingGateway? createRevenueCatBillingGatewayFromConfig({
  PostDeeAuthSessionStore? sessionStore,
}) {
  if (!AppConfig.enableRevenueCatBilling) {
    return null;
  }

  return PurchasesRevenueCatBillingGateway(
    apiKey: AppConfig.revenueCatApiKey,
    androidApiKey: AppConfig.revenueCatAndroidApiKey,
    iosApiKey: AppConfig.revenueCatIosApiKey,
    sessionStore: sessionStore,
  );
}

abstract class RevenueCatPurchasesSdk {
  Future<bool> get isConfigured;
  Future<String> get appUserId;
  Future<void> setDebugLogLevel();
  Future<void> configure(String apiKey, String appUserId);
  Future<void> logIn(String appUserId);
  Future<bool> canMakePayments();
  Future<List<purchases.StoreProduct>> getProducts(List<String> productIds);
  Future<void> purchase(purchases.StoreProduct product);
  Future<void> restorePurchases();
}

class _RevenueCatPurchasesSdk implements RevenueCatPurchasesSdk {
  const _RevenueCatPurchasesSdk();

  @override
  Future<bool> get isConfigured => purchases.Purchases.isConfigured;

  @override
  Future<String> get appUserId => purchases.Purchases.appUserID;

  @override
  Future<void> setDebugLogLevel() =>
      purchases.Purchases.setLogLevel(purchases.LogLevel.debug);

  @override
  Future<void> configure(String apiKey, String appUserId) =>
      purchases.Purchases.configure(
        purchases.PurchasesConfiguration(apiKey)..appUserID = appUserId,
      );

  @override
  Future<void> logIn(String appUserId) async {
    await purchases.Purchases.logIn(appUserId);
  }

  @override
  Future<bool> canMakePayments() => purchases.Purchases.canMakePayments();

  @override
  Future<List<purchases.StoreProduct>> getProducts(List<String> productIds) =>
      purchases.Purchases.getProducts(productIds);

  @override
  Future<void> purchase(purchases.StoreProduct product) async {
    await purchases.Purchases.purchase(
      purchases.PurchaseParams.storeProduct(product),
    );
  }

  @override
  Future<void> restorePurchases() async {
    await purchases.Purchases.restorePurchases();
  }
}

class PurchasesRevenueCatBillingGateway implements RevenueCatBillingGateway {
  PurchasesRevenueCatBillingGateway({
    required this.apiKey,
    required this.androidApiKey,
    required this.iosApiKey,
    this.appUserIdProvider,
    PostDeeAuthSessionStore? sessionStore,
    RevenueCatPurchasesSdk? sdk,
  }) : _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
       _sdk = sdk ?? const _RevenueCatPurchasesSdk();

  final String apiKey;
  final String androidApiKey;
  final String iosApiKey;
  final Future<String?> Function()? appUserIdProvider;
  final PostDeeAuthSessionStore _sessionStore;
  final RevenueCatPurchasesSdk _sdk;

  // RevenueCat's native identity is global. Keep configuration through the
  // terminal purchase/restore callback serialized across gateway instances.
  // A dispatched native operation cannot be canceled on a session change.
  static Future<void> _sdkQueue = Future<void>.value();

  Future<T> _runWithSession<T>(
    Future<T> Function(AuthSessionBinding binding, String userId) operation,
  ) async {
    final binding = _sessionStore.captureSession();
    final session = _sessionStore.session;
    final userId = session.userId;
    if (!session.isSignedIn || userId == null || userId.trim().isEmpty) {
      throw const StoreSubscriptionException(
        'Sign in with Firebase before starting RevenueCat purchases.',
      );
    }
    final result = _sdkQueue.then((_) async {
      binding.ensureCurrent();
      try {
        final value = await operation(binding, userId);
        binding.ensureCurrent();
        return value;
      } catch (_) {
        binding.ensureCurrent();
        rethrow;
      }
    });
    _sdkQueue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<bool> isAvailable() => _runWithSession((binding, userId) async {
        await _ensureConfigured(binding, userId);
        binding.ensureCurrent();
        final available = await _sdk.canMakePayments();
        binding.ensureCurrent();
        return available;
      });

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) =>
      _runWithSession((binding, userId) async {
        await _ensureConfigured(binding, userId);
        binding.ensureCurrent();
        final products = await _sdk.getProducts(productIds.toList());
        binding.ensureCurrent();

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
      });

  @override
  Future<void> buySubscription(String productId) =>
      _runWithSession((binding, userId) async {
        await _ensureConfigured(binding, userId);
        binding.ensureCurrent();
        final product = await _loadProduct(productId, binding);
        binding.ensureCurrent();

        try {
          await _sdk.purchase(product);
          binding.ensureCurrent();
        } on PlatformException catch (error) {
          binding.ensureCurrent();
          throw StoreSubscriptionException(
            error.message ?? 'RevenueCat purchase failed.',
          );
        }
      });

  @override
  Future<void> restorePurchases() => _runWithSession((binding, userId) async {
        await _ensureConfigured(binding, userId);
        binding.ensureCurrent();

        try {
          await _sdk.restorePurchases();
          binding.ensureCurrent();
        } on PlatformException catch (error) {
          binding.ensureCurrent();
          throw StoreSubscriptionException(
            error.message ?? 'RevenueCat restore failed.',
          );
        }
      });

  Future<purchases.StoreProduct> _loadProduct(
    String productId,
    AuthSessionBinding binding,
  ) async {
    binding.ensureCurrent();
    final products = await _sdk.getProducts([productId]);
    binding.ensureCurrent();
    final matchingProducts =
        products.where((product) => product.identifier == productId);

    if (matchingProducts.isEmpty) {
      throw StoreSubscriptionException(
        'RevenueCat product was not found: $productId',
      );
    }

    return matchingProducts.first;
  }

  Future<void> _ensureConfigured(
    AuthSessionBinding binding,
    String appUserId,
  ) async {
    binding.ensureCurrent();
    final selectedApiKey = _apiKeyForCurrentPlatform();

    if (selectedApiKey.isEmpty) {
      throw const StoreSubscriptionException(
        'RevenueCat SDK key is missing. Add REVENUECAT_API_KEY or a platform-specific RevenueCat key.',
      );
    }

    // Retain the injection seam as a consistency check, never as a source of a
    // later account's UID. Identity comes from the session captured at admission.
    final provider = appUserIdProvider;
    if (provider != null) {
      final providedUserId = await provider();
      binding.ensureCurrent();
      if (providedUserId != appUserId) {
        throw const StoreSubscriptionException(
          'RevenueCat identity does not match the account that started this operation.',
        );
      }
    }

    final isConfigured = await _sdk.isConfigured;
    binding.ensureCurrent();
    if (!isConfigured) {
      if (!kReleaseMode) {
        await _sdk.setDebugLogLevel();
        binding.ensureCurrent();
      }

      await _sdk.configure(selectedApiKey, appUserId);
      binding.ensureCurrent();
      return;
    }

    final currentAppUserId = await _sdk.appUserId;
    binding.ensureCurrent();

    if (currentAppUserId != appUserId) {
      await _sdk.logIn(appUserId);
      binding.ensureCurrent();
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
