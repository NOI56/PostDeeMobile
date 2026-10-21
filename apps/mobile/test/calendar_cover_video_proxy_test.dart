import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/calendar/calendar_cover_video_proxy.dart';

Future<HttpServer> _upstream(Future<void> Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    try {
      await handle(request);
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  });
  return server;
}

Uri _source(HttpServer server) => Uri.http(
    '127.0.0.1:${server.port}', '/clip.mp4', {'signature': 'fixture-only'});

Future<HttpClientResponse> _request(Uri url,
    {String method = 'GET', String? range}) async {
  final client = HttpClient();
  addTearDown(() => client.close(force: true));
  final request = await client.openUrl(method, url);
  if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
  return request.close();
}

void main() {
  test('serves owned video ranges on a private loopback URL', () async {
    var reads = 0;
    final upstream = await _upstream((request) async {
      reads++;
      expect(request.uri.queryParameters['signature'], 'fixture-only');
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=3-5');
      expect(
          request.headers.value(HttpHeaders.acceptEncodingHeader), 'identity');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'video/mp4')
        ..set(HttpHeaders.contentRangeHeader, 'bytes 3-5/9')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.contentLength = 3;
      request.response.add([3, 4, 5]);
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream));
    addTearDown(proxy.close);
    expect(proxy.url.scheme, 'http');
    expect(proxy.url.host, '127.0.0.1');
    expect(proxy.url.path.length, greaterThan(24));
    expect(proxy.url.hasQuery, isFalse);
    final response = await _request(proxy.url, range: 'bytes=3-5');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value(HttpHeaders.contentTypeHeader), 'video/mp4');
    expect(
        response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 3-5/9');
    expect(await response.expand((chunk) => chunk).toList(), [3, 4, 5]);
    expect(reads, 1);
  });

  test('synthesizes HEAD through a signed GET with a one-byte range', () async {
    var reads = 0;
    final upstream = await _upstream((request) async {
      reads++;
      expect(request.method, 'GET');
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-0');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes 0-0/900');
      request.response.contentLength = 1;
      request.response.add([7]);
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream));
    addTearDown(proxy.close);
    final response = await _request(proxy.url, method: 'HEAD');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentLength, 900);
    expect(await response.expand((chunk) => chunk).toList(), isEmpty);
    expect(reads, 1);
  });

  test('rejects other paths, queries, methods and malformed ranges locally',
      () async {
    var reads = 0;
    final upstream = await _upstream((request) async {
      reads++;
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream));
    addTearDown(proxy.close);
    for (final url in [
      proxy.url.replace(path: '/unrelated'),
      proxy.url.replace(query: 'url=https://elsewhere.invalid/video'),
    ]) {
      final response = await _request(url);
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    }
    final post = await _request(proxy.url, method: 'POST');
    expect(post.statusCode, HttpStatus.methodNotAllowed);
    await post.drain<void>();
    for (final range in ['bytes=0-1,3-4', 'bytes=5-2', 'bytes=-0', 'invalid']) {
      final response = await _request(proxy.url, range: range);
      expect(response.statusCode, HttpStatus.badRequest);
      await response.drain<void>();
    }
    expect(reads, 0);
  });

  test('does not follow upstream redirects or expose their location', () async {
    final upstream = await _upstream((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader,
          'https://private.invalid/video?signature=must-not-return');
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream));
    addTearDown(proxy.close);
    final response = await _request(proxy.url);
    expect(response.statusCode, HttpStatus.badGateway);
    expect(response.headers.value(HttpHeaders.locationHeader), isNull);
    expect(await response.expand((chunk) => chunk).toList(), isEmpty);
  });

  test('caps request count without opening more upstream requests', () async {
    var reads = 0;
    final upstream = await _upstream((request) async {
      reads++;
      request.response.add([1]);
      await request.response.close();
    });
    final proxy =
        await CalendarCoverVideoProxy.open(_source(upstream), maxRequests: 1);
    addTearDown(proxy.close);
    await (await _request(proxy.url)).drain<void>();
    final response = await _request(proxy.url);
    expect(response.statusCode, HttpStatus.badGateway);
    await response.drain<void>();
    expect(reads, 1);
  });

  test('caps forwarded bytes even if upstream ignores range requests',
      () async {
    final upstream = await _upstream((request) async {
      request.response.contentLength = 100;
      request.response.add(List.filled(100, 1));
      await request.response.close();
    });
    final proxy =
        await CalendarCoverVideoProxy.open(_source(upstream), maxBytes: 8);
    addTearDown(proxy.close);
    var received = 0;
    try {
      final response = await _request(proxy.url);
      await for (final chunk in response) {
        received += chunk.length;
      }
    } catch (_) {
      // Budget exhaustion intentionally closes the bounded local stream.
    }
    expect(received, lessThanOrEqualTo(8));
    expect(proxy.bytesForwarded, 8);
  });

  test('forwards at most three concurrent upstream reads', () async {
    var reads = 0;
    final reached = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final upstream = await _upstream((request) async {
      reads++;
      if (reads == 3) reached.complete();
      await release.future;
      request.response.add([1]);
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream));
    addTearDown(proxy.close);
    final first = [for (var i = 0; i < 3; i++) _request(proxy.url)];
    await reached.future.timeout(const Duration(seconds: 5));
    final fourth = await _request(proxy.url);
    expect(fourth.statusCode, HttpStatus.badGateway);
    await fourth.drain<void>();
    expect(reads, 3);
    release.complete();
    for (final response in await Future.wait(first)) {
      await response.drain<void>();
    }
  });

  test('inactive owners do not dispatch requests and close is idempotent',
      () async {
    var reads = 0;
    var current = true;
    final upstream = await _upstream((request) async {
      reads++;
      await request.response.close();
    });
    final proxy = await CalendarCoverVideoProxy.open(_source(upstream),
        isCurrent: () => current);
    current = false;
    final response = await _request(proxy.url);
    expect(response.statusCode, HttpStatus.badGateway);
    await response.drain<void>();
    expect(reads, 0);
    await proxy.close();
    await proxy.close();
    await expectLater(_request(proxy.url), throwsA(isA<SocketException>()));
  });
}
