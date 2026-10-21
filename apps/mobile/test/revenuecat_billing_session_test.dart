import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/addon_pending_store.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;

const _product = purchases.StoreProduct(
  'postdee_pro_monthly', 'Pro subscription', 'PostDee Pro', 1, 'THB1', 'THB',
);
const _addonProduct = purchases.StoreProduct(
  'postdee_post100_caption50', '100 + 50', 'PostDee add-on', 49, '฿49', 'THB',
);

PostDeeAuthSessionStore _session(String userId) => PostDeeAuthSessionStore(
  initialSession: AuthSession(userId: userId, idToken: 'dummy-$userId-token'),
);

PurchasesRevenueCatBillingGateway _gateway(
  PostDeeAuthSessionStore session,
  _FakePurchasesSdk sdk,
) => PurchasesRevenueCatBillingGateway(
  apiKey: 'dummy-public-sdk-key', androidApiKey: '', iosApiKey: '',
  sessionStore: session, sdk: sdk,
);

void main() {
  test('store checkout ID and RevenueCat history selector remain distinct opaque identifiers', () async {
    final session = _session('account-a');
    final sdk = _FakePurchasesSdk()..addonPurchaseTransactionId = 'GPA.store-1';
    sdk.addonTransactions = [const StoreAddonTransaction(
      productId: 'postdee_post100_caption50', transactionId: 'rc-old')];
    Set<String>? baseline;
    final receipt = await _gateway(session, sdk).buyAddonWithSnapshot(
      _addonProduct.identifier, (ids) async { baseline = ids; });
    expect(receipt.transactionId, 'GPA.store-1');
    expect(receipt.transactionIdKind, 'STORE');
    expect(baseline, {'rc-old'});
    sdk.addonTransactions.add(const StoreAddonTransaction(
      productId: 'postdee_post100_caption50', transactionId: 'rc-1'));
    final recovered = await _gateway(session, sdk).recoverAddonPurchase(
      _addonProduct.identifier, baseline!);
    expect(recovered!.transactionId, 'rc-1');
    expect(recovered.transactionIdKind, 'REVENUECAT');
    expect(recovered.transactionId, isNot(receipt.transactionId));
    expect(sdk.purchaseUserIds, ['account-a']);
  });

  test('history selector persists through pending confirmation and process restart without a second checkout', () async {
    final session = _session('account-a');
    final sdk = _FakePurchasesSdk()..addonPurchaseTransactionId = 'GPA.store-1';
    sdk.addonTransactions = [const StoreAddonTransaction(
      productId: 'postdee_post100_caption50', transactionId: 'rc-old')];
    final pending = _ReceiptWriteFailureStore('GPA.store-1');
    final selectors = <String>[];
    StoreAddonService restartedService() => StoreAddonService(
      sessionStore: session, gateway: _gateway(session, sdk), pendingStore: pending,
      loadCatalog: () async => const AddonCatalogResult(enabled: true, eligible: true,
        productId: 'postdee_post100_caption50', postUnits: 100, aiCaptions: 50,
        priceThb: 49, policyVersion: 2, creditsExpire: false, expiresAt: null, purchasedPacks: 0),
      preparePurchase: () async {},
      confirmPurchase: (product, selector) async {
        expect(product, _addonProduct.identifier);
        expect(selector, 'rc-1');
        expect((await pending.load())!.transactionIdKind, 'REVENUECAT');
        selectors.add(selector);
        // The backend resolves this RevenueCat selector to its trusted store
        // transaction. Its response echoes the requested selector in both cases.
        return AddonConfirmationResult(confirmed: selectors.length > 1,
          transactionId: selector, transactionIdKind: 'REVENUECAT', postUnits: 100, aiCaptions: 50,
          policyVersion: 2, creditsExpire: false, expiresAt: null);
      });

    await expectLater(restartedService().purchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(selectors, isEmpty);
    final interrupted = await pending.load();
    expect(interrupted!.transactionId, isNull);
    expect(interrupted.baselineTransactionIds, ['rc-old']);
    expect(pending.rejectedTransactionId, 'GPA.store-1');

    // The process dies after the store purchase but before its receipt is saved.
    // CustomerInfo history exposes RevenueCat's ID rather than the store order ID.
    sdk.addonTransactions.add(const StoreAddonTransaction(
      productId: 'postdee_post100_caption50', transactionId: 'rc-1'));
    final recovering = restartedService();
    await expectLater(recovering.retryPendingPurchase(), throwsA(isA<StoreAddonPendingException>()));
    expect(recovering.hasPendingPurchase, isTrue);
    expect((await pending.load())!.transactionId, 'rc-1');
    expect((await pending.load())!.transactionIdKind, 'REVENUECAT');
    expect(selectors, ['rc-1']);
    expect(sdk.purchaseUserIds, ['account-a']);

    // A second process starts while the API is still waiting for trusted proof.
    // Rechecking that same persisted selector confirms it without another buy.
    final confirmed = await restartedService().retryPendingPurchase();
    expect(confirmed.confirmed, isTrue);
    expect(confirmed.transactionId, 'rc-1');
    expect(selectors, ['rc-1', 'rc-1']);
    expect(await pending.load(), isNull);
    expect(sdk.purchaseUserIds, ['account-a']);
  });
  test('desktop add-on query checkout and recovery stop before any RevenueCat SDK call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sdk = _FakePurchasesSdk();
    final gateway = _gateway(_session('account-a'), sdk);
    var snapshotWrites = 0;
    await expectLater(gateway.queryAddonProducts({_addonProduct.identifier}), throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    await expectLater(gateway.buyAddon(_addonProduct.identifier), throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    await expectLater(gateway.buyAddonWithSnapshot(_addonProduct.identifier, (_) async { snapshotWrites++; }), throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    await expectLater(gateway.recoverAddonPurchase(_addonProduct.identifier, {}), throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    await expectLater(gateway.reconcilePendingAddonPurchase(), throwsA(isA<StoreAddonPurchaseNotStartedException>()));
    expect(snapshotWrites, 0);
    expect(sdk.calls, isEmpty);
  });

  test('iOS consumable checkout uses the product transaction and shared recovery path', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sdk = _FakePurchasesSdk();
    final gateway = _gateway(_session('account-a'), sdk);
    expect((await gateway.queryAddonProducts({_addonProduct.identifier})).single.id, _addonProduct.identifier);
    expect((await gateway.buyAddon(_addonProduct.identifier)).transactionId, 'addon-transaction');
    expect(await gateway.recoverAddonPurchase(_addonProduct.identifier, {}), isNull);
    expect(sdk.purchaseUserIds, ['account-a']);
  });

  test('iOS monthly subscriptions continue to use the existing RevenueCat purchase path', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final sdk = _FakePurchasesSdk();
    await _gateway(_session('account-a'), sdk).buySubscription(_product.identifier);
    expect(sdk.purchaseUserIds, ['account-a']);
  });
  test('RevenueCat pending checkout reconciles only a unique new transaction, without another payment', () async {
    final session = _session('account-a');
    final sdk = _FakePurchasesSdk(onStep: (step) async {
      if (step == 'addonPurchase') throw PlatformException(code: purchases.PurchasesErrorCode.paymentPendingError.index.toString());
    });
    sdk.addonTransactions = [const StoreAddonTransaction(productId: 'postdee_post100_caption50', transactionId: 'old')];
    final gateway = _gateway(session, sdk);
    await expectLater(gateway.buyAddon(_addonProduct.identifier), throwsA(isA<StoreAddonStorePendingException>()));
    expect(await gateway.reconcilePendingAddonPurchase(), isNull);
    sdk.addonTransactions.add(const StoreAddonTransaction(productId: 'postdee_post100_caption50', transactionId: 'new'));
    expect((await gateway.reconcilePendingAddonPurchase())!.transactionId, 'new');
    expect(sdk.purchaseUserIds, ['account-a']);
  });

  test('RevenueCat cancelled checkout has a terminal error and no pending transaction snapshot', () async {
    final sdk = _FakePurchasesSdk(onStep: (step) async {
      if (step == 'addonPurchase') throw PlatformException(code: purchases.PurchasesErrorCode.purchaseCancelledError.index.toString());
    });
    final gateway = _gateway(_session('account-a'), sdk);
    await expectLater(gateway.buyAddon(_addonProduct.identifier),
      throwsA(isA<StoreSubscriptionException>().having((error) => error is StoreAddonStorePendingException, 'pending', isFalse)));
    expect(await gateway.reconcilePendingAddonPurchase(), isNull);
  });
  test('add-on queries non-subscriptions and retains the exact transaction identifier', () async {
    final session = _session('account-a');
    final sdk = _FakePurchasesSdk();
    final gateway = _gateway(session, sdk);
    final products = await gateway.queryAddonProducts({_addonProduct.identifier});
    expect(products.single.price, '฿49');
    final receipt = await gateway.buyAddon(_addonProduct.identifier);
    expect(receipt.productId, _addonProduct.identifier);
    expect(receipt.transactionId, 'addon-transaction');
    expect(sdk.calls, isNot(contains('products')));
  });

  for (final phase in ['addonProducts', 'addonPurchase']) {
    test('add-on stops after account replacement during $phase', () async {
      final session = _session('account-a');
      final started = Completer<void>();
      final release = Completer<void>();
      final sdk = _FakePurchasesSdk(onStep: (step) async {
        if (step == phase) { started.complete(); await release.future; }
      });
      final failure = expectLater(_gateway(session, sdk).buyAddon(_addonProduct.identifier),
        throwsA(isA<AuthSessionChangedException>()));
      await started.future;
      session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b'));
      release.complete();
      await failure;
      expect(sdk.loggedInUserIds, isEmpty);
      expect(sdk.purchaseUserIds, phase == 'addonProducts' ? isEmpty : ['account-a']);
    });
  }

  test('add-on native purchase and subscription share the global identity queue', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final release = Completer<void>();
    final sdk = _FakePurchasesSdk(onStep: (step) async {
      if (step == 'addonPurchase') { started.complete(); await release.future; }
    });
    final old = expectLater(_gateway(session, sdk).buyAddon(_addonProduct.identifier),
      throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b'));
    final next = _gateway(session, sdk).buySubscription(_product.identifier);
    await Future<void>.delayed(Duration.zero);
    expect(sdk.loggedInUserIds, isEmpty);
    release.complete();
    await Future.wait([old, next]);
    expect(sdk.purchaseUserIds, ['account-a', 'account-b']);
  });
  for (final step in ['isConfigured', 'appUserId', 'debugLogLevel', 'configure', 'logIn', 'products']) {
    test('RevenueCat purchase stops when the account changes during $step', () async {
      final session = _session('account-a');
      final started = Completer<void>();
      final release = Completer<void>();
      final sdk = _FakePurchasesSdk(
        configured: step != 'configure' && step != 'debugLogLevel',
        currentUserId: step == 'logIn' ? 'old-account' : 'account-a',
        onStep: (name) {
          if (name == step) {
            started.complete();
            return release.future;
          }
          return Future<void>.value();
        },
      );
      final expectation = expectLater(
        _gateway(session, sdk).buySubscription(_product.identifier),
        throwsA(isA<AuthSessionChangedException>()),
      );
      await started.future;
      session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b-token'));
      release.complete();
      await expectation;
      expect(sdk.purchaseUserIds, isEmpty);
      expect(sdk.configuredUserIds, isNot(contains('account-b')));
      expect(sdk.loggedInUserIds, isNot(contains('account-b')));
      expect(sdk.calls.last, step);
    });
  }

  test('RevenueCat availability ignores a replaced account payment capability result', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final release = Completer<void>();
    final sdk = _FakePurchasesSdk(onStep: (name) {
      if (name == 'canMakePayments') {
        started.complete();
        return release.future;
      }
      return Future<void>.value();
    });
    final expectation = expectLater(_gateway(session, sdk).isAvailable(),
        throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    session.signOut();
    release.complete();
    await expectation;
    expect(sdk.calls.last, 'canMakePayments');
  });

  test('RevenueCat rejects a delayed identity provider result after account replacement', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final userId = Completer<String?>();
    final sdk = _FakePurchasesSdk();
    final gateway = PurchasesRevenueCatBillingGateway(
      apiKey: 'dummy-public-sdk-key', androidApiKey: '', iosApiKey: '',
      sessionStore: session, sdk: sdk,
      appUserIdProvider: () { started.complete(); return userId.future; },
    );
    final expectation = expectLater(gateway.buySubscription(_product.identifier),
        throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b-token'));
    userId.complete('account-b');
    await expectation;
    expect(sdk.calls, isEmpty);
  });

  test('RevenueCat never uses a mismatched provider UID to configure the SDK', () async {
    final session = _session('account-a');
    final sdk = _FakePurchasesSdk();
    final gateway = PurchasesRevenueCatBillingGateway(
      apiKey: 'dummy-public-sdk-key', androidApiKey: '', iosApiKey: '',
      sessionStore: session, sdk: sdk, appUserIdProvider: () async => 'account-b',
    );
    await expectLater(gateway.buySubscription(_product.identifier),
        throwsA(isA<StoreSubscriptionException>()));
    expect(sdk.calls, isEmpty);
  });

  test('RevenueCat restore stops after stale product-independent configuration', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final release = Completer<void>();
    final sdk = _FakePurchasesSdk(onStep: (name) {
      if (name == 'appUserId') {
        started.complete();
        return release.future;
      }
      return Future<void>.value();
    });
    final expectation = expectLater(_gateway(session, sdk).restorePurchases(),
        throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    session.signOut();
    release.complete();
    await expectation;
    expect(sdk.restoreUserIds, isEmpty);
  });

  test('RevenueCat product query ignores results for a replaced account', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final release = Completer<void>();
    final sdk = _FakePurchasesSdk(onStep: (name) {
      if (name == 'products') {
        started.complete();
        return release.future;
      }
      return Future<void>.value();
    });
    final expectation = expectLater(_gateway(session, sdk).queryProducts({_product.identifier}),
        throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b-token'));
    release.complete();
    await expectation;
    expect(sdk.purchaseUserIds, isEmpty);
  });

  test('RevenueCat serializes SDK work across gateways and rejects stale queued buyers', () async {
    final session = _session('account-a');
    final started = Completer<void>();
    final release = Completer<void>();
    var purchaseCalls = 0;
    final sdk = _FakePurchasesSdk(onStep: (name) {
      if (name == 'purchase' && ++purchaseCalls == 1) {
        started.complete();
        return release.future;
      }
      return Future<void>.value();
    });
    final firstFailure = expectLater(_gateway(session, sdk).buySubscription(_product.identifier),
        throwsA(isA<AuthSessionChangedException>()));
    await started.future;
    final queuedFailure = expectLater(_gateway(session, sdk).buySubscription(_product.identifier),
        throwsA(isA<AuthSessionChangedException>()));
    session.signIn(const AuthSession(userId: 'account-b', idToken: 'dummy-b-token'));
    final newBuyer = _gateway(session, sdk).buySubscription(_product.identifier);
    await Future<void>.value();
    expect(sdk.loggedInUserIds, isEmpty);
    expect(sdk.purchaseUserIds, ['account-a']);
    release.complete();
    await Future.wait([firstFailure, queuedFailure, newBuyer]);
    expect(sdk.loggedInUserIds, ['account-b']);
    expect(sdk.purchaseUserIds, ['account-a', 'account-b']);
  });

  test('RevenueCat preserves the exact captured UID for configuration and purchase', () async {
    final session = _session(' account-a ');
    final sdk = _FakePurchasesSdk(configured: false);
    await _gateway(session, sdk).buySubscription(_product.identifier);
    expect(sdk.configuredUserIds, [' account-a ']);
    expect(sdk.purchaseUserIds, [' account-a ']);
  });

  test('RevenueCat refuses a signed-in session without a stable UID before SDK calls', () async {
    final session = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'dummy-no-uid-token'),
    );
    final sdk = _FakePurchasesSdk();
    await expectLater(_gateway(session, sdk).buySubscription(_product.identifier),
        throwsA(isA<StoreSubscriptionException>()));
    expect(sdk.calls, isEmpty);
  });
}

