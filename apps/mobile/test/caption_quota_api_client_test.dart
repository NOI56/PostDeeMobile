import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _response(
        {String plan = 'STARTER',
        int used = 12,
        int remaining = 38,
        int addon = 5,
        int available = 43}) =>
    {
      'status': 'ok',
      'plan': plan,
      'quota': {
        'limit': 50,
        'usedThisMonth': used,
        'remainingThisMonth': remaining,
        'addonRemaining': addon,
        'availableGenerations': available,
      }
    };

void main() {
  test('reads the authenticated monthly quota and purchased credit balance',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = PostDeeApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        authTokenProvider: () async => 'quota-owner-token');
    final served = server.first.then((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/captions/quota');
      expect(request.uri.queryParameters, isEmpty);
      expect(
          request.headers.value('authorization'), 'Bearer quota-owner-token');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_response()));
      await request.response.close();
    });
    try {
      final result = await api.fetchAiCaptionQuota();
      expect(result.plan, 'STARTER');
      expect(result.isPaid, isTrue);
      expect(result.quota.usedThisMonth, 12);
      expect(result.quota.remainingThisMonth, 38);
      expect(result.quota.addonRemaining, 5);
      expect(result.availableCount, 43);
      await served;
    } finally {
      await server.close(force: true);
    }
  });

  test(
      'keeps addon credits usable when the monthly included quota is exhausted',
      () {
    final result = CaptionQuotaResult.fromJson(
        _response(used: 50, remaining: 0, addon: 5, available: 5));
    expect(result.availableCount, 5);
    final base = _response();
    final quota = Map<String, Object?>.from(base['quota']! as Map);
    quota.remove('availableGenerations');
    expect(
        CaptionQuotaResult.fromJson({...base, 'quota': quota}).availableCount,
        43);
    quota.remove('addonRemaining');
    expect(
        CaptionQuotaResult.fromJson({...base, 'quota': quota}).availableCount,
        38);
  });

  test('retains purchased credits but exposes no available AI uses for Basic',
      () {
    final result = CaptionQuotaResult.fromJson({
      'plan': 'BASIC',
      'quota': {
        'limit': 0,
        'usedThisMonth': 12,
        'remainingThisMonth': 0,
        'addonRemaining': 5,
        'availableGenerations': 0,
      }
    });
    expect(result.isPaid, isFalse);
    expect(result.quota.addonRemaining, 5);
    expect(result.availableCount, 0);
  });

  test('accepts actual use exceeding the monthly allowance after a downgrade',
      () {
    final result = CaptionQuotaResult.fromJson(
        _response(used: 80, remaining: 0, addon: 0, available: 0));
    expect(result.quota.usedThisMonth, 80);
    expect(result.availableCount, 0);
  });

  test('keeps fallback refund and pending refresh metadata with quota balances',
      () {
    final response = _response();
    final quota = Map<String, Object?>.from(response['quota']! as Map);
    final result = CaptionQuotaResult.fromJson({
      ...response,
      'quota': {...quota, 'charged': false, 'usageRefreshPending': true},
    });
    expect(result.quota.charged, isFalse);
    expect(result.quota.usageRefreshPending, isTrue);
    expect(result.quota.addonRemaining, 5);
    expect(result.availableCount, 43);
    expect(CaptionQuotaResult.fromJson(response).quota.usageRefreshPending,
        isFalse);
  });

  test('rejects malformed quota data instead of inventing a balance', () {
    final valid = _response();
    final quota = Map<String, Object?>.from(valid['quota']! as Map);
    for (final invalid in <Map<String, Object?>>[
      {'plan': 'STARTER'},
      {'quota': quota},
      {...valid, 'plan': 'UNKNOWN'},
      {
        ...valid,
        'quota': {...quota, 'limit': -1}
      },
      {
        ...valid,
        'quota': {...quota, 'usedThisMonth': -1}
      },
      {
        ...valid,
        'quota': {...quota, 'remainingThisMonth': 51}
      },
      {
        ...valid,
        'quota': {...quota, 'addonRemaining': -1}
      },
      {
        ...valid,
        'quota': {...quota, 'availableGenerations': '43'}
      },
      {
        ...valid,
        'quota': {...quota, 'usageRefreshPending': 'yes'}
      },
    ]) {
      expect(() => CaptionQuotaResult.fromJson(invalid),
          throwsA(isA<ApiException>()));
    }
  });
}
