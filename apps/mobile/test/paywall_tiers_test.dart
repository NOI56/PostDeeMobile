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

const _owner = 'tier-paywall-owner';
const _tiers = [
  AddonCatalogProduct(
      id: 'small', productId: 'postdee_post40_caption25', postUnits: 40,
      aiCaptions: 25, priceThb: 49, enabled: true, eligible: true),
  AddonCatalogProduct(
      id: 'medium', productId: 'postdee_post90_caption50', postUnits: 90,
      aiCaptions: 50, priceThb: 99, enabled: true, eligible: true),
  AddonCatalogProduct(
      id: 'large', productId: 'postdee_post190_caption100', postUnits: 190,
      aiCaptions: 100, priceThb: 199, enabled: true, eligible: true),
];

AddonCatalogResult _catalog({List<AddonCatalogProduct>? products = _tiers,
    int posts = 0, int captions = 0, bool enabled = true, bool eligible = true}) => AddonCatalogResult(
      enabled: enabled, eligible: eligible, productId: 'postdee_post100_caption50',
      postUnits: 100, aiCaptions: 50, priceThb: 49, policyVersion: 2,
      creditsExpire: false, expiresAt: null, purchasedPacks: 0,
      addonPostUnits: posts, addonAiCaptions: captions,
      catalogVersion: products == null ? null : 3, products: products);

AddonConfirmationResult _confirmed(int posts, int captions, {String? productId}) =>
    AddonConfirmationResult(confirmed: true, transactionId: 'fixture-receipt',
        postUnits: posts, aiCaptions: captions, policyVersion: 2,
        creditsExpire: false, expiresAt: null, productId: productId);

class _NoCheckoutGateway implements StoreBillingGateway {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async => [];
  @override
  Future<StorePurchasePayload> buySubscription(String id) async =>
      throw StateError('Unexpected store purchase');
  @override
  Future<StorePurchasePayload> restoreSubscription(String id) async =>
      throw StateError('Unexpected store restore');
}

class _Subscriptions extends StoreSubscriptionService {
  _Subscriptions(PostDeeAuthSessionStore sessions)
      : super(sessionStore: sessions, gateway: _NoCheckoutGateway(),
          useRevenueCat: false);
  bool pending = false;
  int productReads = 0;
  final purchases = <String>[];
  @override
  bool get hasPendingConfirmation => pending;
  @override
  Future<List<StoreProductInfo>> loadPaidProducts() async {
    productReads++;
    return [
      StoreProductInfo(id: starterProductId, title: '', description: '',
          price: '€5.49'),
      StoreProductInfo(id: productId, title: '', description: '', price: '€8.49'),
    ];
  }
  @override
  Future<StoreSubscriptionVerificationResult> startStarterSubscription() {
    purchases.add('starter');
    return Future.error(StateError('Unexpected subscription'));
  }
  @override
  Future<StoreSubscriptionVerificationResult> startProSubscription() {
    purchases.add('pro');
    return Future.error(StateError('Unexpected subscription'));
  }
}

class _TierAddon extends StoreAddonService {
  _TierAddon(PostDeeAuthSessionStore sessions) : super(sessionStore: sessions);
  AddonCatalogResult catalog = _catalog();
  int catalogReads = 0;
  int legacyReads = 0;
  int legacyPurchases = 0;
  int retries = 0;
  bool pending = false;
  bool supported = true;
  Object? catalogError;
  Future<AddonCatalogResult>? catalogGate;
  final queries = <String>[];
  final purchases = <String>[];
  final missing = <String>{};
  final errors = <String, Object>{};
  final gates = <String, Future<StoreProductInfo?>>{};
  final prices = <String, String>{
    'postdee_post40_caption25': '€1,49',
    'postdee_post90_caption50': '¥290',
    'postdee_post190_caption100': 'CHF 5.75',
  };
  Future<AddonConfirmationResult>? purchaseGate;
  @override
  bool get supportsPlatform => supported;
  @override
  bool get hasPendingPurchase => pending;
  @override
  Future<AddonCatalogResult> loadCatalog() async {
    catalogReads++;
    if (catalogError != null) throw catalogError!;
    return catalogGate == null ? catalog : await catalogGate!;
  }
  StoreProductInfo storeProduct(String id) => StoreProductInfo(
      id: id, title: 'Store item', description: '', price: prices[id]!);
  @override
  Future<StoreProductInfo?> loadProductFor(
      AddonCatalogResult catalog, AddonCatalogProduct product) async {
    queries.add(product.productId);
    if (errors.containsKey(product.productId)) throw errors[product.productId]!;
    if (gates.containsKey(product.productId)) return await gates[product.productId]!;
    return missing.contains(product.productId) ? null : storeProduct(product.productId);
  }
  @override
  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async {
    legacyReads++;
    return const StoreProductInfo(id: 'postdee_post100_caption50', title: '',
        description: '', price: '€1.99');
  }
  @override
  Future<AddonConfirmationResult> purchaseProduct(String productId) async {
    purchases.add(productId);
    if (pending) throw const StoreAddonPendingException();
    if (purchaseGate != null) return await purchaseGate!;
    final product = catalog.products!.firstWhere((item) => item.productId == productId);
    return _confirmed(product.postUnits, product.aiCaptions, productId: productId);
  }
  @override
  Future<AddonConfirmationResult> purchase() async {
    legacyPurchases++;
    return _confirmed(100, 50);
  }
  @override
  Future<AddonConfirmationResult> retryPendingPurchase() async {
    retries++;
    pending = false;
    return _confirmed(100, 50);
  }
}

