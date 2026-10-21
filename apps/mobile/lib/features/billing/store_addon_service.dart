import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/network/postdee_api_client.dart';
import 'store_subscription_service.dart';
import 'addon_pending_store.dart';

class StoreAddonException implements Exception {
  const StoreAddonException(this.message);
  final String message;
}

class StoreAddonPendingException extends StoreAddonException {
  const StoreAddonPendingException()
      : super(
            'รายการเดิมยังรอยืนยัน กรุณาตรวจสอบการซื้ออีกครั้งโดยไม่ต้องซื้อซ้ำ');
}

class _AddonWaitExpired implements Exception {}

/// Owns one account's unfinished consumable transaction across paywall visits.
class StoreAddonSessionCache {
  StoreAddonSessionCache(
      {PostDeeAuthSessionStore? sessionStore,
      StoreAddonService Function()? createService})
      : _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _createService = createService ??
            (() => StoreAddonService(sessionStore: sessionStore)) {
    _sessionStore.addListener(_sessionChanged);
  }
  static final instance = StoreAddonSessionCache();
  final PostDeeAuthSessionStore _sessionStore;
  final StoreAddonService Function() _createService;
  StoreAddonService? _service;
  StoreAddonService get service {
    _sessionChanged();
    return _service ??= _createService();
  }

  void _sessionChanged() {
    if (!(_service?.isCurrent ?? true)) _service = null;
  }

  void dispose() {
    _sessionStore.removeListener(_sessionChanged);
    _service = null;
  }
}

class StoreAddonService {
  StoreAddonService({
    PostDeeAuthSessionStore? sessionStore,
    StoreAddonGateway? gateway,
    Future<AddonCatalogResult> Function()? loadCatalog,
    Future<AddonConfirmationResult> Function(String, String)? confirmPurchase,
    Future<void> Function()? preparePurchase,
    AddonPendingStore? pendingStore,
    DateTime Function()? now,
    this.operationTimeout = const Duration(minutes: 2),
    this.requestTimeout = const Duration(seconds: 15),
  })  : _binding =
            (sessionStore ?? PostDeeAuthSessionStore.instance).captureSession(),
        _gateway = gateway ??
            createRevenueCatBillingGatewayFromConfig(
                sessionStore: sessionStore),
        _loadCatalog = loadCatalog,
        _confirmPurchase = confirmPurchase,
        _preparePurchase = preparePurchase,
        _pendingStore = pendingStore ??
            SharedPreferencesAddonPendingStore(sessionStore: sessionStore),
        _now = now ?? DateTime.now;

  final AuthSessionBinding _binding;
  final StoreAddonGateway? _gateway;
  final Future<AddonCatalogResult> Function()? _loadCatalog;
  final Future<AddonConfirmationResult> Function(String, String)?
      _confirmPurchase;
  final Future<void> Function()? _preparePurchase;
  final AddonPendingStore _pendingStore;
  final DateTime Function() _now;
  final Duration operationTimeout;
  final Duration requestTimeout;
  Future<AddonConfirmationResult>? _operation;
  StoreAddonTransaction? _receipt;
  var _unknownStoreResult = false;
  AddonPendingRecord? _pendingRecord;
  Future<void>? _pendingLoad;
  var _pendingLoaded = false;
  var _pendingLoadFailed = false;
  bool get isCurrent => _binding.isCurrent;
  bool get supportsPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String get platformUnavailableMessage =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'แพ็กเติมนี้ยังไม่รองรับบน iPhone'
          : 'แพ็กเติมนี้รองรับบน Android เท่านั้น';
  bool get hasPendingPurchase =>
      supportsPlatform && isCurrent &&
      (_operation != null ||
          _receipt != null ||
          _unknownStoreResult ||
          _pendingRecord != null ||
          _pendingLoadFailed);
  PostDeeApiClient get _api => PostDeeApiClient(sessionBinding: _binding);

  Future<AddonCatalogResult> loadCatalog() async {
    _binding.ensureCurrent();
    await _restorePending();
    final result =
        await (_loadCatalog ?? _api.loadAddonCatalog)().timeout(requestTimeout);
    _binding.ensureCurrent();
    return result;
  }

  bool _isThisMonth(AddonCatalogResult catalog) {
    final now = _now().toUtc();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return catalog.monthKey == month &&
        catalog.expiresAt.isAfter(now) &&
        catalog.expiresAt.toUtc() == DateTime.utc(now.year, now.month + 1);
  }

  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async {
    _binding.ensureCurrent();
    if (!supportsPlatform) return null;
    if (!catalog.enabled ||
        !catalog.eligible ||
        !_isThisMonth(catalog) ||
        catalog.productId != AppConfig.storePostCaptionAddonProductId ||
        _gateway == null) {
      return null;
    }
    final available = await _gateway.isAvailable().timeout(requestTimeout);
    _binding.ensureCurrent();
    if (!available) return null;
    final products = await _gateway
        .queryAddonProducts({catalog.productId}).timeout(requestTimeout);
    _binding.ensureCurrent();
    return products
        .where((item) =>
            item.id == catalog.productId && item.price.trim().isNotEmpty)
        .firstOrNull;
  }

