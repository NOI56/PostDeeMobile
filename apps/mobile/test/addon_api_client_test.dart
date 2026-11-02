import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  final catalog = <String, Object?>{
    'status': 'ok',
    'enabled': true,
    'eligible': true,
    'productId': 'postdee_post100_caption50',
    'postUnits': 100,
    'aiCaptions': 50,
    'priceThb': 49,
    'policyVersion': 2,
    'creditsExpire': false,
    'expiresAt': null,
    'addonPostUnits': 100,
    'addonAiCaptions': 50,
    'purchasedPacks': 2
  };

  final products = <Map<String, Object?>>[
    {'id': 'small', 'productId': 'postdee_post40_caption25', 'postUnits': 40,
      'aiCaptions': 25, 'priceThb': 49, 'enabled': true, 'eligible': true},
    {'id': 'medium', 'productId': 'postdee_post90_caption50', 'postUnits': 90,
      'aiCaptions': 50, 'priceThb': 99, 'enabled': true, 'eligible': true},
    {'id': 'large', 'productId': 'postdee_post190_caption100', 'postUnits': 190,
      'aiCaptions': 100, 'priceThb': 199, 'enabled': true, 'eligible': true},
  ];

  test('catalog v3 rejects duplicate, unknown and changed immutable SKU grants', () {
    for (final malformed in <Map<String, Object?>>[
      {...catalog, 'catalogVersion': 3, 'products': [products.first, products.first]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'id': 'medium'}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'productId': 'unknown'}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'postUnits': 100}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'aiCaptions': 50}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'priceThb': 29}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'enabled': 'yes'}]},
      {...catalog, 'catalogVersion': 3, 'products': [{...products.first, 'eligible': true, 'enabled': false}]},
      {...catalog, 'catalogVersion': 2, 'products': products},
      {...catalog, 'catalogVersion': 3},
      {...catalog, 'products': products},
      {...catalog, 'catalogVersion': 3, 'products': null},
    ]) {
      expect(() => AddonCatalogResult.fromJson(malformed),
          throwsA(isA<ApiException>()), reason: malformed.toString());
    }
  });

  test('v3 catalog keeps legacy scalar fields and an immutable tier list', () {
    final result = AddonCatalogResult.fromJson({
      ...catalog, 'enabled': false, 'eligible': false,
      'catalogVersion': 3, 'products': products,
    });
    expect(result.productId, 'postdee_post100_caption50');
    expect([result.postUnits, result.aiCaptions, result.priceThb], [100, 50, 49]);
    expect(result.catalogVersion, 3);
    expect(result.products!.map((product) => product.id), ['small', 'medium', 'large']);
    expect(result.products!.map((product) => product.postUnits), [40, 90, 190]);
    expect(result.products!.map((product) => product.aiCaptions), [25, 50, 100]);
    expect(AddonCatalogProduct.definitionFor('postdee_post180_caption100'), isNull);
    expect(result.products!.every((product) => product.enabled && product.eligible), isTrue);
    expect(() => result.products!.clear(), throwsUnsupportedError);
    expect(AddonCatalogResult.fromJson(catalog).products, isNull);
    expect(AddonCatalogResult.fromJson({...catalog, 'products': null}).products, isNull);
    expect(AddonCatalogResult.fromJson({...catalog, 'catalogVersion': 3, 'products': []}).products, isEmpty);
  });

  test('confirmation preserves exact product identity without breaking legacy responses', () {
    final response = <String, Object?>{
      'status': 'ok', 'confirmed': true, 'transactionId': 'tier-receipt',
      'transactionIdKind': 'REVENUECAT', 'productId': 'postdee_post40_caption25',
      'postUnits': 40, 'aiCaptions': 25,
      'policyVersion': 2, 'creditsExpire': false, 'expiresAt': null,
    };
    final result = AddonConfirmationResult.fromJson(response);
    expect(result.productId, 'postdee_post40_caption25');
    expect(result.transactionIdKind, 'REVENUECAT');
    expect([result.postUnits, result.aiCaptions], [40, 25]);
    expect(AddonConfirmationResult.fromJson({...response}..remove('productId')).productId, isNull);
    for (final value in [null, '', ' postdee_post40_caption25', 5]) {
      expect(() => AddonConfirmationResult.fromJson({...response, 'productId': value}),
          throwsA(isA<ApiException>()));
    }
  });

  test('new tier API requests bind each SKU to its verified receipt and quantities', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedProducts = <String>[];
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({
          ...catalog, 'catalogVersion': 3, 'products': products,
        }));
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final product = products.singleWhere((row) => row['productId'] == body['productId']);
        requestedProducts.add(body['productId'] as String);
        expect(body.keys.toSet(), {'productId', 'transactionId', 'transactionIdKind'});
        expect(body['transactionId'], 'receipt-${product['id']}');
        expect(body['transactionIdKind'], 'STORE');
        request.response.write(jsonEncode({
          'status': 'ok', 'confirmed': true,
          'productId': product['productId'], 'transactionId': body['transactionId'],
          'transactionIdKind': body['transactionIdKind'],
          'postUnits': product['postUnits'], 'aiCaptions': product['aiCaptions'],
          'policyVersion': 2, 'creditsExpire': false, 'expiresAt': null,
        }));
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final api = PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    final result = await api.loadAddonCatalog();
    expect(result.products, hasLength(3));
    for (final product in result.products!) {
      final confirmed = await api.confirmAddonPurchase(
          product.productId, 'receipt-${product.id}');
      expect(confirmed.productId, product.productId);
      expect(confirmed.postUnits, product.postUnits);
      expect(confirmed.aiCaptions, product.aiCaptions);
    }
    expect(requestedProducts, products.map((product) => product['productId']).toList());
  });

  test(
      'subscription parses additive quota fields and remains compatible with older API',
      () {
    final old = <String, Object?>{
      'userId': 'owner',
      'plan': 'PRO',
      'status': 'ACTIVE',
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': true
    };
    expect(SubscriptionStatusResult.fromJson(old).addonPostUnits, 0);
    final result = SubscriptionStatusResult.fromJson({
      ...old,
      'monthlyPostLimit': 250,
      'baseMonthlyPostLimit': 250,
      'addonPostUnits': 100,
      'addonAiCaptions': 50,
      'addonExpiresAt': null,
      'addonCreditsExpire': false,
      'availablePostUnits': 348,
    });
    expect(result.monthlyPostLimit, 250);
    expect(result.baseMonthlyPostLimit, 250);
    expect(result.addonPostUnits, 100);
    expect(result.addonAiCaptions, 50);
    expect(result.addonExpiresAt, isNull);
    expect(result.addonCreditsExpire, isFalse);
    expect(result.availablePostUnits, 348);
  });

  test(
      'invalid catalog and unverified credits cannot be accepted as confirmation',
      () {
    expect(AddonCatalogResult.fromJson(catalog).purchasedPacks, 2);
    expect(() => AddonCatalogResult.fromJson({...catalog, 'enabled': 'yes'}),
        throwsA(isA<ApiException>()));
    for (final incompatible in [
      {...catalog, 'policyVersion': 1},
      {...catalog, 'creditsExpire': true},
      {...catalog, 'expiresAt': '2026-11-01T00:00:00.000Z'},
      {...catalog}..remove('policyVersion'),
    ]) {
      expect(() => AddonCatalogResult.fromJson(incompatible),
          throwsA(isA<ApiException>()));
    }
    expect(
        () => AddonConfirmationResult.fromJson(
            {'status': 'ok', 'confirmed': true, 'transactionId': 'txn'}),
        throwsA(isA<ApiException>()));
    expect(
        AddonConfirmationResult.fromJson({
          'status': 'ok',
          'confirmed': false,
          'transactionId': 'txn',
          'policyVersion': 2,
          'creditsExpire': false,
          'expiresAt': null
        }).confirmed,
        isFalse);
  });

  test(
      'catalog GET and pending confirmation POST use the exact product and transaction',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode(catalog));
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body, {
          'productId': 'postdee_post100_caption50',
          'transactionId': body['transactionId'] == 'rc-1' ? 'rc-1' : 'txn-1',
          'transactionIdKind':
              body['transactionId'] == 'rc-1' ? 'REVENUECAT' : 'STORE',
        });
        request.response.statusCode = 202;
        request.response.write(jsonEncode({
          'status': 'ok',
          'confirmed': false,
          'transactionId': body['transactionId'],
          'transactionIdKind': body['transactionIdKind'],
          'policyVersion': 2,
          'creditsExpire': false,
          'expiresAt': null
        }));
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final api = PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    expect((await api.loadAddonCatalog()).priceThb, 49);
    expect(
        (await api.confirmAddonPurchase('postdee_post100_caption50', 'txn-1'))
            .confirmed,
        isFalse);
    expect(
        (await api.confirmAddonPurchase('postdee_post100_caption50', 'rc-1',
                transactionIdKind: 'REVENUECAT'))
            .transactionIdKind,
        'REVENUECAT');
    expect(requests, [
      'GET /billing/addons',
      'POST /billing/addons/confirm',
      'POST /billing/addons/confirm'
    ]);
  });

  test('unknown transaction namespace is rejected before posting a purchase',
      () async {
    final api = PostDeeApiClient(baseUrl: 'http://127.0.0.1:1');
    await expectLater(
        api.confirmAddonPurchase('postdee_post100_caption50', 'rc-1',
            transactionIdKind: 'GUESS'),
        throwsA(isA<ApiException>()));
  });

  test(
      'confirmation parsing defaults legacy missing namespaces to STORE and rejects unknown namespaces',
      () {
    final response = <String, Object?>{
      'status': 'ok',
      'confirmed': false,
      'transactionId': 'same-id',
      'policyVersion': 2,
      'creditsExpire': false,
      'expiresAt': null
    };
    expect(
        AddonConfirmationResult.fromJson(response).transactionIdKind, 'STORE');
    expect(
        AddonConfirmationResult.fromJson(
            {...response, 'transactionIdKind': 'REVENUECAT'}).transactionIdKind,
        'REVENUECAT');
    expect(
        () => AddonConfirmationResult.fromJson(
            {...response, 'transactionIdKind': 'GUESS'}),
        throwsA(isA<ApiException>()));
  });

  test(
      'caption quota separates monthly usage from the remaining purchased bank',
      () {
    final quota = RealClipCaptionQuota.fromJson({
      'limit': 50,
      'usedThisMonth': 50,
      'remainingThisMonth': 0,
      'addonRemaining': 39,
      'availableGenerations': 39
    });
    expect(quota.remainingThisMonth, 0);
    expect(quota.addonRemaining, 39);
    expect(quota.availableGenerations, 39);
  });
}
