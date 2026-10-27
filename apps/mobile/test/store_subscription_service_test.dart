import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

void main() {
  test('RevenueCat purchase does not poll after its native purchase outlives the account', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    var loadCalls = 0;
    final gateway = FakeRevenueCatBillingGateway(onPurchase: () {
      entered.complete();
      return release.future;
    });
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: gateway, useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async { loadCalls += 1; return _subscription(plan: 'PRO'); },
    );
    final failure = expectLater(service.startProSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signIn(const AuthSession(userId: 'buyer-b', idToken: 'dummy-b-token'));
    release.complete();
    await failure;
    expect(loadCalls, 0);
  });

  test('RevenueCat polling rejects a subscription loaded for a superseded session', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final loaded = Completer<SubscriptionStatusResult>();
    var loadCalls = 0;
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () { loadCalls += 1; entered.complete(); return loaded.future; },
    );
    final failure = expectLater(service.startProSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signIn(const AuthSession(userId: 'buyer-b', idToken: 'dummy-b-token'));
    loaded.complete(_subscription(plan: 'PRO'));
    await failure;
    expect(loadCalls, 1);
  });

  test('RevenueCat polling stops before another request after an account change during backoff', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    var loadCalls = 0;
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async { loadCalls += 1; return _subscription(plan: 'BASIC', userId: 'buyer-a'); },
      revenueCatEntitlementWait: (_) { entered.complete(); return release.future; },
    );
    final failure = expectLater(service.startProSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signOut();
    release.complete();
    await failure;
    expect(loadCalls, 1);
  });

  test('RevenueCat restore does not resync or poll after its native callback outlives the account', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    var resyncCalls = 0;
    var loadCalls = 0;
    final gateway = FakeRevenueCatBillingGateway(onRestore: () {
      entered.complete();
      return release.future;
    });
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: gateway, useRevenueCat: true,
      resyncRevenueCatSubscription: () async { resyncCalls += 1; return 'PRO'; },
      loadSubscription: () async { loadCalls += 1; return _subscription(plan: 'PRO'); },
    );
    final failure = expectLater(service.restoreSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signOut();
    release.complete();
    await failure;
    expect(resyncCalls, 0);
    expect(loadCalls, 0);
  });

  test('default RevenueCat HTTP preparation uses the captured operation binding during token refresh', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final token = Completer<String?>();
    session.setIdTokenRefresher(() { entered.complete(); return token.future; });
    final gateway = FakeRevenueCatBillingGateway();
    late _BoundBillingApiClient api;
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: gateway, useRevenueCat: true,
      apiClientFactory: (binding) => api = _BoundBillingApiClient(binding),
    );
    final failure = expectLater(service.startProSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signIn(const AuthSession(userId: 'buyer-b', idToken: 'dummy-b-token'));
    token.complete('dummy-a-refreshed-token');
    await failure;
    expect(gateway.purchasedProductId, isNull);
    expect(api.requestTokens, isEmpty);
    expect(api.calls, ['prepare']);
  });

  test('RevenueCat preparation and polling share one API client bound to the buyer', () async {
    final session = _signedInSession();
    var apiCreations = 0;
    late _BoundBillingApiClient api;
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      apiClientFactory: (binding) { apiCreations += 1; return api = _BoundBillingApiClient(binding); },
    );
    final result = await service.startProSubscription();
    expect(result.subscription.plan, 'PRO');
    expect(apiCreations, 1);
    expect(api.calls, ['prepare', 'load']);
    expect(api.requestTokens, ['dummy-a-token', 'dummy-a-token']);
  });

  test('RevenueCat polling rejects another account subscription even without a session change', () async {
    final service = StoreSubscriptionService(
      sessionStore: _signedInSession(), revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async => _subscription(plan: 'PRO', userId: 'buyer-b'),
    );
    await expectLater(service.startProSubscription(),
      throwsA(isA<StoreSubscriptionException>().having(
        (error) => error.message, 'message',
        'Subscription does not belong to the account that started this operation.',
      )),
    );
  });

  test('RevenueCat restore preserves session cancellation when a stale resync returns an API error', () async {
    final session = _signedInSession();
    final entered = Completer<void>();
    final resync = Completer<String>();
    var loadCalls = 0;
    final service = StoreSubscriptionService(
      sessionStore: session, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      resyncRevenueCatSubscription: () { entered.complete(); return resync.future; },
      loadSubscription: () async { loadCalls += 1; return _subscription(plan: 'PRO', userId: 'buyer-a'); },
    );
    final failure = expectLater(service.restoreSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
    await entered.future;
    session.signOut();
    resync.completeError(const ApiException('Old account resync failed', statusCode: 502));
    await failure;
    expect(loadCalls, 0);
  });

  test('startProSubscription verifies Android purchase token with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_pro_monthly',
          purchaseToken: 'android-purchase-token',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request);
      },
    );

    final result = await service.startProSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'ANDROID',
      'productId': 'postdee_pro_monthly',
      'purchaseToken': 'android-purchase-token',
    });
    expect(result.subscription.isPro, isTrue);
  });

  test('startProSubscription uses RevenueCat without store verify when enabled',
      () async {
    var verifyCalls = 0;
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_pro_monthly',
          purchaseToken: 'android-purchase-token',
        ),
      ),
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      verifyPurchase: (_) async {
        verifyCalls += 1;
        throw StateError('store verify should not be called');
      },
      loadSubscription: () async => _subscription(plan: 'PRO'),
    );

    final result = await service.startProSubscription();

    expect(revenueCatGateway.purchasedProductId, 'postdee_pro_monthly');
    expect(verifyCalls, 0);
    expect(result.purchase.provider, 'revenuecat');
    expect(result.subscription.isPro, isTrue);
  });

  test('startStarterSubscription polls until RevenueCat webhook entitlement',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: loadCalls < 3 ? 'BASIC' : 'STARTER');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    final result = await service.startStarterSubscription();

    expect(result.subscription.isStarter, isTrue);
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('startStarterSubscription stops polling when entitlement never arrives',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: 'BASIC');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    await expectLater(
      service.startStarterSubscription(),
      throwsA(isA<StoreSubscriptionException>()),
    );
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('RevenueCat entitlement polling retries transient backend failures',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async {
        loadCalls += 1;
        if (loadCalls == 1) {
          throw const ApiException('Backend is waking up', statusCode: 503);
        }
        return _subscription(plan: loadCalls == 2 ? 'BASIC' : 'PRO');
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    final result = await service.startProSubscription();

    expect(result.subscription.isPro, isTrue);
    expect(loadCalls, 3);
    expect(waitCalls, 2);
  });

  test('RevenueCat entitlement polling does not retry authentication errors',
      () async {
    var loadCalls = 0;
    var waitCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(),
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async {
        loadCalls += 1;
        throw const ApiException('Unauthorized', statusCode: 401);
      },
      revenueCatEntitlementPollAttempts: 3,
      revenueCatEntitlementWait: (_) async => waitCalls += 1,
    );

    await expectLater(
      service.startProSubscription(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(loadCalls, 1);
    expect(waitCalls, 0);
  });

  for (final plan in ['STARTER', 'PRO']) {
    test('$plan purchase stops when the session changes during readiness',
        () async {
      final sessionStore = PostDeeAuthSessionStore.instance;
      sessionStore.signIn(const AuthSession(idToken: 'dummy-purchase-A'));
      addTearDown(sessionStore.clear);
      final readiness = Completer<void>();
      final readinessStarted = Completer<void>();
      final gateway = FakeRevenueCatBillingGateway();
      var loadCalls = 0;
      final service = StoreSubscriptionService(
        revenueCatGateway: gateway,
        useRevenueCat: true,
        prepareSubscriptionPurchase: () {
          readinessStarted.complete();
          return readiness.future;
        },
        loadSubscription: () async {
          loadCalls += 1;
          return _subscription(plan: plan);
        },
      );
      final purchase = plan == 'STARTER'
          ? service.startStarterSubscription()
          : service.startProSubscription();
      final expectation = expectLater(
        purchase,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await readinessStarted.future;
      sessionStore.signOut();
      sessionStore.signIn(const AuthSession(idToken: 'dummy-purchase-B'));
      readiness.complete();
      await expectation;

      expect(gateway.purchasedProductId, isNull);
      expect(loadCalls, 0);
      expect(sessionStore.session.idToken, 'dummy-purchase-B');
    });

    test('$plan purchase waits for backend readiness before calling RevenueCat',
        () async {
      final readiness = Completer<void>();
      final readinessStarted = Completer<void>();
      final gateway = FakeRevenueCatBillingGateway();
      var loadCalls = 0;
      final service = StoreSubscriptionService(
        revenueCatGateway: gateway,
        useRevenueCat: true,
        prepareSubscriptionPurchase: () {
          readinessStarted.complete();
          return readiness.future;
        },
        loadSubscription: () async {
          loadCalls += 1;
          expect(gateway.purchasedProductId, isNotNull);
          return _subscription(plan: plan);
        },
      );

      final resultFuture = plan == 'STARTER'
          ? service.startStarterSubscription()
          : service.startProSubscription();
      await readinessStarted.future;
      expect(gateway.purchasedProductId, isNull);
      expect(loadCalls, 0);
      readiness.complete();
      final result = await resultFuture;

      expect(gateway.purchasedProductId,
          plan == 'STARTER' ? service.starterProductId : service.productId);
      expect(result.subscription.plan, plan);
      expect(loadCalls, 1);
    });

    test('$plan purchase does not call RevenueCat when backend readiness fails',
        () async {
      final gateway = FakeRevenueCatBillingGateway();
      var loadCalls = 0;
      final service = StoreSubscriptionService(
        revenueCatGateway: gateway,
        useRevenueCat: true,
        prepareSubscriptionPurchase: () async => throw const ApiException(
          'Account deletion is in progress.',
          statusCode: 409,
          code: 'ACCOUNT_DELETION_IN_PROGRESS',
        ),
        loadSubscription: () async {
          loadCalls += 1;
          return _subscription(plan: plan);
        },
      );

      await expectLater(
        plan == 'STARTER'
            ? service.startStarterSubscription()
            : service.startProSubscription(),
        throwsA(isA<ApiException>().having(
          (error) => error.code,
          'code',
          'ACCOUNT_DELETION_IN_PROGRESS',
        )),
      );
      expect(gateway.purchasedProductId, isNull);
      expect(loadCalls, 0);
    });

    for (final readinessError in [
      const ApiException('Route not found', statusCode: 404),
      const ApiException('Not implemented', statusCode: 501),
      const ApiException('Unsupported readiness response',
          code: 'PURCHASE_READINESS_UNSUPPORTED'),
    ]) {
      test('$plan purchase explains an incompatible API before opening the '
          'store (${readinessError.statusCode ?? readinessError.code})',
          () async {
        final gateway = FakeRevenueCatBillingGateway();
        var loadCalls = 0;
        final service = StoreSubscriptionService(
          revenueCatGateway: gateway,
          useRevenueCat: true,
          prepareSubscriptionPurchase: () async => throw readinessError,
          loadSubscription: () async {
            loadCalls += 1;
            return _subscription(plan: plan);
          },
        );

        await expectLater(
          plan == 'STARTER'
              ? service.startStarterSubscription()
              : service.startProSubscription(),
          throwsA(isA<StoreSubscriptionException>().having(
            (error) => error.message,
            'message',
            'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง',
          )),
        );
        expect(gateway.purchasedProductId, isNull);
        expect(loadCalls, 0);
      });
    }

    for (final readinessError in [
      const ApiException('Unauthorized', statusCode: 401),
      const ApiException('Service unavailable', statusCode: 503),
    ]) {
      test('$plan purchase preserves preparation failures '
          '(${readinessError.statusCode}) without opening the store', () async {
        final gateway = FakeRevenueCatBillingGateway();
        var loadCalls = 0;
        final service = StoreSubscriptionService(
          revenueCatGateway: gateway,
          useRevenueCat: true,
          prepareSubscriptionPurchase: () async => throw readinessError,
          loadSubscription: () async {
            loadCalls += 1;
            return _subscription(plan: plan);
          },
        );

        await expectLater(
          plan == 'STARTER'
              ? service.startStarterSubscription()
              : service.startProSubscription(),
          throwsA(same(readinessError)),
        );
        expect(gateway.purchasedProductId, isNull);
        expect(loadCalls, 0);
      });
    }
  }

  test('restoreSubscription restores once and accepts the active paid plan',
      () async {
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    var resyncCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      resyncRevenueCatSubscription: () async {
        resyncCalls += 1;
        return 'STARTER';
      },
      loadSubscription: () async => _subscription(plan: 'STARTER'),
    );

    final result = await service.restoreSubscription();

    expect(revenueCatGateway.restoreCalls, 1);
    expect(resyncCalls, 1);
    expect(result.purchase.productId, 'postdee_starter_monthly');
    expect(result.subscription.isStarter, isTrue);
  });

  test('restoreSubscription stops immediately when no purchase is available',
      () async {
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    var loadCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      resyncRevenueCatSubscription: () async => 'BASIC',
      loadSubscription: () async {
        loadCalls += 1;
        return _subscription(plan: 'BASIC');
      },
    );

    await expectLater(
      service.restoreSubscription(),
      throwsA(
        isA<StoreSubscriptionException>().having(
          (error) => error.message,
          'message',
          'ไม่พบรายการสมาชิกที่กู้คืนได้ในบัญชีนี้',
        ),
      ),
    );
    expect(revenueCatGateway.restoreCalls, 1);
    expect(loadCalls, 0);
  });

  final restoreResyncErrorCases = <({
    String? code,
    int statusCode,
    String expectedMessage,
  })>[
    (
      code: 'REVENUECAT_RESYNC_NOT_CONFIGURED',
      statusCode: 501,
      expectedMessage: 'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง',
    ),
    (
      code: 'REVENUECAT_ENTITLEMENT_NOT_MAPPED',
      statusCode: 409,
      expectedMessage:
          'พบรายการสมาชิกแล้ว แต่แพ็กเกจยังเชื่อมกับระบบไม่ถูกต้อง กรุณาติดต่อทีม PostDee',
    ),
    (
      code: 'REVENUECAT_RESYNC_FAILED',
      statusCode: 502,
      expectedMessage: 'เชื่อมต่อระบบสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    ),
    (
      code: null,
      statusCode: 501,
      expectedMessage: 'ระบบกู้คืนสมาชิกยังตั้งค่าไม่เสร็จ กรุณาลองใหม่ภายหลัง',
    ),
  ];

  for (final errorCase in restoreResyncErrorCases) {
    test(
        'restoreSubscription explains RevenueCat resync error '
        '${errorCase.code ?? errorCase.statusCode}', () async {
      final revenueCatGateway = FakeRevenueCatBillingGateway();
      var loadCalls = 0;
      final service = StoreSubscriptionService(
        revenueCatGateway: revenueCatGateway,
        useRevenueCat: true,
        resyncRevenueCatSubscription: () async => throw ApiException(
          'Backend RevenueCat resync failed',
          statusCode: errorCase.statusCode,
          code: errorCase.code,
        ),
        loadSubscription: () async {
          loadCalls += 1;
          return _subscription(plan: 'BASIC');
        },
      );

      await expectLater(
        service.restoreSubscription(),
        throwsA(
          isA<StoreSubscriptionException>().having(
            (error) => error.message,
            'message',
            errorCase.expectedMessage,
          ),
        ),
      );
      expect(revenueCatGateway.restoreCalls, 1);
      expect(loadCalls, 0);
    });
  }

  test('restoreProSubscription verifies iOS transaction id with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        restorePayload: const StorePurchasePayload.ios(
          productId: 'postdee_pro_monthly',
          transactionId: 'ios-transaction-id',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request);
      },
    );

    final result = await service.restoreProSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'IOS',
      'productId': 'postdee_pro_monthly',
      'transactionId': 'ios-transaction-id',
    });
    expect(result.subscription.isPro, isTrue);
  });

  test('startStarterSubscription verifies the Starter product with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        purchasePayload: const StorePurchasePayload.android(
          productId: 'postdee_starter_monthly',
          purchaseToken: 'android-starter-purchase-token',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request, plan: 'STARTER');
      },
    );

    final result = await service.startStarterSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'ANDROID',
      'productId': 'postdee_starter_monthly',
      'purchaseToken': 'android-starter-purchase-token',
    });
    expect(result.subscription.isStarter, isTrue);
  });

  test(
      'restoreStarterSubscription verifies the Starter transaction with backend',
      () async {
    VerifyStorePurchaseRequest? verifiedRequest;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(
        restorePayload: const StorePurchasePayload.ios(
          productId: 'postdee_starter_monthly',
          transactionId: 'ios-starter-transaction-id',
        ),
      ),
      verifyPurchase: (request) async {
        verifiedRequest = request;
        return _verifiedSubscription(request, plan: 'STARTER');
      },
    );

    final result = await service.restoreStarterSubscription();

    expect(verifiedRequest?.toJson(), {
      'platform': 'IOS',
      'productId': 'postdee_starter_monthly',
      'transactionId': 'ios-starter-transaction-id',
    });
    expect(result.subscription.isStarter, isTrue);
  });

  test('startProSubscription fails before backend verify when store is offline',
      () async {
    var verifyCalls = 0;
    final service = StoreSubscriptionService(
      gateway: FakeStoreBillingGateway(available: false),
      verifyPurchase: (_) async {
        verifyCalls += 1;
        throw StateError('verify should not be called');
      },
    );

    await expectLater(
      service.startProSubscription(),
      throwsA(isA<StoreSubscriptionException>()),
    );
    expect(verifyCalls, 0);
  });
}

