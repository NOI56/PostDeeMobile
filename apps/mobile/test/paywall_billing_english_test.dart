import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

SubscriptionStatusResult _plan(String name) => SubscriptionStatusResult(
    userId: 'english-billing-owner',
    plan: name,
    status: name == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
    canSchedule: name != 'BASIC',
    canUseAiCaptions: name != 'BASIC',
    canUseAnalytics: name == 'PRO');

StoreSubscriptionVerificationResult _verified(String plan) =>
    StoreSubscriptionVerificationResult(
      purchase: StorePurchaseResult(
          provider: 'store',
          platform: 'ANDROID',
          productId: plan == 'STARTER'
              ? 'postdee_starter_monthly'
              : 'postdee_pro_monthly',
          verifiedAt: DateTime.utc(2026, 10, 28),
          purchaseToken: 'fake-receipt'),
      subscription: _plan(plan),
    );

const _addonResult = AddonConfirmationResult(
    confirmed: true,
    transactionId: 'fake-addon',
    postUnits: 100,
    aiCaptions: 50,
    policyVersion: 2,
    creditsExpire: false,
    expiresAt: null);

class _NoCheckoutGateway implements StoreBillingGateway {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async =>
      const [];
  @override
  Future<StorePurchasePayload> buySubscription(String id) async =>
      throw StateError('A screen test must use its injected fake operation');
  @override
  Future<StorePurchasePayload> restoreSubscription(String id) async =>
      throw StateError('A screen test must use its injected fake operation');
}

class _Subscription extends StoreSubscriptionService {
  _Subscription(PostDeeAuthSessionStore sessions)
      : super(
            gateway: _NoCheckoutGateway(),
            useRevenueCat: false,
            sessionStore: sessions);
  bool pending = false;
  bool storePending = false;
  bool acknowledgmentPending = false;
  final calls = <String>[];
  Future<StoreSubscriptionVerificationResult> Function()? buy;
  Future<StoreSubscriptionVerificationResult> Function()? retry;
  Future<StoreSubscriptionVerificationResult> Function()? restore;
  @override
  bool get supportsUnifiedRestore => true;
  @override
  bool get hasPendingConfirmation => pending;
  @override
  bool get hasPendingStoreOperation => storePending;
  @override
  bool get hasPendingStoreAcknowledgement => acknowledgmentPending;
  @override
  Future<List<StoreProductInfo>> loadPaidProducts() async => [
        StoreProductInfo(
            id: starterProductId,
            title: 'Starter',
            description: '',
            price: '€5.49'),
        StoreProductInfo(
            id: productId, title: 'Pro', description: '', price: '€8.49'),
      ];
  @override
  Future<StoreSubscriptionVerificationResult> startProSubscription() {
    calls.add('pro');
    return buy?.call() ?? Future.value(_verified('PRO'));
  }

  @override
  Future<StoreSubscriptionVerificationResult> startStarterSubscription() {
    calls.add('starter');
    return buy?.call() ?? Future.value(_verified('STARTER'));
  }

  @override
  Future<StoreSubscriptionVerificationResult> retryPendingConfirmation() {
    calls.add('retry');
    return retry?.call() ?? Future.value(_verified('PRO'));
  }

  @override
  Future<StoreSubscriptionVerificationResult> restoreSubscription() {
    calls.add('restore');
    return restore?.call() ?? Future.value(_verified('PRO'));
  }
}

