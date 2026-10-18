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
    PostDeeApiClient(sessionBinding: binding);

class _BillingOperation {
  const _BillingOperation({
    required this.binding,
    required this.userId,
    required this.prepare,
    required this.load,
    required this.resync,
    required this.verify,
  });

  final AuthSessionBinding binding;
  final String? userId;
  final SubscriptionPurchasePreparation prepare;
  final SubscriptionLoader load;
  final RevenueCatSubscriptionResync resync;
  final StorePurchaseVerifier verify;
}

Future<void> _defaultSubscriptionWait(Duration duration) =>
    Future<void>.delayed(duration);

class _StoreOperationWaitExpired implements Exception {
  const _StoreOperationWaitExpired();
}

class StoreSubscriptionException implements Exception {
  const StoreSubscriptionException(this.message);

  final String message;

  @override
  String toString() => 'StoreSubscriptionException: $message';
}

class StoreSubscriptionStorePendingException
    extends StoreSubscriptionException {
  const StoreSubscriptionStorePendingException()
      : super('ยังไม่ทราบผลจากร้านค้า กรุณาตรวจสอบรายการเดิมก่อนซื้อซ้ำ');
}

class StoreSubscriptionConfirmationPendingException
    extends StoreSubscriptionException {
  const StoreSubscriptionConfirmationPendingException({this.cause})
      : super(
          'ร้านค้าดำเนินการซื้อแล้ว แต่ PostDee ยังยืนยันแพ็กเกจไม่ได้ กรุณาตรวจสอบการซื้ออีกครั้งโดยไม่ต้องซื้อซ้ำ',
        );

  final Object? cause;
}

class _PendingSubscriptionConfirmation {
  _PendingSubscriptionConfirmation({
    required this.productId,
    required this.confirm,
    required this.operation,
  });

  final String productId;
  final Future<StoreSubscriptionVerificationResult> Function() confirm;
  final _BillingOperation operation;
  Future<StoreSubscriptionVerificationResult>? inFlight;
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

/// Rechecks the native store's existing transaction without starting a buy.
abstract interface class PendingNativePurchaseReconciler {
  bool get hasPendingAcknowledgement;
  Future<void> reconcilePendingPurchase();
}

abstract class RevenueCatBillingGateway {
  Future<bool> isAvailable();
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds);
  Future<void> buySubscription(String productId);
  Future<void> restorePurchases();
}

/// Retains unfinished purchases for one signed-in user in memory only.
class StoreSubscriptionSessionCache {
  StoreSubscriptionSessionCache({
    PostDeeAuthSessionStore? sessionStore,
    StoreSubscriptionService Function()? createService,
  })  : _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _createService = createService ??
            (() => StoreSubscriptionService(sessionStore: sessionStore)) {
    _sessionStore.addListener(_handleSessionChanged);
  }

  static final instance = StoreSubscriptionSessionCache();
  final PostDeeAuthSessionStore _sessionStore;
  final StoreSubscriptionService Function() _createService;
  StoreSubscriptionService? _cachedService;
  String? _cachedOwner;
  AuthSessionBinding? _cachedBinding;
  var _generation = 0;

  String? get _currentOwner => _sessionStore.session.isSignedIn
      ? _sessionStore.session.stableUserId
      : null;

  StoreSubscriptionService get service {
    final owner = _currentOwner;
    if (_cachedOwner != owner || !(_cachedBinding?.isCurrent ?? true)) {
      _invalidateCachedService();
    }
    if (owner == null) return _newService(owner);
    _cachedOwner = owner;
    return _cachedService ??= _newService(owner);
  }

  StoreSubscriptionService _newService(String? owner) {
    final generation = _generation;
    final originalSession = _sessionStore.session;
    final binding = _sessionStore.captureSession();
    _cachedBinding = binding;
    final service = _createService();
    service._sessionStore = _sessionStore;
    service._sessionValidator = () =>
        _generation == generation &&
        binding.isCurrent &&
        (owner == null
            ? identical(_sessionStore.session, originalSession)
            : _currentOwner == owner);
    return service;
  }

  void _handleSessionChanged() {
    if (_currentOwner != _cachedOwner || !(_cachedBinding?.isCurrent ?? true)) {
      _invalidateCachedService();
    }
  }

  void _invalidateCachedService() {
    _generation += 1;
    _cachedService?._invalidateSession();
    _cachedService = null;
    _cachedOwner = null;
    _cachedBinding = null;
  }

