import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

// Release builds with Firebase sign-in send ID tokens on every API call; a
// cleartext base URL (such as the localhost default) must never receive them.
void main() {
  Future<({HttpServer server, HttpClient http, int Function() requests})> serve() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"status":"ok","templates":[]}');
      await request.response.close();
    });
    return (server: server, http: http, requests: () => requests);
  }

  test('a release Firebase build refuses an http API base URL before sending', () async {
    final fixture = await serve();
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://127.0.0.1:${fixture.server.port}',
        httpClient: fixture.http,
        authTokenProvider: () async => 'firebase-id-token',
        releaseMode: true,
        enableFirebaseAuth: true,
      );

      await expectLater(
        client.listTemplates(),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'INSECURE_API_BASE_URL')),
      );
      expect(fixture.requests(), 0);
    } finally {
      fixture.http.close(force: true);
      await fixture.server.close(force: true);
    }
  });

  test('debug and mock-auth builds keep using a local http API', () async {
    final fixture = await serve();
    try {
      for (final (releaseMode, enableFirebaseAuth) in [(false, true), (true, false)]) {
        final client = PostDeeApiClient(
          baseUrl: 'http://127.0.0.1:${fixture.server.port}',
          httpClient: fixture.http,
          authTokenProvider: () async => null,
          releaseMode: releaseMode,
          enableFirebaseAuth: enableFirebaseAuth,
        );
        expect(await client.listTemplates(), isEmpty);
      }
      expect(fixture.requests(), 2);
    } finally {
      fixture.http.close(force: true);
      await fixture.server.close(force: true);
    }
  });
}
