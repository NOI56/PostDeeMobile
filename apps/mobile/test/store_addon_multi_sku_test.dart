import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _legacySku = 'postdee_post100_caption50';
const _products = [
  AddonCatalogProduct(id: 'small', productId: 'postdee_post40_caption25',
      postUnits: 40, aiCaptions: 25, priceThb: 49,
      enabled: true, eligible: true),
  AddonCatalogProduct(id: 'medium', productId: 'postdee_post90_caption50',
      postUnits: 90, aiCaptions: 50, priceThb: 99,
      enabled: true, eligible: true),
  AddonCatalogProduct(id: 'large', productId: 'postdee_post190_caption100',
      postUnits: 190, aiCaptions: 100, priceThb: 199,
      enabled: true, eligible: true),
];
const _prices = ['€1,49', '¥490', 'CHF 4.25'];

Set<String> _historicalSkus() =>
    {_legacySku}..add(AppConfig.storePostCaptionAddonProductId);

AddonCatalogResult _catalog({List<AddonCatalogProduct>? products = _products,
    bool enabled = false, bool eligible = false, int policyVersion = 2,
    bool creditsExpire = false, DateTime? expiresAt}) => AddonCatalogResult(
  enabled: enabled, eligible: eligible, productId: _legacySku,
  postUnits: 100, aiCaptions: 50, priceThb: 49,
  policyVersion: policyVersion, creditsExpire: creditsExpire,
  expiresAt: expiresAt, purchasedPacks: 0,
  catalogVersion: products == null ? null : 3, products: products,
);

AddonConfirmationResult _confirmed(String productId, String transactionId,
    {String? returnedProductId, bool omitProductId = false,
    bool confirmed = true, String transactionIdKind = 'STORE',
    int? postUnits, int? aiCaptions}) {
  final definition = AddonCatalogProduct.definitionFor(productId);
  return AddonConfirmationResult(confirmed: confirmed, transactionId: transactionId,
    transactionIdKind: transactionIdKind,
    productId: omitProductId ? null : returnedProductId ?? productId,
    postUnits: postUnits ?? definition?.postUnits ?? 100,
    aiCaptions: aiCaptions ?? definition?.aiCaptions ?? 50,
    policyVersion: 2, creditsExpire: false, expiresAt: null);
}

AddonCatalogProduct _offer({bool enabled = true, bool eligible = true,
    int postUnits = 40, int aiCaptions = 25, int priceThb = 49}) =>
    AddonCatalogProduct(id: 'small', productId: _products.first.productId,
      postUnits: postUnits, aiCaptions: aiCaptions, priceThb: priceThb,
      enabled: enabled, eligible: eligible);

