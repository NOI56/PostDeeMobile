import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

const _request = CreatePostRequest(
  clientRequestId: 'submit_fixture',
  caption: 'original caption',
  videoS3Key: 'uploads/existing.mp4',
  platforms: ['YOUTUBE_SHORTS'],
  platformSettings: {
    'YOUTUBE_SHORTS': {'visibility': 'private'}
  },
  mediaContentFingerprint: '0123456789abcdef',
);

Map<String, Object?> _accepted({String status = 'PUBLISHING'}) => {
      'status': 'ok',
      'recovered': true,
      'idempotentReplay': true,
      'post': {
        'id': 'existing-post',
        'videoS3Key': 'uploads/existing.mp4',
        'platforms': ['YOUTUBE_SHORTS'],
        'status': status
      },
    };

void main() {
  for (final state in ['QUEUED', 'PUBLISHING', 'PUBLISHED', 'FAILED']) {
    test('recovers an existing $state submission with exact intent and auth',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        expect(request.method, 'POST');
        expect(request.uri.path, '/posts/submissions/recover');
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer owner-token');
        expect(jsonDecode(await utf8.decoder.bind(request).join()),
            _request.toJson());
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_accepted(status: state)));
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          authTokenProvider: () async => 'owner-token',
        );
        final result = (await client.recoverPostSubmission(_request))!;
        expect(result.id, 'existing-post');
        expect(result.status, state);
        expect(result.idempotentReplay, isTrue);
        await task;
      } finally {
        await server.close(force: true);
      }
    });
  }

  test(
      'only typed not-found means absent; an old API route is never treated as absent',
      () async {
    for (final code in [
      'POST_SUBMISSION_NOT_FOUND',
      'IDEMPOTENCY_KEY_REUSED',
      'PRIVATE_PROVIDER_CODE',
      'generic404'
    ]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        await request.drain<void>();
        request.response.statusCode =
            code == 'IDEMPOTENCY_KEY_REUSED' ? 409 : 404;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          if (code != 'generic404') 'code': code,
          'message': 'provider-private-value',
        }));
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );
        if (code == 'POST_SUBMISSION_NOT_FOUND') {
          expect(await client.recoverPostSubmission(_request), isNull);
        } else {
          await expectLater(
              client.recoverPostSubmission(_request),
              throwsA(isA<ApiException>()
                  .having(
                      (error) => error.code,
                      'safe code',
                      code == 'IDEMPOTENCY_KEY_REUSED'
                          ? code
                          : 'POST_SUBMISSION_RECOVERY_UNAVAILABLE')
                  .having((error) => error.message, 'safe message',
                      isNot(contains('provider-private-value')))));
        }
        await task;
      } finally {
        await server.close(force: true);
      }
    }
  });

  test('malformed recovery acknowledgement cannot erase a local receipt',
      () async {
    for (final invalid in <Map<String, Object?>>[
      {'recovered': false},
      {'idempotentReplay': false},
      {'post': null},
      {
        'post': {'id': 'existing-post'}
      },
    ]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({..._accepted(), ...invalid}));
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
        );
        await expectLater(client.recoverPostSubmission(_request),
            throwsA(isA<ApiException>()));
        await task;
      } finally {
        await server.close(force: true);
      }
    }
  });

  for (final responseStatus in [HttpStatus.ok, HttpStatus.notFound]) {
    test('recovery response $responseStatus cannot cross an owner change',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sessions = PostDeeAuthSessionStore(
          initialSession:
              const AuthSession(userId: 'owner-a', idToken: 'token-a'));
      final requestArrived = Completer<void>();
      final release = Completer<void>();
      final task = () async {
        final request = await server.first;
        await request.drain<void>();
        requestArrived.complete();
        await release.future;
        request.response.statusCode = responseStatus;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(responseStatus == HttpStatus.ok
            ? _accepted()
            : {'code': 'POST_SUBMISSION_NOT_FOUND', 'message': 'absent'}));
        await request.response.close();
      }();
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          sessionBinding: sessions.captureSession(),
        );
        final result = client.recoverPostSubmission(_request);
        final assertion =
            expectLater(result, throwsA(isA<AuthSessionChangedException>()));
        await requestArrived.future;
        sessions
            .signIn(const AuthSession(userId: 'owner-b', idToken: 'token-b'));
        release.complete();
        await assertion;
        await task;
      } finally {
        await server.close(force: true);
        sessions.dispose();
      }
    });
  }
}