class _FakePurchasesSdk implements RevenueCatPurchasesSdk, RevenueCatConsumablePurchasesSdk {
  _FakePurchasesSdk({this.configured = true, this.currentUserId = 'account-a', this.onStep});
  bool configured;
  String currentUserId;
  final Future<void> Function(String step)? onStep;
  final calls = <String>[];
  final configuredUserIds = <String>[];
  final loggedInUserIds = <String>[];
  final purchaseUserIds = <String>[];
  final restoreUserIds = <String>[];
  var addonPurchaseTransactionId = 'addon-transaction';
  List<StoreAddonTransaction> addonTransactions = [];

  Future<void> _step(String name) async {
    calls.add(name);
    await onStep?.call(name);
  }

  @override
  Future<bool> get isConfigured async {
    await _step('isConfigured');
    return configured;
  }

  @override
  Future<String> get appUserId async {
    await _step('appUserId');
    return currentUserId;
  }

  @override
  Future<void> setDebugLogLevel() => _step('debugLogLevel');

  @override
  Future<void> configure(String apiKey, String appUserId) async {
    configuredUserIds.add(appUserId);
    await _step('configure');
    configured = true;
    currentUserId = appUserId;
  }

  @override
  Future<void> logIn(String appUserId) async {
    loggedInUserIds.add(appUserId);
    await _step('logIn');
    currentUserId = appUserId;
  }

