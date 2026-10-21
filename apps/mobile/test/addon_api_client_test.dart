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
    'monthKey': '2026-10',
    'expiresAt': '2026-11-01T00:00:00.000Z',
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
      'monthlyPostLimit': 350,
      'baseMonthlyPostLimit': 250,
      'addonPostUnits': 100,
      'addonAiCaptions': 50,
      'addonExpiresAt': '2026-11-01T00:00:00.000Z'
    });
    expect(result.monthlyPostLimit, 350);
    expect(result.baseMonthlyPostLimit, 250);
    expect(result.addonPostUnits, 100);
    expect(result.addonAiCaptions, 50);
    expect(result.addonExpiresAt, DateTime.utc(2026, 11));
  });

  test(
      'invalid catalog and unverified credits cannot be accepted as confirmation',
      () {
    expect(AddonCatalogResult.fromJson(catalog).purchasedPacks, 2);
    expect(() => AddonCatalogResult.fromJson({...catalog, 'enabled': 'yes'}),
        throwsA(isA<ApiException>()));
    expect(
        () => AddonConfirmationResult.fromJson(
            {'status': 'ok', 'confirmed': true, 'transactionId': 'txn'}),
        throwsA(isA<ApiException>()));
    expect(
        AddonConfirmationResult.fromJson(
                {'status': 'ok', 'confirmed': false, 'transactionId': 'txn'})
            .confirmed,
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
          'transactionId': 'txn-1'
        });
        request.response.statusCode = 202;
        request.response.write(jsonEncode(
            {'status': 'ok', 'confirmed': false, 'transactionId': 'txn-1'}));
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
    expect(requests, ['GET /billing/addons', 'POST /billing/addons/confirm']);
  });
}