StoreSubscriptionVerificationResult _verifiedSubscription(
  VerifyStorePurchaseRequest request, {
  String plan = 'PRO',
}) =>
    StoreSubscriptionVerificationResult(
      purchase: StorePurchaseResult(
        provider: 'store',
        platform: request.platform,
        productId: request.productId,
        verifiedAt: DateTime.parse('2026-06-04T00:00:00.000Z'),
        purchaseToken: request.purchaseToken,
        transactionId: request.transactionId,
      ),
      subscription: SubscriptionStatusResult(
        userId: 'seller-store',
        plan: plan,
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: plan == 'PRO',
        canUseAiAudioReview: false,
        canUseAiVideoReview: false,
      ),
    );

SubscriptionStatusResult _subscription({
  required String plan,
  String userId = 'seller-revenuecat',
}) =>
    SubscriptionStatusResult(
      userId: userId,
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
      canUseAiAudioReview: false,
      canUseAiVideoReview: false,
    );

class FakeStoreBillingGateway implements StoreBillingGateway {
  const FakeStoreBillingGateway({
    this.available = true,
    this.purchasePayload,
    this.restorePayload,
  });

  final bool available;

  final StorePurchasePayload? purchasePayload;
  final StorePurchasePayload? restorePayload;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      productIds
          .map(
            (productId) => StoreProductInfo(
              id: productId,
              title: 'PostDee Pro',
              description: 'Monthly Pro subscription',
              price: '299 THB',
            ),
          )
          .toList();

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async =>
      purchasePayload ??
      StorePurchasePayload.android(
        productId: productId,
        purchaseToken: 'android-purchase-token',
      );

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async =>
      restorePayload ??
      StorePurchasePayload.ios(
        productId: productId,
        transactionId: 'ios-transaction-id',
      );
}

