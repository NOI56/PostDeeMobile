import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;

const _business = 'postdee_business_monthly';
const _starter = 'postdee_starter_monthly';
const _pro = 'postdee_pro_monthly';
const _product = purchases.StoreProduct(
    _business, 'Business monthly', 'Business', 399, '€12.99', 'EUR');

purchases.CustomerInfo _customer(
    {List<String> active = const [],
    purchases.Store store = purchases.Store.playStore,
    purchases.OwnershipType ownership = purchases.OwnershipType.purchased,
    String? basePlan,
    List<String>? reportedSubscriptions,
    bool omitActiveEntitlements = false,
    bool omitAllEntitlements = false,
    String originalOwner = 'upgrade-owner'}) {
  final entitlements = {
    for (var i = 0; i < active.length; i++)
      'plan-$i': purchases.EntitlementInfo('plan-$i', true, true,
          '2026-11-01T00:00:00Z', '2026-11-01T00:00:00Z', active[i], true,
          store: store,
          ownershipType: ownership,
          productPlanIdentifier: basePlan,
          expirationDate: '2099-01-01T00:00:00Z')
  };
  return purchases.CustomerInfo(
      purchases.EntitlementInfos(omitAllEntitlements ? const {} : entitlements,
          omitActiveEntitlements ? const {} : entitlements),
      const {},
      reportedSubscriptions ?? active,
      active,
      const [],
      '2026-11-01T00:00:00Z',
      originalOwner,
      const {},
      '2026-11-02T00:00:00Z');
}

PostDeeAuthSessionStore _sessions() => PostDeeAuthSessionStore(
    initialSession:
        const AuthSession(userId: 'upgrade-owner', idToken: 'fixture-token'));

