import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/billing/paywall_screen.dart';
import 'package:postdee_mobile/features/billing/store_addon_service.dart';
import 'package:postdee_mobile/features/billing/store_subscription_service.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';

void main() {
  final previewDirectory = Platform.environment['POSTDEE_ADDON_PREVIEW_DIR'];
  setUp(() => PostDeeAuthSessionStore.instance
      .signIn(const AuthSession(userId: 'owner-a', idToken: 'dummy')));
  tearDown(PostDeeAuthSessionStore.instance.clear);

  Future<void> show(WidgetTester tester, _Addon addon,
      {VoidCallback? onPurchased}) async {
    await tester.pumpWidget(MaterialApp(
        home: PaywallScreen(
            service: StoreSubscriptionService(
                gateway: _Store(), useRevenueCat: false),
            addonService: addon,
            onAddonPurchased: onPurchased,
            loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'owner-a',
                plan: 'PRO',
                status: 'ACTIVE',
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: true))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('paywall-addon-card')), 400);
  }

  testWidgets(
      'one-time add-on shows 100 posts, 50 captions and the actual store price',
      (tester) async {
    final addon = _Addon();
    await show(tester, addon);
    expect(find.text('โพสต์เพิ่ม 100 หน่วย + AI แคปชั่น 50 เครดิต'),
        findsOneWidget);
    expect(find.text('ซื้อครั้งเดียว €1.49'), findsOneWidget);
    var callbacks = 0;
    await tester.pumpWidget(const SizedBox());
    await show(tester, addon, onPurchased: () => callbacks++);
    await tester.ensureVisible(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    expect(callbacks, 1);
    expect(find.text('เติมเครดิตสำเร็จ'), findsOneWidget);
  });

  for (final state in ['disabled', 'basic', 'missing']) {
    testWidgets('$state prevents add-on checkout before payment',
        (tester) async {
      final addon = _Addon(
          enabled: state != 'disabled',
          eligible: state != 'basic',
          hasProduct: state != 'missing');
      await show(tester, addon);
      final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('paywall-buy-addon')));
      expect(button.onPressed, isNull);
      expect(addon.purchaseCalls, 0);
    });
  }

  testWidgets('closing new checkout keeps the purchased balance visible',
      (tester) async {
    final addon =
        _Addon(enabled: false, addonPostUnits: 70, addonAiCaptions: 25);
    await show(tester, addon);
    expect(find.text('เครดิตคงเหลือ: โพสต์ 70 หน่วย · AI 25 เครดิต'),
        findsOneWidget);
    expect(find.textContaining('เครดิตซื้อเพิ่มไม่หมดอายุ'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('paywall-buy-addon')))
            .onPressed,
        isNull);
    expect(addon.purchaseCalls, 0);
  });

  testWidgets(
      'iPhone displays nonexpiring credits and supports the consumable checkout',
      (tester) async {
    final addon = _Addon();
    await show(tester, addon);
    expect(find.textContaining('เครดิตซื้อเพิ่มไม่หมดอายุ'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('paywall-buy-addon')))
            .onPressed,
        isNotNull);
    expect(addon.purchaseCalls, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('unconfirmed purchase offers receipt recheck without success',
      (tester) async {
    final addon = _Addon(pending: true);
    await show(tester, addon);
    await tester.ensureVisible(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    expect(find.text('เติมเครดิตสำเร็จ'), findsNothing);
    expect(find.byKey(const ValueKey('paywall-retry-addon')), findsOneWidget);
  });

  testWidgets('pending add-on offers support without dispatching another payment',
      (tester) async {
    final addon = _Addon(pending: true);
    await show(tester, addon);
    await tester.ensureVisible(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paywall-buy-addon')));
    await tester.pumpAndSettle();
    final calls = addon.purchaseCalls;
    final help = find.byKey(const ValueKey('paywall-addon-help'));
    await tester.ensureVisible(help);
    await tester.pumpAndSettle();
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('ช่วยตรวจสอบการซื้อ'), findsOneWidget);
    expect(find.textContaining('support@postdee.app'), findsOneWidget);
    expect(find.textContaining('อย่าซื้อซ้ำ'), findsOneWidget);
    expect(addon.purchaseCalls, calls);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('paywall-buy-addon'))).onPressed, isNull);
  });

  testWidgets(
      'subscribing from Basic refreshes add-on eligibility without reopening the screen',
      (tester) async {
    final addon = _Addon(eligible: false);
    var plan = 'BASIC';
    SubscriptionStatusResult subscription() => SubscriptionStatusResult(
        userId: 'owner-a',
        plan: plan,
        status: plan == 'BASIC' ? 'INACTIVE' : 'ACTIVE',
        canSchedule: plan != 'BASIC',
        canUseAiCaptions: plan != 'BASIC',
        canUseAnalytics: false);
    final service = StoreSubscriptionService(
        gateway: _Store(),
        useRevenueCat: false,
        verifyPurchase: (request) async {
          addon.eligible = true;
          plan = 'STARTER';
          return StoreSubscriptionVerificationResult(
              purchase: StorePurchaseResult(
                  provider: 'store',
                  platform: 'ANDROID',
                  productId: request.productId,
                  verifiedAt: DateTime.utc(2026, 10, 21)),
              subscription: subscription());
        });
    await tester.pumpWidget(MaterialApp(
        home: PaywallScreen(
            service: service,
            addonService: addon,
            loadSubscription: () async => subscription())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('สมัคร Starter'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สมัคร Starter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('paywall-buy-addon')), 250);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('paywall-buy-addon')))
            .onPressed,
        isNotNull);
    expect(find.text('ซื้อครั้งเดียว €1.49'), findsOneWidget);
  });

  testWidgets(
      'renders the real add-on card at phone width and large text with local store data',
      (tester) async {
    tester.view.physicalSize = const Size(376, 812);
    tester.view.devicePixelRatio = 1;
    final originalTheme =
        AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppTheme.applyThemeMode(originalTheme);
    });
    AppTheme.applyThemeMode(ThemeMode.light);
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
    for (final scale in [1.0, 1.35]) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: PaywallScreen(
                key: UniqueKey(),
                addonService: _Addon(
                    price: '฿49.00', addonPostUnits: 100, addonAiCaptions: 50),
                service: StoreSubscriptionService(
                    gateway: _Store(), useRevenueCat: false),
                loadSubscription: () async => const SubscriptionStatusResult(
                    userId: 'owner-a',
                    plan: 'PRO',
                    status: 'ACTIVE',
                    canSchedule: true,
                    canUseAiCaptions: true,
                    canUseAnalytics: true)),
          )));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('paywall-addon-card'));
      await tester.scrollUntilVisible(card, 350);
      await Scrollable.ensureVisible(tester.element(card), alignment: .5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(812));
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(previewDirectory!);
          await directory.create(recursive: true);
          await File(
                  '${directory.path}/addon-card-${scale == 1 ? 'normal' : 'large-text'}.png')
              .writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  }, skip: previewDirectory == null);
}

