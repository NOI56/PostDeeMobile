import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';

const _owner = 'paywall-english-owner';

SubscriptionStatusResult _subscription([String plan = 'BASIC']) =>
    SubscriptionStatusResult(
      userId: _owner,
      plan: plan,
      status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
      canSchedule: plan != 'BASIC',
      canUseAiCaptions: plan != 'BASIC',
      canUseAnalytics: plan == 'PRO',
    );

class _Gateway implements StoreBillingGateway {
  final queries = <Set<String>>[];
  String starterPrice = '€5,49';
  String proPrice = '¥1,280';
  Object? error;
  bool empty = false;
  Future<List<StoreProductInfo>>? gate;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> productIds) async {
    queries.add(Set.of(productIds));
    if (error != null) {
      throw error!;
    }
    if (gate != null) {
      return await gate!;
    }
    if (empty) {
      return [];
    }
    return productIds
        .map((id) => StoreProductInfo(
              id: id,
              title: 'Store title',
              description: 'Store description',
              price: id.contains('starter') ? starterPrice : proPrice,
            ))
        .toList();
  }

  @override
  Future<StorePurchasePayload> buySubscription(String productId) async =>
      throw StateError('Unexpected subscription purchase');

  @override
  Future<StorePurchasePayload> restoreSubscription(String productId) async =>
      throw StateError('Unexpected subscription restore');
}

class _Billing extends StoreSubscriptionService {
  _Billing(_Gateway gateway, PostDeeAuthSessionStore sessions)
      : super(gateway: gateway, useRevenueCat: false, sessionStore: sessions);

  @override
  bool get supportsUnifiedRestore => true;
}

class _Addons extends StoreAddonService {
  _Addons(PostDeeAuthSessionStore sessions) : super(sessionStore: sessions);

  int catalogReads = 0;
  int productReads = 0;
  String price = 'CHF 1.25';
  bool supported = true;
  bool enabled = true;
  bool eligible = true;
  bool missingProduct = false;
  int postCredits = 0;
  int aiCredits = 0;
  Object? error;
  Future<AddonCatalogResult>? gate;
  @override
  bool get supportsPlatform => supported;
  @override
  bool get hasPendingPurchase => false;
  @override
  Future<AddonCatalogResult> loadCatalog() async {
    catalogReads++;
    if (error != null) {
      throw error!;
    }
    if (gate != null) {
      return await gate!;
    }
    return AddonCatalogResult(
      enabled: enabled,
      eligible: eligible,
      productId: 'postdee_post100_caption50',
      postUnits: 100,
      aiCaptions: 50,
      priceThb: 49,
      policyVersion: 2,
      creditsExpire: false,
      purchasedPacks: 0,
      addonPostUnits: postCredits,
      addonAiCaptions: aiCredits,
    );
  }

  @override
  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async {
    productReads++;
    if (missingProduct) {
      return null;
    }
    return StoreProductInfo(
        id: catalog.productId,
        title: 'Store pack',
        description: '',
        price: price);
  }

  @override
  Future<AddonConfirmationResult> purchase() async =>
      throw StateError('Unexpected add-on purchase');
}

class _Fixture {
  _Fixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = ValueNotifier(locale) {
    billing = _Billing(gateway, sessions);
    addons = _Addons(sessions);
  }

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final sessions = PostDeeAuthSessionStore(
      initialSession: const AuthSession(userId: _owner, idToken: 'fake-token'));
  final gateway = _Gateway();
  late final _Billing billing;
  late final _Addons addons;
  SubscriptionStatusResult subscription = _subscription();
  int subscriptionReads = 0;
  Object? subscriptionError;
  Future<SubscriptionStatusResult>? subscriptionGate;

  Future<SubscriptionStatusResult> loadSubscription() async {
    subscriptionReads++;
    if (subscriptionError != null) {
      throw subscriptionError!;
    }
    return subscriptionGate == null ? subscription : await subscriptionGate!;
  }

  Widget app() => ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) {
          AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
          return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(),
            initialRoute: '/paywall',
            routes: {
              '/paywall': (_) => PaywallScreen(
                    key: const ValueKey('english-paywall'),
                    sessionStore: sessions,
                    service: billing,
                    addonService: addons,
                    loadSubscription: loadSubscription,
                  ),
            },
          );
        },
      );

  void dispose() {
    language.dispose();
    sessions.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(target, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Finder _planContent(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Column)).first;

void _readable(WidgetTester tester, Finder text) {
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: tester.widget<Text>(text).data);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
      reason: tester.widget<Text>(text).data);
}

