import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test(
      'reads a single encoded post id and owned preview through the authenticated endpoint',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          authHeaders: PostDeeApiAuthHeaders(
              authTokenProvider: () async => 'owner-token'));
      final result = client.getPostById('post/id', includeMedia: true);
      final request = await server.first;
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, ['posts', 'post/id']);
      expect(request.uri.queryParameters['includeMedia'], 'true');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer owner-token');
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'post': {
            'id': 'post/id',
            'caption': 'Owned',
            'videoS3Key': 'uploads/owner/clip.mp4',
            'platforms': ['TIKTOK'],
            'status': 'PUBLISHING',
            'createdAt': '2026-10-21T00:00:00.000Z',
            'videoUrl': 'https://private-media.test/video?signature=safe'
          }
        }));
      await request.response.close();
      expect((await result)?.videoUrl?.host, 'private-media.test');
    } finally {
      await server.close(force: true);
    }
  });

  for (final code in ['POST_NOT_FOUND', null]) {
    test(
        'only exact missing-post contract is absence, generic route 404 stays an error ($code)',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final client = PostDeeApiClient(
            baseUrl: 'http://${server.address.address}:${server.port}');
        final operation = client.getPostById('missing');
        final checked = code == null
            ? expectLater(operation, throwsA(isA<ApiException>()))
            : null;
        final request = await server.first;
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'error',
            if (code != null) 'code': code,
            'message': 'Missing'
          }));
        await request.response.close();
        if (checked != null) {
          await checked;
        } else {
          expect(await operation, isNull);
        }
      } finally {
        await server.close(force: true);
      }
    });
  }
}