  @override
  Future<bool> canMakePayments() async {
    await _step('canMakePayments');
    return true;
  }

  @override
  Future<List<purchases.StoreProduct>> getProducts(List<String> productIds) async {
    await _step('products');
    return [_product];
  }

  @override
  Future<void> purchase(purchases.StoreProduct product) async {
    purchaseUserIds.add(currentUserId);
    await _step('purchase');
  }

  @override
  Future<void> restorePurchases() async {
    restoreUserIds.add(currentUserId);
    await _step('restore');
  }

  @override
  Future<List<purchases.StoreProduct>> getNonSubscriptionProducts(List<String> ids) async {
    await _step('addonProducts');
    return [_addonProduct];
  }

  @override
  Future<StoreAddonTransaction> purchaseConsumable(purchases.StoreProduct product) async {
    purchaseUserIds.add(currentUserId);
    await _step('addonPurchase');
    return StoreAddonTransaction(productId: product.identifier, transactionId: addonPurchaseTransactionId);
  }

  @override
  Future<List<StoreAddonTransaction>> getAddonTransactions() async {
    await _step('addonTransactions');
    return addonTransactions.map((transaction) => StoreAddonTransaction(
      productId: transaction.productId, transactionId: transaction.transactionId,
      transactionIdKind: 'REVENUECAT')).toList();
  }
}

class _ReceiptWriteFailureStore implements AddonPendingStore {
  _ReceiptWriteFailureStore(this.rejectedTransactionId);
  final String rejectedTransactionId;
  final _saved = InMemoryAddonPendingStore();
  var _rejectReceiptOnce = true;

  @override
  Future<AddonPendingRecord?> load() => _saved.load();

  @override
  Future<void> save(AddonPendingRecord record) async {
    if (_rejectReceiptOnce && record.transactionId == rejectedTransactionId) {
      _rejectReceiptOnce = false;
      throw const AddonPendingDataException('Simulated process interruption before receipt persistence');
    }
    await _saved.save(record);
  }

  @override
  Future<void> clear({required String intentId}) => _saved.clear(intentId: intentId);
}