const _features = {
  'Basic': [
    '3 free post units/month after phone verification',
    'Up to 2 store links',
    'Phone verification required to post',
    'No AI captions or scheduling',
  ],
  'Starter': [
    '120 multi-channel post units/month',
    'Up to 7 store links',
    'Schedule up to 14 days ahead + Calendar + Templates',
    'AI captions from clip audio: 50 credits/month',
    'Automatic watermark',
  ],
  'Pro': [
    '250 multi-channel post units/month',
    'Up to 20 store links',
    'Everything in Starter + full analytics',
    'Schedule up to 30 days ahead',
    'AI captions from audio + images: 120 credits/month',
  ],
};

void main() {
  tearDown(() => AppTheme.applyThemeMode(ThemeMode.light));

  testWidgets('English paywall explains the paid plan benefits',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Choose a plan'), findsOneWidget);
    expect(
        find.text(
            'Upgrade to unlock scheduling, AI captions, and full analytics'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English paywall names both subscriptions and unified restore',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Starter'));
    expect(find.text('Subscribe Starter'), findsOneWidget);
    await _reveal(tester, find.text('Pro'));
    expect(find.text('Subscribe Pro'), findsOneWidget);
    await _reveal(tester, find.byType(OutlinedButton));
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English monthly prices retain each raw store currency string',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Starter'));
    expect(find.text('€5,49/month'), findsOneWidget);
    await _reveal(tester, find.text('Pro'));
    expect(find.text('¥1,280/month'), findsOneWidget);
    expect(fixture.gateway.queries.single,
        {'postdee_starter_monthly', 'postdee_pro_monthly'});
    expect(tester.takeException(), isNull);
  });

  for (final entry in _features.entries) {
    testWidgets('${entry.key} English benefits retain exact allowances',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _reveal(tester, find.text(entry.key));
      final plan = _planContent(entry.key);
      for (final feature in entry.value) {
        expect(find.descendant(of: plan, matching: find.text(feature)),
            findsOneWidget);
      }
      expect(find.textContaining('AI editing'), findsNothing);
      expect(find.textContaining('editing minutes'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Basic limitations keep warning marks rather than included checks',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (final label in [
      'Phone verification required to post',
      'No AI captions or scheduling',
    ]) {
      final row =
          find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byIcon(Icons.remove)),
          findsOneWidget);
      expect(
          find.descendant(of: row, matching: find.byIcon(Icons.check_circle)),
          findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'BASIC': 'Basic',
    'FREE': 'Basic',
    'STARTER': 'Starter',
    'PRO': 'Pro',
  }.entries) {
    testWidgets('${entry.key} remains marked on the matching current plan card',
        (tester) async {
      final fixture = _Fixture()..subscription = _subscription(entry.key);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _reveal(tester, find.text(entry.value));
      final plan = _planContent(entry.value);
      expect(find.descendant(of: plan, matching: find.text('Current plan')),
          findsOneWidget);
      expect(find.descendant(of: plan, matching: find.byType(FilledButton)),
          findsNothing);
      expect(fixture.subscriptionReads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an unknown backend plan never claims a current card',
      (tester) async {
    final fixture = _Fixture()..subscription = _subscription('FUTURE_PLAN');
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    for (final name in _features.keys) {
      await _reveal(tester, find.text(name));
      expect(
          find.descendant(
              of: _planContent(name), matching: find.text('Current plan')),
          findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('live locale changes preserve current plan and loaded raw prices',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'))
      ..subscription = _subscription('STARTER');
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(PaywallScreen));
    await _reveal(tester, find.text('Starter'));
    expect(find.text('€5,49/เดือน'), findsOneWidget);
    expect(
        find.descendant(
            of: _planContent('Starter'),
            matching: find.text('แพ็กเกจปัจจุบัน')),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PaywallScreen)), same(state));
    expect(find.text('€5,49/month'), findsOneWidget);
    expect(
        find.descendant(
            of: _planContent('Starter'), matching: find.text('Current plan')),
        findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('€5,49/เดือน'), findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.gateway.queries, hasLength(1));
    expect(fixture.addons.catalogReads, 1);
    expect(fixture.addons.productReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual monthly store price is preserved apart from outer spaces',
      (tester) async {
    final fixture = _Fixture();
    fixture.gateway.starterPrice = '  R\$ 12,90  ';
    fixture.gateway.proPrice = '  2\u202f990,00\u00a0Ft  ';
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Starter'));
    expect(find.text('R\$ 12,90/month'), findsOneWidget);
    await _reveal(tester, find.text('Pro'));
    expect(find.text('2\u202f990,00\u00a0Ft/month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly cancellation and country pricing notice is English',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final notice = find.text(
        'Prices vary by store and country · Cancel monthly plans at any time');
    await _reveal(tester, notice);
    expect(notice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one-time pack keeps its exact units and raw store checkout price',
      (tester) async {
    final fixture = _Fixture()..subscription = _subscription('PRO');
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));

    expect(find.text('One-time credit pack'), findsOneWidget);
    expect(find.text('100 post units + 50 AI caption credits'), findsOneWidget);
    expect(
        find.text('Thailand price: THB 49 · Pay the price shown by your store'),
        findsOneWidget);
    expect(find.text('Available for repeat purchases'), findsOneWidget);
    expect(find.text('One-time purchase CHF 1.25'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('paywall-buy-addon')).onPressed,
        isNotNull);
    expect(fixture.addons.productReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'credit policy preserves nonexpiry monthly-first and retained bank',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));
    expect(
        find.text(
            'Purchased credits do not expire · Monthly quota is used first · No automatic renewal'),
        findsOneWidget);
    expect(
        find.text(
            '1 channel uses 1 post unit · Credits are usable with Starter or Pro. Your credits are retained if your subscription expires.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English checkout retains localized add-on price text exactly',
      (tester) async {
    final fixture = _Fixture();
    fixture.addons.price = '  ๑๒,๙๐ บาท  ';
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));
    expect(find.text('One-time purchase   ๑๒,๙๐ บาท  '), findsOneWidget);
    expect(
        find.text('Thailand price: THB 49 · Pay the price shown by your store'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final credits in [(138, 0), (0, 47)]) {
    testWidgets(
        'remaining bank keeps post and caption units distinct ($credits)',
        (tester) async {
      final fixture = _Fixture();
      fixture.addons.postCredits = credits.$1;
      fixture.addons.aiCredits = credits.$2;
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _reveal(tester, _key('paywall-addon-card'));
      expect(
          find.text(
              'Credits remaining: ${credits.$1} post units · ${credits.$2} AI caption credits'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final state in ['disabled', 'ineligible', 'missing', 'error']) {
    testWidgets('credit pack $state remains unavailable with an English reason',
        (tester) async {
      final fixture = _Fixture();
      fixture.addons.enabled = state != 'disabled';
      fixture.addons.eligible = state != 'ineligible';
      fixture.addons.missingProduct = state == 'missing';
      if (state == 'error') {
        fixture.addons.error = StateError('Catalog unavailable');
      }
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await _reveal(tester, _key('paywall-addon-card'));
      final message = switch (state) {
        'disabled' => 'Credit packs are not on sale yet',
        'ineligible' =>
          'For Starter or Pro members · Subscribe to a plan above first',
        'missing' => 'Could not load the credit pack from your store.',
        _ => 'Could not load credit pack. Please try again.',
      };
      expect(find.text(message), findsOneWidget);
      expect(find.text('Buy credit pack'), findsOneWidget);
      expect(tester.widget<FilledButton>(_key('paywall-buy-addon')).onPressed,
          isNull);
      expect(fixture.addons.productReads, state == 'missing' ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'credit pack loading cannot show a buyable or invented store price',
      (tester) async {
    final fixture = _Fixture();
    final catalog = Completer<AddonCatalogResult>();
    fixture.addons.gate = catalog.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!catalog.isCompleted) {
        catalog.complete(const AddonCatalogResult(
            enabled: false,
            eligible: false,
            productId: 'postdee_post100_caption50',
            postUnits: 100,
            aiCaptions: 50,
            priceThb: 49,
            policyVersion: 2,
            creditsExpire: false,
            purchasedPacks: 0));
      }
    });
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));
    expect(find.text('Loading credit pack...'), findsOneWidget);
    expect(find.text('Buy credit pack'), findsOneWidget);
    expect(find.text('One-time purchase CHF 1.25'), findsNothing);
    expect(tester.widget<FilledButton>(_key('paywall-buy-addon')).onPressed,
        isNull);
    expect(fixture.addons.productReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'credit-bank counts translate without another catalog or product read',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    fixture.addons.postCredits = 138;
    fixture.addons.aiCredits = 47;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, _key('paywall-addon-card'));
    expect(find.text('เครดิตคงเหลือ: โพสต์ 138 หน่วย · AI 47 เครดิต'),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text('Credits remaining: 138 post units · 47 AI caption credits'),
        findsOneWidget);
    expect(find.text('One-time purchase CHF 1.25'), findsOneWidget);
    expect(fixture.addons.catalogReads, 1);
    expect(fixture.addons.productReads, 1);
    expect(fixture.gateway.queries, hasLength(1));
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'subscription loading cannot invent a current plan or enable buying',
      (tester) async {
    final fixture = _Fixture();
    final status = Completer<SubscriptionStatusResult>();
    fixture.subscriptionGate = status.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!status.isCompleted) {
        status.complete(_subscription());
      }
    });
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Checking current plan...'), findsOneWidget);
    expect(find.text('Current plan'), findsNothing);
    await tester.scrollUntilVisible(find.text('Subscribe Starter'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subscribe Starter'))
            .onPressed,
        isNull);
    status.complete(_subscription());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Subscribe Starter'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subscribe Starter'))
            .onPressed,
        isNotNull);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stored subscription errors follow locale and retry only that read',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'))
      ..subscriptionError = StateError('Account request unavailable');
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดแพ็กเกจปัจจุบันไม่สำเร็จ'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not load your current plan. Try again before subscribing, or restore your previous purchase.'),
        findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(fixture.gateway.queries, hasLength(1));
    expect(fixture.addons.catalogReads, 1);
    expect(fixture.addons.productReads, 1);
    await _reveal(tester, find.text('Subscribe Starter'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subscribe Starter'))
            .onPressed,
        isNull);
    fixture.subscriptionError = null;
    await _reveal(tester, _key('paywall-retry-subscription'));
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(_key('paywall-retry-subscription'));
    await tester.pumpAndSettle();
    expect(fixture.subscriptionReads, 2);
    expect(fixture.gateway.queries, hasLength(1));
    expect(fixture.addons.catalogReads, 1);
    expect(
        find.textContaining('Could not load your current plan'), findsNothing);
    await _reveal(tester, find.text('Subscribe Starter'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subscribe Starter'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'price loading translates without inventing amounts or re-querying',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    final products = Completer<List<StoreProductInfo>>();
    fixture.gateway.gate = products.future;
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!products.isCompleted) {
        products.complete([]);
      }
    });
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Starter'));
    expect(
        find.descendant(
            of: _planContent('Starter'),
            matching: find.text('กำลังโหลดราคา...')),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _planContent('Starter'),
            matching: find.text('Loading prices...')),
        findsOneWidget);
    expect(find.text('€5,49/month'), findsNothing);
    expect(find.text('199 ฿/month'), findsNothing);
    expect(fixture.gateway.queries, hasLength(1));
    products.complete(const [
      StoreProductInfo(
          id: 'postdee_starter_monthly',
          title: '',
          description: '',
          price: '€5,49'),
      StoreProductInfo(
          id: 'postdee_pro_monthly',
          title: '',
          description: '',
          price: '¥1,280'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('€5,49/month'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable store prices follow locale and reload without plan reads',
      (tester) async {
    final fixture = _Fixture(locale: const Locale('th'));
    fixture.gateway.empty = true;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Starter'));
    expect(
        find.descendant(
            of: _planContent('Starter'),
            matching: find.text('ตรวจราคาในร้านค้า')),
        findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _planContent('Starter'),
            matching: find.text('Check prices in the store')),
        findsOneWidget);
    await _reveal(tester, _key('paywall-price-error'));
    expect(find.text('Reload store prices'), findsOneWidget);
    expect(fixture.gateway.queries, hasLength(1));
    fixture.gateway.empty = false;
    await tester.tap(_key('paywall-price-error'));
    await tester.pumpAndSettle();
    expect(fixture.gateway.queries, hasLength(2));
    expect(fixture.subscriptionReads, 1);
    expect(fixture.addons.catalogReads, 1);
    await _reveal(tester, find.text('Starter'));
    expect(find.text('€5,49/month'), findsOneWidget);
    expect(find.text('Check prices in the store'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('English plan cards and credit rules fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture(dark: dark, scale: 2);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      _readable(tester, find.text('Choose a plan'));
      _readable(
          tester,
          find.text(
              'Upgrade to unlock scheduling, AI captions, and full analytics'));
      for (final entry in _features.entries) {
        await _reveal(tester, find.text(entry.key));
        _readable(tester, find.text(entry.key));
        for (final feature in entry.value) {
          await _reveal(tester, find.text(feature));
          _readable(tester, find.text(feature));
        }
        if (entry.key != 'Basic') {
          final cta = find.text('Subscribe ${entry.key}');
          await _reveal(tester, cta);
          _readable(tester, cta);
          expect(
              tester
                  .widget<FilledButton>(find.widgetWithText(
                      FilledButton, 'Subscribe ${entry.key}'))
                  .onPressed,
              isNotNull);
        }
        expect(tester.takeException(), isNull);
      }
      await _reveal(tester, _key('paywall-addon-card'));
      for (final label in [
        'One-time credit pack',
        '100 post units + 50 AI caption credits',
        'Purchased credits do not expire · Monthly quota is used first · No automatic renewal',
        '1 channel uses 1 post unit · Credits are usable with Starter or Pro. Your credits are retained if your subscription expires.',
        'One-time purchase CHF 1.25',
        'Restore purchases',
        'Prices vary by store and country · Cancel monthly plans at any time',
      ]) {
        await _reveal(tester, find.text(label));
        _readable(tester, find.text(label));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
