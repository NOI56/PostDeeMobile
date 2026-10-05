import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

const imageKey =
    'uploads/seller/11111111-1111-4111-8111-111111111111/profile-logo.png';
final png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII='));

Future<void> withServer(Future<void> Function(PostDeeApiClient) run,
    Future<void> Function(HttpRequest) handle,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen(handle);
  try {
    await run(PostDeeApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        authTokenProvider: () async => 'firebase-image-token',
        requestTimeout: timeout));
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

void main() {
  test(
      'image upload uses authenticated JSON, returns a registered owned key, and loads PNG bytes',
      () async {
    await withServer((client) async {
      expect(await client.uploadLinkInBioImage(slot: 'logo', bytes: png),
          imageKey);
      expect(await client.loadLinkInBioImage(imageKey), png);
    }, (request) async {
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer firebase-image-token');
      if (request.method == 'POST') {
        expect(request.uri.path, '/link-in-bio/images');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body, {'slot': 'logo', 'imageBase64': base64Encode(png)});
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'image': {'key': imageKey}
        }));
      } else {
        expect(request.method, 'GET');
        expect(request.uri.path, '/link-in-bio/image');
        expect(request.uri.queryParameters, {'key': imageKey});
        expect(request.headers.value(HttpHeaders.acceptHeader), 'image/png');
        await request.drain<void>();
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      }
      await request.response.close();
    });
  });

  test('rejects unsafe upload keys even when the server says success',
      () async {
    for (final key in [
      'https://evil.example/logo.png',
      'uploads/seller/a/../profile-logo.png',
      'uploads/seller/11111111-1111-4111-8111-111111111111/video.mp4',
      'unknown'
    ]) {
      await withServer((client) async {
        await expectLater(client.uploadLinkInBioImage(slot: 'logo', bytes: png),
            throwsA(isA<ApiException>()));
      }, (request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'image': {'key': key}
        }));
        await request.response.close();
      });
    }
  });

  test(
      'rejects invalid local image input and unsafe preview paths before contacting a server',
      () async {
    final client = PostDeeApiClient(baseUrl: 'http://127.0.0.1:1');
    for (final invalid in [
      Uint8List(0),
      Uint8List(20),
      Uint8List(512 * 1024 + 1)
    ]) {
      await expectLater(
          client.uploadLinkInBioImage(slot: 'logo', bytes: invalid),
          throwsA(isA<ApiException>()));
    }
    await expectLater(client.uploadLinkInBioImage(slot: 'avatar', bytes: png),
        throwsA(isA<ApiException>()));
    await expectLater(client.loadLinkInBioImage('https://evil.example/image'),
        throwsA(isA<ApiException>()));
  });

  test(
      'preview propagates a JSON permission error and rejects a non-PNG success',
      () async {
    await withServer((client) async {
      await expectLater(
          client.loadLinkInBioImage(imageKey),
          throwsA(isA<ApiException>()
              .having((error) => error.statusCode, 'status', 403)
              .having((error) => error.code, 'code', 'IMAGE_FORBIDDEN')));
    }, (request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 403
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'error',
          'code': 'IMAGE_FORBIDDEN',
          'message': 'No access'
        }));
      await request.response.close();
    });
    await withServer((client) async {
      await expectLater(
          client.loadLinkInBioImage(imageKey), throwsA(isA<ApiException>()));
    }, (request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>not an image</html>');
      await request.response.close();
    });
  });

  test('preview refuses responses exceeding the PNG byte limit', () async {
    await withServer((client) async {
      await expectLater(
          client.loadLinkInBioImage(imageKey), throwsA(isA<ApiException>()));
    }, (request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(Uint8List(512 * 1024 + 1));
      await request.response.close();
    });
  });

  test(
      'preview body has a full deadline and cancellation does not close the shared client',
      () async {
    var count = 0;
    await withServer((client) async {
      await expectLater(
          client.loadLinkInBioImage(imageKey),
          throwsA(isA<ApiException>()
              .having((error) => error.code, 'code', apiRequestTimeoutCode)));
      expect(await client.loadLinkInBioImage(imageKey), png);
    }, (request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType('image', 'png');
      if (count++ == 0) {
        request.response.add(png.sublist(0, 8));
        await request.response.flush();
      } else {
        request.response.add(png);
        await request.response.close();
      }
    }, timeout: const Duration(milliseconds: 200));
  });

  test('image upload deadline includes a stalled token refresh', () async {
    final client = PostDeeApiClient(
        baseUrl: 'http://127.0.0.1:1',
        authTokenProvider: () => Completer<String?>().future,
        requestTimeout: const Duration(milliseconds: 25));
    await expectLater(
        client.uploadLinkInBioImage(slot: 'logo', bytes: png),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', apiRequestTimeoutCode)));
  });
}
