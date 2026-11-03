import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _business = 'postdee_business_monthly';
const _pro = 'postdee_pro_monthly';
const _starter = 'postdee_starter_monthly';

SubscriptionStatusResult _status(
        {String plan = 'BUSINESS',
        String? purchasedPlan,
        bool available = true,
        String owner = 'business-owner'}) =>
    SubscriptionStatusResult.fromJson({
      'userId': owner,
      'plan': plan,
      'purchasedPlan': purchasedPlan,
      'status': 'ACTIVE',
      'businessPlanAvailable': available,
      'maxProfileLinks': 50,
      'monthlyPostLimit': 400,
      'monthlyAiCaptionLimit': 220,
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': false
    });

StoreSubscriptionVerificationResult _verified(
        VerifyStorePurchaseRequest request,
        {String? productId,
        String? platform,
        String? receipt,
        String plan = 'BUSINESS',
        String? purchasedPlan,
        String owner = 'business-owner'}) =>
    StoreSubscriptionVerificationResult(
        purchase: StorePurchaseResult(
            provider: 'store',
            platform: platform ?? request.platform,
            productId: productId ?? request.productId,
            verifiedAt: DateTime.utc(2026, 11, 2),
            purchaseToken: request.platform == 'ANDROID'
                ? receipt ?? request.purchaseToken
                : null,
            transactionId: request.platform == 'IOS'
                ? receipt ?? request.transactionId
                : null),
        subscription:
            _status(plan: plan, purchasedPlan: purchasedPlan, owner: owner));

