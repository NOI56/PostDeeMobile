import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _configuredLegacy = AppConfig.storePostCaptionAddonProductId;
const _canonicalLegacy = AppConfig.legacyPostCaptionAddonProductId;
Set<String> _historicalSkus() => {_canonicalLegacy}..add(_configuredLegacy);
const _tiers = [
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

AddonCatalogResult _catalog({bool legacyEnabled = true,
    List<AddonCatalogProduct>? products}) => AddonCatalogResult(
      enabled: legacyEnabled, eligible: legacyEnabled,
      productId: _configuredLegacy, postUnits: 100, aiCaptions: 50,
      priceThb: 49, policyVersion: 2, creditsExpire: false, expiresAt: null,
      purchasedPacks: 0, catalogVersion: products == null ? null : 3,
      products: products);

AddonConfirmationResult _legacyConfirmation(String receipt) =>
    AddonConfirmationResult(confirmed: true, transactionId: receipt,
        postUnits: 100, aiCaptions: 50, policyVersion: 2,
        creditsExpire: false, expiresAt: null);

void main() {
  test('configured legacy $_configuredLegacy still buys 100/50 with an older API',
      () async {
    final sessions = PostDeeAuthSessionStore(initialSession:
        const AuthSession(userId: 'alias-owner', idToken: 'fake-token'));
    final gateway = _Gateway();
    final confirmedProducts = <String>[];
    final catalog = _catalog();
    final billing = StoreAddonService(sessionStore: sessions, gateway: gateway,
        pendingStore: InMemoryAddonPendingStore(),
        loadCatalog: () async => catalog, preparePurchase: () async {},
        confirmPurchase: (productId, receipt) async {
          confirmedProducts.add(productId);
          return _legacyConfirmation(receipt);
        });
    final product = await billing.loadProduct(catalog);
    expect(product?.id, _configuredLegacy);
    expect(product?.price, 'CAD 1.25');
    final result = await billing.purchase();
    expect(result.postUnits, 100);
    expect(result.aiCaptions, 50);
    expect(result.productId, isNull);
    expect(gateway.queries.every(
        (ids) => ids.length == 1 && ids.single == _configuredLegacy), isTrue);
    expect(gateway.buys, [_configuredLegacy]);
    expect(confirmedProducts, [_configuredLegacy]);
    expect(billing.hasPendingPurchase, isFalse);
  });

  for (final historicalSku in _historicalSkus()) {
    test('retired v1 $historicalSku receipt survives the three-tier catalog',
        () async {
      final sessions = PostDeeAuthSessionStore(initialSession:
          const AuthSession(userId: 'historical-owner', idToken: 'fake-token'));
      final gateway = _Gateway();
      final record = AddonPendingRecord.fromJson({
        'version': 1, 'productId': historicalSku,
        'intentId': 'historical-intent', 'transactionId': 'historical-receipt',
      });
      final pending = InMemoryAddonPendingStore(initialRecord: record);
      final catalog = _catalog(legacyEnabled: false, products: _tiers);
      final confirmedProducts = <String>[];
      var reads = 0;
      final billing = StoreAddonService(sessionStore: sessions, gateway: gateway,
          pendingStore: pending, loadCatalog: () async { reads++; return catalog; },
          preparePurchase: () async {},
          confirmPurchase: (productId, receipt) async {
            confirmedProducts.add(productId);
            return _legacyConfirmation(receipt);
          });
      expect(catalog.enabled, isFalse);
      expect(catalog.products!.any((product) =>
          product.productId == _configuredLegacy ||
          product.productId == _canonicalLegacy), isFalse);
      await expectLater(billing.purchaseProduct(_tiers.first.productId),
          throwsA(isA<StoreAddonPendingException>()));
      expect((await pending.load())!.toJson(), record.toJson());
      final result = await billing.retryPendingPurchase();
      expect(result.postUnits, 100);
      expect(result.aiCaptions, 50);
      expect(result.transactionId, 'historical-receipt');
      expect(result.transactionIdKind, 'STORE');
      expect(confirmedProducts, [historicalSku]);
      expect(reads, 0);
      expect(gateway.queries, isEmpty);
      expect(gateway.buys, isEmpty);
      expect(await pending.load(), isNull);
    });
  }
}

class _Gateway implements StoreAddonGateway {
  final queries = <Set<String>>[];
  final buys = <String>[];
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryAddonProducts(Set<String> ids) async {
    queries.add(Set.of(ids));
    return [
      for (final id in _historicalSkus())
        StoreProductInfo(id: id, title: 'Historical pack',
            description: '', price: 'CAD 1.25'),
      const StoreProductInfo(id: 'postdee_post40_caption25', title: 'Small pack',
          description: '', price: '€1,49'),
    ];
  }
  @override
  Future<StoreAddonTransaction> buyAddon(String productId) async {
    buys.add(productId);
    return StoreAddonTransaction(productId: productId,
        transactionId: 'configured-legacy-receipt');
  }
}