void main() {
  for (var index = 0; index < _products.length; index++) {
    final product = _products[index];
    test('selected ${product.id} tier uses its exact SKU and localized price',
        () async {
      final fixture = _Fixture();
      final billing = fixture.service();
      final loaded = await billing.loadProductFor(fixture.catalog, product);
      expect(loaded?.id, product.productId);
      expect(loaded?.price, _prices[index]);
      // Root flags describe legacy checkout, not the tier's independent gate.
      expect(fixture.catalog.enabled, isFalse);
      expect(fixture.catalog.eligible, isFalse);
      final result = await billing.purchaseProduct(product.productId);
      expect(result.productId, product.productId);
      expect(result.postUnits, product.postUnits);
      expect(result.aiCaptions, product.aiCaptions);
      expect(fixture.gateway.buys, [product.productId]);
      expect(fixture.gateway.queries.every(
          (ids) => ids.length == 1 && ids.single == product.productId), isTrue);
      expect(fixture.confirmations, [product.productId]);
      expect(billing.hasPendingPurchase, isFalse);
    });
  }

  test('an older API retains the exact legacy purchase and product methods',
      () async {
    final fixture = _Fixture()
      ..catalog = _catalog(products: null, enabled: true, eligible: true);
    final billing = fixture.service();
    expect((await billing.loadProduct(fixture.catalog))?.price, '£1.25');
    final result = await billing.purchase();
    expect(result.postUnits, 100);
    expect(result.aiCaptions, 50);
    expect(fixture.gateway.buys, [_legacySku]);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test('two confirmed medium purchases remain two distinct 90/50 receipts', () async {
    final fixture = _Fixture();
    final billing = fixture.service();
    final one = await billing.purchaseProduct(_products[1].productId);
    expect(billing.hasPendingPurchase, isFalse);
    expect(await fixture.pending.load(), isNull);
    final two = await billing.purchaseProduct(_products[1].productId);
    expect(one.transactionId, isNot(two.transactionId));
    expect(one.postUnits + two.postUnits, 180);
    expect(one.aiCaptions + two.aiCaptions, 100);
    expect(fixture.confirmations, [_products[1].productId, _products[1].productId]);
    expect(fixture.gateway.buys, [_products[1].productId, _products[1].productId]);
    expect(billing.hasPendingPurchase, isFalse);
  });

  test('new payment intents persist immutable version2 grant expectations', () async {
    final fixture = _Fixture();
    final billing = fixture.service(confirm: (sku, receipt) async =>
        _confirmed(sku, receipt, confirmed: false));
    await expectLater(billing.purchaseProduct(_products.first.productId),
        throwsA(isA<StoreAddonPendingException>()));
    final saved = (await fixture.pending.load())!.toJson();
    expect(saved['version'], 2);
    expect(saved['expectedPostUnits'], 40);
    expect(saved['expectedAiCaptions'], 25);
    expect(saved['productId'], _products.first.productId);
  });

  for (final namespace in ['STORE', 'REVENUECAT']) {
    test('historical unknown v1 alias keeps 100/50 when recovered as $namespace', () async {
      const oldAlias = 'postdee_historical_custom_10050';
      final fixture = _Fixture();
      final pending = InMemoryAddonPendingStore(initialRecord:
          AddonPendingRecord.fromJson({
            'version': 1, 'productId': oldAlias, 'intentId': 'old-alias',
            'transactionId': 'old-alias-receipt', 'transactionIdKind': namespace,
          }));
      var checks = 0;
      final billing = fixture.service(pendingStore: pending,
          confirm: (sku, receipt) async {
        expect(sku, oldAlias);
        expect(receipt, 'old-alias-receipt');
        checks++;
        return _confirmed(sku, receipt, transactionIdKind: namespace,
            postUnits: checks == 1 ? 40 : 100,
            aiCaptions: checks == 1 ? 25 : 50,
            returnedProductId: checks == 2 ? _products.first.productId : null,
            omitProductId: checks == 3);
      });
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(billing.retryPendingPurchase(),
            throwsA(isA<StoreAddonPendingException>()));
        expect(billing.hasPendingPurchase, isTrue);
        expect((await pending.load())!.productId, oldAlias);
      }
      final result = await billing.retryPendingPurchase();
      expect([result.postUnits, result.aiCaptions], [100, 50]);
      expect(result.transactionIdKind, namespace);
      expect(fixture.catalogReads, 0);
      expect(fixture.gateway.buys, isEmpty);
      expect(await pending.load(), isNull);
    });
  }

  for (final currentProduct in _products) {
    for (final namespace in ['STORE', 'REVENUECAT']) {
      for (final legacyResponse in [true, false]) {
        test('v1 alias colliding with ${currentProduct.id} stays 100/50 '
            '($namespace, legacy response=$legacyResponse)', () async {
          final fixture = _Fixture();
          final record = AddonPendingRecord.fromJson({
            'version': 1, 'productId': currentProduct.productId,
            'intentId': 'historical-alias', 'transactionId': 'historical-receipt',
            'transactionIdKind': namespace,
          });
          final pending = InMemoryAddonPendingStore(initialRecord: record);
          var checks = 0;
          final billing = fixture.service(pendingStore: pending,
              confirm: (sku, receipt) async {
            expect(sku, currentProduct.productId);
            expect(receipt, 'historical-receipt');
            checks++;
            return _confirmed(sku,
                checks == 4 ? 'different-receipt' : receipt,
                postUnits: checks == 1 ? currentProduct.postUnits : 100,
                aiCaptions: checks == 1 ? currentProduct.aiCaptions : 50,
                returnedProductId: checks == 2 ? 'different-product' : null,
                transactionIdKind: checks == 3
                    ? (namespace == 'STORE' ? 'REVENUECAT' : 'STORE') : namespace,
                omitProductId: checks == 5 && legacyResponse);
          });
          for (var attempt = 0; attempt < 4; attempt++) {
            await expectLater(billing.retryPendingPurchase(),
                throwsA(isA<StoreAddonPendingException>()));
            expect((await pending.load())!.toJson(), record.toJson());
            expect(billing.hasPendingPurchase, isTrue);
          }
          final result = await billing.retryPendingPurchase();
          expect([result.postUnits, result.aiCaptions], [100, 50]);
          expect(result.transactionId, 'historical-receipt');
          expect(result.transactionIdKind, namespace);
          expect(result.productId, legacyResponse ? null : currentProduct.productId);
          expect(await pending.load(), isNull);
          expect(billing.hasPendingPurchase, isFalse);
          expect(fixture.gateway.buys, isEmpty);
          expect(fixture.gateway.queries, isEmpty);
          expect(fixture.catalogReads, 0);
        });
      }
    }
  }

  test('known SKU cannot recover with an altered version2 grant snapshot', () async {
    final fixture = _Fixture();
    final record = AddonPendingRecord(version: 2,
        productId: _products.first.productId, intentId: 'altered-grant',
        transactionId: 'altered-grant-receipt',
        expectedPostUnits: 100, expectedAiCaptions: 50);
    final pending = InMemoryAddonPendingStore(initialRecord: record);
    final billing = fixture.service(pendingStore: pending);
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
    expect((await pending.load())!.toJson(), record.toJson());
    expect(fixture.confirmations, isEmpty);
    expect(fixture.gateway.buys, isEmpty);
  });

  test('retired version2 SKU verifies its saved grant and exact server product identity', () async {
    final fixture = _Fixture();
    const historicalSku = 'postdee_retired_post70_caption35';
    final record = AddonPendingRecord(version: 2,
        productId: historicalSku, intentId: 'retired-snapshot',
        transactionId: 'retired-snapshot-receipt',
        expectedPostUnits: 70, expectedAiCaptions: 35);
    final pending = InMemoryAddonPendingStore(initialRecord: record);
    var checks = 0;
    final billing = fixture.service(pendingStore: pending,
        confirm: (sku, receipt) async {
      checks++;
      return _confirmed(sku, receipt, postUnits: checks == 1 ? 100 : 70,
          aiCaptions: checks == 1 ? 50 : 35, omitProductId: checks == 2);
    });
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(billing.retryPendingPurchase(),
          throwsA(isA<StoreAddonPendingException>()));
      expect((await pending.load())!.toJson(), record.toJson());
    }
    final result = await billing.retryPendingPurchase();
    expect([result.postUnits, result.aiCaptions], [70, 35]);
    expect(result.productId, historicalSku);
    expect(await pending.load(), isNull);
    expect(fixture.catalogReads, 0);
    expect(fixture.gateway.buys, isEmpty);
  });

  final unavailableCatalogs = <String, AddonCatalogResult>{
    'absent': _catalog(products: []),
    'disabled': _catalog(products: [_offer(enabled: false, eligible: false)]),
    'ineligible': _catalog(products: [_offer(eligible: false)]),
    'changed post grant': _catalog(products: [_offer(postUnits: 41)]),
    'changed caption grant': _catalog(products: [_offer(aiCaptions: 26)]),
    'changed Thai reference': _catalog(products: [_offer(priceThb: 50)]),
    'expiring policy': _catalog(creditsExpire: true),
    'old policy': _catalog(policyVersion: 1),
  };
  for (final entry in unavailableCatalogs.entries) {
    test('${entry.key} tier is rejected before payment', () async {
      final fixture = _Fixture()..catalog = entry.value;
      final billing = fixture.service();
      expect(await billing.loadProductFor(fixture.catalog, _products.first),
          isNull);
      await expectLater(billing.purchaseProduct(_products.first.productId),
          throwsA(isA<StoreAddonException>()));
      expect(fixture.gateway.buys, isEmpty);
      expect(fixture.confirmations, isEmpty);
      expect(billing.hasPendingPurchase, isFalse);
    });

    test('${entry.key} after preparation prevents checkout', () async {
      final fixture = _Fixture();
      final billing = fixture.service(prepare: () async {
        fixture.catalog = entry.value;
      });
      await expectLater(billing.purchaseProduct(_products.first.productId),
          throwsA(isA<StoreAddonException>()));
      expect(fixture.catalogReads, 2);
      expect(fixture.gateway.buys, isEmpty);
      expect(fixture.confirmations, isEmpty);
      expect(billing.hasPendingPurchase, isFalse);
    });
  }

  test('unknown tier and legacy-only API never silently select another pack',
      () async {
    final fixture = _Fixture();
    await expectLater(fixture.service().purchaseProduct('unmapped-sku'),
        throwsA(isA<StoreAddonException>()));
    fixture.catalog = _catalog(products: null, enabled: true, eligible: true);
    await expectLater(
        fixture.service().purchaseProduct(_products.first.productId),
        throwsA(isA<StoreAddonException>()));
    expect(fixture.gateway.buys, isEmpty);
  });

  for (final mismatch in [
    'product', 'missing product', 'post units', 'caption credits',
    'transaction', 'namespace', 'unconfirmed',
  ]) {
    test('$mismatch confirmation retains the exact tier receipt until retry',
        () async {
      final fixture = _Fixture();
      final selected = _products.first;
      var checks = 0;
      final billing = fixture.service(confirm: (sku, receipt) async {
        checks++;
        if (checks > 1) return _confirmed(sku, receipt);
        return _confirmed(sku,
            mismatch == 'transaction' ? 'different-receipt' : receipt,
            returnedProductId: mismatch == 'product'
                ? _products.last.productId : null,
            omitProductId: mismatch == 'missing product',
            postUnits: mismatch == 'post units' ? 100 : null,
            aiCaptions: mismatch == 'caption credits' ? 50 : null,
            transactionIdKind: mismatch == 'namespace' ? 'REVENUECAT' : 'STORE',
            confirmed: mismatch != 'unconfirmed');
      });
      await expectLater(billing.purchaseProduct(selected.productId),
          throwsA(isA<StoreAddonPendingException>()));
      final retained = (await fixture.pending.load())!;
      expect(retained.productId, selected.productId);
      expect(retained.transactionId, 'receipt-1');
      expect(retained.transactionIdKind, 'STORE');
      expect(billing.hasPendingPurchase, isTrue);
      await expectLater(billing.purchaseProduct(_products.last.productId),
          throwsA(isA<StoreAddonPendingException>()));
      expect(fixture.gateway.buys, [selected.productId]);
      final confirmed = await billing.retryPendingPurchase();
      expect(confirmed.postUnits, 40);
      expect(confirmed.aiCaptions, 25);
      expect(confirmed.productId, selected.productId);
      expect(fixture.gateway.buys, [selected.productId]);
      expect(await fixture.pending.load(), isNull);
      expect(billing.hasPendingPurchase, isFalse);
    });
  }

  for (final legacySku in _historicalSkus()) {
    test('retired v1 $legacySku receipt still confirms its historical 100/50',
        () async {
      final fixture = _Fixture();
      final pending = InMemoryAddonPendingStore(initialRecord:
          AddonPendingRecord.fromJson({
            'version': 1, 'productId': legacySku, 'intentId': 'old-intent',
            'transactionId': 'old-store-receipt',
          }));
      final billing = fixture.service(pendingStore: pending,
          confirm: (sku, receipt) async {
        expect(sku, legacySku);
        return _confirmed(sku, receipt, omitProductId: true);
      });
      expect(fixture.catalog.products!.any(
          (product) => product.productId == legacySku), isFalse);
      final result = await billing.retryPendingPurchase();
      expect(result.postUnits, 100);
      expect(result.aiCaptions, 50);
      expect(fixture.catalogReads, 0);
      expect(fixture.gateway.queries, isEmpty);
      expect(fixture.gateway.buys, isEmpty);
      expect(await pending.load(), isNull);
    });
  }

  test('a restarted tier purchase recovers while its sale offer is absent',
      () async {
    final fixture = _Fixture();
    final selected = _products[1];
    final first = fixture.service(confirm: (sku, receipt) async =>
        _confirmed(sku, receipt, confirmed: false));
    await expectLater(first.purchaseProduct(selected.productId),
        throwsA(isA<StoreAddonPendingException>()));
    final saved = (await fixture.pending.load())!.toJson();
    expect(saved['version'], 2);
    expect(saved['expectedPostUnits'], 90);
    expect(saved['expectedAiCaptions'], 50);
    fixture.catalog = _catalog(products: []);
    final restarted = fixture.service();
    await expectLater(restarted.purchaseProduct(_products.last.productId),
        throwsA(isA<StoreAddonPendingException>()));
    expect((await fixture.pending.load())!.toJson(), saved);
    final result = await restarted.retryPendingPurchase();
    expect(result.productId, selected.productId);
    expect(result.postUnits, 90);
    expect(result.aiCaptions, 50);
    expect(fixture.gateway.buys, [selected.productId]);
    expect(await fixture.pending.load(), isNull);
  });

  test('new tier RevenueCat selectors require their original namespace',
      () async {
    final fixture = _Fixture();
    final selected = _products.last;
    final pending = InMemoryAddonPendingStore(initialRecord: AddonPendingRecord(
        version: 2, expectedPostUnits: selected.postUnits,
        expectedAiCaptions: selected.aiCaptions,
        productId: selected.productId, intentId: 'rc-intent',
        transactionId: 'opaque-selector', transactionIdKind: 'REVENUECAT'));
    var checks = 0;
    final billing = fixture.service(pendingStore: pending,
        confirm: (sku, receipt) async => _confirmed(sku, receipt,
            transactionIdKind: ++checks == 1 ? 'STORE' : 'REVENUECAT'));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    expect((await pending.load())!.transactionIdKind, 'REVENUECAT');
    expect((await billing.retryPendingPurchase()).aiCaptions, 100);
    expect(fixture.gateway.buys, isEmpty);
    expect(await pending.load(), isNull);
  });

  test('wrong native SKU stays pending and cannot confirm another product',
      () async {
    final fixture = _Fixture();
    fixture.gateway.nativeReceipt = StoreAddonTransaction(
        productId: _products.last.productId, transactionId: 'wrong-native');
    final billing = fixture.service();
    await expectLater(billing.purchaseProduct(_products.first.productId),
        throwsA(isA<StoreAddonPendingException>()));
    expect((await fixture.pending.load())!.productId, _products.first.productId);
    expect((await fixture.pending.load())!.transactionId, isNull);
    fixture.gateway.recoveredReceipt = fixture.gateway.nativeReceipt;
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    expect(fixture.gateway.recoveryProducts, [_products.first.productId]);
    expect(fixture.confirmations, isEmpty);
    expect(fixture.gateway.buys, [_products.first.productId]);
    expect(billing.hasPendingPurchase, isTrue);
  });

  test('unconfirmed historical SKU keeps the account locked without deleting evidence',
      () async {
    final fixture = _Fixture();
    final record = AddonPendingRecord(productId: 'unknown-historical-sku',
        intentId: 'unknown-intent', transactionId: 'unknown-receipt');
    final pending = InMemoryAddonPendingStore(initialRecord: record);
    final billing = fixture.service(pendingStore: pending,
        confirm: (sku, receipt) async => _confirmed(sku, receipt, confirmed: false));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonPendingException>()));
    await expectLater(billing.purchaseProduct(_products.first.productId),
        throwsA(isA<StoreAddonPendingException>()));
    expect(billing.hasPendingPurchase, isTrue);
    expect((await pending.load())!.toJson(), record.toJson());
    expect(fixture.gateway.buys, isEmpty);
    expect(fixture.confirmations, ['unknown-historical-sku']);
  });

  test('verified refund of a tier receipt clears pending without another charge',
      () async {
    final fixture = _Fixture();
    final pending = InMemoryAddonPendingStore(initialRecord: AddonPendingRecord(
        version: 2, expectedPostUnits: _products.first.postUnits,
        expectedAiCaptions: _products.first.aiCaptions,
        productId: _products.first.productId, intentId: 'refunded',
        transactionId: 'refunded-receipt'));
    final billing = fixture.service(pendingStore: pending,
        confirm: (_, __) async => throw const ApiException('Refunded',
            code: 'ADDON_PURCHASE_REVOKED', statusCode: 409));
    await expectLater(billing.retryPendingPurchase(),
        throwsA(isA<StoreAddonException>().having(
            (error) => error is StoreAddonPendingException, 'pending', isFalse)));
    expect(await pending.load(), isNull);
    expect(billing.hasPendingPurchase, isFalse);
    expect(fixture.gateway.buys, isEmpty);
  });

  test('account replacement during tier checkout never confirms for the next owner',
      () async {
    final fixture = _Fixture();
    final completion = Completer<StoreAddonTransaction>();
    fixture.gateway.nativeFuture = completion.future;
    final billing = fixture.service();
    final failed = expectLater(
        billing.purchaseProduct(_products.first.productId),
        throwsA(isA<AuthSessionChangedException>()));
    await fixture.gateway.buyStarted.future;
    fixture.sessions.signIn(
        const AuthSession(userId: 'replacement-owner', idToken: 'other-token'));
    completion.complete(StoreAddonTransaction(
        productId: _products.first.productId, transactionId: 'late-old-owner'));
    await failed;
    expect(fixture.confirmations, isEmpty);
    expect(fixture.gateway.buys, [_products.first.productId]);
    expect(billing.hasPendingPurchase, isFalse);
  });
}