class _Addon extends StoreAddonService {
  _Addon(PostDeeAuthSessionStore sessions) : super(sessionStore: sessions);
  bool pending = false;
  int purchases = 0;
  int retries = 0;
  Future<AddonConfirmationResult> Function()? buy;
  Future<AddonConfirmationResult> Function()? retry;
  @override
  bool get supportsPlatform => true;
  @override
  bool get hasPendingPurchase => pending;
  @override
  Future<AddonCatalogResult> loadCatalog() async => const AddonCatalogResult(
      enabled: true,
      eligible: true,
      productId: 'postdee_post100_caption50',
      postUnits: 100,
      aiCaptions: 50,
      priceThb: 49,
      policyVersion: 2,
      creditsExpire: false,
      expiresAt: null,
      purchasedPacks: 0,
      addonPostUnits: 0,
      addonAiCaptions: 0);
  @override
  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async =>
      const StoreProductInfo(
          id: 'postdee_post100_caption50',
          title: 'Pack',
          description: '',
          price: '€1.49');
  @override
  Future<AddonConfirmationResult> purchase() {
    purchases++;
    return buy?.call() ?? Future.value(_addonResult);
  }

  @override
  Future<AddonConfirmationResult> retryPendingPurchase() {
    retries++;
    return retry?.call() ?? Future.value(_addonResult);
  }
}

class _Fixture {
  final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(
          userId: 'english-billing-owner', idToken: 'fake-token'));
  late final service = _Subscription(sessions);
  late final addon = _Addon(sessions);
  final callbacks = <String>[];
  var addonCallbacks = 0;
  var reads = 0;
  String plan = 'BASIC';

  Widget app(
      {String languageCode = 'en', bool dark = false, double scale = 1}) {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    return MaterialApp(
      locale: Locale(languageCode),
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: child!),
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      supportedLocales: PostDeeLocalizations.supportedLocales,
      home: PaywallScreen(
          key: const ValueKey('english-billing'),
          sessionStore: sessions,
          service: service,
          addonService: addon,
          loadSubscription: () async {
            reads++;
            return _plan(plan);
          },
          onSubscribed: callbacks.add,
          onAddonPurchased: () => addonCallbacks++),
    );
  }
}

