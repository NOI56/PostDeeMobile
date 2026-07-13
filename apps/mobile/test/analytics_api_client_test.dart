import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('loads the selected analytics range and parses daily metrics', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final client = _clientFor(server);
      final resultFuture = client.loadAnalyticsSummary(range: '7d');
      final request = await server.first;

      expect(request.method, 'GET');
      expect(request.uri.path, '/analytics/summary');
      expect(request.uri.queryParameters['range'], '7d');

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'summary': {
            'range': '7d',
            'totalViews': 120,
            'totalLikes': 12,
            'platforms': <Object?>[],
            'daily': [
              {'date': '2026-07-13T00:00:00.000Z', 'views': 120, 'likes': 12},
            ],
          },
        }));
      await request.response.close();

      final result = await resultFuture;
      expect(result.range, '7d');
      expect(result.daily.single.views, 120);
      expect(result.daily.single.likes, 12);
    } finally {
      await server.close(force: true);
    }
  });

  test('keeps the backend error code on ApiException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    try {
      final client = _clientFor(server);
      final resultFuture = client.loadAnalyticsSummary();
      final expectation = expectLater(
        resultFuture,
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 402)
              .having((error) => error.code, 'code', 'PRO_REQUIRED'),
        ),
      );
      final request = await server.first;

      request.response
        ..statusCode = HttpStatus.paymentRequired
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'error',
          'code': 'PRO_REQUIRED',
          'message': 'Unified Analytics requires the Pro plan',
        }));
      await request.response.close();
      await expectation;
    } finally {
      await server.close(force: true);
    }
  });
}

PostDeeApiClient _clientFor(HttpServer server) {
  return PostDeeApiClient(
    baseUrl: 'http://${server.address.address}:${server.port}',
    authHeaders: PostDeeApiAuthHeaders(
      authTokenProvider: () async => null,
      mockUserId: 'analytics-test-user',
      mockSubscriptionPlan: 'PRO',
    ),
  );
}