class _Fixture {
  final sessions = PostDeeAuthSessionStore(initialSession:
      const AuthSession(userId: 'tier-owner', idToken: 'fake-token'));
  final gateway = _Gateway();
  final pending = InMemoryAddonPendingStore();
  final confirmations = <String>[];
  AddonCatalogResult catalog = _catalog();
  int catalogReads = 0;

  StoreAddonService service({AddonPendingStore? pendingStore,
      Future<AddonCatalogResult> Function()? loadCatalog,
      Future<void> Function()? prepare,
      Future<AddonConfirmationResult> Function(String, String)? confirm}) =>
      StoreAddonService(sessionStore: sessions, gateway: gateway,
        pendingStore: pendingStore ?? pending,
        loadCatalog: loadCatalog ?? () async { catalogReads++; return catalog; },
        preparePurchase: prepare ?? () async {},
        confirmPurchase: (productId, transactionId) async {
          confirmations.add(productId);
          return confirm == null ? _confirmed(productId, transactionId)
              : await confirm(productId, transactionId);
        });
}

class _Gateway implements StoreAddonGateway, DurableAddonPurchaseGateway,
    PendingAddonPurchaseReconciler {
  final queries = <Set<String>>[];
  final buys = <String>[];
  final buyStarted = Completer<void>();
  StoreAddonTransaction? nativeReceipt;
  Future<StoreAddonTransaction>? nativeFuture;
  StoreAddonTransaction? recoveredReceipt;
  final recoveryProducts = <String>[];

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryAddonProducts(Set<String> ids) async {
    queries.add(Set.of(ids));
    return [
      const StoreProductInfo(id: _legacySku, title: 'Legacy',
          description: '', price: '£1.25'),
      for (var index = 0; index < _products.length; index++)
        StoreProductInfo(id: _products[index].productId, title: 'Tier',
            description: '', price: _prices[index]),
    ];
  }
  @override
  Future<StoreAddonTransaction> buyAddon(String productId) async {
    buys.add(productId);
    if (!buyStarted.isCompleted) buyStarted.complete();
    if (nativeFuture != null) return await nativeFuture!;
    return nativeReceipt ?? StoreAddonTransaction(
        productId: productId, transactionId: 'receipt-${buys.length}');
  }
  @override
  Future<StoreAddonTransaction> buyAddonWithSnapshot(String productId,
      Future<void> Function(Set<String>) persistBeforeDispatch) async {
    await persistBeforeDispatch({'old-receipt'});
    return buyAddon(productId);
  }
  @override
  Future<StoreAddonTransaction?> recoverAddonPurchase(String productId,
      Set<String> baselineTransactionIds) async {
    recoveryProducts.add(productId);
    return recoveredReceipt;
  }
  @override
  Future<StoreAddonTransaction?> reconcilePendingAddonPurchase() async =>
      recoveredReceipt;
}