  void dispose() {
    _sessionStore.removeListener(_handleSessionChanged);
    _invalidateCachedService();
  }
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
    this.subscriptionConfirmationTimeout = const Duration(seconds: 30),
    this.storeOperationTimeout = const Duration(minutes: 2),
    this.productQueryTimeout = const Duration(seconds: 10),
  })  : assert(revenueCatEntitlementPollAttempts > 0),
        assert(subscriptionConfirmationTimeout > Duration.zero),
        assert(storeOperationTimeout > Duration.zero),
        assert(productQueryTimeout > Duration.zero),
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
        _verifyPurchase = verifyPurchase;

  final StoreBillingGateway _gateway;
  final RevenueCatBillingGateway? _revenueCatGateway;
  final StorePurchaseVerifier? _verifyPurchase;
  final SubscriptionLoader? _loadSubscription;
  PostDeeAuthSessionStore _sessionStore;
  final BoundSubscriptionApiClientFactory _apiClientFactory;
  final int _revenueCatEntitlementPollAttempts;
  final Duration _revenueCatEntitlementPollInterval;
  final SubscriptionWait _revenueCatEntitlementWait;
  final RevenueCatSubscriptionResync? _resyncRevenueCatSubscription;
  final SubscriptionPurchasePreparation? _prepareSubscriptionPurchase;
  final String productId;
  final String starterProductId;
  final Duration subscriptionConfirmationTimeout;
  final Duration storeOperationTimeout;
  final Duration productQueryTimeout;
  Future<StoreSubscriptionVerificationResult>? _storeOperation;
  AuthSessionBinding? _storeOperationBinding;
  AuthSessionBinding? _nativeOperationBinding;
  _PendingSubscriptionConfirmation? _pendingConfirmation;
  bool Function()? _sessionValidator;
  var _sessionInvalidated = false;

  bool get supportsUnifiedRestore => _revenueCatGateway != null;
  bool get _isSessionValid =>
      !_sessionInvalidated && (_sessionValidator?.call() ?? true);
  bool get hasPendingConfirmation {
    if (!_isSessionValid ||
        !(_pendingConfirmation?.operation.binding.isCurrent ?? true) ||
        !(_storeOperationBinding?.isCurrent ?? true) ||
        !(_nativeOperationBinding?.isCurrent ?? true)) {
      _pendingConfirmation = null;
      _storeOperation = null;
      _storeOperationBinding = null;
    }
    return _pendingConfirmation != null || _storeOperation != null;
  }

  bool get hasPendingStoreOperation =>
      hasPendingConfirmation &&
      _storeOperation != null &&
      _pendingConfirmation == null;
  bool get hasPendingStoreAcknowledgement =>
      _isSessionValid &&
      (_nativeOperationBinding?.isCurrent ?? true) &&
      _revenueCatGateway == null &&
      _gateway is PendingNativePurchaseReconciler &&
      (_gateway as PendingNativePurchaseReconciler).hasPendingAcknowledgement;

  void _invalidateSession() {
    _sessionInvalidated = true;
    _pendingConfirmation = null;
    _storeOperation = null;
    _storeOperationBinding = null;
  }

  void _ensureSessionActive() {
    if (!_isSessionValid) {
      _pendingConfirmation = null;
      _storeOperation = null;
      _storeOperationBinding = null;
      throw const StoreSubscriptionException(
        'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่',
      );
    }
  }

  _BillingOperation _captureOperation() {
    _ensureSessionActive();
    final binding = _sessionStore.captureSession();
    final userId = _sessionStore.session.userId;
    final api = _apiClientFactory(binding);
    binding.ensureCurrent();
    return _BillingOperation(
      binding: binding,
      userId: userId,
      prepare: _prepareSubscriptionPurchase ?? api.prepareSubscriptionPurchase,
      load: _loadSubscription ?? api.loadCurrentSubscription,
      resync: _resyncRevenueCatSubscription ??
          api.resyncRevenueCatPurchasedSubscription,
      verify: _verifyPurchase ?? api.verifyStoreSubscription,
    );
  }

  void _ensureOperationCurrent(_BillingOperation operation) {
    _ensureSessionActive();
    if (!operation.binding.isCurrent) {
      if (identical(_pendingConfirmation?.operation, operation)) {
        _pendingConfirmation = null;
      }
    }
    operation.binding.ensureCurrent();
  }

  void _ensureSubscriptionOwner(
    SubscriptionStatusResult subscription,
    _BillingOperation operation,
  ) {
    final userId = operation.userId;
    if (userId != null &&
        userId.trim().isNotEmpty &&
        subscription.userId != userId) {
      throw const StoreSubscriptionException(
        'Subscription does not belong to the account that started this operation.',
      );
    }
  }

  Future<StoreSubscriptionVerificationResult> retryPendingConfirmation() async {
    _ensureSessionActive();
    _nativeOperationBinding?.ensureCurrent();
    final operation = _storeOperation;
    if (operation != null) {
      final binding = _storeOperationBinding!;
      binding.ensureCurrent();
      if (_pendingConfirmation == null &&
          _revenueCatGateway == null &&
          _gateway is PendingNativePurchaseReconciler) {
        // Store reconciliation can emit a terminal event into the original
        // operation; continue verifying that same future and receipt once.
        await (_gateway as PendingNativePurchaseReconciler)
            .reconcilePendingPurchase()
            .timeout(productQueryTimeout)
            .catchError((_) {});
        binding.ensureCurrent();
      }
      return _awaitStoreOperation(operation, binding: binding);
    }
    return _retryReceiptConfirmation();
  }

  Future<StoreSubscriptionVerificationResult>
      _retryReceiptConfirmation() async {
    _ensureSessionActive();
    final pending = _pendingConfirmation;
    if (pending == null) {
      throw const StoreSubscriptionException('ไม่มีรายการซื้อที่รอยืนยัน');
    }
    _ensureOperationCurrent(pending.operation);

    // Share any unfinished verification so a retry cannot submit the same
    // receipt concurrently after the UI deadline expires.
    var confirmation = pending.inFlight;
    if (confirmation == null) {
      confirmation = Future<StoreSubscriptionVerificationResult>.sync(
        pending.confirm,
      );
      pending.inFlight = confirmation;
      final currentConfirmation = confirmation;
      void clearInFlight() {
        if (identical(pending.inFlight, currentConfirmation)) {
          pending.inFlight = null;
        }
      }

      confirmation.then<void>(
        (_) => clearInFlight(),
        onError: (Object _, StackTrace __) => clearInFlight(),
      );
    }

    try {
      final result =
          await confirmation.timeout(subscriptionConfirmationTimeout);
      _ensureOperationCurrent(pending.operation);
      if (identical(_pendingConfirmation, pending)) {
        _pendingConfirmation = null;
      }
      if (hasPendingStoreAcknowledgement && _storeOperation == null) {
        // Keep this verified result available while the native acknowledgement
        // is retried, without submitting its receipt for verification again.
        _storeOperation = Future.value(result);
        _storeOperationBinding = pending.operation.binding;
      }
      return result;
    } catch (error) {
      _ensureOperationCurrent(pending.operation);
      throw StoreSubscriptionConfirmationPendingException(cause: error);
    }
  }

  void _ensureNoPendingPurchase() {
    _ensureSessionActive();
    _nativeOperationBinding?.ensureCurrent();
    if (_storeOperation != null) {
      throw const StoreSubscriptionStorePendingException();
    }
    if (hasPendingConfirmation) {
      throw const StoreSubscriptionConfirmationPendingException();
    }
  }

  Future<StoreSubscriptionVerificationResult> _confirmCompletedPurchase({
    required String productId,
    required Future<StoreSubscriptionVerificationResult> Function() confirm,
    required _BillingOperation operation,
  }) {
    _ensureOperationCurrent(operation);
    _pendingConfirmation = _PendingSubscriptionConfirmation(
      productId: productId,
      confirm: confirm,
      operation: operation,
    );
    return _retryReceiptConfirmation();
  }

  Future<StoreSubscriptionVerificationResult> _runStoreOperation(
    Future<StoreSubscriptionVerificationResult> Function() operation,
  ) {
    _ensureSessionActive();
    _nativeOperationBinding?.ensureCurrent();
    final running = _storeOperation;
    if (running != null) {
      return _awaitStoreOperation(running, binding: _storeOperationBinding!);
    }
    final binding = _sessionStore.captureSession();
    _nativeOperationBinding ??= binding;
    final future = Future<StoreSubscriptionVerificationResult>.sync(operation);
    _storeOperation = future;
    _storeOperationBinding = binding;
    return _awaitStoreOperation(future, binding: binding);
  }

  Future<StoreSubscriptionVerificationResult> _awaitStoreOperation(
    Future<StoreSubscriptionVerificationResult> operation, {
    required AuthSessionBinding binding,
  }) async {
    _ensureSessionActive();
    binding.ensureCurrent();
    try {
      final result = await operation.timeout(storeOperationTimeout,
          onTimeout: () => throw const _StoreOperationWaitExpired());
      _ensureSessionActive();
      binding.ensureCurrent();
      if (identical(_storeOperation, operation) &&
          !hasPendingStoreAcknowledgement) {
        _storeOperation = null;
        _storeOperationBinding = null;
      }
      return result;
    } on _StoreOperationWaitExpired {
      _ensureSessionActive();
      binding.ensureCurrent();
      // Keep the actual SDK future: a UI timeout cannot cancel a store purchase.
      throw const StoreSubscriptionStorePendingException();
    } catch (_) {
      if (identical(_storeOperation, operation)) {
        _storeOperation = null;
        _storeOperationBinding = null;
      }
      _ensureSessionActive();
      binding.ensureCurrent();
      rethrow;
    }
  }

  Future<List<StoreProductInfo>> loadPaidProducts() async {
    return _queryProducts({starterProductId, productId});
  }

  StoreSubscriptionVerificationResult _recordRestoredSubscription(
    StoreSubscriptionVerificationResult result,
  ) {
    _ensureSessionActive();
    if (_pendingConfirmation?.productId == result.purchase.productId) {
      _pendingConfirmation = null;
    }
    return result;
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
    _ensureNoPendingPurchase();
    return _runStoreOperation(_startStarterSubscription);
  }

  Future<StoreSubscriptionVerificationResult>
      _startStarterSubscription() async {
    final operation = _captureOperation();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _startRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: starterProductId,
        expectedPlan: 'STARTER',
        operation: operation,
      );
    }

    await _ensureStoreAvailable();
    _ensureOperationCurrent(operation);
    final payload = await _gateway.buySubscription(starterProductId);
    _ensureOperationCurrent(operation);

    return _confirmCompletedPurchase(
      productId: starterProductId,
      confirm: () => _verifyPayload(payload, starterProductId, operation),
      operation: operation,
    );
  }

  Future<StoreSubscriptionVerificationResult> startProSubscription() async {
    _ensureNoPendingPurchase();
    return _runStoreOperation(_startProSubscription);
  }

  Future<StoreSubscriptionVerificationResult> _startProSubscription() async {
    final operation = _captureOperation();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _startRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: productId,
        expectedPlan: 'PRO',
        operation: operation,
      );
    }

    await _ensureStoreAvailable();
    _ensureOperationCurrent(operation);
    final payload = await _gateway.buySubscription(productId);
    _ensureOperationCurrent(operation);

    return _confirmCompletedPurchase(
      productId: productId,
      confirm: () => _verifyPayload(payload, productId, operation),
      operation: operation,
    );
  }

  Future<StoreSubscriptionVerificationResult>
      restoreStarterSubscription() async {
    return _runStoreOperation(_restoreStarterSubscription);
  }

  Future<StoreSubscriptionVerificationResult>
      _restoreStarterSubscription() async {
    _ensureSessionActive();
    final operation = _captureOperation();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _restoreRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: starterProductId,
        expectedPlan: 'STARTER',
        operation: operation,
      );
    }

    await _ensureStoreAvailable();
    _ensureOperationCurrent(operation);
    final payload = await _gateway.restoreSubscription(starterProductId);
    _ensureOperationCurrent(operation);

    return _recordRestoredSubscription(
      await _verifyPayload(payload, starterProductId, operation),
    );
  }

  Future<StoreSubscriptionVerificationResult> restoreProSubscription() async {
    return _runStoreOperation(_restoreProSubscription);
  }

  Future<StoreSubscriptionVerificationResult> _restoreProSubscription() async {
    _ensureSessionActive();
    final operation = _captureOperation();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      return _restoreRevenueCatSubscription(
        gateway: revenueCatGateway,
        productId: productId,
        expectedPlan: 'PRO',
        operation: operation,
      );
    }

    await _ensureStoreAvailable();
    _ensureOperationCurrent(operation);
    final payload = await _gateway.restoreSubscription(productId);
    _ensureOperationCurrent(operation);

    return _recordRestoredSubscription(
      await _verifyPayload(payload, productId, operation),
    );
  }

  Future<StoreSubscriptionVerificationResult> restoreSubscription() async {
    return _runStoreOperation(_restoreSubscription);
  }

  Future<StoreSubscriptionVerificationResult> _restoreSubscription() async {
    _ensureSessionActive();
    final operation = _captureOperation();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway == null) {
      throw const StoreSubscriptionException(
        'Restoring purchases is not available with the current billing setup.',
      );
    }

    await _ensureRevenueCatAvailable(revenueCatGateway);
    _ensureOperationCurrent(operation);
    await revenueCatGateway.restorePurchases();
    _ensureOperationCurrent(operation);
    final resyncedPlan = await _resyncRevenueCatForRestore(operation);
    final expectedProductsByPlan = {
      'STARTER': starterProductId,
      'PRO': productId,
    };
    _ensureRestorablePlan(resyncedPlan, expectedProductsByPlan.keys);

    return _recordRestoredSubscription(
      await _readRevenueCatSubscription(
        expectedProductsByPlan: expectedProductsByPlan,
        operation: 'restore',
        sessionOperation: operation,
      ),
    );
  }

  Future<void> _ensureStoreAvailable() async {
    _ensureSessionActive();
    final available = await _gateway.isAvailable();
    _ensureSessionActive();
    if (!available) {
      throw const StoreSubscriptionException(
        'Store purchases are not available on this device.',
      );
    }
  }

  Future<List<StoreProductInfo>> _queryProducts(Set<String> productIds) async {
    _ensureSessionActive();
    final binding = _sessionStore.captureSession();
    final revenueCatGateway = _revenueCatGateway;

    if (revenueCatGateway != null) {
      await _ensureRevenueCatAvailable(revenueCatGateway);
      binding.ensureCurrent();
      final products = await revenueCatGateway.queryProducts(productIds);
      _ensureSessionActive();
      binding.ensureCurrent();
      return products;
    }

    await _ensureStoreAvailable();
    binding.ensureCurrent();
    final products = await _gateway.queryProducts(productIds);
    _ensureSessionActive();
    binding.ensureCurrent();
    return products;
  }

  Future<void> _ensureRevenueCatAvailable(
    RevenueCatBillingGateway gateway,
  ) async {
    _ensureSessionActive();
    final available = await gateway.isAvailable();
    _ensureSessionActive();
    if (!available) {
      throw const StoreSubscriptionException(
        'Store purchases are not available on this device.',
      );
    }
  }

  Future<StoreSubscriptionVerificationResult> _startRevenueCatSubscription({
    required RevenueCatBillingGateway gateway,
    required String productId,
    required String expectedPlan,
    required _BillingOperation operation,
  }) async {
    _ensureOperationCurrent(operation);
    await _ensureRevenueCatAvailable(gateway);
    _ensureOperationCurrent(operation);
    await _prepareRevenueCatPurchase(operation);
    _ensureOperationCurrent(operation);
    await gateway.buySubscription(productId);
    _ensureOperationCurrent(operation);

    return _confirmCompletedPurchase(
      productId: productId,
      operation: operation,
      confirm: () => _readRevenueCatSubscription(
        expectedProductsByPlan: {expectedPlan: productId},
        operation: 'purchase',
        sessionOperation: operation,
      ),
    );
  }

  Future<StoreSubscriptionVerificationResult> _restoreRevenueCatSubscription({
    required RevenueCatBillingGateway gateway,
    required String productId,
    required String expectedPlan,
    required _BillingOperation operation,
  }) async {
    _ensureOperationCurrent(operation);
    await _ensureRevenueCatAvailable(gateway);
    _ensureOperationCurrent(operation);
    await gateway.restorePurchases();
    _ensureOperationCurrent(operation);
    final resyncedPlan = await _resyncRevenueCatForRestore(operation);
    _ensureRestorablePlan(resyncedPlan, {expectedPlan});

    return _recordRestoredSubscription(
      await _readRevenueCatSubscription(
        expectedProductsByPlan: {expectedPlan: productId},
        operation: 'restore',
        sessionOperation: operation,
      ),
    );
  }

  Future<void> _prepareRevenueCatPurchase(_BillingOperation operation) async {
    _ensureOperationCurrent(operation);
    try {
      await operation.prepare();
      _ensureOperationCurrent(operation);
    } on ApiException catch (error) {
      _ensureOperationCurrent(operation);
      if (error.statusCode == HttpStatus.notFound ||
          error.statusCode == HttpStatus.notImplemented ||
          error.code == 'PURCHASE_READINESS_UNSUPPORTED') {
        throw const StoreSubscriptionException(
          'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง',
        );
      }
      rethrow;
    }
  }

  Future<String> _resyncRevenueCatForRestore(_BillingOperation operation) async {
    _ensureOperationCurrent(operation);
    try {
      final plan = await operation.resync();
      _ensureOperationCurrent(operation);
      return plan;
    } on ApiException catch (error) {
      _ensureOperationCurrent(operation);
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
    required _BillingOperation sessionOperation,
  }) async {
    final elapsed = Stopwatch()..start();
    Duration remainingTime() {
      final remaining = subscriptionConfirmationTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Timed out confirming the subscription.');
      }
      return remaining;
    }

    for (var attempt = 0;
        attempt < _revenueCatEntitlementPollAttempts;
        attempt += 1) {
      _ensureOperationCurrent(sessionOperation);
      late final SubscriptionStatusResult subscription;

      try {
        final remaining = remainingTime();
        subscription = await sessionOperation.load().timeout(remaining);
        _ensureOperationCurrent(sessionOperation);
      } catch (error) {
        _ensureOperationCurrent(sessionOperation);
        final hasAnotherAttempt =
            attempt + 1 < _revenueCatEntitlementPollAttempts;
        if (!hasAnotherAttempt ||
            elapsed.elapsed >= subscriptionConfirmationTimeout ||
            !_isRetryableSubscriptionLoadError(error)) {
          rethrow;
        }

        final remaining = remainingTime();
        await _revenueCatEntitlementWait(
          _revenueCatEntitlementPollInterval,
        ).timeout(remaining);
        _ensureOperationCurrent(sessionOperation);
        continue;
      }

      _ensureSubscriptionOwner(subscription, sessionOperation);
      final purchasePlan = subscription.purchasedPlan ?? subscription.plan;
      final productId = expectedProductsByPlan[purchasePlan.toUpperCase()];

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
        final remaining = remainingTime();
        await _revenueCatEntitlementWait(
          _revenueCatEntitlementPollInterval,
        ).timeout(remaining);
        _ensureOperationCurrent(sessionOperation);
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
    _BillingOperation operation,
  ) async {
    _ensureOperationCurrent(operation);
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

      final result = await operation.verify(
        VerifyStorePurchaseRequest.android(
          productId: payload.productId,
          purchaseToken: purchaseToken,
        ),
      );
      _ensureOperationCurrent(operation);
      _ensureSubscriptionOwner(result.subscription, operation);
      return result;
    }

    if (payload.platform == 'IOS') {
      final transactionId = payload.transactionId;

      if (transactionId == null || transactionId.isEmpty) {
        throw const StoreSubscriptionException(
          'iOS purchase is missing a transaction id.',
        );
      }

      final result = await operation.verify(
        VerifyStorePurchaseRequest.ios(
          productId: payload.productId,
          transactionId: transactionId,
        ),
      );
      _ensureOperationCurrent(operation);
      _ensureSubscriptionOwner(result.subscription, operation);
      return result;
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
  })  : _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
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