void main() {
  for (final action in ['quote', 'purchase', 'restore']) {
    test('direct native Business $action stops before any provider request',
        () async {
      final f = _Fixture();
      final service = f.service();
      await expectLater(
          switch (action) {
            'quote' => service.loadBusinessProduct(),
            'purchase' => service.purchaseBusiness(),
            _ => service.restoreBusinessSubscription(),
          },
          throwsA(isA<StoreSubscriptionException>()));
      expect(f.native.queries, isEmpty);
      expect(f.native.buys, isEmpty);
      expect(f.native.restores, isEmpty);
      expect(f.requests, isEmpty);
      expect(f.preparations, 0);
    });
  }

  test(
      'legacy paid query is preserved and Business has an independent localized quote',
      () async {
    final f = _Fixture();
    final service = f.service();
    final products = await service.loadPaidProducts();
    expect(f.native.queries.single, {_starter, _pro});
    expect(products.map((p) => p.id), [_starter, _pro]);
    final businessService = f.service(rc: true);
    expect(businessService.supportsBusinessSubscriptions, isTrue);
    expect(service.supportsBusinessSubscriptions, isFalse);
    expect((await businessService.loadBusinessProduct())?.price, '€12.99');
    expect(f.revenueCat.queries.single, {_business});
  });

  test('dedicated Business metadata query rejects another SKU', () async {
    final f = _Fixture();
    f.revenueCat.products = const [
      StoreProductInfo(id: _pro, title: 'Pro', description: '', price: '฿299')
    ];
    expect(await f.service(rc: true).loadBusinessProduct(), isNull);
    expect(f.revenueCat.queries.single, {_business});
  });

  for (final old in {'STARTER': _starter, 'PRO': _pro}.entries) {
    test('Business upgrade uses authoritative purchased ${old.key} SKU',
        () async {
      final f = _Fixture()
        ..subscription = _status(plan: old.key, purchasedPlan: old.key);
      f.revenueCat.onBuy = (_) async {
        f.subscription = _status(purchasedPlan: 'BUSINESS');
      };
      final result = await f.service(rc: true).purchaseBusiness();
      expect(result.subscription.isBusiness, isTrue);
      expect(f.revenueCat.expectedOldProducts, [old.value]);
      expect(f.revenueCat.buys, [_business]);
    });
  }

  for (final effective in ['BASIC', 'BUSINESS']) {
    test('purchased Basic uses no old SKU beneath effective $effective',
        () async {
      final f = _Fixture()
        ..subscription = _status(plan: effective, purchasedPlan: 'BASIC');
      f.revenueCat.onBuy = (_) async {
        f.subscription = _status(purchasedPlan: 'BUSINESS');
      };
      await f.service(rc: true).purchaseBusiness();
      expect(f.revenueCat.expectedOldProducts, [null]);
      expect(f.revenueCat.buys, [_business]);
    });
  }

  test('a gateway without verified Business purchase support cannot dispatch',
      () async {
    final f = _Fixture();
    final unsupported = _UnsupportedBusinessGateway();
    final service = StoreSubscriptionService(
        useRevenueCat: true,
        sessionStore: f.sessions,
        revenueCatGateway: unsupported,
        loadSubscription: () async =>
            _status(plan: 'PRO', purchasedPlan: 'PRO'),
        prepareBusinessSubscriptionPurchase: () async {});
    expect(service.supportsBusinessSubscriptions, isFalse);
    await expectLater(service.purchaseBusiness(),
        throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
    expect(unsupported.buys, isEmpty);
  });

  test('legacy RevenueCat adapter can restore owned Business with sales off',
      () async {
    final f = _Fixture();
    final legacy = _UnsupportedBusinessGateway();
    final service = StoreSubscriptionService(
        useRevenueCat: true,
        sessionStore: f.sessions,
        revenueCatGateway: legacy,
        loadSubscription: () async =>
            _status(purchasedPlan: 'BUSINESS', available: false),
        resyncRevenueCatSubscription: () async => 'BUSINESS');
    final result = await service.restoreBusinessSubscription();
    expect(result.subscription.isBusiness, isTrue);
    expect(legacy.restores, 1);
    expect(legacy.buys, isEmpty);
    expect(service.supportsBusinessSubscriptions, isFalse);
  });

  test(
      'pending Business upgrade retries the same confirmation without a second replacement',
      () async {
    final f = _Fixture()
      ..subscription = _status(plan: 'STARTER', purchasedPlan: 'STARTER');
    f.revenueCat.onBuy = (_) async {};
    final service = f.service(rc: true);
    await expectLater(service.purchaseBusiness(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    await expectLater(service.purchaseBusiness(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    f.subscription = _status(purchasedPlan: 'BUSINESS');
    await service.retryPendingConfirmation();
    expect(service.hasPendingConfirmation, isFalse);
    expect(f.revenueCat.expectedOldProducts, [_starter]);
    expect(f.revenueCat.buys, [_business]);
  });

  for (final purchased in ['BUSINESS', 'UNKNOWN']) {
    test('purchased $purchased cannot be treated as a fresh Business purchase',
        () async {
      final f = _Fixture()..subscription = _status(purchasedPlan: purchased);
      await expectLater(f.service(rc: true).purchaseBusiness(),
          throwsA(isA<StoreBusinessPurchaseReconciliationException>()));
      expect(f.revenueCat.buys, isEmpty);
      expect(f.revenueCat.expectedOldProducts, isEmpty);
    });
  }

  test('Business RevenueCat checkout uses exact SKU and plan', () async {
    final f = _Fixture();
    final result = await f.service(rc: true).purchaseBusiness();
    expect(result.purchase.productId, _business);
    expect(result.subscription.isBusiness, isTrue);
    expect(f.preparations, 1);
    expect(f.revenueCat.buys, [_business]);
    expect(f.requests, isEmpty);
  });

  test('old API missing Business offer blocks RevenueCat before charge',
      () async {
    final f = _Fixture()
      ..subscription = _status(available: false, plan: 'BASIC');
    await expectLater(f.service(rc: true).purchaseBusiness(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(f.native.buys, isEmpty);
    expect(f.revenueCat.buys, isEmpty);
    expect(f.preparations, 0);
  });

  test('Business RevenueCat gate is refreshed immediately before charge',
      () async {
    final f = _Fixture();
    final service = f.service(rc: true);
    expect(await service.loadBusinessProduct(), isNotNull);
    f.subscription = _status(available: false);
    await expectLater(
        service.purchaseBusiness(), throwsA(isA<StoreSubscriptionException>()));
    expect(f.native.buys, isEmpty);
    expect(f.revenueCat.buys, isEmpty);
  });

  test('Business RevenueCat readiness failure never starts SDK payment',
      () async {
    final f = _Fixture()
      ..preparationFailure = const ApiException('Offer unavailable',
          code: 'BUSINESS_PLAN_UNAVAILABLE', statusCode: 409);
    await expectLater(
        f.service(rc: true).purchaseBusiness(), throwsA(isA<ApiException>()));
    expect(f.native.buys, isEmpty);
    expect(f.revenueCat.buys, isEmpty);
  });

  test('Business offer disabled during readiness stops RevenueCat dispatch',
      () async {
    final f = _Fixture();
    f.onPrepare = () async {
      f.subscription = _status(available: false);
    };
    await expectLater(f.service(rc: true).purchaseBusiness(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(f.preparations, 1);
    expect(f.native.buys, isEmpty);
    expect(f.revenueCat.buys, isEmpty);
  });
  for (final products in <List<StoreProductInfo>>[
    [],
    const [
      StoreProductInfo(id: _pro, title: '', description: '', price: '฿399')
    ],
    const [
      StoreProductInfo(id: _business, title: '', description: '', price: '')
    ],
    const [
      StoreProductInfo(id: _business, title: '', description: '', price: '   ')
    ],
  ]) {
    test(
        'missing or invalid exact Business quote cannot start purchase ${products.length}',
        () async {
      final f = _Fixture()..revenueCat.products = products;
      await expectLater(f.service(rc: true).purchaseBusiness(),
          throwsA(isA<StoreSubscriptionException>()));
      expect(f.revenueCat.buys, isEmpty);
    });
  }

  for (final mismatch in ['plan', 'purchasedPlan', 'owner']) {
    test('RevenueCat Business $mismatch mismatch keeps confirmation pending',
        () async {
      final f = _Fixture();
      f.revenueCat.onBuy = (_) async {
        f.subscription = _status(
            plan: mismatch == 'plan' ? 'PRO' : 'BUSINESS',
            purchasedPlan: mismatch == 'purchasedPlan' ? 'STARTER' : null,
            owner: mismatch == 'owner' ? 'other-owner' : 'business-owner');
      };
      final service = f.service(rc: true);
      await expectLater(service.purchaseBusiness(),
          throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
      expect(service.hasPendingConfirmation, isTrue);
      expect(f.revenueCat.buys, [_business]);
      expect(f.native.buys, isEmpty);
    });
  }

  test('unavailable RevenueCat cannot fall back to a native Business payment',
      () async {
    final f = _Fixture()..revenueCat.available = false;
    await expectLater(f.service(rc: true).purchaseBusiness(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(f.native.queries, isEmpty);
    expect(f.native.buys, isEmpty);
    expect(f.revenueCat.buys, isEmpty);
  });

  test('ambiguous Business metadata cannot choose a product or start checkout',
      () async {
    final f = _Fixture()
      ..revenueCat.products = const [
        StoreProductInfo(
            id: _business, title: '', description: '', price: '€12.99'),
        StoreProductInfo(
            id: _business, title: '', description: '', price: '€14.99'),
      ];
    await expectLater(f.service(rc: true).purchaseBusiness(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(f.revenueCat.buys, isEmpty);
    expect(f.requests, isEmpty);
  });

  test(
      'Business RevenueCat confirmation retry never buys again or falls back to native',
      () async {
    final f = _Fixture();
    f.revenueCat.onBuy = (_) async {
      f.subscription = _status(purchasedPlan: 'BASIC');
    };
    final service = f.service(rc: true);
    await expectLater(service.purchaseBusiness(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionException>()));
    f.subscription = _status(purchasedPlan: 'BUSINESS');
    await service.retryPendingConfirmation();
    expect(service.hasPendingConfirmation, isFalse);
    expect(f.revenueCat.buys, [_business]);
    expect(f.native.buys, isEmpty);
    expect(f.requests, isEmpty);
  });

  test('a Pro trial over Basic cannot confirm the paid Business entitlement',
      () async {
    final f = _Fixture()
      ..subscription = _status(plan: 'BUSINESS', purchasedPlan: 'BASIC');
    f.revenueCat.onBuy = (_) async {};
    final service = f.service(rc: true);
    await expectLater(service.purchaseBusiness(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    expect(f.revenueCat.buys, [_business]);
  });

  for (final unified in [false, true]) {
    test(
        'Business RevenueCat ${unified ? 'unified' : 'specific'} restore survives disabled sales',
        () async {
      final f = _Fixture()..subscription = _status(available: false);
      final service = f.service(rc: true);
      final result = unified
          ? await service.restoreSubscription()
          : await service.restoreBusinessSubscription();
      expect(result.purchase.productId, _business);
      expect(result.subscription.isBusiness, isTrue);
      expect(f.preparations, 0);
      expect(f.revenueCat.buys, isEmpty);
      expect(f.revenueCat.restores, 1);
    });
  }

  test(
      'rejected direct Business restore preserves a legacy Pro pending confirmation',
      () async {
    final f = _Fixture()..subscription = _status(plan: 'BASIC');
    f.verify = (_) async =>
        throw const ApiException('temporary error', statusCode: 503);
    final service = f.service();
    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    await expectLater(service.restoreBusinessSubscription(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(service.hasPendingConfirmation, isTrue);
    expect(f.native.restores, isEmpty);
    expect(f.native.buys, [_pro]);
  });

  for (final phase in ['gate', 'quote', 'prepare', 'purchase', 'confirm']) {
    test('Business rejects account replacement during $phase', () async {
      final f = _Fixture();
      final started = Completer<void>();
      final release = Completer<void>();
      Future<void> pause() {
        started.complete();
        return release.future;
      }

      if (phase == 'gate') f.onLoad = pause;
      if (phase == 'quote') f.revenueCat.onQuery = pause;
      if (phase == 'prepare') f.onPrepare = pause;
      if (phase == 'purchase') f.revenueCat.onBuy = (_) => pause();
      if (phase == 'confirm') {
        f.onLoad = () async {
          if (f.revenueCat.buys.isNotEmpty) await pause();
        };
      }
      final service = f.service(rc: true);
      final checked = expectLater(service.purchaseBusiness(),
          throwsA(isA<AuthSessionChangedException>()));
      await started.future;
      f.sessions.signIn(const AuthSession(
          userId: 'replacement-owner', idToken: 'other-token'));
      release.complete();
      await checked;
      expect(service.hasPendingConfirmation, isFalse);
      if (phase != 'purchase' && phase != 'confirm') {
        expect(f.revenueCat.buys, isEmpty);
      }
      expect(f.native.buys, isEmpty);
    });
  }

  for (final rc in [false, true]) {
    for (final target in ['STARTER', 'PRO']) {
      test(
          'active paid Business cannot start $target ${rc ? 'RC' : 'native'} checkout',
          () async {
        final f = _Fixture()..subscription = _status(purchasedPlan: 'BUSINESS');
        final service = f.service(rc: rc);
        await expectLater(
            target == 'STARTER'
                ? service.startStarterSubscription()
                : service.startProSubscription(),
            throwsA(isA<StoreSubscriptionException>()));
        expect(f.native.buys, isEmpty);
        expect(f.revenueCat.buys, isEmpty);
        expect(service.hasPendingConfirmation, isFalse);
      });

      test(
          'legacy purchased-plan fallback blocks active Business before $target ${rc ? 'RC' : 'native'}',
          () async {
        final f = _Fixture()..subscription = _status();
        final service = f.service(rc: rc);
        await expectLater(
            target == 'STARTER'
                ? service.startStarterSubscription()
                : service.startProSubscription(),
            throwsA(isA<StoreSubscriptionException>()));
        expect(f.native.buys, isEmpty);
        expect(f.revenueCat.buys, isEmpty);
      });

      test(
          '$target ${rc ? 'RC' : 'native'} preflight rejects account replacement before payment',
          () async {
        final f = _Fixture()
          ..subscription = _status(plan: 'BASIC', purchasedPlan: 'BASIC');
        final started = Completer<void>();
        final release = Completer<void>();
        f.onLoad = () {
          started.complete();
          return release.future;
        };
        final service = f.service(rc: rc);
        final checked = expectLater(
            target == 'STARTER'
                ? service.startStarterSubscription()
                : service.startProSubscription(),
            throwsA(isA<AuthSessionChangedException>()));
        await started.future;
        f.sessions.signIn(const AuthSession(
            userId: 'replacement-owner', idToken: 'other-token'));
        release.complete();
        await checked;
        expect(f.native.buys, isEmpty);
        expect(f.revenueCat.buys, isEmpty);
        expect(service.hasPendingConfirmation, isFalse);
      });

      test(
          '$target ${rc ? 'RC' : 'native'} preflight rejects another owner snapshot',
          () async {
        final f = _Fixture()
          ..subscription = _status(plan: 'BASIC', owner: 'another-owner');
        final service = f.service(rc: rc);
        await expectLater(
            target == 'STARTER'
                ? service.startStarterSubscription()
                : service.startProSubscription(),
            throwsA(isA<StoreSubscriptionException>()));
        expect(f.native.buys, isEmpty);
        expect(f.revenueCat.buys, isEmpty);
      });

      for (final trial in [false, true]) {
        test(
            '${trial ? 'effective Business trial' : 'expired Business reconciled to Basic'} permits $target ${rc ? 'RC' : 'native'}',
            () async {
          final f = _Fixture()
            ..subscription = _status(
                plan: trial ? 'BUSINESS' : 'BASIC', purchasedPlan: 'BASIC');
          final sku = target == 'STARTER' ? _starter : _pro;
          f.native.onBuy = () async {};
          f.revenueCat.onBuy = (_) async {
            f.subscription = _status(plan: target, purchasedPlan: target);
          };
          f.verify = (request) async =>
              _verified(request, plan: target, purchasedPlan: target);
          final service = f.service(rc: rc);
          final result = target == 'STARTER'
              ? await service.startStarterSubscription()
              : await service.startProSubscription();
          expect(result.purchase.productId, sku);
          expect(rc ? f.revenueCat.buys : f.native.buys, [sku]);
        });
      }
    }
  }
}

class _Fixture {
  _Fixture() {
    revenueCat.onBuy = (_) async {
      subscription = _status(purchasedPlan: 'BUSINESS');
    };
  }
  final sessions = PostDeeAuthSessionStore(
      initialSession:
          const AuthSession(userId: 'business-owner', idToken: 'fake-token'));
  final native = _NativeGateway();
  final revenueCat = _RevenueCatGateway();
  final requests = <VerifyStorePurchaseRequest>[];
  SubscriptionStatusResult subscription =
      _status(plan: 'BASIC', purchasedPlan: 'BASIC');
  var preparations = 0;
  Object? preparationFailure;
  Future<void> Function()? onLoad, onPrepare, onVerify;
  Future<StoreSubscriptionVerificationResult> Function(
      VerifyStorePurchaseRequest)? verify;

  StoreSubscriptionService service({bool rc = false}) =>
      StoreSubscriptionService(
          sessionStore: sessions,
          useRevenueCat: rc,
          gateway: native,
          revenueCatGateway: revenueCat,
          prepareBusinessSubscriptionPurchase: () async {
            preparations++;
            await onPrepare?.call();
            if (preparationFailure != null) throw preparationFailure!;
          },
          prepareSubscriptionPurchase: () async {},
          loadSubscription: () async {
            await onLoad?.call();
            return subscription;
          },
          resyncRevenueCatSubscription: () async =>
              subscription.purchasedPlan ?? subscription.plan,
          revenueCatEntitlementPollAttempts: 1,
          verifyPurchase: (request) async {
            requests.add(request);
            await onVerify?.call();
            return verify == null ? _verified(request) : await verify!(request);
          });
}

class _NativeGateway implements StoreBillingGateway {
  final queries = <Set<String>>[];
  final buys = <String>[];
  final restores = <String>[];
  List<StoreProductInfo>? products;
  StorePurchasePayload? payload;
  Future<void> Function()? onQuery, onBuy;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async {
    queries.add(Set.of(ids));
    await onQuery?.call();
    return products ??
        [
          for (final id in ids)
            StoreProductInfo(
                id: id, title: 'Monthly', description: '', price: '€12.99')
        ];
  }

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async {
    buys.add(productId);
    await onBuy?.call();
    return payload ??
        StorePurchasePayload.android(
            productId: productId, purchaseToken: 'business-native-token');
  }

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async {
    restores.add(productId);
    return StorePurchasePayload.ios(
        productId: productId, transactionId: 'business-restored-id');
  }
}

class _RevenueCatGateway
    implements RevenueCatBillingGateway, RevenueCatBusinessPurchaseGateway {
  final buys = <String>[];
  final queries = <Set<String>>[];
  final expectedOldProducts = <String?>[];
  var restores = 0;
  var available = true;
  List<StoreProductInfo>? products;
  Future<void> Function()? onQuery;
  Future<void> Function(String)? onBuy;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async {
    queries.add(Set.of(ids));
    await onQuery?.call();
    return products ??
        [
          for (final id in ids)
            StoreProductInfo(
                id: id, title: 'Monthly', description: '', price: '€12.99')
        ];
  }

  @override
  Future<void> buySubscription(String productId) async {
    buys.add(productId);
    await onBuy?.call(productId);
  }

  @override
  Future<void> buyBusinessSubscription(String productId,
      {String? expectedOldProductId}) async {
    expectedOldProducts.add(expectedOldProductId);
    await buySubscription(productId);
  }

  @override
  Future<void> restorePurchases() async {
    restores++;
  }
}

class _UnsupportedBusinessGateway implements RevenueCatBillingGateway {
  final buys = <String>[];
  var restores = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async =>
      const [];
  @override
  Future<void> buySubscription(String productId) async {
    buys.add(productId);
  }

  @override
  Future<void> restorePurchases() async {
    restores++;
  }
}
