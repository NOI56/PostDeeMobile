import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Matcher get _timeoutError => isA<ApiException>()
    .having((e) => e.statusCode, 'status', 408)
    .having((e) => e.code, 'code', 'API_REQUEST_TIMEOUT');

class _DelayedOpenClient implements HttpClient {
  _DelayedOpenClient(this.delegate);
  final HttpClient delegate;
  final obtained = Completer<void>();
  final release = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await delegate.openUrl(method, url);
    if (!obtained.isCompleted) {
      obtained.complete();
      await release.future;
    }
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a late connection is aborted without unhandled errors or late send',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final delayed = _DelayedOpenClient(http);
    var requests = 0;
    final handler = server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.write('{"status":"ok","service":"postdee-api"}');
      await request.response.close();
    });
    try {
      final client = PostDeeApiClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          httpClient: delayed,
          requestTimeout: const Duration(milliseconds: 200));
      final expectation =
          expectLater(client.checkHealth(), throwsA(_timeoutError));
      await delayed.obtained.future;
      await expectation;
      delayed.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, 0);
      expect((await client.checkHealth()).isOk, isTrue);
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
    }
  });

  for (final stallBody in [false, true]) {
    test(
        'bounds stalled ${stallBody ? 'body' : 'headers'} without closing other requests',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      var requests = 0;
      final firstReceived = Completer<void>();
      final handler = server.listen((request) async {
        await request.drain<void>();
        requests++;
        if (requests == 1) {
          firstReceived.complete();
          if (stallBody) {
            request.response.write('{"status":');
            await request.response.flush();
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        request.response.write('{"status":"ok","service":"postdee-api"}');
        await request.response.close();
      });
      try {
        final client = PostDeeApiClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          httpClient: http,
          requestTimeout: const Duration(milliseconds: 350),
        );
        final timedOut = expectLater(
            client.checkHealth().timeout(const Duration(seconds: 2)),
            throwsA(_timeoutError));
        await firstReceived.future;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final concurrentHealthyRequest = client.checkHealth();
        await timedOut;
        expect((await concurrentHealthyRequest).isOk, isTrue);
        expect(requests, 2);
      } finally {
        http.close(force: true);
        await handler.cancel();
        await server.close(force: true);
      }
    });
  }

  test('late auth refresh cannot send a post after the deadline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final token = Completer<String?>();
    var sentRequests = 0;
    final handler = server.listen((request) async {
      sentRequests++;
      await request.drain<void>();
      request.response.write('{}');
      await request.response.close();
    });
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: http,
        authTokenProvider: () => token.future,
        requestTimeout: const Duration(milliseconds: 100),
      );
      await expectLater(
          client
              .createPost(const CreatePostRequest(
                clientRequestId: 'stable-request',
                caption: 'ทดสอบ',
                videoS3Key: 'uploads/seller/test.mp4',
                platforms: ['TIKTOK'],
              ))
              .timeout(const Duration(seconds: 2)),
          throwsA(_timeoutError));
      token.complete('test-token');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sentRequests, 0);
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
    }
  });

  test('AI transcription has a longer budget than ordinary JSON requests',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final handler = server.listen((request) async {
      await request.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response.write(jsonEncode({
        'transcript': {
          'text': 'สวัสดี',
          'segments': [],
          'language': 'th',
        }
      }));
      await request.response.close();
    });
    try {
      final client = PostDeeApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: http,
        requestTimeout: const Duration(milliseconds: 100),
        aiRequestTimeout: const Duration(seconds: 2),
      );
      expect((await client.transcribeClip('uploads/test.mp4')).text, 'สวัสดี');
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
    }
  });

  test('legacy upload response cannot wait indefinitely', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final directory =
        await Directory.systemTemp.createTemp('postdee-deadline-');
    final file =
        await File('${directory.path}/test.mp4').writeAsBytes([1, 2, 3]);
    final handler = server.listen((request) async {
      await request.drain<void>();
    });
    try {
      final client = PostDeeApiClient(
          httpClient: http,
          uploadRequestTimeout: const Duration(milliseconds: 200));
      await expectLater(
          client
              .uploadVideoFile(
                  UploadResult(
                    id: 'legacy',
                    videoS3Key: 'uploads/test.mp4',
                    storageProvider: 'private',
                    uploadUrl: 'http://127.0.0.1:${server.port}/object',
                    uploadMethod: 'PUT',
                  ),
                  file)
              .timeout(const Duration(seconds: 2)),
          throwsA(_timeoutError));
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('multipart stalled PUT retries are bounded and abort the upload session',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final directory =
        await Directory.systemTemp.createTemp('postdee-part-deadline-');
    final file =
        await File('${directory.path}/test.mp4').writeAsBytes([1, 2, 3]);
    var signedUrls = 0;
    var aborts = 0;
    final base = 'http://127.0.0.1:${server.port}';
    final handler = server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'PUT') return;
      if (request.method == 'DELETE') {
        aborts++;
        request.response.write('{}');
      } else {
        signedUrls++;
        request.response.write(jsonEncode({
          'part': {
            'partNumber': 1,
            'sizeBytes': 3,
            'uploadUrl': '$base/object/$signedUrls',
            'uploadMethod': 'PUT',
            'uploadHeaders': {},
          }
        }));
      }
      await request.response.close();
    });
    try {
      final client = PostDeeApiClient(
          baseUrl: base,
          httpClient: http,
          requestTimeout: const Duration(seconds: 1),
          uploadRequestTimeout: const Duration(milliseconds: 100));
      await expectLater(
          client
              .uploadVideoFile(
                  const UploadResult(
                    id: 'managed',
                    videoS3Key: 'uploads/test.mp4',
                    storageProvider: 'private',
                    uploadProtocol: 'multipart-v1',
                    partSizeBytes: 3,
                    partCount: 1,
                  ),
                  file)
              .timeout(const Duration(seconds: 3)),
          throwsA(_timeoutError));
      expect(signedUrls, 3);
      expect(aborts, 1);
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('timed-out multipart completion checks committed status before aborting',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = HttpClient();
    final directory =
        await Directory.systemTemp.createTemp('postdee-complete-deadline-');
    final file =
        await File('${directory.path}/test.mp4').writeAsBytes([1, 2, 3]);
    final base = 'http://127.0.0.1:${server.port}';
    var completionAccepted = false;
    var aborts = 0;
    final handler = server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'PUT') {
        request.response.headers.set(HttpHeaders.etagHeader, '"etag-one"');
      } else if (request.uri.path.endsWith('/complete')) {
        completionAccepted = true;
        return;
      } else if (request.method == 'GET') {
        request.response.write(jsonEncode({
          'sessionStatus': 'COMPLETED',
          'upload': {
            'id': 'managed',
            'videoS3Key': 'uploads/test.mp4',
            'storageProvider': 'private',
          }
        }));
      } else if (request.method == 'DELETE') {
        aborts++;
        request.response.write('{}');
      } else {
        request.response.write(jsonEncode({
          'part': {
            'partNumber': 1,
            'sizeBytes': 3,
            'uploadUrl': '$base/object',
            'uploadMethod': 'PUT',
            'uploadHeaders': {},
          }
        }));
      }
      await request.response.close();
    });
    try {
      final client = PostDeeApiClient(
          baseUrl: base,
          httpClient: http,
          requestTimeout: const Duration(milliseconds: 200));
      await client.uploadVideoFile(
          const UploadResult(
            id: 'managed',
            videoS3Key: 'uploads/test.mp4',
            storageProvider: 'private',
            uploadProtocol: 'multipart-v1',
            partSizeBytes: 3,
            partCount: 1,
          ),
          file);
      expect(completionAccepted, isTrue);
      expect(aborts, 0);
    } finally {
      http.close(force: true);
      await handler.cancel();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