class _Fixture {
  _Fixture({this.language = 'en', this.dark = false, this.scale = 1});
  final String language;
  final bool dark;
  final double scale;
  final sessions = PostDeeAuthSessionStore(initialSession:
      const AuthSession(userId: _owner, idToken: 'fixture-token'));
  late final billing = _Subscriptions(sessions);
  late final addons = _TierAddon(sessions);
  int subscriptionReads = 0;
  int callbacks = 0;
  String plan = 'PRO';
  Widget app() {
    AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(language),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true,
            textScaler: TextScaler.linear(scale)), child: child!),
      home: PaywallScreen(sessionStore: sessions, service: billing,
        addonService: addons, onAddonPurchased: () => callbacks++,
        loadSubscription: () async {
          subscriptionReads++;
          return SubscriptionStatusResult(userId: _owner, plan: plan,
              status: 'ACTIVE', canSchedule: plan != 'BASIC',
              canUseAiCaptions: plan != 'BASIC', canUseAnalytics: false);
        }),
    );
  }
  void dispose() => sessions.dispose();
}

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _card(AddonCatalogProduct tier) => _key('paywall-addon-card-${tier.productId}');
Finder _buy(AddonCatalogProduct tier) => _key('paywall-buy-addon-${tier.productId}');

Future<void> _reveal(WidgetTester tester, Finder target, {bool settle = true}) async {
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(target, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void _readable(WidgetTester tester, Finder label) {
  expect(label, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.height,
      greaterThanOrEqualTo(paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5));
}

void main() {
  final previewDirectory = Platform.environment['POSTDEE_TIERS_PREVIEW_DIR'];
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  for (final tier in _tiers) {
    testWidgets('tier cards preserve catalog quantities and dispatch the selected store SKU (${tier.id})',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      for (final product in _tiers) {
        await _reveal(tester, _card(product));
        expect(find.descendant(of: _card(product), matching:
            find.text('${product.postUnits} post units + ${product.aiCaptions} AI caption credits')),
            findsOneWidget);
        expect(find.descendant(of: _card(product), matching:
            find.text('One-time purchase ${fixture.addons.prices[product.productId]}')),
            findsOneWidget);
      }
      expect(_key('paywall-addon-card'), findsNothing);
      expect(fixture.addons.legacyReads, 0);
      expect(fixture.addons.purchases, isEmpty);
      expect(fixture.addons.queries.toSet(), _tiers.map((item) => item.productId).toSet());
      await _reveal(tester, _buy(tier));
      await tester.tap(_buy(tier));
      await tester.pumpAndSettle();
      expect(fixture.addons.purchases, [tier.productId]);
      expect(fixture.addons.legacyPurchases, 0);
      expect(fixture.callbacks, 1);
      expect(find.text('Added ${tier.postUnits} post units and ${tier.aiCaptions} AI caption credits. Purchased credits do not expire. Your monthly quota is used first.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('each tier waits for its own quote and a missing quote stays disabled',
      (tester) async {
    final fixture = _Fixture();
    final delayed = Completer<StoreProductInfo?>();
    fixture.addons.gates[_tiers[1].productId] = delayed.future;
    fixture.addons.missing.add(_tiers[2].productId);
    addTearDown(fixture.dispose);
    addTearDown(() { if (!delayed.isCompleted) delayed.complete(null); });
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 400));
    await _reveal(tester, _buy(_tiers.first), settle: false);
    expect(tester.widget<FilledButton>(_buy(_tiers.first)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[1])).onPressed, isNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[2])).onPressed, isNull);
    expect(find.text('One-time purchase ¥290'), findsNothing);
    expect(find.text('One-time purchase CHF 5.75'), findsNothing);
    expect(fixture.addons.queries, hasLength(3));
    expect(fixture.addons.purchases, isEmpty);
    delayed.complete(fixture.addons.storeProduct(_tiers[1].productId));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_buy(_tiers[1])).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[2])).onPressed, isNull);
    expect(find.text('One-time purchase ¥290'), findsOneWidget);
    expect(fixture.addons.catalogReads, 1);
    expect(fixture.addons.legacyReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong product IDs and blank store prices cannot enable a tier',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.gates[_tiers.first.productId] = Future.value(
        const StoreProductInfo(id: 'wrong-product', title: '', description: '',
            price: '€0.01'));
    fixture.addons.prices[_tiers[1].productId] = ' \t ';
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _buy(_tiers.last));
    expect(tester.widget<FilledButton>(_buy(_tiers.first)).onPressed, isNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[1])).onPressed, isNull);
    expect(tester.widget<FilledButton>(_buy(_tiers.last)).onPressed, isNotNull);
    expect(find.text('One-time purchase €0.01'), findsNothing);
    expect(tester.widget<TextButton>(_key('paywall-reload-addons')).onPressed,
        isNotNull);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each new offer uses its own availability instead of legacy root flags',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.catalog = _catalog(enabled: false, eligible: false, products: [
      _tiers.first,
      const AddonCatalogProduct(id: 'medium', productId: 'postdee_post90_caption50',
          postUnits: 90, aiCaptions: 50, priceThb: 99, enabled: true, eligible: false),
      const AddonCatalogProduct(id: 'large', productId: 'postdee_post190_caption100',
          postUnits: 190, aiCaptions: 100, priceThb: 199, enabled: false, eligible: true),
    ]);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _buy(_tiers.last));
    expect(tester.widget<FilledButton>(_buy(_tiers.first)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[1])).onPressed, isNull);
    expect(tester.widget<FilledButton>(_buy(_tiers.last)).onPressed, isNull);
    expect(fixture.addons.queries, [_tiers.first.productId]);
    expect(fixture.addons.legacyReads, 0);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed and missing tier quotes can reload without another subscription read',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.errors[_tiers[2].productId] = StateError('Store unavailable');
    fixture.addons.missing.add(_tiers[1].productId);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _buy(_tiers.first));
    expect(tester.widget<FilledButton>(_buy(_tiers.first)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[1])).onPressed, isNull);
    expect(tester.widget<FilledButton>(_buy(_tiers[2])).onPressed, isNull);
    final reload = find.widgetWithText(TextButton, 'Reload credit pack');
    await _reveal(tester, reload);
    fixture.addons.errors.clear();
    fixture.addons.missing.clear();
    await tester.tap(reload);
    await tester.pumpAndSettle();
    for (final tier in _tiers) {
      expect(tester.widget<FilledButton>(_buy(tier)).onPressed, isNotNull);
    }
    expect(fixture.subscriptionReads, 1);
    expect(fixture.billing.productReads, 1);
    expect(fixture.addons.catalogReads, 2);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy APIs keep the existing single pack and checkout method',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.catalog = _catalog(products: null);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));
    expect(_key('paywall-addon-tiers'), findsNothing);
    expect(find.text('100 post units + 50 AI caption credits'), findsOneWidget);
    expect(find.text('One-time purchase €1.99'), findsOneWidget);
    expect(fixture.addons.queries, isEmpty);
    expect(fixture.addons.legacyReads, 1);
    final buy = _key('paywall-buy-addon');
    await _reveal(tester, buy);
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(fixture.addons.legacyPurchases, 1);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.callbacks, 1);
    expect(find.text('Added 100 post units and 50 AI caption credits. Purchased credits do not expire. Your monthly quota is used first.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all disabled new tiers never fall back to a buyable legacy product',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.catalog = _catalog(products: _tiers.map((tier) =>
        AddonCatalogProduct(id: tier.id, productId: tier.productId,
            postUnits: tier.postUnits, aiCaptions: tier.aiCaptions,
            priceThb: tier.priceThb, enabled: false, eligible: true)).toList(),
        posts: 70, captions: 25);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-tiers'));
    expect(_key('paywall-addon-card'), findsNothing);
    expect(_key('paywall-addon-unavailable'), findsOneWidget);
    expect(find.text('Credit packs are not on sale yet'), findsOneWidget);
    expect(find.text('Credits remaining: 70 post units · 25 AI caption credits'),
        findsOneWidget);
    expect(fixture.addons.queries, isEmpty);
    expect(fixture.addons.legacyReads, 0);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical pending receipt remains recoverable outside the sale tiers',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.pending = true;
    fixture.addons.catalog = _catalog(products: const [], posts: 12, captions: 8);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-tiers'));
    expect(_key('paywall-addon-card'), findsNothing);
    expect(find.text('Credits remaining: 12 post units · 8 AI caption credits'),
        findsOneWidget);
    final help = _key('paywall-addon-help');
    await _reveal(tester, help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Purchase help'), findsOneWidget);
    expect(find.textContaining('postdee.support@gmail.com'), findsOneWidget);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    final retry = _key('paywall-retry-addon');
    await _reveal(tester, retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(fixture.addons.retries, 1);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(fixture.callbacks, 1);
    expect(find.text('Added 100 post units and 50 AI caption credits. Purchased credits do not expire. Your monthly quota is used first.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final lock in ['addon', 'subscription']) {
    testWidgets('an account-wide $lock pending purchase locks every new SKU',
        (tester) async {
      final fixture = _Fixture();
      fixture.addons.pending = lock == 'addon';
      fixture.billing.pending = lock == 'subscription';
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      for (final tier in _tiers) {
        await _reveal(tester, _buy(tier));
        expect(tester.widget<FilledButton>(_buy(tier)).onPressed, isNull);
      }
      expect(fixture.addons.purchases, isEmpty);
      expect(fixture.addons.legacyPurchases, 0);
      expect(fixture.billing.purchases, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading and reading other tiers never starts another operation',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (var round = 0; round < 3; round++) {
      for (final tier in round.isEven ? _tiers : _tiers.reversed) {
        await _reveal(tester, _buy(tier));
        expect(tester.widget<FilledButton>(_buy(tier)).onPressed, isNotNull);
      }
    }
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(fixture.addons.catalogReads, 1);
    expect(fixture.addons.queries, hasLength(3));
    expect(fixture.subscriptionReads, 1);
    expect(fixture.billing.productReads, 1);
    expect(fixture.addons.purchases, isEmpty);
    expect(fixture.addons.legacyPurchases, 0);
    expect(fixture.addons.retries, 0);
    expect(fixture.billing.purchases, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late new-SKU purchase result cannot grant another account credits',
      (tester) async {
    final fixture = _Fixture();
    final purchase = Completer<AddonConfirmationResult>();
    fixture.addons.purchaseGate = purchase.future;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _buy(_tiers.first));
    await tester.tap(_buy(_tiers.first));
    await tester.pump();
    fixture.sessions.signIn(const AuthSession(
        userId: 'replacement-owner', idToken: 'replacement-token'));
    await tester.pump();
    purchase.complete(_confirmed(40, 25, productId: _tiers.first.productId));
    await tester.pumpAndSettle();
    expect(fixture.callbacks, 0);
    expect(find.text('Credits added'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.addons.purchases, [_tiers.first.productId]);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['th', 'en']) {
    for (final dark in [false, true]) {
      testWidgets('tier quantities and store actions fit 320dp 2x ($language dark=$dark)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture(language: language, dark: dark, scale: 2);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();
        for (final tier in _tiers) {
          final text = find.text(language == 'th'
              ? 'โพสต์เพิ่ม ${tier.postUnits} หน่วย + AI แคปชั่น ${tier.aiCaptions} เครดิต'
              : '${tier.postUnits} post units + ${tier.aiCaptions} AI caption credits');
          await _reveal(tester, text);
          _readable(tester, text);
          await _reveal(tester, _buy(tier));
          _readable(tester, find.text(language == 'th'
              ? 'ซื้อครั้งเดียว ${fixture.addons.prices[tier.productId]}'
              : 'One-time purchase ${fixture.addons.prices[tier.productId]}'));
          expect(_buy(tier).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(fixture.addons.purchases, isEmpty);
        expect(fixture.billing.purchases, isEmpty);
      });
    }
  }

  testWidgets('offline tier screenshots show the quoted fixture store prices',
      (tester) async {
    tester.view.physicalSize = const Size(376, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    for (final settings in [('th', false), ('en', true)]) {
      final fixture = _Fixture(language: settings.$1, dark: settings.$2);
      addTearDown(fixture.dispose);
      // Offline visual fixtures only: these are not verified store prices.
      fixture.addons.prices.addAll({
        _tiers[0].productId: '฿49.00',
        _tiers[1].productId: '฿99.00',
        _tiers[2].productId: '฿199.00',
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey, child: fixture.app()));
      await tester.pumpAndSettle();
      final group = _key('paywall-addon-tiers');
      await _reveal(tester, group);
      await Scrollable.ensureVisible(tester.element(group), alignment: 0);
      await tester.pumpAndSettle();
      expect(fixture.addons.purchases, isEmpty);
      expect(fixture.addons.legacyPurchases, 0);
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(previewDirectory!);
          await directory.create(recursive: true);
          final filename = settings.$1 == 'th'
              ? 'tiers-th-light.png' : 'tiers-en-dark.png';
          await File('${directory.path}/$filename')
              .writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  }, skip: previewDirectory == null);
}
