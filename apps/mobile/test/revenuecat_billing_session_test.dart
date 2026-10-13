import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;

const _product = purchases.StoreProduct(
  'postdee_pro_monthly', 'Pro subscription', 'PostDee Pro', 1, 'THB1', 'THB',
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

class _FakePurchasesSdk implements RevenueCatPurchasesSdk {
  _FakePurchasesSdk({this.configured = true, this.currentUserId = 'account-a', this.onStep});
  bool configured;
  String currentUserId;
  final Future<void> Function(String step)? onStep;
  final calls = <String>[];
  final configuredUserIds = <String>[];
  final loggedInUserIds = <String>[];
  final purchaseUserIds = <String>[];
  final restoreUserIds = <String>[];

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
}
