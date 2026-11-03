import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _owner = 'business-paywall-owner';
const _businessSku = 'postdee_business_monthly';

SubscriptionStatusResult _status(String plan,
        {bool available = true, String? purchasedPlan}) =>
    SubscriptionStatusResult(
        userId: _owner,
        plan: plan,
        status: 'ACTIVE',
        purchasedPlan: purchasedPlan,
        businessPlanAvailable: available,
        monthlyPostLimit: plan == 'BUSINESS' ? 400 : 3,
        maxProfileLinks: plan == 'BUSINESS' ? 50 : 2,
        canSchedule: plan != 'BASIC',
        canUseAiCaptions: plan != 'BASIC',
        canUseAnalytics: false);

StoreSubscriptionVerificationResult _verified({bool available = true}) =>
    StoreSubscriptionVerificationResult(
        purchase: StorePurchaseResult(
            provider: 'store',
            platform: 'ANDROID',
            productId: _businessSku,
            verifiedAt: DateTime.utc(2026, 11, 3)),
        subscription: _status('BUSINESS', available: available));

class _Gateway implements StoreBillingGateway {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async => [];
  @override
  Future<StorePurchasePayload> buySubscription(String id) async =>
      throw StateError('Unexpected native checkout');
  @override
  Future<StorePurchasePayload> restoreSubscription(String id) async =>
      throw StateError('Unexpected native restore');
}

class _Billing extends StoreSubscriptionService {
  _Billing(PostDeeAuthSessionStore sessions)
      : super(
            sessionStore: sessions, gateway: _Gateway(), useRevenueCat: false);
  int paidReads = 0;
  int businessReads = 0;
  String starterPrice = '€5.49';
  String proPrice = '€8.49';
  bool pending = false;
  bool businessSupported = true;
  Object? quoteError;
  StoreProductInfo? quote = const StoreProductInfo(
      id: _businessSku,
      title: 'Store business',
      description: '',
      price: '€10,99');
  Future<StoreProductInfo?>? quoteGate;
  final operations = <String>[];
  Future<StoreSubscriptionVerificationResult>? purchaseGate;
  Object? purchaseError;
  @override
  bool get supportsUnifiedRestore => true;
  @override
  bool get supportsBusinessSubscriptions => businessSupported;
  @override
  bool get hasPendingConfirmation => pending;
  @override
  Future<List<StoreProductInfo>> loadPaidProducts() async {
    paidReads++;
    return [
      StoreProductInfo(
          id: starterProductId, title: '', description: '', price: starterPrice),
      StoreProductInfo(
          id: productId, title: '', description: '', price: proPrice)
    ];
  }

  @override
  Future<StoreProductInfo?> loadBusinessProduct() async {
    businessReads++;
    if (quoteError != null) throw quoteError!;
    return quoteGate == null ? quote : await quoteGate!;
  }

  @override
  Future<StoreSubscriptionVerificationResult> purchaseBusiness() async {
    operations.add('business');
    if (purchaseError != null) throw purchaseError!;
    return purchaseGate == null ? _verified() : await purchaseGate!;
  }

  @override
  Future<StoreSubscriptionVerificationResult> startStarterSubscription() async {
    operations.add('starter');
    throw StateError('Wrong plan action');
  }

  @override
  Future<StoreSubscriptionVerificationResult> startProSubscription() async {
    operations.add('pro');
    throw StateError('Wrong plan action');
  }

  @override
  Future<StoreSubscriptionVerificationResult> retryPendingConfirmation() async {
    operations.add('retry');
    pending = false;
    return _verified(available: false);
  }

  @override
  Future<StoreSubscriptionVerificationResult> restoreSubscription() async {
    operations.add('restore');
    return _verified(available: false);
  }
}