  Future<AddonConfirmationResult> purchase() {
    _binding.ensureCurrent();
    if (!supportsPlatform) {
      return Future.error(
          StoreAddonPurchaseNotStartedException(platformUnavailableMessage));
    }
    if (hasPendingPurchase) {
      return Future.error(const StoreAddonPendingException());
    }
    final operation = _purchaseAndConfirm();
    _operation = operation;
    return _awaitOperation(operation);
  }

  Future<AddonConfirmationResult> _purchaseAndConfirm() async {
    await _restorePending();
    if (_pendingRecord != null) throw const StoreAddonPendingException();
    final catalog = await loadCatalog();
    if (!catalog.enabled ||
        !catalog.eligible ||
        !_isThisMonth(catalog) ||
        catalog.postUnits != 100 ||
        catalog.aiCaptions != 50 ||
        catalog.priceThb != 49) {
      throw const StoreAddonException(
          'แพ็กเติมยังไม่พร้อมซื้อสำหรับบัญชีนี้ กรุณาตรวจสอบแพ็กเกจอีกครั้ง');
    }
    final product = await loadProduct(catalog);
    _binding.ensureCurrent();
    if (product == null) {
      throw const StoreAddonException(
          'ยังโหลดแพ็กเติมจากร้านค้าไม่ได้ กรุณาลองใหม่');
    }
    if (!_isThisMonth(catalog)) {
      throw const StoreAddonException(
          'เริ่มเดือนใหม่แล้ว กรุณาโหลดแพ็กเติมอีกครั้ง');
    }
    await (_preparePurchase ?? _api.prepareSubscriptionPurchase)()
        .timeout(requestTimeout);
    _binding.ensureCurrent();
    if (!_isThisMonth(catalog)) {
      throw const StoreAddonException(
          'เริ่มเดือนใหม่แล้ว กรุณาโหลดแพ็กเติมอีกครั้ง');
    }
    late final StoreAddonTransaction receipt;
    final intent = AddonPendingRecord(
        productId: product.id,
        intentId:
            '${_now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}');
    try {
      await _pendingStore.save(intent);
    } catch (_) {
      _binding.ensureCurrent();
      _pendingLoaded = false;
      _pendingLoadFailed = true;
      rethrow;
    }
    _binding.ensureCurrent();
    _pendingRecord = intent;
    try {
      final gateway = _gateway!;
      if (gateway is DurableAddonPurchaseGateway) {
        receipt = await (gateway as DurableAddonPurchaseGateway)
            .buyAddonWithSnapshot(product.id, (baseline) async {
          await _writePending(baseline: baseline.toList());
          if (!_isThisMonth(catalog)) {
            throw const StoreAddonPurchaseNotStartedException();
          }
        });
      } else {
        receipt = await gateway.buyAddon(product.id);
      }
    } on StoreAddonPurchaseCancelledException {
      await _clearPending();
      rethrow;
    } on StoreAddonPurchaseNotStartedException {
      await _clearPending();
      rethrow;
    } on StoreAddonStorePendingException {
      _binding.ensureCurrent();
      _unknownStoreResult = true;
      throw const StoreAddonPendingException();
    }
    _binding.ensureCurrent();
    if (receipt.productId != product.id ||
        receipt.transactionId.trim().isEmpty) {
      _unknownStoreResult = true;
      throw const StoreAddonPendingException();
    }
    _receipt = receipt;
    await _writePending(transactionId: receipt.transactionId);
    return _confirmReceipt();
  }

  Future<AddonConfirmationResult> retryPendingPurchase() async {
    _binding.ensureCurrent();
    if (!supportsPlatform) {
      throw StoreAddonPurchaseNotStartedException(platformUnavailableMessage);
    }
    final running = _operation;
    if (running != null) return _awaitOperation(running);
    _pendingLoaded = false;
    await _restorePending();
    if (_receipt == null && !_unknownStoreResult) {
      return Future.error(
          const StoreAddonException('ไม่มีรายการซื้อที่รอยืนยัน'));
    }
    final operation =
        _receipt == null ? _reconcileStoreResult() : _confirmReceipt();
    _operation = operation;
    return _awaitOperation(operation);
  }

