import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('loads the authenticated caption quota without generating a caption',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = PostDeeApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}',
      authTokenProvider: () async => 'caption-owner-token',
    );
    final served = server.first.then((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/captions/quota');
      expect(request.uri.queryParameters, isEmpty);
      expect(
          request.headers.value('authorization'), 'Bearer caption-owner-token');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'plan': 'STARTER',
        'quota': {'limit': 50, 'usedThisMonth': 12, 'remainingThisMonth': 38},
      }));
      await request.response.close();
    });
    try {
      final result = await client.fetchAiCaptionQuota();
      expect(result.plan, 'STARTER');
      expect(result.quota.limit, 50);
      expect(result.quota.usedThisMonth, 12);
      expect(result.quota.remainingThisMonth, 38);
      await served;
    } finally {
      await server.close(force: true);
    }
  });

  test(
      'rejects missing or malformed quota rather than inventing a zero balance',
      () {
    for (final body in <Map<String, Object?>>[
      {'status': 'ok', 'plan': 'STARTER'},
      {
        'status': 'ok',
        'quota': {'limit': 50, 'usedThisMonth': 12, 'remainingThisMonth': 38}
      },
      {
        'status': 'ok',
        'plan': 'UNKNOWN',
        'quota': {'limit': 50, 'usedThisMonth': 12, 'remainingThisMonth': 38}
      },
      {
        'status': 'ok',
        'plan': 'STARTER',
        'quota': {'limit': 50, 'usedThisMonth': -1, 'remainingThisMonth': 51}
      },
    ]) {
      expect(() => CaptionQuotaResult.fromJson(body),
          throwsA(isA<ApiException>()));
    }
    final downgraded = CaptionQuotaResult.fromJson({
      'plan': 'STARTER',
      'quota': {'limit': 50, 'usedThisMonth': 70, 'remainingThisMonth': 0},
    });
    expect(downgraded.quota.usedThisMonth, 70);
    expect(downgraded.quota.remainingThisMonth, 0);
  });
}