Future<void> _start(WidgetTester tester, Finder action) async {
  if (action.evaluate().isEmpty) {
    await tester.scrollUntilVisible(action, 300,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pump();
}

void main() {
  late _Fixture fixture;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.applyThemeMode(ThemeMode.light);
    fixture = _Fixture();
  });
  tearDown(() => fixture.sessions.dispose());

  testWidgets(
      'English subscription progress and verified success keep one checkout',
      (tester) async {
    final result = Completer<StoreSubscriptionVerificationResult>();
    fixture.service.buy = () => result.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.service.calls, isEmpty);
    await _start(tester, find.text('Subscribe Pro'));
    expect(find.text('Processing your purchase...'), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.service.calls, ['pro']);
    result.complete(_verified('PRO'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribed to Pro'), findsOneWidget);
    expect(find.text('Your plan features are now unlocked.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Processing your purchase...'), findsNothing);
    expect(fixture.callbacks, ['pro']);
    expect(fixture.service.calls, ['pro']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English restore progress applies only the verified plan',
      (tester) async {
    final result = Completer<StoreSubscriptionVerificationResult>();
    fixture.service.restore = () => result.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.text('Restore purchases'));
    expect(find.text('Restoring purchases...'), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    result.complete(_verified('STARTER'));
    await tester.pumpAndSettle();
    expect(find.text('Purchases restored'), findsOneWidget);
    expect(find.text('STARTER plan access has been restored.'), findsOneWidget);
    expect(fixture.callbacks, ['starter']);
    expect(fixture.service.calls, ['restore']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'purchase progress and success use the live locale without another checkout',
      (tester) async {
    final result = Completer<StoreSubscriptionVerificationResult>();
    fixture.service.buy = () => result.future;
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    await _start(tester, find.text('สมัคร Pro'));
    expect(find.text('กำลังดำเนินการสั่งซื้อ...'), findsOneWidget);
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    expect(find.text('Processing your purchase...'), findsOneWidget);
    expect(fixture.service.calls, ['pro']);
    expect(fixture.reads, 1);
    expect(fixture.callbacks, isEmpty);
    result.complete(_verified('PRO'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribed to Pro'), findsOneWidget);
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    expect(find.text('สมัคร Pro สำเร็จ'), findsOneWidget);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Subscribed to Pro'), findsOneWidget);
    expect(fixture.service.calls, ['pro']);
    expect(fixture.callbacks, ['pro']);
  });

  for (final operation in ['subscribe', 'retry', 'restore']) {
    testWidgets(
        'English $operation fallback error leaves the purchase unconfirmed',
        (tester) async {
      Future<StoreSubscriptionVerificationResult> failure() async =>
          throw StateError('opaque-provider-error');
      fixture.service.buy = failure;
      fixture.service.retry = failure;
      fixture.service.restore = failure;
      fixture.service.pending = operation == 'retry';
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _start(
          tester,
          operation == 'subscribe'
              ? find.text('Subscribe Pro')
              : operation == 'restore'
                  ? find.text('Restore purchases')
                  : find.byKey(const ValueKey('paywall-retry-purchase')));
      await tester.pumpAndSettle();
      final message = switch (operation) {
        'subscribe' => 'Could not subscribe. Please try again.',
        'retry' => 'Could not check your purchase. Please try again.',
        _ => 'Could not restore purchases. Please try again.',
      };
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('opaque-provider-error'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.callbacks, isEmpty);
      expect(fixture.service.calls,
          [operation == 'subscribe' ? 'pro' : operation]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unknown subscription service text remains unchanged in English',
      (tester) async {
    const custom = 'ข้อความเพิ่มเติมจากร้านค้าที่ไม่รู้จัก';
    fixture.service.buy =
        () async => throw const StoreSubscriptionException(custom);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.text('Subscribe Pro'));
    await tester.pumpAndSettle();
    expect(find.text(custom), findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.service.calls, ['pro']);
  });

  testWidgets('pending subscription error is localized when it finishes',
      (tester) async {
    final result = Completer<StoreSubscriptionVerificationResult>();
    fixture.service.buy = () => result.future;
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    await _start(tester, find.text('สมัคร Pro'));
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    result.completeError(StateError('opaque-late-error'));
    await tester.pumpAndSettle();
    expect(find.text('Could not subscribe. Please try again.'), findsOneWidget);
    expect(find.textContaining('opaque-late-error'), findsNothing);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.service.calls, ['pro']);
    expect(fixture.reads, 1);
  });

  testWidgets(
      'known subscription service error is translated without verification',
      (tester) async {
    fixture.service.buy = () async => throw const StoreSubscriptionException(
        'ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.text('Subscribe Pro'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Subscriptions are unavailable for this app version. Please try again later.'),
        findsOneWidget);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.service.calls, ['pro']);
  });

  for (final state in ['confirmation', 'store', 'acknowledgment']) {
    testWidgets('English $state warning keeps new payments locked',
        (tester) async {
      fixture.service.pending = true;
      fixture.service.storePending = state == 'store';
      fixture.service.acknowledgmentPending = state == 'acknowledgment';
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final message = switch (state) {
        'store' =>
          'The store result is not known yet. Check your previous purchase before buying again.',
        'acknowledgment' =>
          'Your store has not finished the previous purchase. Check it before buying again.',
        _ =>
          'Your store has processed the purchase, but PostDee could not confirm your plan yet. Check the purchase again without buying again.',
      };
      expect(find.text(message), findsOneWidget);
      expect(find.text('Check purchase again'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Subscribe Pro'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Subscribe Pro'))
              .onPressed,
          isNull);
      expect(fixture.service.calls, isEmpty);
      expect(fixture.callbacks, isEmpty);
    });
  }

  testWidgets(
      'pending subscription recheck confirms once without another payment',
      (tester) async {
    final confirmation = Completer<StoreSubscriptionVerificationResult>();
    fixture.service.buy = () async {
      fixture.service.pending = true;
      throw const StoreSubscriptionConfirmationPendingException();
    };
    fixture.service.retry = () => confirmation.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.text('Subscribe Pro'));
    await tester.pumpAndSettle();
    final warning =
        find.byKey(const ValueKey('paywall-purchase-awaiting-confirmation'));
    await tester.scrollUntilVisible(warning, -300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(warning);
    await tester.pumpAndSettle();
    final warningTexts = tester
        .widgetList<Text>(
            find.descendant(of: warning, matching: find.byType(Text)))
        .map((text) => text.data ?? '')
        .join(' ');
    expect(warningTexts, isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
    expect(find.text('Subscribed to Pro'), findsNothing);
    expect(fixture.callbacks, isEmpty);
    expect(fixture.service.calls, ['pro']);
    await _start(tester, find.byKey(const ValueKey('paywall-retry-purchase')));
    expect(find.text('Checking your purchase...'), findsOneWidget);
    fixture.service.pending = false;
    confirmation.complete(_verified('PRO'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase confirmed'), findsOneWidget);
    expect(find.text('PRO plan access has been restored.'), findsOneWidget);
    expect(fixture.service.calls, ['pro', 'retry']);
    expect(fixture.callbacks, ['pro']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English add-on progress and verified success call back once',
      (tester) async {
    fixture.plan = 'PRO';
    final confirmation = Completer<AddonConfirmationResult>();
    fixture.addon.buy = () => confirmation.future;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.addon.purchases, 0);
    await _start(tester, find.byKey(const ValueKey('paywall-buy-addon')));
    expect(find.text('Buying credit pack...'), findsOneWidget);
    expect(fixture.addonCallbacks, 0);
    expect(fixture.addon.purchases, 1);
    confirmation.complete(_addonResult);
    await tester.pumpAndSettle();
    expect(find.text('Credits added'), findsOneWidget);
    expect(
        find.text('Added 100 post units and 50 AI caption credits. Purchased '
            'credits do not expire. Your monthly quota is used first.'),
        findsOneWidget);
    expect(fixture.addonCallbacks, 1);
    expect(fixture.addon.purchases, 1);
    expect(fixture.service.calls, isEmpty);
  });

  testWidgets('pending add-on help and retry never start another payment',
      (tester) async {
    fixture.plan = 'PRO';
    fixture.addon.buy = () async {
      fixture.addon.pending = true;
      throw const StoreAddonPendingException();
    };
    fixture.addon.retry = () async {
      fixture.addon.pending = false;
      return _addonResult;
    };
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    expect(find.text('Credits added'), findsNothing);
    expect(fixture.addonCallbacks, 0);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('paywall-buy-addon')))
            .onPressed,
        isNull);
    await _start(tester, find.byKey(const ValueKey('paywall-addon-help')));
    await tester.pumpAndSettle();
    expect(find.text('Purchase help'), findsOneWidget);
    expect(find.textContaining('postdee.support@gmail.com'), findsOneWidget);
    final content =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(content, isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
    expect(content, contains('password'));
    expect(fixture.addon.purchases, 1);
    expect(fixture.addon.retries, 0);
    await tester.pumpWidget(fixture.app(languageCode: 'th'));
    await tester.pumpAndSettle();
    expect(find.text('ช่วยตรวจสอบการซื้อ'), findsOneWidget);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Purchase help'), findsOneWidget);
    expect(fixture.addon.purchases, 1);
    expect(fixture.addon.retries, 0);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await _start(tester, find.byKey(const ValueKey('paywall-retry-addon')));
    await tester.pumpAndSettle();
    expect(find.text('Credits added'), findsOneWidget);
    expect(fixture.addon.purchases, 1);
    expect(fixture.addon.retries, 1);
    expect(fixture.addonCallbacks, 1);
    expect(fixture.service.calls, isEmpty);
  });

  testWidgets('English add-on generic failure preserves no-success state',
      (tester) async {
    fixture.plan = 'PRO';
    fixture.addon.buy = () async => throw StateError('opaque-addon-error');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    expect(find.text('Could not buy the credit pack. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('opaque-addon-error'), findsNothing);
    expect(fixture.addonCallbacks, 0);
    expect(fixture.addon.purchases, 1);
    expect(find.text('Credits added'), findsNothing);
  });

  testWidgets('known refunded add-on service error adds no credits',
      (tester) async {
    fixture.plan = 'PRO';
    fixture.addon.buy = () async => throw const StoreAddonException(
        'รายการนี้ได้รับการคืนเงินหรือยกเลิกแล้ว จึงไม่เพิ่มเครดิต');
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _start(tester, find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This purchase was refunded or canceled, so no credits were added.'),
        findsOneWidget);
    expect(fixture.addonCallbacks, 0);
    expect(fixture.addon.purchases, 1);
    expect(fixture.service.calls, isEmpty);
  });

  for (final operation in ['subscribe', 'restore', 'retry', 'addon']) {
    testWidgets('English $operation rejects a previous owner late result',
        (tester) async {
      final subscription = Completer<StoreSubscriptionVerificationResult>();
      final addon = Completer<AddonConfirmationResult>();
      fixture.service.buy = () => subscription.future;
      fixture.service.restore = () => subscription.future;
      fixture.service.retry = () => subscription.future;
      fixture.service.pending = operation == 'retry';
      fixture.addon.buy = () => addon.future;
      if (operation == 'addon') fixture.plan = 'PRO';
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _start(
          tester,
          switch (operation) {
            'subscribe' => find.text('Subscribe Pro'),
            'restore' => find.text('Restore purchases'),
            'retry' => find.byKey(const ValueKey('paywall-retry-purchase')),
            _ => find.byKey(const ValueKey('paywall-buy-addon')),
          });
      fixture.sessions.signIn(const AuthSession(
          userId: 'replacement-owner', idToken: 'replacement'));
      await tester.pump();
      if (operation == 'addon') {
        addon.complete(_addonResult);
      } else {
        subscription.complete(_verified('PRO'));
      }
      await tester.pumpAndSettle();
      expect(fixture.callbacks, isEmpty);
      expect(fixture.addonCallbacks, 0);
      expect(find.byType(AlertDialog), findsNothing);
      final ownerError =
          find.byKey(const ValueKey('paywall-subscription-error'));
      await tester.scrollUntilVisible(ownerError, -300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(ownerError, findsOneWidget);
      final message = tester
          .widgetList<Text>(
              find.descendant(of: ownerError, matching: find.byType(Text)))
          .map((text) => text.data ?? '')
          .join(' ');
      expect(message, isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))));
      expect(fixture.sessions.session.stableUserId, 'replacement-owner');
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    for (final kind in ['progress', 'help', 'credits']) {
      testWidgets('English $kind billing dialog fits 320dp 2x (dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        fixture.plan = kind == 'progress' ? 'BASIC' : 'PRO';
        fixture.addon.pending = kind == 'help';
        final completion = Completer<StoreSubscriptionVerificationResult>();
        fixture.service.buy = () => completion.future;
        await tester.pumpWidget(fixture.app(dark: dark, scale: 2));
        await tester.pumpAndSettle();
        if (kind == 'progress') {
          await _start(tester, find.text('Subscribe Pro'));
          expect(find.text('Processing your purchase...'), findsOneWidget);
          expect(tester.takeException(), isNull);
          completion.complete(_verified('PRO'));
          await tester.pumpAndSettle();
          expect(find.text('Subscribed to Pro'), findsOneWidget);
        } else if (kind == 'help') {
          await _start(
              tester, find.byKey(const ValueKey('paywall-addon-help')));
          await tester.pumpAndSettle();
          expect(find.text('Purchase help'), findsOneWidget);
        } else {
          await _start(tester, find.byKey(const ValueKey('paywall-buy-addon')));
          await tester.pumpAndSettle();
          expect(find.text('Credits added'), findsOneWidget);
        }
        final close = find.text(kind == 'help' ? 'Got it' : 'OK');
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }
}