  Future<AddonConfirmationResult> _confirmReceipt() async {
    _binding.ensureCurrent();
    final receipt = _receipt!;
    late final AddonConfirmationResult result;
    try {
      result = await (_confirmPurchase ?? _api.confirmAddonPurchase)(
              receipt.productId, receipt.transactionId)
          .timeout(requestTimeout);
    } on ApiException catch (error) {
      _binding.ensureCurrent();
      if (error.code == 'ADDON_PURCHASE_REVOKED') {
        await _clearPending();
        throw const StoreAddonException(
            'รายการนี้ได้รับการคืนเงินหรือยกเลิกแล้ว จึงไม่เพิ่มเครดิต');
      }
      rethrow;
    }
    _binding.ensureCurrent();
    if (!result.confirmed ||
        result.transactionId != receipt.transactionId ||
        result.postUnits != 100 ||
        result.aiCaptions != 50 ||
        result.expiresAt == null) {
      throw const StoreAddonPendingException();
    }
    return result;
  }

  Future<AddonConfirmationResult> _reconcileStoreResult() async {
    _binding.ensureCurrent();
    final gateway = _gateway;
    final record = _pendingRecord;
    StoreAddonTransaction? receipt;
    if (gateway is DurableAddonPurchaseGateway &&
        record?.baselineTransactionIds != null) {
      receipt = await (gateway as DurableAddonPurchaseGateway)
          .recoverAddonPurchase(
              record!.productId, record.baselineTransactionIds!.toSet())
          .timeout(requestTimeout);
    } else if (gateway is PendingAddonPurchaseReconciler) {
      receipt = await (gateway as PendingAddonPurchaseReconciler)
          .reconcilePendingAddonPurchase()
          .timeout(requestTimeout);
    } else {
      throw const StoreAddonPendingException();
    }
    _binding.ensureCurrent();
    if (receipt == null ||
        receipt.productId != AppConfig.storePostCaptionAddonProductId ||
        receipt.transactionId.trim().isEmpty) {
      throw const StoreAddonPendingException();
    }
    _receipt = receipt;
    _unknownStoreResult = false;
    await _writePending(transactionId: receipt.transactionId);
    return _confirmReceipt();
  }

  Future<void> _restorePending() async {
    _binding.ensureCurrent();
    if (_pendingLoaded) return;
    final loading = _pendingLoad ??= _loadPendingRecord();
    try {
      await loading;
    } finally {
      if (identical(_pendingLoad, loading)) _pendingLoad = null;
    }
  }

  Future<void> _loadPendingRecord() async {
    try {
      final record = await _pendingStore.load();
      _binding.ensureCurrent();
      final sameIntent = record?.intentId == _pendingRecord?.intentId;
      if (!sameIntent || record == null) _receipt = null;
      _unknownStoreResult = false;
      _pendingRecord = record;
      _pendingLoaded = true;
      _pendingLoadFailed = false;
      if (record != null) {
        if (record.productId != AppConfig.storePostCaptionAddonProductId) {
          _unknownStoreResult = true;
          throw const StoreAddonPendingException();
        }
        if (record.transactionId != null) {
          _receipt = StoreAddonTransaction(
              productId: record.productId,
              transactionId: record.transactionId!);
        } else {
          _unknownStoreResult = true;
        }
      }
    } catch (_) {
      _binding.ensureCurrent();
      _pendingLoadFailed = true;
      rethrow;
    }
  }

  Future<void> _writePending(
      {String? transactionId, List<String>? baseline}) async {
    _binding.ensureCurrent();
    final previous = _pendingRecord!;
    final record = AddonPendingRecord(
        productId: previous.productId,
        intentId: previous.intentId,
        transactionId: transactionId ?? previous.transactionId,
        baselineTransactionIds: baseline ?? previous.baselineTransactionIds);
    await _pendingStore.save(record);
    _binding.ensureCurrent();
    _pendingRecord = record;
  }

  Future<void> _clearPending() async {
    _binding.ensureCurrent();
    final record = _pendingRecord;
    if (record != null) await _pendingStore.clear(intentId: record.intentId);
    _binding.ensureCurrent();
    _pendingRecord = null;
    _receipt = null;
    _unknownStoreResult = false;
    _pendingLoadFailed = false;
  }

  Future<AddonConfirmationResult> _awaitOperation(
      Future<AddonConfirmationResult> operation) async {
    try {
      final result = await operation.timeout(operationTimeout,
          onTimeout: () => throw _AddonWaitExpired());
      _binding.ensureCurrent();
      if (identical(_operation, operation)) {
        await _clearPending();
        _operation = null;
      }
      return result;
    } on _AddonWaitExpired {
      _binding.ensureCurrent();
      // Keep the SDK future: a UI deadline cannot cancel a dispatched payment.
      throw const StoreAddonPendingException();
    } catch (error) {
      _binding.ensureCurrent();
      if (identical(_operation, operation)) _operation = null;
      if (_receipt != null ||
          _unknownStoreResult ||
          _pendingRecord != null ||
          _pendingLoadFailed) {
        throw const StoreAddonPendingException();
      }
      rethrow;
    }
  }
}