class _Addons extends StoreAddonService {
  _Addons(PostDeeAuthSessionStore sessions) : super(sessionStore: sessions);
  bool pending = false;
  @override
  bool get hasPendingPurchase => pending;
  @override
  Future<AddonCatalogResult> loadCatalog() async => const AddonCatalogResult(
      enabled: false,
      eligible: false,
      productId: 'postdee_post100_caption50',
      postUnits: 100,
      aiCaptions: 50,
      priceThb: 49,
      policyVersion: 2,
      creditsExpire: false,
      purchasedPacks: 0);
}

class _Fixture {
  final sessions = PostDeeAuthSessionStore(
      initialSession:
          const AuthSession(userId: _owner, idToken: 'fixture-token'));
  late final billing = _Billing(sessions);
  late final addons = _Addons(sessions);
  String plan = 'BASIC';
  String? purchasedPlan;
  bool available = true;
  int reads = 0;
  final callbacks = <String>[];
  Widget app({String language = 'en', bool dark = false, double scale = 1}) {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(language),
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!),
        home: PaywallScreen(
            sessionStore: sessions,
            service: billing,
            addonService: addons,
            onSubscribed: callbacks.add,
            loadSubscription: () async {
              reads++;
              return _status(plan,
                  available: available, purchasedPlan: purchasedPlan);
            }));
  }

  void dispose() => sessions.dispose();
}

Finder _key(String value) => find.byKey(ValueKey(value));
Future<void> _reveal(WidgetTester tester, Finder target,
    {bool settle = true}) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(target, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  if (settle) await tester.pumpAndSettle();
}

