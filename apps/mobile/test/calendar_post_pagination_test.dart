import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

Map<String, Object?> _post(String id, String createdAt) => {
      'id': id,
      'caption': 'Clip $id',
      'platforms': ['TIKTOK'],
      'status': 'PUBLISHED',
      'createdAt': createdAt,
    };

/// Serves one JSON page per request and records each request's query.
Future<(HttpServer, List<Map<String, String>>)> _servePages(
    Map<String, Object?> Function(Map<String, String> query) pageFor) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final queries = <Map<String, String>>[];
  server.listen((request) async {
    queries.add(request.uri.queryParameters);
    await request.drain<void>();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(pageFor(request.uri.queryParameters)));
    await request.response.close();
  });
  return (server, queries);
}

PostDeeApiClient _client(HttpServer server) => PostDeeApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}',
      authTokenProvider: () async => 'calendar-page-token',
    );

void main() {
  test('calendar follows cursors one bounded page at a time until the last page',
      () async {
    final (server, queries) = await _servePages((query) => switch (query['cursor']) {
          null => {
              'status': 'ok',
              'posts': [_post('d', '2026-10-04T00:00:00.000Z'), _post('c', '2026-10-03T00:00:00.000Z')],
              'nextCursor': 'cursor-1',
            },
          'cursor-1' => {
              'status': 'ok',
              'posts': [_post('b', '2026-10-02T00:00:00.000Z')],
              'nextCursor': 'cursor/2+',
            },
          _ => {
              'status': 'ok',
              'posts': [_post('a', '2026-10-01T00:00:00.000Z')],
              'nextCursor': null,
            },
        });
    try {
      final posts = await _client(server).listCalendarPosts();
      expect(posts.map((post) => post.id), ['d', 'c', 'b', 'a']);
      expect(queries, [
        {'pageSize': '100'},
        {'pageSize': '100', 'cursor': 'cursor-1'},
        {'pageSize': '100', 'cursor': 'cursor/2+'},
      ]);
    } finally {
      await server.close(force: true);
    }
  });

  test('calendar stops after the page that reaches the requested history start',
      () async {
    final (server, queries) = await _servePages((_) => {
          'status': 'ok',
          'posts': [
            _post('recent', '2026-10-10T00:00:00.000Z'),
            _post('older', '2026-08-20T00:00:00.000Z'),
          ],
          'nextCursor': 'more-history',
        });
    try {
      final posts = await _client(server)
          .listCalendarPosts(createdSince: DateTime.utc(2026, 9, 1));
      expect(posts.map((post) => post.id), ['recent', 'older']);
      expect(queries, hasLength(1));
    } finally {
      await server.close(force: true);
    }
  });

  test('calendar caps the number of pages and never repeats a post', () async {
    var page = 0;
    final (server, queries) = await _servePages((_) {
      page += 1;
      return {
        'status': 'ok',
        'posts': [_post('repeat', '2026-10-05T00:00:00.000Z'), _post('p$page', '2026-10-0${5 - page}T00:00:00.000Z')],
        'nextCursor': 'next-$page',
      };
    });
    try {
      final posts = await _client(server).listCalendarPosts(maxPages: 2);
      expect(queries, hasLength(2));
      expect(posts.map((post) => post.id), ['repeat', 'p1', 'p2']);
    } finally {
      await server.close(force: true);
    }
  });

  test('a calendar page rejects a malformed cursor value', () async {
    final (server, _) = await _servePages((_) => {
          'status': 'ok',
          'posts': <Object>[],
          'nextCursor': 42,
        });
    try {
      await expectLater(_client(server).listCalendarPostsPage(),
          throwsA(isA<ApiException>()));
    } finally {
      await server.close(force: true);
    }
  });
}
