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