void main() {
  final previewDirectory = Platform.environment['POSTDEE_BUSINESS_PREVIEW_DIR'];
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));
  for (final language in ['th', 'en']) {
    testWidgets('Business ownership reconciliation explains recovery without success ($language)',
        (tester) async {
      final fixture = _Fixture();
      fixture.billing.purchaseError =
          const StoreBusinessPurchaseReconciliationException();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app(language: language));
      await tester.pumpAndSettle();
      final buy = _key('paywall-subscribe-business');
      await _reveal(tester, buy);
      await tester.tap(buy);
      await tester.pumpAndSettle();
      expect(find.text(language == 'th'
          ? 'กรุณากู้คืนการซื้อ หรือตรวจสอบสมาชิกเดิมในร้านค้าที่สมัครไว้ก่อนสมัคร Business'
          : 'Restore purchases or check your existing subscription in the original store before subscribing to Business.'),
          findsOneWidget);
      expect(fixture.billing.operations, ['business']);
      expect(fixture.callbacks, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Subscribed to Business'), findsNothing);
      expect(find.text('สมัคร Business สำเร็จ'), findsNothing);
      expect(find.textContaining(_businessSku), findsNothing);
      expect(tester.widget<FilledButton>(buy).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Business new sale stays unavailable without the supported billing provider',
      (tester) async {
    final fixture = _Fixture();
    fixture.billing.businessSupported = false;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Pro'));
    expect(find.text('Business'), findsNothing);
    expect(fixture.billing.businessReads, 0);
    expect(fixture.billing.operations, isEmpty);
    fixture.plan = 'BUSINESS';
    fixture.purchasedPlan = 'BUSINESS';
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Business'));
    expect(find.text('Current plan'), findsOneWidget);
    expect(_key('paywall-subscribe-business'), findsNothing);
    expect(fixture.billing.businessReads, 0);
    expect(fixture.billing.operations, isEmpty);
  });
  testWidgets(
      'Business sale requires explicit backend availability and its own store quote',
      (tester) async {
    final fixture = _Fixture()..available = false;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Pro'));
    expect(find.text('Business'), findsNothing);
    expect(fixture.billing.businessReads, 0);
    expect(fixture.billing.operations, isEmpty);
    fixture.available = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Business'));
    expect(find.text('400 multi-channel post units/month'), findsOneWidget);
    expect(find.text('Up to 50 store links'), findsOneWidget);
    expect(find.text('AI captions from audio + images: 220 credits/month'),
        findsOneWidget);
    expect(find.text('€10,99/month'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(_key('paywall-subscribe-business'))
            .onPressed,
        isNotNull);
    expect(fixture.billing.businessReads, 1);
    expect(fixture.billing.operations, isEmpty);
  });

  testWidgets(
      'Business checkout after category switching keeps the selected plan action',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(_key('paywall-addons-category'));
    await tester.pumpAndSettle();
    await tester.tap(_key('paywall-main-plans-category'));
    await tester.pumpAndSettle();
    final buy = _key('paywall-subscribe-business');
    await _reveal(tester, buy);
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(fixture.billing.operations, ['business']);
    expect(fixture.callbacks, ['business']);
    expect(find.text('Subscribed to Business'), findsOneWidget);
    expect(fixture.billing.businessReads, 1);
  });

  for (final missing in ['null', 'wrong-id', 'blank', 'error']) {
    testWidgets('Business $missing quote cannot enable checkout and can retry',
        (tester) async {
      final fixture = _Fixture();
      if (missing == 'error') {
        fixture.billing.quoteError = StateError('Store offline');
      }
      fixture.billing.quote = missing == 'null'
          ? null
          : StoreProductInfo(
              id: missing == 'wrong-id' ? 'postdee_pro_monthly' : _businessSku,
              title: '',
              description: '',
              price: missing == 'blank' ? '  ' : '€10,99');
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _reveal(tester, _key('paywall-subscribe-business'));
      expect(
          tester
              .widget<FilledButton>(_key('paywall-subscribe-business'))
              .onPressed,
          isNull);
      final retry = _key('paywall-business-price-error');
      await _reveal(tester, retry);
      fixture.billing.quoteError = null;
      fixture.billing.quote = const StoreProductInfo(
          id: _businessSku, title: '', description: '', price: 'CHF 11.00');
      await tester.tap(retry);
      await tester.pumpAndSettle();
      await _reveal(tester, _key('paywall-subscribe-business'));
      expect(
          tester
              .widget<FilledButton>(_key('paywall-subscribe-business'))
              .onPressed,
          isNotNull);
      expect(find.text('CHF 11.00/month'), findsOneWidget);
      expect(fixture.reads, 1);
      expect(fixture.billing.paidReads, 1);
      expect(fixture.billing.businessReads, 2);
      expect(fixture.billing.operations, isEmpty);
    });
  }

  testWidgets('Business loading quote stays disabled without an invented price',
      (tester) async {
    final fixture = _Fixture();
    final quote = Completer<StoreProductInfo?>();
    fixture.billing.quoteGate = quote.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!quote.isCompleted) quote.complete(null);
    });
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 200));
    await _reveal(tester, _key('paywall-subscribe-business'), settle: false);
    expect(
        tester
            .widget<FilledButton>(_key('paywall-subscribe-business'))
            .onPressed,
        isNull);
    expect(find.text('€10,99/month'), findsNothing);
    quote.complete(fixture.billing.quote);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(_key('paywall-subscribe-business'))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'Business delayed quote cannot populate a paywall after account change',
      (tester) async {
    final fixture = _Fixture();
    final quote = Completer<StoreProductInfo?>();
    fixture.billing.quoteGate = quote.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!quote.isCompleted) quote.complete(null);
    });
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 200));
    fixture.sessions
        .signIn(const AuthSession(userId: 'different-owner', idToken: 'other'));
    quote.complete(fixture.billing.quote);
    await tester.pumpAndSettle();
    expect(find.text('€10,99/month'), findsNothing);
    expect(_key('paywall-subscribe-business'), findsNothing);
    expect(fixture.billing.operations, isEmpty);
    expect(fixture.callbacks, isEmpty);
  });

  testWidgets(
      'Business delayed verification cannot apply to a different account',
      (tester) async {
    final fixture = _Fixture();
    final purchase = Completer<StoreSubscriptionVerificationResult>();
    fixture.billing.purchaseGate = purchase.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!purchase.isCompleted) purchase.complete(_verified());
    });
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final buy = _key('paywall-subscribe-business');
    await _reveal(tester, buy);
    await tester.tap(buy);
    await tester.pump(const Duration(milliseconds: 200));
    fixture.sessions
        .signIn(const AuthSession(userId: 'different-owner', idToken: 'other'));
    purchase.complete(_verified());
    await tester.pumpAndSettle();
    expect(fixture.billing.operations, ['business']);
    expect(fixture.callbacks, isEmpty);
    expect(find.text('Subscribed to Business'), findsNothing);
  });

  for (final operation in ['restore', 'retry']) {
    testWidgets('paid Business $operation survives a disabled new-sale offer',
        (tester) async {
      final fixture = _Fixture()..available = false;
      fixture.billing.pending = operation == 'retry';
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final action = operation == 'retry'
          ? _key('paywall-retry-purchase')
          : find.widgetWithText(OutlinedButton, 'Restore purchases');
      await _reveal(tester, action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(fixture.billing.operations, [operation]);
      expect(fixture.callbacks, ['business']);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Business'));
      expect(find.text('Current plan'), findsOneWidget);
      expect(_key('paywall-subscribe-business'), findsNothing);
    });
  }

  testWidgets(
      'active purchased Business directs lower-plan changes to store management',
      (tester) async {
    final fixture = _Fixture()
      ..plan = 'BUSINESS'
      ..purchasedPlan = 'BUSINESS';
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_key('paywall-business-manage-subscription'), findsOneWidget);
    for (final plan in ['starter', 'pro']) {
      final button = _key('paywall-subscribe-$plan');
      await _reveal(tester, button);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    }
    expect(fixture.billing.operations, isEmpty);
  });

  testWidgets(
      'effective Business trial with purchased Basic still allows paid Starter and Pro',
      (tester) async {
    final fixture = _Fixture()
      ..plan = 'BUSINESS'
      ..purchasedPlan = 'BASIC';
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_key('paywall-business-manage-subscription'), findsNothing);
    for (final plan in ['starter', 'pro']) {
      final button = _key('paywall-subscribe-$plan');
      await _reveal(tester, button);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    }
    expect(fixture.billing.operations, isEmpty);
  });

  for (final language in ['th', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
          'Business quotas and purchase fit 320dp 2x ($language dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await tester
            .pumpWidget(fixture.app(language: language, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        for (final label in language == 'th'
            ? [
                'Business',
                'โพสต์หลายช่องทาง 400 หน่วย/เดือน',
                'ลิงก์ร้านสูงสุด 50 ลิงก์',
                'AI แคปชั่นจากเสียง + ภาพ 220 เครดิต/เดือน'
              ]
            : [
                'Business',
                '400 multi-channel post units/month',
                'Up to 50 store links',
                'AI captions from audio + images: 220 credits/month'
              ]) {
          await _reveal(tester, find.text(label));
          expect(find.text(label), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await _reveal(tester, _key('paywall-subscribe-business'));
        expect(
            _key('paywall-subscribe-business').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('offline Thai Business screenshot uses a mock store quote',
      (tester) async {
    tester.view.physicalSize = const Size(376, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    // This is an offline widget fixture, not Store Sandbox or live store metadata.
    fixture.billing.starterPrice = '฿199.00';
    fixture.billing.proPrice = '฿299.00';
    fixture.billing.quote = const StoreProductInfo(
        id: _businessSku,
        title: 'Mock Business quote',
        description: '',
        price: '฿399.00');
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: fixture.app(language: 'th')));
    await tester.pumpAndSettle();
    final buy = _key('paywall-subscribe-business');
    await _reveal(tester, buy);
    await Scrollable.ensureVisible(tester.element(find.text('Business')),
        alignment: 0.1);
    await tester.pumpAndSettle();
    expect(buy.hitTestable(), findsOneWidget);
    expect(fixture.billing.operations, isEmpty);
    expect(tester.takeException(), isNull);
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(previewDirectory!);
        await directory.create(recursive: true);
        await File('${directory.path}/business-th-light.png')
            .writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }, skip: previewDirectory == null);
}
