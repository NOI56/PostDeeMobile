import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';

const _sku = 'postdee_post100_caption50';
const _product = StoreProductInfo(
    id: _sku, title: 'เติมเครดิต', description: '', price: '฿49.00');
final _now = DateTime.utc(2026, 10, 21);
AddonCatalogResult _catalog(
        {bool enabled = true,
        bool eligible = true,
        String month = '2026-10'}) =>
    AddonCatalogResult(
        enabled: enabled,
        eligible: eligible,
        productId: _sku,
        postUnits: 100,
        aiCaptions: 50,
        priceThb: 49,
        monthKey: month,
        expiresAt: DateTime.utc(2026, 11),
        purchasedPacks: 0);
AddonConfirmationResult _confirmation(String id, {bool confirmed = true}) =>
    AddonConfirmationResult(
        confirmed: confirmed,
        transactionId: id,
        postUnits: 100,
        aiCaptions: 50,
        expiresAt: DateTime.utc(2026, 11));

void main() {
  late PostDeeAuthSessionStore session;
  late _Gateway gateway;
  setUp(() {
    session = PostDeeAuthSessionStore(
        initialSession: const AuthSession(userId: 'owner-a', idToken: 'dummy'));
    gateway = _Gateway();
  });
  StoreAddonService service(
          {Future<AddonCatalogResult> Function()? catalog,
          Future<AddonConfirmationResult> Function(String, String)? confirm,
          Duration timeout = const Duration(seconds: 1)}) =>
      StoreAddonService(
          sessionStore: session,
          gateway: gateway,
          now: () => _now,
          loadCatalog: catalog ?? () async => _catalog(),
          confirmPurchase: confirm ?? (_, id) async => _confirmation(id),
          preparePurchase: () async {},
          pendingStore: InMemoryAddonPendingStore(),
          operationTimeout: timeout);

  test('iPhone cannot start add-on checkout or recover a stored transaction',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final billing = service();
    expect(billing.supportsPlatform, isFalse);
    expect(await billing.loadProduct(_catalog()), isNull);
    await expectLater(billing.purchase(),
        throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    expect(gateway.buyCalls, 0);
  });

  test('disabled API, Basic, stale month and missing SKU never charge',
      () async {
    for (final catalog in [
      _catalog(enabled: false),
      _catalog(eligible: false),
      _catalog(month: '2026-09')
    ]) {
      await expectLater(service(catalog: () async => catalog).purchase(),
          throwsA(isA<StoreAddonException>()));
    }
    gateway.products = [];
    await expectLater(
        service().purchase(), throwsA(isA<StoreAddonException>()));
    expect(gateway.buyCalls, 0);
  });

  test(
      'a new store transaction is confirmed before credit success and repeat purchases work',
      () async {
    final ids = <String>[];
    final billing = service(confirm: (sku, id) async {
      expect(sku, _sku);
      ids.add(id);
      return _confirmation(id);
    });
    expect((await billing.purchase()).transactionId, 'txn-1');
    expect((await billing.purchase()).transactionId, 'txn-2');
    expect(ids, ['txn-1', 'txn-2']);
    expect(gateway.buyCalls, 2);
  });

  test(
      'server pending and API failure retain the receipt and retry without buying twice',
      () async {
    var calls = 0;
    final billing = service(confirm: (_, id) async {
      calls++;
      if (calls == 1) return _confirmation(id, confirmed: false);
      if (calls == 2) throw const ApiException('offline');
      return _confirmation(id);
    });
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    expect((await billing.retryPendingPurchase()).transactionId, 'txn-1');
    expect(gateway.buyCalls, 1);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test(
      'a timed out native purchase retains the late transaction and blocks a second buy',
      () async {
    final storeResult = Completer<StoreAddonTransaction>();
    gateway.purchaseResult = storeResult.future;
    final billing = service(timeout: const Duration(milliseconds: 10));
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    storeResult.complete(const StoreAddonTransaction(
        productId: _sku, transactionId: 'late-txn'));
    expect((await billing.retryPendingPurchase()).transactionId, 'late-txn');
    expect(gateway.buyCalls, 1);
  });

  test(
      'account change during native purchase never confirms for the next account',
      () async {
    final storeResult = Completer<StoreAddonTransaction>();
    gateway.purchaseResult = storeResult.future;
    var confirmations = 0;
    final billing = service(confirm: (_, id) async {
      confirmations++;
      return _confirmation(id);
    });
    final result = billing.purchase();
    await Future<void>.delayed(Duration.zero);
    session.signIn(const AuthSession(userId: 'owner-b', idToken: 'other'));
    storeResult.complete(const StoreAddonTransaction(
        productId: _sku, transactionId: 'old-owner'));
    await expectLater(result, throwsA(isA<AuthSessionChangedException>()));
    expect(confirmations, 0);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test('mismatched confirmation cannot report purchase success', () async {
    final billing =
        service(confirm: (_, id) async => _confirmation('different-txn'));
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
  });

  test(
      'a restarted service rechecks the persisted receipt without another checkout',
      () async {
    final pending = InMemoryAddonPendingStore();
    final first = StoreAddonService(
        sessionStore: session,
        gateway: gateway,
        pendingStore: pending,
        now: () => _now,
        loadCatalog: () async => _catalog(),
        preparePurchase: () async {},
        confirmPurchase: (_, id) async => _confirmation(id, confirmed: false));
    await expectLater(
        first.purchase(), throwsA(isA<StoreAddonPendingException>()));
    final restartedGateway = _Gateway();
    final restarted = StoreAddonService(
        sessionStore: session,
        gateway: restartedGateway,
        pendingStore: pending,
        now: () => _now,
        loadCatalog: () async => _catalog(),
        preparePurchase: () async {},
        confirmPurchase: (_, id) async => _confirmation(id));
    expect((await restarted.retryPendingPurchase()).transactionId, 'txn-1');
    expect(restartedGateway.buyCalls, 0);
    expect(await pending.load(), isNull);
  });

  test(
      'persisted intent and baseline recover the late transaction after process death',
      () async {
    final pending = InMemoryAddonPendingStore(
        initialRecord: AddonPendingRecord(
            productId: _sku,
            intentId: 'intent-before-process-death',
            baselineTransactionIds: ['older-txn']));
    gateway.reconciledTransaction =
        const StoreAddonTransaction(productId: _sku, transactionId: 'late-txn');
    final restarted = StoreAddonService(
        sessionStore: session,
        gateway: gateway,
        pendingStore: pending,
        now: () => _now,
        loadCatalog: () async => _catalog(),
        preparePurchase: () async {},
        confirmPurchase: (_, id) async => _confirmation(id));
    expect((await restarted.retryPendingPurchase()).transactionId, 'late-txn');
    expect(gateway.buyCalls, 0);
    expect(await pending.load(), isNull);
  });

  test(
      'a verified refund clears the pending transaction and reports no granted credits',
      () async {
    final pending = InMemoryAddonPendingStore(
        initialRecord: AddonPendingRecord(
            productId: _sku,
            intentId: 'refunded-intent',
            transactionId: 'refunded-txn'));
    final billing = StoreAddonService(
        sessionStore: session,
        gateway: gateway,
        pendingStore: pending,
        confirmPurchase: (_, id) async => throw const ApiException('refunded',
            code: 'ADDON_PURCHASE_REVOKED', statusCode: 409));
    await expectLater(
        billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonException>().having(
            (error) => error is StoreAddonPendingException,
            'pending',
            isFalse)));
    expect(billing.hasPendingPurchase, isFalse);
    expect(await pending.load(), isNull);
    expect(gateway.buyCalls, 0);
  });

  test(
      'SDK pending error blocks another charge and reconciles the original late transaction',
      () async {
    gateway.buyError = const StoreAddonStorePendingException();
    final billing = service();
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    gateway.reconciledTransaction = const StoreAddonTransaction(
        productId: _sku, transactionId: 'pending-then-completed');
    expect((await billing.retryPendingPurchase()).transactionId,
        'pending-then-completed');
    expect(gateway.buyCalls, 1);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test(
      'canonical owner preparation must complete before dispatch and an account switch stops checkout',
      () async {
    final preparing = Completer<void>();
    final billing = StoreAddonService(
        sessionStore: session,
        gateway: gateway,
        now: () => _now,
        loadCatalog: () async => _catalog(),
        preparePurchase: () => preparing.future,
        pendingStore: InMemoryAddonPendingStore(),
        confirmPurchase: (_, id) async => _confirmation(id));
    final result = expectLater(
        billing.purchase(), throwsA(isA<AuthSessionChangedException>()));
    await Future<void>.delayed(Duration.zero);
    expect(gateway.buyCalls, 0);
    session.signOut();
    preparing.complete();
    await result;
    expect(gateway.buyCalls, 0);
  });

  test('unsupported server preparation never starts a payment', () async {
    final billing = StoreAddonService(
        sessionStore: session,
        gateway: gateway,
        now: () => _now,
        loadCatalog: () async => _catalog(),
        preparePurchase: () async => throw const ApiException('unsupported'),
        pendingStore: InMemoryAddonPendingStore(),
        confirmPurchase: (_, id) async => _confirmation(id));
    await expectLater(billing.purchase(), throwsA(isA<ApiException>()));
    expect(gateway.buyCalls, 0);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test(
      'missing transaction after store completion cannot start another payment',
      () async {
    gateway.purchaseResult = Future.value(
        const StoreAddonTransaction(productId: _sku, transactionId: ''));
    final billing = service();
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
    await expectLater(
        billing.purchase(), throwsA(isA<StoreAddonPendingException>()));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    expect(gateway.buyCalls, 1);
  });

  test(
      'the account cache retains pending receipts when reopening and invalidates on account replacement',
      () async {
    var ready = false;
    final cache = StoreAddonSessionCache(
        sessionStore: session,
        createService: () => service(
            confirm: (_, id) async => _confirmation(id, confirmed: ready)));
    addTearDown(cache.dispose);
    final first = cache.service;
    await expectLater(
        first.purchase(), throwsA(isA<StoreAddonPendingException>()));
    final reopened = cache.service;
    expect(identical(first, reopened), isTrue);
    expect(reopened.hasPendingPurchase, isTrue);
    ready = true;
    expect((await reopened.retryPendingPurchase()).transactionId, 'txn-1');
    expect(gateway.buyCalls, 1);
    session.signIn(const AuthSession(userId: 'owner-b', idToken: 'other'));
    expect(identical(cache.service, first), isFalse);
    expect(cache.service.hasPendingPurchase, isFalse);
  });

  test(
      'a catalog check completed after an account replacement never starts checkout',
      () async {
    final response = Completer<AddonCatalogResult>();
    final billing = service(catalog: () => response.future);
    final result = expectLater(
        billing.purchase(), throwsA(isA<AuthSessionChangedException>()));
    session.signOut();
    response.complete(_catalog());
    await result;
    expect(gateway.buyCalls, 0);
  });
}

class _Gateway
    implements
        StoreAddonGateway,
        PendingAddonPurchaseReconciler,
        DurableAddonPurchaseGateway {
  var buyCalls = 0;
  List<StoreProductInfo> products = [_product];
  Future<StoreAddonTransaction>? purchaseResult;
  Object? buyError;
  StoreAddonTransaction? reconciledTransaction;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryAddonProducts(Set<String> ids) async =>
      products;
  @override
  Future<StoreAddonTransaction> buyAddon(String id) async {
    buyCalls++;
    if (buyError != null) throw buyError!;
    return purchaseResult ??
        Future.value(StoreAddonTransaction(
            productId: id, transactionId: 'txn-$buyCalls'));
  }

  @override
  Future<StoreAddonTransaction?> reconcilePendingAddonPurchase() async =>
      reconciledTransaction;

  @override
  Future<StoreAddonTransaction> buyAddonWithSnapshot(String productId,
      Future<void> Function(Set<String>) persistBeforeDispatch) async {
    await persistBeforeDispatch({});
    return buyAddon(productId);
  }

  @override
  Future<StoreAddonTransaction?> recoverAddonPurchase(
          String productId, Set<String> baselineTransactionIds) async =>
      reconciledTransaction;
}