PurchasesRevenueCatBillingGateway _gateway(
        PostDeeAuthSessionStore sessions, RevenueCatPurchasesSdk sdk) =>
    PurchasesRevenueCatBillingGateway(
        apiKey: 'fixture-public-key',
        androidApiKey: '',
        iosApiKey: '',
        sessionStore: sessions,
        sdk: sdk);

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final old in [_starter, _pro]) {
    test(
        'Android Business upgrade replaces exactly $old with deliberate proration',
        () async {
      final sdk = _BusinessSdk()
        ..customer = _customer(active: [old], basePlan: 'monthly');
      await _gateway(_sessions(), sdk)
          .buyBusinessSubscription(_business, expectedOldProductId: old);
      expect(sdk.businessPurchases, [_business]);
      expect(sdk.changes.single?.oldProductIdentifier, '$old:monthly');
      expect(sdk.changes.single?.replacementMode,
          purchases.StoreReplacementMode.chargeProratedPrice);
      expect(sdk.genericPurchases, isEmpty);
      expect(sdk.snapshotReads, 1);
      expect(sdk.purchaseOwners, ['upgrade-owner']);
    });

    test(
        'iOS Business upgrade verifies App Store ownership before same-group purchase $old',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final sdk = _BusinessSdk()
        ..customer = _customer(active: [old], store: purchases.Store.appStore);
      await _gateway(_sessions(), sdk)
          .buyBusinessSubscription(_business, expectedOldProductId: old);
      expect(sdk.businessPurchases, [_business]);
      expect(sdk.changes.single, isNull);
      expect(sdk.genericPurchases, isEmpty);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('fresh Business purchase has no replacement on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final sdk = _BusinessSdk();
      await _gateway(_sessions(), sdk).buyBusinessSubscription(_business);
      expect(sdk.businessPurchases, [_business]);
      expect(sdk.changes.single, isNull);
      expect(sdk.snapshotReads, 1);
    });
    test('stale Basic server cannot create parallel Business on $platform',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      final sdk = _BusinessSdk()
        ..customer = _customer(
            active: [_pro],
            store: platform == TargetPlatform.android
                ? purchases.Store.playStore
                : purchases.Store.appStore);
      await expectLater(
          _gateway(_sessions(), sdk).buyBusinessSubscription(_business),
          throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
      expect(sdk.businessPurchases, isEmpty);
      expect(sdk.genericPurchases, isEmpty);
    });
    test('cross-store Business upgrade cannot charge on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final sdk = _BusinessSdk()
        ..customer = _customer(
            active: [_pro],
            store: platform == TargetPlatform.android
                ? purchases.Store.appStore
                : purchases.Store.playStore);
      await expectLater(
          _gateway(_sessions(), sdk)
              .buyBusinessSubscription(_business, expectedOldProductId: _pro),
          throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
      expect(sdk.businessPurchases, isEmpty);
    });
  }

  for (final customer in [
    _customer(),
    _customer(active: [_starter]),
    _customer(active: [_starter, _pro]),
    _customer(active: [_pro], store: purchases.Store.unknownStore),
    _customer(active: [_pro], ownership: purchases.OwnershipType.unknown),
    _customer(active: [_pro], ownership: purchases.OwnershipType.familyShared),
  ]) {
    test(
        'unknown mismatched or multiple old subscriptions require reconciliation ${customer.activeSubscriptions}',
        () async {
      final sdk = _BusinessSdk()..customer = customer;
      await expectLater(
          _gateway(_sessions(), sdk)
              .buyBusinessSubscription(_business, expectedOldProductId: _pro),
          throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
      expect(sdk.businessPurchases, isEmpty);
      expect(sdk.genericPurchases, isEmpty);
    });
  }

  test(
      'Business upgrade requires optional SDK support before a native purchase',
      () async {
    await expectLater(
        _gateway(_sessions(), _LegacySdk())
            .buyBusinessSubscription(_business, expectedOldProductId: _pro),
        throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
  });

  test('base-plan mismatch is rejected without guessing an old product',
      () async {
    final sdk = _BusinessSdk()
      ..customer = _customer(active: [_pro], basePlan: 'monthly');
    await expectLater(
        _gateway(_sessions(), sdk).buyBusinessSubscription(_business,
            expectedOldProductId: '$_pro:annual'),
        throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
    expect(sdk.businessPurchases, isEmpty);
  });

  test('already qualified old product preserves its exact base plan once',
      () async {
    final sdk = _BusinessSdk()
      ..customer = _customer(active: ['$_pro:monthly'], basePlan: 'monthly');
    await _gateway(_sessions(), sdk)
        .buyBusinessSubscription(_business, expectedOldProductId: _pro);
    expect(sdk.changes.single?.oldProductIdentifier, '$_pro:monthly');
  });

  for (final customer in [
    _customer(active: [_pro], reportedSubscriptions: const []),
    _customer(active: [_pro], omitActiveEntitlements: true),
    _customer(active: [_pro], omitAllEntitlements: true),
    _customer(reportedSubscriptions: [_pro]),
  ]) {
    test(
        'orphan SDK ownership never authorizes a fresh Business purchase ${customer.entitlements}',
        () async {
      final sdk = _BusinessSdk()..customer = customer;
      await expectLater(
          _gateway(_sessions(), sdk).buyBusinessSubscription(_business),
          throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
      expect(sdk.businessPurchases, isEmpty);
      expect(sdk.genericPurchases, isEmpty);
    });
  }

  test('current SDK owner changing after the fresh snapshot prevents dispatch',
      () async {
    final sdk = _BusinessSdk()..customer = _customer(active: [_pro]);
    sdk.onSnapshot = () async {
      sdk.owner = 'foreign-native-owner';
    };
    await expectLater(
        _gateway(_sessions(), sdk)
            .buyBusinessSubscription(_business, expectedOldProductId: _pro),
        throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
    expect(sdk.businessPurchases, isEmpty);
  });

  test(
      'historical anonymous original UID does not replace the current native owner',
      () async {
    final sdk = _BusinessSdk()
      ..customer = _customer(
          active: [_pro], originalOwner: r'$RCAnonymousID:historical');
    await _gateway(_sessions(), sdk)
        .buyBusinessSubscription(_business, expectedOldProductId: _pro);
    expect(sdk.purchaseOwners, ['upgrade-owner']);
  });

  test('an invalid replacement never retries as an independent subscription',
      () async {
    final sdk = _BusinessSdk()..customer = _customer(active: [_pro]);
    sdk.onPurchase = () async => throw StateError('store rejected replacement');
    await expectLater(
        _gateway(_sessions(), sdk)
            .buyBusinessSubscription(_business, expectedOldProductId: _pro),
        throwsA(isA<StateError>()));
    expect(sdk.businessPurchases, [_business]);
    expect(sdk.changes.single?.replacementMode,
        purchases.StoreReplacementMode.chargeProratedPrice);
    expect(sdk.genericPurchases, isEmpty);
  });

  for (final phase in ['snapshot', 'purchase']) {
    test('Business upgrade preserves original owner during $phase', () async {
      final sessions = _sessions();
      final sdk = _BusinessSdk()..customer = _customer(active: [_pro]);
      final started = Completer<void>();
      final release = Completer<void>();
      Future<void> pause() {
        started.complete();
        return release.future;
      }

      if (phase == 'snapshot') sdk.onSnapshot = pause;
      if (phase == 'purchase') sdk.onPurchase = pause;
      final checked = expectLater(
          _gateway(sessions, sdk)
              .buyBusinessSubscription(_business, expectedOldProductId: _pro),
          throwsA(isA<AuthSessionChangedException>()));
      await started.future;
      sessions.signIn(const AuthSession(
          userId: 'replacement-owner', idToken: 'other-token'));
      release.complete();
      await checked;
      expect(sdk.genericPurchases, isEmpty);
      expect(
          sdk.businessPurchases, phase == 'purchase' ? [_business] : isEmpty);
      if (phase == 'purchase') expect(sdk.purchaseOwners, ['upgrade-owner']);
    });
  }
}

class _BusinessSdk
    implements RevenueCatPurchasesSdk, RevenueCatBusinessPurchasesSdk {
  String owner = 'upgrade-owner';
  purchases.CustomerInfo customer = _customer();
  var snapshotReads = 0;
  final businessPurchases = <String>[];
  final genericPurchases = <String>[];
  final purchaseOwners = <String>[];
  final changes = <purchases.StoreProductChangeInfo?>[];
  Future<void> Function()? onSnapshot, onPurchase;
  @override
  Future<bool> get isConfigured async => true;
  @override
  Future<String> get appUserId async => owner;
  @override
  Future<void> setDebugLogLevel() async {}
  @override
  Future<void> configure(String key, String userId) async {
    owner = userId;
  }

  @override
  Future<void> logIn(String userId) async {
    owner = userId;
  }

  @override
  Future<bool> canMakePayments() async => true;
  @override
  Future<List<purchases.StoreProduct>> getProducts(List<String> ids) async =>
      [_product];
  @override
  Future<void> purchase(purchases.StoreProduct product) async {
    genericPurchases.add(product.identifier);
  }

  @override
  Future<void> restorePurchases() async {}
  @override
  Future<purchases.CustomerInfo> loadCustomerInfoForBusinessPurchase() async {
    snapshotReads++;
    await onSnapshot?.call();
    return customer;
  }

  @override
  Future<void> purchaseBusiness(purchases.StoreProduct product,
      {purchases.StoreProductChangeInfo? productChangeInfo}) async {
    businessPurchases.add(product.identifier);
    changes.add(productChangeInfo);
    purchaseOwners.add(owner);
    await onPurchase?.call();
  }
}

class _LegacySdk implements RevenueCatPurchasesSdk {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Legacy SDK must not dispatch Business');
}
