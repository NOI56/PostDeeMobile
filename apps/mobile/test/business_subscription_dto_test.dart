import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _subscription(String plan, {Object? limit}) => {
      'userId': 'business-owner',
      'plan': plan,
      'status': 'ACTIVE',
      'maxProfileLinks': limit,
      'monthlyPostLimit': 400,
      'monthlyAiCaptionLimit': 220,
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': false,
    };

Map<String, Object?> _profile(int count) => {
      'storeName': 'Business shop',
      'slug': 'business-shop',
      'links': List.generate(
          count,
          (i) => {
                'id': 'link-$i',
                'title': 'Link $i',
                'url': 'https://example.com/item/$i',
              }),
      'isPublished': false,
      'updatedAt': '2026-11-02T00:00:00Z',
    };

void main() {
  test('Business has its own immutable monthly product identifier', () {
    expect(AppConfig.storeBusinessMonthlyProductId, 'postdee_business_monthly');
  });

  test('Business identity inherits paid capabilities and finite 50-link limit',
      () {
    final result = SubscriptionStatusResult.fromJson(_subscription('BUSINESS'));
    expect(result.isBusiness, isTrue);
    expect(result.isPro, isFalse);
    expect(result.isStarter, isFalse);
    expect(result.isPaid, isTrue);
    expect(result.hasProFeatures, isTrue);
    expect(result.maxProfileLinks, 50);
    expect(result.monthlyPostLimit, 400);
    expect(result.monthlyAiCaptionLimit, 220);
    expect(result.businessPlanAvailable, isFalse);
    expect(result.canUseAnalytics, isFalse);
  });

  for (final entry
      in {'BASIC': 2, 'STARTER': 7, 'PRO': 20, 'UNKNOWN': 2}.entries) {
    test('a 50-link server value cannot overgrant ${entry.key}', () {
      final result = SubscriptionStatusResult.fromJson(
          _subscription(entry.key, limit: 50));
      expect(result.maxProfileLinks, entry.value);
      expect(result.isBusiness, isFalse);
    });
  }
  for (final limit in [1, 20, 49, 50]) {
    test('Business accepts bounded server limit $limit', () {
      expect(
          SubscriptionStatusResult.fromJson(
                  _subscription('BUSINESS', limit: limit))
              .maxProfileLinks,
          limit);
    });
  }
  for (final limit in [0, -1, 51, 999999, '50', 50.1, true]) {
    test('invalid Business link limit $limit uses finite plan fallback', () {
      expect(
          SubscriptionStatusResult.fromJson(
                  _subscription('BUSINESS', limit: limit))
              .maxProfileLinks,
          50);
    });
  }
  for (final flag in [null, false, 'true', 1]) {
    test('missing or invalid offer flag $flag cannot enable a sale', () {
      final json = _subscription('BUSINESS')..['businessPlanAvailable'] = flag;
      expect(SubscriptionStatusResult.fromJson(json).businessPlanAvailable,
          isFalse);
    });
  }
  test('explicit server Business offer flag is additive', () {
    final json = _subscription('BASIC')..['businessPlanAvailable'] = true;
    expect(
        SubscriptionStatusResult.fromJson(json).businessPlanAvailable, isTrue);
  });

  test('Business caption quota includes the real monthly and purchased banks',
      () {
    final quota = CaptionQuotaResult.fromJson({
      'plan': 'BUSINESS',
      'quota': {
        'limit': 220,
        'usedThisMonth': 20,
        'remainingThisMonth': 200,
        'addonRemaining': 25,
        'availableGenerations': 225
      },
    });
    expect(quota.isPaid, isTrue);
    expect(quota.availableCount, 225);
  });

  test('profile parser preserves every one of 50 links without truncation', () {
    final profile = LinkInBioProfileResult.fromJson(_profile(50),
        apiBaseUri: Uri.parse('https://api.example.com'));
    expect(profile.links, hasLength(50));
    expect(profile.links.last.id, 'link-49');
    expect(
        () => LinkInBioProfileResult.fromJson(_profile(51),
            apiBaseUri: Uri.parse('https://api.example.com')),
        throwsA(isA<ApiException>()));
  });

  for (final echo in [null, 'PRO', 'BUSINESS']) {
    test('Business purchase readiness requires exact plan echo $echo',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final api = PostDeeApiClient(
            baseUrl: 'http://${server.address.address}:${server.port}');
        final operation = api.prepareBusinessSubscriptionPurchase();
        final checked = echo == 'BUSINESS'
            ? expectLater(operation, completes)
            : expectLater(operation, throwsA(isA<ApiException>()));
        final request = await server.first;
        expect(request.uri.path, '/billing/purchase-readiness');
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body, {'purchaseConfirmationProtocol': 2, 'plan': 'BUSINESS'});
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'purchaseReady': true,
          'preparationProtocol': 1,
          if (echo != null) 'plan': echo
        }));
        await request.response.close();
        await checked;
      } finally {
        await server.close(force: true);
      }
    });
  }
}