class FakeRevenueCatBillingGateway implements RevenueCatBillingGateway {
  FakeRevenueCatBillingGateway({this.available = true, this.onPurchase, this.onRestore});

  final bool available;
  final Future<void> Function()? onPurchase;
  final Future<void> Function()? onRestore;
  String? purchasedProductId;
  var restoreCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async =>
      productIds
          .map(
            (productId) => StoreProductInfo(
              id: productId,
              title: 'PostDee RevenueCat',
              description: 'RevenueCat subscription',
              price: 'Test Store',
            ),
          )
          .toList();

  @override
  Future<void> buySubscription(String productId) async {
    purchasedProductId = productId;
    await onPurchase?.call();
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls += 1;
    await onRestore?.call();
  }
}

PostDeeAuthSessionStore _signedInSession() => PostDeeAuthSessionStore(
  initialSession: const AuthSession(userId: 'buyer-a', idToken: 'dummy-a-token'),
);

class _BoundBillingApiClient implements PostDeeApiClient {
  _BoundBillingApiClient(this.binding);
  final AuthSessionBinding binding;
  final calls = <String>[];
  final requestTokens = <String?>[];

  Future<void> _request(String name) async {
    calls.add(name);
    final token = await binding.currentIdToken();
    binding.ensureCurrent();
    requestTokens.add(token);
  }

  @override
  Future<void> prepareSubscriptionPurchase() => _request('prepare');

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    await _request('load');
    return _subscription(plan: 'PRO', userId: 'buyer-a');
  }

  @override
  Future<String> resyncRevenueCatSubscription() async {
    await _request('resync');
    return 'PRO';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
