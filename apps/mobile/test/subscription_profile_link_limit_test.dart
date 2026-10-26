import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _subscription(String plan,
        {Object? limit, bool includeLimit = false}) =>
    {
      'userId': 'profile-link-owner',
      'plan': plan,
      'status': 'ACTIVE',
      'canSchedule': plan != 'BASIC',
      'canUseAiCaptions': plan != 'BASIC',
      'canUseAnalytics': plan == 'PRO',
      if (includeLimit) 'maxProfileLinks': limit,
    };

void main() {
  for (final entry in {
    'FREE': 2,
    'BASIC': 2,
    'STARTER': 7,
    'PRO': 20,
    'unknown': 2,
    '': 2,
    'pro': 20
  }.entries) {
    test('old subscription without maxProfileLinks uses effective ${entry.key}',
        () {
      final result =
          SubscriptionStatusResult.fromJson(_subscription(entry.key));
      expect(result.maxProfileLinks, entry.value);
    });
  }

  test('trial access uses effective plan rather than purchased plan or status',
      () {
    final json = _subscription('PRO')..['purchasedPlan'] = 'BASIC';
    json['status'] = 'TRIAL';
    final result = SubscriptionStatusResult.fromJson(json);
    expect(result.maxProfileLinks, 20);
    expect(result.purchasedPlan, 'BASIC');
  });

  for (final limit in [1, 2, 7, 20]) {
    test('accepts a valid server profile-link limit $limit', () {
      final result = SubscriptionStatusResult.fromJson(
          _subscription('PRO', includeLimit: true, limit: limit));
      expect(result.maxProfileLinks, limit);
    });
  }

  for (final entry in {'BASIC': 2, 'STARTER': 7, 'unknown': 2}.entries) {
    test('server limit cannot overgrant effective ${entry.key}', () {
      final result = SubscriptionStatusResult.fromJson(
          _subscription(entry.key, includeLimit: true, limit: 20));
      expect(result.maxProfileLinks, entry.value);
    });
  }

  for (final limit in [
    null,
    0,
    -1,
    21,
    999999999,
    '20',
    'unlimited',
    7.5,
    true
  ]) {
    test('invalid maxProfileLinks $limit retains a finite plan fallback', () {
      expect(
          SubscriptionStatusResult.fromJson(
                  _subscription('STARTER', includeLimit: true, limit: limit))
              .maxProfileLinks,
          7);
      expect(
          SubscriptionStatusResult.fromJson(
                  _subscription('unknown', includeLimit: true, limit: limit))
              .maxProfileLinks,
          2);
    });
  }

  test('const constructors keep optional fallback and validate explicit limits',
      () {
    const old = SubscriptionStatusResult(
        userId: 'owner',
        plan: 'STARTER',
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: false);
    const lower = SubscriptionStatusResult(
        userId: 'owner',
        plan: 'PRO',
        status: 'ACTIVE',
        maxProfileLinks: 7,
        canSchedule: true,
        canUseAiCaptions: true,
        canUseAnalytics: true);
    const invalid = SubscriptionStatusResult(
        userId: 'owner',
        plan: 'BASIC',
        status: 'ACTIVE',
        maxProfileLinks: -1,
        canSchedule: false,
        canUseAiCaptions: false,
        canUseAnalytics: false);
    expect(old.maxProfileLinks, 7);
    expect(lower.maxProfileLinks, 7);
    expect(invalid.maxProfileLinks, 2);
  });

  test(
      'subscription client reads the additive entitlement without changing its route',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final api = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}');
      final response = api.loadCurrentSubscription();
      final request = await server.first;
      expect(request.method, 'GET');
      expect(request.uri.path, '/billing/subscription');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'subscription': _subscription('STARTER', includeLimit: true, limit: 7)
        }));
      await request.response.close();
      expect((await response).maxProfileLinks, 7);
    } finally {
      await server.close(force: true);
    }
  });
}
