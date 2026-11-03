import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test(
      'calendar parses platform captions without changing stored shared summary',
      () {
    final post = CalendarPostResult.fromJson({
      'id': 'calendar',
      'caption': 'original shared',
      'status': 'QUEUED',
      'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
      'createdAt': '2030-11-03T00:00:00.000Z',
      'updatedAt': '2030-11-03T00:00:01.000Z',
      'scheduledAt': '2030-11-03T01:00:00.000Z',
      'platformSettings': {
        'TIKTOK': {'caption': 'edited TikTok'},
        'YOUTUBE_SHORTS': {'caption': 'edited YouTube', 'title': 'Keep title'}
      },
    });
    expect(post.caption, 'original shared');
    expect(post.captionPreview, 'edited TikTok');
    expect(post.toScheduledPost()!.platformSettings, post.platformSettings);
    expect(
        CalendarPostResult.fromScheduledPost(post.toScheduledPost()!)
            .captionPreview,
        'edited TikTok');
    expect(post.updatedAt, DateTime.utc(2030, 11, 3, 0, 0, 1));
  });
  test(
      'caption patch encodes id, serializes optional edits and parses settings/version',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final updated = DateTime.utc(2030, 11, 3);
    final task = () async {
      final request = await server.first;
      expect(request.method, 'PATCH');
      expect(request.uri.path, '/posts/post%2F1/caption');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'caption': 'new shared',
        'platformCaptions': {'TIKTOK': 'new', 'INSTAGRAM_REELS': null},
        'youtubeTitle': 'New title',
        'expectedUpdatedAt': updated.toIso8601String(),
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'post': {
          'id': 'post/1',
          'caption': 'new shared',
          'status': 'QUEUED',
          'createdAt': updated.toIso8601String(),
          'updatedAt': updated.toIso8601String(),
          'platformSettings': {
            'TIKTOK': {'caption': 'new', 'publishMode': 'INBOX_DRAFT'}
          },
        }
      }));
      await request.response.close();
    }();
    try {
      final result =
          await PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
              .updatePostCaption('post/1',
                  caption: 'new shared',
                  platformCaptions: {'TIKTOK': 'new', 'INSTAGRAM_REELS': null},
                  youtubeTitle: 'New title',
                  expectedUpdatedAt: updated);
      expect(result.platformSettings['TIKTOK'],
          {'caption': 'new', 'publishMode': 'INBOX_DRAFT'});
      expect(result.updatedAt, updated);
      await task;
    } finally {
      await server.close(force: true);
    }
  });

  test(
      'legacy route 404 becomes stable unavailable error while missing owned post stays not found',
      () async {
    for (final code in [null, 'POST_NOT_FOUND']) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final task = () async {
        final request = await server.first;
        await request.drain<void>();
        request.response.statusCode = 404;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(
            {'message': 'Not Found', if (code != null) 'code': code}));
        await request.response.close();
      }();
      try {
        await expectLater(
            PostDeeApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
                .updatePostCaption('one', caption: 'new'),
            throwsA(isA<ApiException>().having((e) => e.code, 'stable code',
                code ?? 'POST_CAPTION_EDIT_UNAVAILABLE')));
        await task;
      } finally {
        await server.close(force: true);
      }
    }
  });
}
