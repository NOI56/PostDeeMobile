import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

void main() {
  SubscriptionStatusResult trialSubscription(String purchasedPlan) => SubscriptionStatusResult.fromJson({
    'userId':'seller-revenuecat','plan':'PRO','purchasedPlan':purchasedPlan,'status':'ACTIVE',
    'canSchedule':true,'canUseAiCaptions':true,'canUseAnalytics':true,
  });
  setUp(() {
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'seller-revenuecat', idToken: 'dummy-billing-token',
    ));
  });
  tearDown(PostDeeAuthSessionStore.instance.clear);

  test('a Pro trial cannot confirm an unpaid Pro purchase', () async {
    var loads = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async => trialSubscription(++loads == 1 ? 'BASIC' : 'PRO'),
      revenueCatEntitlementWait: (_) async {},
    );
    final result = await service.startProSubscription();
    expect(loads, 2);
    expect(result.subscription.plan, 'PRO');
  });

  test('Starter restore succeeds beneath a Pro trial while retaining Pro access', () async {
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      resyncRevenueCatSubscription: () async => 'STARTER',
      loadSubscription: () async => trialSubscription('STARTER'),
      revenueCatEntitlementPollAttempts: 1,
    );
    final result = await service.restoreStarterSubscription();
    expect(result.purchase.productId, 'postdee_starter_monthly');
    expect(result.subscription.plan, 'PRO');
  });

  test('default restore API uses paid resync with the original account binding', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId:'seller-revenuecat',idToken:'trial-owner'));
    late _TrialRestoreApi client;
    final service = StoreSubscriptionService(sessionStore:sessions,
      revenueCatGateway:FakeRevenueCatBillingGateway(),useRevenueCat:true,
      apiClientFactory:(binding)=>client=_TrialRestoreApi(binding));
    final result=await service.restoreStarterSubscription();
    expect(client.calls,['paid:trial-owner','load:trial-owner']);
    expect(result.subscription.plan,'PRO');
    expect(result.purchase.productId,'postdee_starter_monthly');
  });

  test('native pending purchase keeps its original binding after the UI timeout', () async {
    final sessions = PostDeeAuthSessionStore(initialSession:
      const AuthSession(userId: 'seller-revenuecat', idToken: 'owner-a'));
    final completion = Completer<StorePurchasePayload>();
    var verifications = 0;
    final service = StoreSubscriptionService(
      sessionStore: sessions,
      gateway: _DelayedStoreGateway(completion), useRevenueCat: false,
      storeOperationTimeout: const Duration(milliseconds: 20),
      verifyPurchase: (request) async { verifications += 1; return _verifiedSubscription(request); },
    );
    await expectLater(service.startProSubscription(),
      throwsA(isA<StoreSubscriptionStorePendingException>()));
    sessions.signIn(const AuthSession(userId: 'next-owner', idToken: 'owner-b'));
    await expectLater(service.retryPendingConfirmation(), throwsA(isA<AuthSessionChangedException>()));
    completion.complete(const StorePurchasePayload.android(
      productId: 'postdee_pro_monthly', purchaseToken: 'old-owner-receipt'));
    await Future<void>.delayed(Duration.zero);
    expect(verifications, 0);
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('native acknowledgement is never reconciled for the next account', () async {
    final sessions = PostDeeAuthSessionStore(initialSession:
      const AuthSession(userId: 'seller-revenuecat', idToken: 'owner-a'));
    final gateway = _AcknowledgementStoreGateway();
    final service = StoreSubscriptionService(
      sessionStore: sessions, gateway: gateway, useRevenueCat: false,
      verifyPurchase: (request) async => _verifiedSubscription(request),
    );
    await service.startProSubscription();
    expect(service.hasPendingStoreAcknowledgement, isTrue);
    sessions.signIn(const AuthSession(userId: 'next-owner', idToken: 'owner-b'));
    await expectLater(service.retryPendingConfirmation(), throwsA(isA<AuthSessionChangedException>()));
    expect(gateway.reconciliations, 0);
    expect(service.hasPendingConfirmation, isFalse);
    expect(service.hasPendingStoreAcknowledgement, isFalse);
    await expectLater(service.startProSubscription(), throwsA(isA<AuthSessionChangedException>()));
    expect(gateway.purchaseCalls, 1);
  });

  for (final starter in [false, true]) {
    test('readiness completes before ${starter ? 'Starter' : 'Pro'} purchase', () async {
      final prepared = Completer<void>();
      final preparationStarted = Completer<void>();
      final gateway = FakeRevenueCatBillingGateway();
      final service = StoreSubscriptionService(
        revenueCatGateway: gateway,
        useRevenueCat: true,
        prepareSubscriptionPurchase: () {
          preparationStarted.complete();
          return prepared.future;
        },
        loadSubscription: () async => _subscription(plan: starter ? 'STARTER' : 'PRO'),
      );
      final purchase = starter ? service.startStarterSubscription() : service.startProSubscription();
      await preparationStarted.future;
      expect(gateway.purchaseCalls, 0);
      prepared.complete();
      expect((await purchase).subscription.plan, starter ? 'STARTER' : 'PRO');
      expect(gateway.purchaseCalls, 1);
    });

    for (final failure in [
      const ApiException('Missing', statusCode: 404),
      const ApiException('Unsupported', statusCode: 501),
      const ApiException('Old protocol', code: 'PURCHASE_READINESS_UNSUPPORTED'),
    ]) {
      test('unsupported readiness blocks ${starter ? 'Starter' : 'Pro'} ${failure.statusCode ?? failure.code}', () async {
        final gateway = FakeRevenueCatBillingGateway();
        var loads = 0;
        final service = StoreSubscriptionService(
          revenueCatGateway: gateway,
          useRevenueCat: true,
          prepareSubscriptionPurchase: () async => throw failure,
          loadSubscription: () async { loads += 1; return _subscription(plan: 'PRO'); },
        );
        await expectLater(starter ? service.startStarterSubscription() : service.startProSubscription(),
          throwsA(isA<StoreSubscriptionException>().having((e) => e.message, 'message',
            'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง')));
        expect(gateway.purchaseCalls, 0);
        expect(loads, 0);
        expect(service.hasPendingConfirmation, isFalse);
      });
    }
  }

  test('switch during readiness never starts a purchase for the next account', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner-a', idToken: 'a'));
    final prepared = Completer<void>();
    final preparationStarted = Completer<void>();
    final gateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      sessionStore: sessions, revenueCatGateway: gateway, useRevenueCat: true,
      prepareSubscriptionPurchase: () { preparationStarted.complete(); return prepared.future; },
      loadSubscription: () async => throw StateError('must not load'),
    );
    final expectation = expectLater(service.startProSubscription(), throwsA(isA<AuthSessionChangedException>()));
    await preparationStarted.future;
    sessions.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    prepared.complete();
    await expectation;
    expect(gateway.purchaseCalls, 0);
  });

  test('pending confirmation retains its original binding after account changes', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner-a', idToken: 'a'));
    final gateway = FakeRevenueCatBillingGateway();
    var loads = 0;
    final service = StoreSubscriptionService(
      sessionStore: sessions, revenueCatGateway: gateway, useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async { loads += 1; throw const ApiException('Unavailable', statusCode: 503); },
      revenueCatEntitlementPollAttempts: 1,
    );
    await expectLater(service.startProSubscription(), throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    sessions.signIn(const AuthSession(userId: 'owner-b', idToken: 'b'));
    await expectLater(service.retryPendingConfirmation(), throwsA(isA<AuthSessionChangedException>()));
    expect(loads, 1);
    expect(gateway.purchaseCalls, 1);
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('RevenueCat refuses an entitlement from a different UID', () async {
    final service = StoreSubscriptionService(
      revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async => _subscription(plan: 'PRO', userId: 'another-user'),
    );
    await expectLater(service.startProSubscription(), throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
  });

  for (final status in [401, 409, 503]) {
    test('readiness preserves backend failure $status without buying', () async {
      final failure = ApiException('Blocked', statusCode: status);
      final gateway = FakeRevenueCatBillingGateway();
      final service = StoreSubscriptionService(
        revenueCatGateway: gateway, useRevenueCat: true,
        prepareSubscriptionPurchase: () async => throw failure,
        loadSubscription: () async => throw StateError('must not poll'),
      );
      await expectLater(service.startProSubscription(), throwsA(same(failure)));
      expect(gateway.purchaseCalls, 0);
    });
  }

  test('default billing API factory keeps preparation and confirmation in one binding', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'seller-revenuecat', idToken: 'original-token'));
    final clients = <_RecordingSubscriptionApi>[];
    final service = StoreSubscriptionService(
      sessionStore: sessions, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      apiClientFactory: (binding) {
        final api = _RecordingSubscriptionApi(binding);
        clients.add(api);
        return api;
      },
    );
    expect((await service.startProSubscription()).subscription.isPro, isTrue);
    expect(clients, hasLength(1));
    expect(clients.single.calls, ['prepare:original-token', 'load:original-token']);
  });

  test('default receipt verification keeps the purchase binding while a token refresh is pending', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'seller-revenuecat', idToken: 'original-token'));
    final refreshStarted = Completer<void>();
    final refreshed = Completer<AuthCredentialSnapshot?>();
    sessions.setAuthCredentialRefresher(() { refreshStarted.complete(); return refreshed.future; });
    late _RecordingSubscriptionApi api;
    final service = StoreSubscriptionService(
      sessionStore: sessions, gateway: FakeStoreBillingGateway(), useRevenueCat: false,
      apiClientFactory: (binding) => api = _RecordingSubscriptionApi(binding),
    );
    final expectation = expectLater(service.startProSubscription(), throwsA(isA<AuthSessionChangedException>()));
    await refreshStarted.future;
    sessions.signIn(const AuthSession(userId: 'next-account', idToken: 'next-token'));
    refreshed.complete(const AuthCredentialSnapshot(userId: 'next-account', idToken: 'next-token'));
    await expectation;
    expect(api.calls, isEmpty);
    expect(service.hasPendingConfirmation, isFalse);
  });

  for (final phase in ['availability', 'purchase', 'restore', 'resync']) {
    test('billing stops work after an account change during $phase', () async {
      final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'seller-revenuecat', idToken: 'a'));
      final started = Completer<void>();
      final release = Completer<void>();
      Future<void> pause() { started.complete(); return release.future; }
      var preparationCalls = 0;
      var resyncCalls = 0;
      var loads = 0;
      final gateway = FakeRevenueCatBillingGateway(
        onAvailable: phase == 'availability' ? pause : null,
        onPurchase: phase == 'purchase' ? pause : null,
        onRestore: phase == 'restore' ? pause : null,
      );
      final service = StoreSubscriptionService(
        sessionStore: sessions, revenueCatGateway: gateway, useRevenueCat: true,
        prepareSubscriptionPurchase: () async { preparationCalls += 1; },
        resyncRevenueCatSubscription: () async {
          resyncCalls += 1;
          if (phase == 'resync') await pause();
          return 'PRO';
        },
        loadSubscription: () async { loads += 1; return _subscription(plan: 'PRO'); },
      );
      final restoring = phase == 'restore' || phase == 'resync';
      final expectation = expectLater(restoring ? service.restoreSubscription() : service.startProSubscription(),
        throwsA(isA<AuthSessionChangedException>()));
      await started.future;
      sessions.signIn(const AuthSession(userId: 'next-account', idToken: 'b'));
      release.complete();
      await expectation;
      expect(loads, 0);
      expect(resyncCalls, phase == 'resync' ? 1 : 0);
      expect(preparationCalls, phase == 'purchase' ? 1 : 0);
      expect(service.hasPendingConfirmation, isFalse);
      if (phase == 'availability') expect(gateway.purchaseCalls, 0);
    });
  }

  test('polling never loads the next account after its wait callback changes the session', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'seller-revenuecat', idToken: 'a'));
    var loads = 0;
    final service = StoreSubscriptionService(
      sessionStore: sessions, revenueCatGateway: FakeRevenueCatBillingGateway(), useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async { loads += 1; return _subscription(plan: 'BASIC'); },
      revenueCatEntitlementWait: (_) async {
        sessions.signIn(const AuthSession(userId: 'next-account', idToken: 'b'));
      },
    );
    await expectLater(service.startProSubscription(), throwsA(isA<AuthSessionChangedException>()));
    expect(loads, 1);
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('a completed SDK timeout is an error, not an unfinished purchase', () async {
    final completion = Completer<StorePurchasePayload>();
    final gateway = _DelayedStoreGateway(completion);
    final service = StoreSubscriptionService(
      gateway: gateway,
      useRevenueCat: false,
      verifyPurchase: (request) async => _verifiedSubscription(request),
    );
    final purchase = service.startProSubscription();
    final expectation = expectLater(purchase, throwsA(isA<TimeoutException>()));
    completion.completeError(TimeoutException('SDK operation ended'));
    await expectation;
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('a late confirmed purchase awaiting the API shows receipt pending', () async {
    final completion = Completer<StorePurchasePayload>();
    final verification = Completer<StoreSubscriptionVerificationResult>();
    final service = StoreSubscriptionService(
      gateway: _DelayedStoreGateway(completion),
      useRevenueCat: false,
      storeOperationTimeout: const Duration(milliseconds: 20),
      verifyPurchase: (_) => verification.future,
    );
    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionStorePendingException>()));
    completion.complete(const StorePurchasePayload.android(
        productId: 'postdee_pro_monthly', purchaseToken: 'late-receipt'));
    await Future<void>.delayed(Duration.zero);
    expect(service.hasPendingConfirmation, isTrue);
    expect(service.hasPendingStoreOperation, isFalse);
    verification.complete(_verifiedSubscription(const VerifyStorePurchaseRequest.android(
        productId: 'postdee_pro_monthly', purchaseToken: 'late-receipt')));
    await service.retryPendingConfirmation();
  });

  test('a stalled store purchase stops waiting and rechecks without buying twice',
      () async {
    final completion = Completer<StorePurchasePayload>();
    final gateway = _DelayedStoreGateway(completion);
    final service = StoreSubscriptionService(gateway: gateway,
      useRevenueCat: false, storeOperationTimeout: const Duration(milliseconds: 30),
      verifyPurchase: (request) async => _verifiedSubscription(request));
    await expectLater(service.startProSubscription(),
      throwsA(isA<StoreSubscriptionStorePendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    await expectLater(service.startProSubscription(),
      throwsA(isA<StoreSubscriptionStorePendingException>()));
    completion.complete(const StorePurchasePayload.android(
      productId: 'postdee_pro_monthly', purchaseToken: 'delayed-receipt'));
    final result = await service.retryPendingConfirmation();
    expect(result.subscription.isPro, isTrue);
    expect(gateway.purchaseCalls, 1);
    expect(service.hasPendingConfirmation, isFalse);
  });
  test('session cache retains pending purchases only for the signed-in owner',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
        initialSession:
            AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    final gateway = FakeStoreBillingGateway();
    var verifyCalls = 0;
    final cache = StoreSubscriptionSessionCache(
      sessionStore: sessionStore,
      createService: () => StoreSubscriptionService(
        gateway: gateway,
        useRevenueCat: false,
        verifyPurchase: (_) async {
          verifyCalls += 1;
          throw const ApiException('Unavailable', statusCode: 503);
        },
      ),
    );
    addTearDown(cache.dispose);
    final original = cache.service;
    await expectLater(original.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));

    sessionStore.setAuthCredentialRefresher(() async =>
        const AuthCredentialSnapshot(userId: 'owner-a', idToken: 'rotated-token'));
    expect(await sessionStore.currentIdToken(), 'rotated-token');
    sessionStore.updateDisplayName('Renamed owner');
    expect(cache.service, same(original));
    expect(cache.service.hasPendingConfirmation, isTrue);
    sessionStore.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    expect(cache.service, isNot(same(original)));
    expect(cache.service.hasPendingConfirmation, isFalse);
    expect(original.hasPendingConfirmation, isFalse);
    await expectLater(original.retryPendingConfirmation(),
        throwsA(isA<StoreSubscriptionException>()));
    expect(verifyCalls, 1);
    expect(gateway.purchaseCalls, 1);

    sessionStore.clear();
    expect(cache.service, isNot(same(cache.service)));
    sessionStore.signIn(AuthSession.authenticated(
        userId: 'owner-a', idToken: 'new-session-token'));
    expect(cache.service, isNot(same(original)));
    expect(cache.service.hasPendingConfirmation, isFalse);
  });

  test('same-UID sign-in starts a new billing cache lifecycle', () async {
    final sessions = PostDeeAuthSessionStore(initialSession: const AuthSession(userId: 'owner-a', idToken: 'a'));
    final gateway = FakeStoreBillingGateway();
    final cache = StoreSubscriptionSessionCache(
      sessionStore: sessions,
      createService: () => StoreSubscriptionService(
        gateway: gateway, useRevenueCat: false,
        verifyPurchase: (_) async => throw const ApiException('Unavailable', statusCode: 503),
      ),
    );
    addTearDown(cache.dispose);
    final previous = cache.service;
    await expectLater(previous.startProSubscription(), throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    sessions.signIn(const AuthSession(userId: 'owner-a', idToken: 'new-sign-in-token'));
    expect(cache.service, isNot(same(previous)));
    expect(cache.service.hasPendingConfirmation, isFalse);
    expect(previous.hasPendingConfirmation, isFalse);
  });

  test('legacy completed purchase can recheck the same receipt without buying',
      () async {
    final gateway = FakeStoreBillingGateway();
    final verifiedRequests = <VerifyStorePurchaseRequest>[];
    final service = StoreSubscriptionService(
      gateway: gateway,
      useRevenueCat: false,
      verifyPurchase: (request) async {
        verifiedRequests.add(request);
        if (verifiedRequests.length == 1) {
          throw const ApiException('Service Suspended', statusCode: 503);
        }
        return _verifiedSubscription(request);
      },
    );

    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    await expectLater(service.startStarterSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    final result = await service.retryPendingConfirmation();

    expect(result.subscription.isPro, isTrue);
    expect(service.hasPendingConfirmation, isFalse);
    expect(gateway.purchaseCalls, 1);
    expect(verifiedRequests, hasLength(2));
    expect(verifiedRequests.first.toJson(), verifiedRequests.last.toJson());
  });

  test('account switch rejects an old in-flight verification result', () async {
    final sessionStore = PostDeeAuthSessionStore(
        initialSession:
            AuthSession.authenticated(userId: 'owner-a', idToken: 'token-a'));
    final verification = Completer<StoreSubscriptionVerificationResult>();
    var verifyCalls = 0;
    final cache = StoreSubscriptionSessionCache(
      sessionStore: sessionStore,
      createService: () => StoreSubscriptionService(
        gateway: FakeStoreBillingGateway(),
        useRevenueCat: false,
        verifyPurchase: (_) {
          verifyCalls += 1;
          return verification.future;
        },
      ),
    );
    addTearDown(cache.dispose);
    final oldService = cache.service;
    final purchase = oldService.startProSubscription();
    final expectation = expectLater(
        purchase,
        throwsA(isA<StoreSubscriptionException>().having(
            (error) => error.message,
            'message',
            'บัญชีเปลี่ยนแล้ว กรุณาเปิดหน้าแพ็กเกจใหม่')));
    await Future<void>.delayed(Duration.zero);
    sessionStore.signIn(
        AuthSession.authenticated(userId: 'owner-b', idToken: 'token-b'));
    verification.complete(_verifiedSubscription(
        const VerifyStorePurchaseRequest.android(
            productId: 'postdee_pro_monthly',
            purchaseToken: 'old-owner-token')));
    await expectation;
    expect(verifyCalls, 1);
    expect(oldService.hasPendingConfirmation, isFalse);
    expect(cache.service.hasPendingConfirmation, isFalse);
  });

  test('a timed out receipt retry shares the unfinished verification',
      () async {
    final verification = Completer<StoreSubscriptionVerificationResult>();
    final gateway = FakeStoreBillingGateway();
    var verifyCalls = 0;
    final service = StoreSubscriptionService(
      gateway: gateway,
      useRevenueCat: false,
      subscriptionConfirmationTimeout: const Duration(milliseconds: 50),
      verifyPurchase: (_) {
        verifyCalls += 1;
        return verification.future;
      },
    );

    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    expect(service.hasPendingConfirmation, isTrue);
    final retry = service.retryPendingConfirmation();
    verification.complete(_verifiedSubscription(
      const VerifyStorePurchaseRequest.android(
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token',
      ),
    ));

    expect((await retry).subscription.isPro, isTrue);
    expect(verifyCalls, 1);
    expect(gateway.purchaseCalls, 1);
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('RevenueCat confirmation deadline stops polling and late updates',
      () async {
    final backend = Completer<SubscriptionStatusResult>();
    var backendAvailable = false;
    var loadCalls = 0;
    final gateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      revenueCatGateway: gateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      subscriptionConfirmationTimeout: const Duration(milliseconds: 50),
      loadSubscription: () {
        loadCalls += 1;
        return backendAvailable
            ? Future.value(_subscription(plan: 'PRO'))
            : backend.future;
      },
      revenueCatEntitlementWait: (_) async {},
    );

    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    // A timeout rounded to milliseconds may allow another attempt within the
    // remaining budget. The backend stays pending until the explicit retry.
    final callsAtDeadline = loadCalls;
    expect(callsAtDeadline, greaterThanOrEqualTo(1));
    backend.complete(_subscription(plan: 'PRO'));
    await Future<void>.delayed(Duration.zero);
    expect(loadCalls, callsAtDeadline);
    expect(service.hasPendingConfirmation, isTrue);

    backendAvailable = true;
    expect(
        (await service.retryPendingConfirmation()).subscription.isPro, isTrue);
    expect(loadCalls, callsAtDeadline + 1);
    expect(gateway.purchaseCalls, 1);
    expect(service.hasPendingConfirmation, isFalse);
  });

  test('RevenueCat cancellation never records a completed purchase', () async {
    final gateway = FakeRevenueCatBillingGateway(
      purchaseError: const StoreSubscriptionException('Purchase canceled'),
    );
    final service = StoreSubscriptionService(
      revenueCatGateway: gateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async => throw StateError('must not check backend'),
    );

    await expectLater(
        service.startProSubscription(),
        throwsA(isA<StoreSubscriptionException>()
            .having((error) => error.message, 'message', 'Purchase canceled')));
    expect(service.hasPendingConfirmation, isFalse);
    expect(gateway.purchaseCalls, 1);
  });

  test('restoring the purchased plan clears pending confirmation safely',
      () async {
    var backendAvailable = false;
    final gateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      revenueCatGateway: gateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      revenueCatEntitlementPollAttempts: 1,
      resyncRevenueCatSubscription: () async => 'PRO',
      loadSubscription: () async {
        if (!backendAvailable) {
          throw const ApiException('Unavailable', statusCode: 503);
        }
        return _subscription(plan: 'PRO');
      },
    );

    await expectLater(service.startProSubscription(),
        throwsA(isA<StoreSubscriptionConfirmationPendingException>()));
    backendAvailable = true;
    final result = await service.restoreSubscription();

    expect(result.subscription.isPro, isTrue);
    expect(service.hasPendingConfirmation, isFalse);
    expect(gateway.purchaseCalls, 1);
    expect(gateway.restoreCalls, 1);
  });

  test(
      'completed RevenueCat purchase stays pending when backend is unavailable',
      () async {
    final gateway = FakeRevenueCatBillingGateway();
    final service = StoreSubscriptionService(
      revenueCatGateway: gateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
      loadSubscription: () async =>
          throw const ApiException('Service Suspended', statusCode: 503),
      revenueCatEntitlementPollAttempts: 1,
    );

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await expectLater(
        service.startProSubscription(),
        throwsA(isA<StoreSubscriptionException>().having(
          (error) => error.message,
          'message',
          'ร้านค้าดำเนินการซื้อแล้ว แต่ PostDee ยังยืนยันแพ็กเกจไม่ได้ กรุณาตรวจสอบการซื้ออีกครั้งโดยไม่ต้องซื้อซ้ำ',
        )),
      );
    }
    expect(gateway.purchaseCalls, 1);
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
        isA<StoreSubscriptionConfirmationPendingException>().having(
          (error) => error.cause,
          'cause',
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      ),
    );
    expect(loadCalls, 1);
    expect(waitCalls, 0);
  });

  test('restoreSubscription restores once and accepts the active paid plan',
      () async {
    final revenueCatGateway = FakeRevenueCatBillingGateway();
    var resyncCalls = 0;
    final service = StoreSubscriptionService(
      revenueCatGateway: revenueCatGateway,
      useRevenueCat: true,
      prepareSubscriptionPurchase: () async {},
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
      prepareSubscriptionPurchase: () async {},
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
        prepareSubscriptionPurchase: () async {},
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
        userId: 'seller-revenuecat',
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

class _DelayedStoreGateway extends FakeStoreBillingGateway {
  _DelayedStoreGateway(this.completion);
  final Completer<StorePurchasePayload> completion;
  @override
  Future<StorePurchasePayload> buySubscription(String productId) {
    purchaseCalls++;
    return completion.future;
  }
}

class _AcknowledgementStoreGateway extends FakeStoreBillingGateway
    implements PendingNativePurchaseReconciler {
  var reconciliations = 0;
  @override
  bool get hasPendingAcknowledgement => true;
  @override
  Future<void> reconcilePendingPurchase() async { reconciliations += 1; }
}

class FakeStoreBillingGateway implements StoreBillingGateway {
  FakeStoreBillingGateway({
    this.available = true,
    this.purchasePayload,
    this.restorePayload,
  });

  final bool available;

  final StorePurchasePayload? purchasePayload;
  final StorePurchasePayload? restorePayload;
  var purchaseCalls = 0;

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
  Future<StorePurchasePayload> buySubscription(String productId) async {
    purchaseCalls += 1;
    return purchasePayload ??
        StorePurchasePayload.android(
          productId: productId,
          purchaseToken: 'android-purchase-token',
        );
  }

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async =>
      restorePayload ??
      StorePurchasePayload.ios(
        productId: productId,
        transactionId: 'ios-transaction-id',
      );
}

class _TrialRestoreApi extends PostDeeApiClient {
  _TrialRestoreApi(this.binding):super(sessionBinding:binding);
  final AuthSessionBinding binding;
  final calls=<String>[];
  @override
  Future<String> resyncRevenueCatSubscription() async => throw StateError('must not use effective trial plan to restore');
  @override
  Future<String> resyncRevenueCatPurchasedSubscription() async { calls.add('paid:${await binding.currentIdToken()}');return 'STARTER'; }
  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    calls.add('load:${await binding.currentIdToken()}');
    return SubscriptionStatusResult.fromJson({'userId':'seller-revenuecat','plan':'PRO','purchasedPlan':'STARTER','status':'ACTIVE',
      'canSchedule':true,'canUseAiCaptions':true,'canUseAnalytics':true});
  }
}

class _RecordingSubscriptionApi extends PostDeeApiClient {
  _RecordingSubscriptionApi(this.binding) : super(sessionBinding: binding);
  final AuthSessionBinding binding;
  final calls = <String>[];

  @override
  Future<void> prepareSubscriptionPurchase() async {
    calls.add('prepare:${await binding.currentIdToken()}');
  }

  @override
  Future<SubscriptionStatusResult> loadCurrentSubscription() async {
    calls.add('load:${await binding.currentIdToken()}');
    return _subscription(plan: 'PRO');
  }

  @override
  Future<StoreSubscriptionVerificationResult> verifyStoreSubscription(VerifyStorePurchaseRequest request) async {
    calls.add('verify:${await binding.currentIdToken()}');
    return _verifiedSubscription(request);
  }
}

class FakeRevenueCatBillingGateway implements RevenueCatBillingGateway {
  FakeRevenueCatBillingGateway({
    this.available = true, this.purchaseError,
    this.onAvailable, this.onPurchase, this.onRestore,
  });

  final bool available;
  final StoreSubscriptionException? purchaseError;
  final Future<void> Function()? onAvailable;
  final Future<void> Function()? onPurchase;
  final Future<void> Function()? onRestore;
  String? purchasedProductId;
  var purchaseCalls = 0;
  var restoreCalls = 0;

  @override
  Future<bool> isAvailable() async {
    await onAvailable?.call();
    return available;
  }

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
    purchaseCalls += 1;
    await onPurchase?.call();
    if (purchaseError != null) throw purchaseError!;
    purchasedProductId = productId;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls += 1;
    await onRestore?.call();
  }
}
