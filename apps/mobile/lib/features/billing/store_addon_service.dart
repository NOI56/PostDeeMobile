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
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get platformUnavailableMessage =>
      'แพ็กเติมนี้รองรับบน Android และ iPhone เท่านั้น';
  bool get hasPendingPurchase =>
      supportsPlatform &&
      isCurrent &&
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

  bool _hasExpectedPack(AddonCatalogResult catalog) =>
      catalog.hasNonExpiringPolicy &&
      AddonCatalogProduct.definitionFor(AppConfig.storePostCaptionAddonProductId) == null &&
      catalog.productId == AppConfig.storePostCaptionAddonProductId &&
      catalog.postUnits == 100 &&
      catalog.aiCaptions == 50 &&
      catalog.priceThb == 49;

  AddonCatalogProduct? _receiptDefinition(String productId) {
    final tier = AddonCatalogProduct.definitionFor(productId);
    if (tier != null) return tier;
    if (productId != AppConfig.legacyPostCaptionAddonProductId &&
        productId != AppConfig.storePostCaptionAddonProductId) {
      return null;
    }
    return AddonCatalogProduct(id: 'legacy', productId: productId,
        postUnits: 100, aiCaptions: 50, priceThb: 49,
        enabled: false, eligible: false);
  }

  AddonCatalogProduct? _pendingDefinition(AddonPendingRecord record) {
    if (record.version == 1) {
      // Shipped v1 intents describe the original immutable 100/50 pack, even
      // if its historical alias now names a different approved sale tier.
      // A current SKU definition must never reinterpret that old contract.
      return AddonCatalogProduct(id: 'legacy', productId: record.productId,
          postUnits: 100, aiCaptions: 50, priceThb: 49,
          enabled: false, eligible: false);
    }
    final known = _receiptDefinition(record.productId);
    final postUnits = record.expectedPostUnits;
    final aiCaptions = record.expectedAiCaptions;
    if (postUnits == null || aiCaptions == null ||
        (known != null && (postUnits != known.postUnits || aiCaptions != known.aiCaptions))) {
      return null;
    }
    return AddonCatalogProduct(id: known?.id ?? 'historical',
        productId: record.productId, postUnits: postUnits, aiCaptions: aiCaptions,
        priceThb: known?.priceThb ?? 0, enabled: false, eligible: false);
  }

  AddonCatalogProduct? _availableOffer(AddonCatalogResult catalog, String productId) {
    if (!catalog.hasNonExpiringPolicy) return null;
    if (AddonCatalogProduct.definitionFor(productId) == null) {
      if (!_hasExpectedPack(catalog) || !catalog.enabled || !catalog.eligible ||
          catalog.productId != productId) {
        return null;
      }
      return AddonCatalogProduct(id: 'legacy', productId: productId,
          postUnits: catalog.postUnits, aiCaptions: catalog.aiCaptions,
          priceThb: catalog.priceThb, enabled: true, eligible: true);
    }
    final matches = catalog.products?.where((product) => product.productId == productId).toList();
    if (matches == null || matches.length != 1) return null;
    final product = matches.single;
    return product.hasApprovedDefinition && product.enabled && product.eligible
        ? product : null;
  }

  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async {
    _binding.ensureCurrent();
    if (!supportsPlatform) return null;
    if (!catalog.enabled ||
        !catalog.eligible ||
        !_hasExpectedPack(catalog) ||
        _gateway == null) {
      return null;
    }
    return _loadStoreProduct(catalog.productId);
  }

  Future<StoreProductInfo?> loadProductFor(
      AddonCatalogResult catalog, AddonCatalogProduct product) async {
    _binding.ensureCurrent();
    if (!supportsPlatform || _gateway == null ||
        AddonCatalogProduct.definitionFor(product.productId) == null) {
      return null;
    }
    final offer = _availableOffer(catalog, product.productId);
    if (offer == null || !offer.sameOfferAs(product)) return null;
    return _loadStoreProduct(product.productId);
  }

  Future<StoreProductInfo?> _loadStoreProduct(String productId) async {
    final available = await _gateway!.isAvailable().timeout(requestTimeout);
    _binding.ensureCurrent();
    if (!available) return null;
    final products = await _gateway
        .queryAddonProducts({productId}).timeout(requestTimeout);
    _binding.ensureCurrent();
    return products
        .where((item) =>
            item.id == productId && item.price.trim().isNotEmpty)
        .firstOrNull;
  }

  Future<AddonConfirmationResult> purchase() =>
      _startPurchase(AppConfig.storePostCaptionAddonProductId);

  Future<AddonConfirmationResult> purchaseProduct(String productId) =>
      _startPurchase(productId);

  Future<AddonConfirmationResult> _startPurchase(String productId) {
    _binding.ensureCurrent();
    if (!supportsPlatform) {
      return Future.error(
          StoreAddonPurchaseNotStartedException(platformUnavailableMessage));
    }
    if (hasPendingPurchase) {
      return Future.error(const StoreAddonPendingException());
    }
    if (_receiptDefinition(productId) == null) {
      return Future.error(const StoreAddonException(
          'แพ็กเติมยังไม่พร้อมซื้อสำหรับบัญชีนี้ กรุณาตรวจสอบแพ็กเกจอีกครั้ง'));
    }
    final operation = _purchaseAndConfirm(productId);
    _operation = operation;
    return _awaitOperation(operation);
  }

  Future<AddonConfirmationResult> _purchaseAndConfirm(String productId) async {
    await _restorePending();
    if (_pendingRecord != null) throw const StoreAddonPendingException();
    final catalog = await loadCatalog();
    final offer = _availableOffer(catalog, productId);
    if (offer == null) {
      throw const StoreAddonException(
          'แพ็กเติมยังไม่พร้อมซื้อสำหรับบัญชีนี้ กรุณาตรวจสอบแพ็กเกจอีกครั้ง');
    }
    final product = AddonCatalogProduct.definitionFor(productId) == null
        ? await loadProduct(catalog) : await loadProductFor(catalog, offer);
    _binding.ensureCurrent();
    if (product == null) {
      throw const StoreAddonException(
          'ยังโหลดแพ็กเติมจากร้านค้าไม่ได้ กรุณาลองใหม่');
    }
    await (_preparePurchase ?? _api.prepareSubscriptionPurchase)()
        .timeout(requestTimeout);
    _binding.ensureCurrent();
    final preparedCatalog = await loadCatalog();
    final preparedOffer = _availableOffer(preparedCatalog, productId);
    if (preparedOffer == null || !offer.sameOfferAs(preparedOffer) ||
        productId != product.id) {
      throw const StoreAddonException(
          'ระบบซื้อเครดิตยังไม่พร้อม กรุณาโหลดแพ็กเติมใหม่');
    }
    late final StoreAddonTransaction receipt;
    final intent = AddonPendingRecord(
        version: 2,
        expectedPostUnits: offer.postUnits,
        expectedAiCaptions: offer.aiCaptions,
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
          final dispatchOffer = _availableOffer(preparedCatalog, productId);
          if (dispatchOffer == null || !offer.sameOfferAs(dispatchOffer)) {
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
    await _writePending(
        transactionId: receipt.transactionId,
        transactionIdKind: receipt.transactionIdKind);
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
      final confirm = _confirmPurchase;
      result = await (confirm != null
              ? confirm(receipt.productId, receipt.transactionId)
              : _api.confirmAddonPurchase(
                  receipt.productId, receipt.transactionId,
                  transactionIdKind: receipt.transactionIdKind))
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
    final record = _pendingRecord;
    final definition = record == null ? null : _pendingDefinition(record);
    if (!result.confirmed ||
        result.transactionId != receipt.transactionId ||
        result.transactionIdKind != receipt.transactionIdKind ||
        definition == null ||
        record?.productId != receipt.productId ||
        result.postUnits != definition.postUnits ||
        result.aiCaptions != definition.aiCaptions ||
        (result.productId != null && result.productId != receipt.productId) ||
        (record?.version == 2 &&
            AddonCatalogProduct.definitionFor(receipt.productId) != null &&
            result.productId != receipt.productId) ||
        (record?.version == 2 && _receiptDefinition(receipt.productId) == null &&
            result.productId != receipt.productId) ||
        !result.hasNonExpiringPolicy) {
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
        record == null || receipt.productId != record.productId ||
        _pendingDefinition(record) == null ||
        receipt.transactionId.trim().isEmpty) {
      throw const StoreAddonPendingException();
    }
    _receipt = receipt;
    _unknownStoreResult = false;
    await _writePending(
        transactionId: receipt.transactionId,
        transactionIdKind: receipt.transactionIdKind);
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
        if (_pendingDefinition(record) == null) {
          _unknownStoreResult = true;
          throw const StoreAddonPendingException();
        }
        if (record.transactionId != null) {
          _receipt = StoreAddonTransaction(
              productId: record.productId,
              transactionId: record.transactionId!,
              transactionIdKind: record.transactionIdKind);
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
      {String? transactionId,
      String? transactionIdKind,
      List<String>? baseline}) async {
    _binding.ensureCurrent();
    final previous = _pendingRecord!;
    final record = AddonPendingRecord(
        version: previous.version,
        expectedPostUnits: previous.expectedPostUnits,
        expectedAiCaptions: previous.expectedAiCaptions,
        productId: previous.productId,
        intentId: previous.intentId,
        transactionId: transactionId ?? previous.transactionId,
        transactionIdKind: transactionIdKind ?? previous.transactionIdKind,
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
