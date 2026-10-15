import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('readiness DTO preserves explicit states and safe optional bindings',
      () {
    final states = {
      'ready': SocialPublishingState.ready,
      'connected': SocialPublishingState.connected,
      'reconnect_required': SocialPublishingState.reconnectRequired,
      'permission_missing': SocialPublishingState.permissionMissing,
      'not_connected': SocialPublishingState.notConnected,
      'unavailable': SocialPublishingState.unavailable,
    };
    for (final entry in states.entries) {
      final value = SocialPublishingConnectionReadiness.fromJson({
        'platform': 'YOUTUBE_SHORTS',
        'state': entry.key,
        'connectionId': 'local-id',
        'connectionRevision': 'a' * 64,
      });
      expect(value.state, entry.value);
      expect(value.connectionId, 'local-id');
      expect(value.connectionRevision, 'a' * 64);
      expect(
          value.blocksPublishing,
          entry.value != SocialPublishingState.ready &&
              entry.value != SocialPublishingState.connected);
    }
    expect(
        SocialPublishingConnectionReadiness.fromJson({
          'platform': 'INSTAGRAM_REELS',
          'state': 'connected',
        }).connectionId,
        isNull);
  });

  test('unknown or malformed readiness state fails closed without raw errors',
      () {
    for (final state in [null, 1, true, 'provider-private-state']) {
      final value = SocialPublishingConnectionReadiness.fromJson({
        'platform': 'INSTAGRAM_REELS',
        'state': state,
        'reasonCode': 'provider-private-value',
      });
      expect(value.state, SocialPublishingState.unavailable);
      expect(value.blocksPublishing, isTrue);
      expect(value.reasonCode, isNull);
    }
  });

  test(
      'readiness loader authenticates fresh owner-scoped GET without account IDs',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final task = () async {
      var calls = 0;
      await for (final request in server) {
        expect(request.method, 'GET');
        expect(request.uri.path, '/social-connections/publishing-readiness');
        expect(request.uri.query, isEmpty);
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer test-token');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'connections': [
            {'platform': 'YOUTUBE_SHORTS', 'state': 'ready'},
          ],
        }));
        await request.response.close();
        if (++calls == 2) break;
      }
    }();
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authTokenProvider: () async => 'test-token',
      );
      for (var i = 0; i < 2; i++) {
        final results = await client.loadSocialPublishingReadiness();
        expect(results.single.state, SocialPublishingState.ready);
        expect(() => results.clear(), throwsUnsupportedError);
      }
      await task;
    } finally {
      await server.close(force: true);
    }
  });

  test(
      'readiness preserves session cancellation when the signed-in owner changes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final store = PostDeeAuthSessionStore(
        initialSession:
            const AuthSession(userId: 'owner-a', idToken: 'token-a'));
    final token = Completer<String?>();
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        sessionBinding: store.captureSession(),
        authTokenProvider: () => token.future,
      );
      final result = client.loadSocialPublishingReadiness();
      final assertion =
          expectLater(result, throwsA(isA<AuthSessionChangedException>()));
      store.signIn(const AuthSession(userId: 'owner-b', idToken: 'token-b'));
      token.complete('token-a');
      await assertion;
    } finally {
      await server.close(force: true);
      store.dispose();
    }
  });

  test(
      'readiness HTTP error preserves an owner change instead of compatibility fallback',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessions = PostDeeAuthSessionStore(
        initialSession:
            const AuthSession(userId: 'owner-a', idToken: 'token-a'));
    final task = () async {
      final request = await server.first;
      sessions.signIn(const AuthSession(userId: 'owner-b', idToken: 'token-b'));
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'old route'}));
      await request.response.close();
    }();
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        sessionBinding: sessions.captureSession(),
      );
      await expectLater(client.loadSocialPublishingReadiness(),
          throwsA(isA<AuthSessionChangedException>()));
      await task;
    } finally {
      await server.close(force: true);
      sessions.dispose();
    }
  });

  test('readiness malformed responses and HTTP failures use safe errors',
      () async {
    for (final mode in ['404', '500', 'malformed', 'duplicate', 'bad-item']) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        request.response.headers.contentType = ContentType.json;
        if (mode == '404' || mode == '500') {
          request.response.statusCode = int.parse(mode);
          request.response.write(jsonEncode({
            'message': 'provider-private-value',
            'code': 'PRIVATE_PROVIDER_CODE',
          }));
        } else {
          request.response.write(jsonEncode({
            'status': 'ok',
            'connections': switch (mode) {
              'malformed' => 'provider-private-value',
              'bad-item' => [null],
              _ => [
                  {'platform': 'YOUTUBE_SHORTS', 'state': 'ready'},
                  {'platform': 'YOUTUBE_SHORTS', 'state': 'not_connected'},
                ],
            },
          }));
        }
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );
        await expectLater(
            client.loadSocialPublishingReadiness(),
            throwsA(isA<ApiException>()
                .having((error) => error.message, 'safe message',
                    isNot(contains('provider-private-value')))
                .having((error) => error.code, 'safe code',
                    isNot('PRIVATE_PROVIDER_CODE'))
                .having((error) => error.statusCode, 'status',
                    mode == '404' || mode == '500' ? int.parse(mode) : null)));
        await task;
      } finally {
        await server.close(force: true);
      }
    }
  });
}