class InAppPurchaseStoreBillingGateway
    implements StoreBillingGateway, PendingNativePurchaseReconciler {
  InAppPurchaseStoreBillingGateway({
    InAppPurchase? store,
    this.purchaseTimeout = const Duration(minutes: 2),
    this.acknowledgementTimeout = const Duration(seconds: 5),
  }) : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  /// Kept for source compatibility. The service owns UI deadlines; this gateway
  /// must keep listening while the native store still has an unknown result.
  final Duration purchaseTimeout;
  final Duration acknowledgementTimeout;
  Future<StorePurchasePayload>? _activeOperation;
  String? _activeProductId;
  Set<PurchaseStatus>? _activeStatuses;
  Future<void>? _reconciliationFuture;
  final Map<String, PurchaseDetails> _pendingAcknowledgements = {};
  final Map<String, Future<void>> _acknowledgementOperations = {};
  @override
  bool get hasPendingAcknowledgement => _pendingAcknowledgements.isNotEmpty;

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
    if (_activeOperation != null || _pendingAcknowledgements.isNotEmpty) {
      throw const StoreSubscriptionStorePendingException();
    }
    return _retainPurchaseFlow(
      productId: productId,
      startFlow: () async {
        final product = await _loadProduct(productId);
        late final bool started;
        try {
          started = await _store.buyNonConsumable(
            purchaseParam: PurchaseParam(productDetails: product),
          );
        } catch (_) {
          // The request may have reached the store. Its purchase stream or a
          // later reconciliation must determine the outcome before buying again.
          return;
        }

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
    final active = _activeOperation;
    if (active != null) {
      if (_activeProductId != productId) {
        throw const StoreSubscriptionStorePendingException();
      }
      unawaited(reconcilePendingPurchase().catchError((_) {}));
      return active;
    }
    return _retainPurchaseFlow(
      productId: productId,
      startFlow: () async {
        await _retryAcknowledgements();
        try {
          await _store.restorePurchases();
        } catch (_) {
          // A transport error does not prove that the store has no transaction.
        }
      },
      acceptedStatuses: const {
        PurchaseStatus.purchased,
        PurchaseStatus.restored,
      },
    );
  }

  Future<StorePurchasePayload> _retainPurchaseFlow({
    required String productId,
    required Future<void> Function() startFlow,
    required Set<PurchaseStatus> acceptedStatuses,
  }) {
    final statuses = Set<PurchaseStatus>.of(acceptedStatuses);
    _activeProductId = productId;
    _activeStatuses = statuses;
    late final Future<StorePurchasePayload> operation;
    operation = _runPurchaseFlow(
      productId: productId,
      startFlow: startFlow,
      acceptedStatuses: statuses,
    ).whenComplete(() {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
        _activeProductId = null;
        _activeStatuses = null;
      }
    });
    _activeOperation = operation;
    return operation;
  }

  @override
  Future<void> reconcilePendingPurchase() {
    final running = _reconciliationFuture;
    if (running != null) return running;
    _activeStatuses?.add(PurchaseStatus.restored);
    late final Future<void> operation;
    operation = (() async {
      await _retryAcknowledgements();
      await _store.restorePurchases();
    })()
        .whenComplete(() {
      if (identical(_reconciliationFuture, operation)) {
        _reconciliationFuture = null;
      }
    });
    _reconciliationFuture = operation;
    return operation;
  }

  String _receiptKey(PurchaseDetails purchase) =>
      '${purchase.productID}:${purchase.purchaseID ?? purchase.verificationData.serverVerificationData}';

  Future<void> _acknowledge(PurchaseDetails purchase) {
    final key = _receiptKey(purchase);
    final running = _acknowledgementOperations[key];
    if (running != null) return running;
    _pendingAcknowledgements[key] = purchase;
    late final Future<void> operation;
    operation = Future<void>.sync(() => _store.completePurchase(purchase))
        .then<void>((_) {
      _pendingAcknowledgements.remove(key);
    }).whenComplete(() {
      if (identical(_acknowledgementOperations[key], operation)) {
        _acknowledgementOperations.remove(key);
      }
    });
    _acknowledgementOperations[key] = operation;
    return operation;
  }

  Future<void> _retryAcknowledgements() async {
    for (final purchase in _pendingAcknowledgements.values.toList()) {
      try {
        await _acknowledge(purchase);
      } catch (_) {
        // Keep this known receipt for another explicit reconciliation attempt.
      }
    }
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
    var isHandlingTerminal = false;
    late final StreamSubscription<List<PurchaseDetails>> subscription;

    subscription = _store.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID != productId ||
              completer.isCompleted ||
              isHandlingTerminal) {
            continue;
          }

          if (acceptedStatuses.contains(purchase.status)) {
            isHandlingTerminal = true;
            try {
              if (purchase.pendingCompletePurchase) {
                try {
                  await _acknowledge(purchase).timeout(acknowledgementTimeout);
                } catch (_) {
                  // A purchased/restored receipt is still available to verify.
                  // Keep its acknowledgement queued and never start a second buy.
                }
              }

              completer.complete(_payloadFromPurchase(purchase));
            } catch (error) {
              if (!completer.isCompleted) {
                completer.completeError(
                  StoreSubscriptionException(
                    'Could not complete store purchase: $error',
                  ),
                );
              }
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
        // Transport failure is an unknown result, not store cancellation.
        // Keep the listener and original future for a late event or restore.
      },
    );

    try {
      unawaited(startFlow().then<void>((_) {},
          onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted && !isHandlingTerminal) {
          completer.completeError(error, stack);
        }
      }));
      return await completer.future;
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