class _Addon extends StoreAddonService {
  _Addon(
      {this.enabled = true,
      this.eligible = true,
      this.hasProduct = true,
      this.pending = false,
      this.price = '€1.49',
      this.addonPostUnits = 0,
      this.addonAiCaptions = 0});
  final int addonPostUnits, addonAiCaptions;
  final String price;
  final bool enabled, hasProduct, pending;
  bool eligible;
  var purchaseCalls = 0;
  var waiting = false;
  @override
  bool get hasPendingPurchase => waiting;
  @override
  Future<AddonCatalogResult> loadCatalog() async => AddonCatalogResult(
      enabled: enabled,
      eligible: eligible,
      productId: 'postdee_post100_caption50',
      postUnits: 100,
      aiCaptions: 50,
      priceThb: 49,
      policyVersion: 2,
      creditsExpire: false,
      expiresAt: null,
      purchasedPacks: 0,
      addonPostUnits: addonPostUnits,
      addonAiCaptions: addonAiCaptions);
  @override
  Future<StoreProductInfo?> loadProduct(AddonCatalogResult catalog) async =>
      hasProduct
          ? StoreProductInfo(
              id: 'postdee_post100_caption50',
              title: 'Pack',
              description: '',
              price: price)
          : null;
  @override
  Future<AddonConfirmationResult> purchase() async {
    purchaseCalls++;
    if (pending) {
      waiting = true;
      throw const StoreAddonPendingException();
    }
    return AddonConfirmationResult(
        confirmed: true,
        transactionId: 'txn-1',
        postUnits: 100,
        aiCaptions: 50,
        policyVersion: 2,
        creditsExpire: false,
        expiresAt: null);
  }
}

class _Store implements StoreBillingGateway {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProductInfo>> queryProducts(Set<String> ids) async => [];
  @override
  Future<StorePurchasePayload> buySubscription(String id) async =>
      StorePurchasePayload.android(
          productId: id, purchaseToken: 'dummy-receipt');
  @override
  Future<StorePurchasePayload> restoreSubscription(String id) async =>
      throw UnimplementedError();
}
