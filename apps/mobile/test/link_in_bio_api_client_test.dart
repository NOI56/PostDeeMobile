import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _profile({bool published = true, String? path}) => {
      'storeName': 'ร้านมินา',
      'slug': 'mina-shop',
      'links': [
        {'id': 'shop', 'title': 'ร้านค้า', 'url': 'https://example.com/shop'}
      ],
      'isPublished': published,
      'publishedAt': published ? '2026-10-05T00:00:00.000Z' : null,
      'updatedAt': '2026-10-05T00:00:00.000Z',
      'publicPath': published ? (path ?? '/p/mina-shop') : null,
    };

Future<void> _withServer(
  Future<void> Function(PostDeeApiClient client) run,
  Future<Map<String, Object?>> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    final body = await handle(request);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  });
  try {
    await run(PostDeeApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}/api/',
    ));
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

void main() {
  test('rejects a double-hyphen slug even when its public path matches', () {
    final json = _profile()
      ..['slug'] = 'my--shop'
      ..['publicPath'] = '/p/my--shop';
    expect(
      () => LinkInBioProfileResult.fromJson(json, apiBaseUri: Uri.parse('https://api.example.com')),
      throwsA(isA<ApiException>()),
    );
  });

  test('loads confirmed profile and resolves public path on actual API origin',
      () async {
    await _withServer((client) async {
      final profile = await client.loadLinkInBioProfile();
      expect(profile!.storeName, 'ร้านมินา');
      expect(profile.publicUrl!.path, '/p/mina-shop');
      expect(profile.publicUrl!.host, '127.0.0.1');
      expect(profile.publicUrl!.scheme, 'http');
      expect(profile.publicUrl!.hasQuery, isFalse);
      expect(profile.links.single.title, 'ร้านค้า');
    }, (request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/link-in-bio');
      await request.drain<void>();
      return {'status': 'ok', 'profile': _profile()};
    });
  });

  test(
      'null profile is a confirmed empty account, malformed success is rejected',
      () async {
    await _withServer((client) async {
      expect(await client.loadLinkInBioProfile(), isNull);
    }, (request) async => {'status': 'ok', 'profile': null});
    await _withServer((client) async {
      await expectLater(
          client.loadLinkInBioProfile(), throwsA(isA<ApiException>()));
    }, (request) async => {'status': 'ok'});
  });

  for (final path in [
    '//evil.example/p/mina-shop',
    'https://evil.example/p/mina-shop',
    '/p/another-shop',
    '/p/mina-shop?redirect=evil',
    '/p/mina-shop#fragment',
    '/other/mina-shop',
    '/p/my--shop',
  ]) {
    test('rejects untrusted public path $path', () async {
      await _withServer((client) async {
        await expectLater(
            client.loadLinkInBioProfile(), throwsA(isA<ApiException>()));
      }, (request) async => {'status': 'ok', 'profile': _profile(path: path)});
    });
  }

  test('publish serializes only entered real links and unpublish uses DELETE',
      () async {
    await _withServer((client) async {
      final published = await client.publishLinkInBioProfile(
        storeName: 'ร้านมินา',
        slug: 'mina-shop',
        links: const [
          LinkInBioLinkResult(
              id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop'),
        ],
      );
      expect(published.isPublished, isTrue);
      final unpublished = await client.unpublishLinkInBioProfile();
      expect(unpublished.isPublished, isFalse);
      expect(unpublished.publicUrl, isNull);
    }, (request) async {
      expect(request.uri.path, '/link-in-bio/publish');
      if (request.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body, {
          'storeName': 'ร้านมินา',
          'slug': 'mina-shop',
          'links': [
            {
              'id': 'shop',
              'title': 'ร้านค้า',
              'url': 'https://example.com/shop'
            }
          ],
        });
        return {'status': 'ok', 'profile': _profile()};
      }
      expect(request.method, 'DELETE');
      await request.drain<void>();
      return {'status': 'ok', 'profile': _profile(published: false)};
    });
  });

  test('publish rejects a response that does not confirm publication',
      () async {
    await _withServer((client) async {
      await expectLater(
        client.publishLinkInBioProfile(
            storeName: 'ร้านมินา',
            slug: 'mina-shop',
            links: const [
              LinkInBioLinkResult(
                  id: 'shop', title: 'ร้านค้า', url: 'https://example.com/shop')
            ]),
        throwsA(isA<ApiException>()),
      );
    },
        (request) async =>
            {'status': 'ok', 'profile': _profile(published: false)});
  });
}
