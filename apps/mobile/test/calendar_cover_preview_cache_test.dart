import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/calendar/calendar_cover_preview_cache.dart';

PostSummaryResult _post(String id,
        {String? coverKey, Uri? coverUrl, Uri? videoUrl, String? videoKey}) =>
    PostSummaryResult(
      id: id,
      caption: 'ภาพปกที่เลือก',
      videoS3Key: videoKey ?? 'uploads/owner/$id/video.mp4',
      coverImageS3Key: coverKey,
      coverImageUrl: coverUrl,
      videoUrl: videoUrl,
      platforms: const ['TIKTOK'],
      status: 'PUBLISHED',
      createdAt: DateTime.utc(2026, 10, 21),
    );

Uri _cover(String id) => Uri.https('private-media.test', '/$id/cover.jpg');
Future<void> _settleRequests() => Future<void>.delayed(Duration.zero);
Matcher _hasCover(Uri url) => isA<CalendarCoverPreview>()
    .having((preview) => preview.imageUrl, 'imageUrl', url);

void main() {
  test('provided safe cover is used without reading or downloading a video',
      () async {
    var reads = 0;
    final cache = CalendarCoverPreviewCache(
        loadPost: (_) async {
          reads++;
          return null;
        },
        isCurrent: () => true);
    addTearDown(cache.dispose);
    for (final url in [
      _cover('one'),
      Uri.parse('http://localhost/cover.jpg')
    ]) {
      expect(
          await cache.load(_post('one',
              coverKey: 'uploads/owner/one/cover.jpg',
              coverUrl: url,
              videoUrl: Uri.https('private-media.test', '/one/video.mp4'))),
          _hasCover(url));
    }
    expect(reads, 0);
  });

  test('legacy rows without a cover or clip never request a video fallback',
      () async {
    var reads = 0;
    final cache = CalendarCoverPreviewCache(
        loadPost: (_) async {
          reads++;
          return _post('legacy', coverUrl: _cover('invented'));
        },
        isCurrent: () => true);
    addTearDown(cache.dispose);
    for (final key in [null, '', '   ']) {
      expect(
          await cache.load(_post('legacy',
              coverKey: key,
              videoKey: '',
              videoUrl: Uri.https('private-media.test', '/video.mp4'))),
          isNull);
    }
    expect(await cache.load(_post(' ', coverKey: 'cover.jpg')), isNull);
    expect(reads, 0);
  });

  test('rebuilds share one request and retain the chosen cover result',
      () async {
    var reads = 0;
    final response = Completer<PostSummaryResult?>();
    final cache = CalendarCoverPreviewCache(
        loadPost: (_) {
          reads++;
          return response.future;
        },
        isCurrent: () => true);
    addTearDown(cache.dispose);
    final post = _post('one', coverKey: 'uploads/owner/one/cover.jpg');
    final requests = [for (var i = 0; i < 8; i++) cache.load(post)];
    await _settleRequests();
    expect(reads, 1);
    response.complete(_post('one', coverUrl: _cover('one')));
    expect(await Future.wait(requests), everyElement(_hasCover(_cover('one'))));
    expect(await cache.load(post), _hasCover(_cover('one')));
    expect(reads, 1);
  });

  test('cover reads obey the configured concurrency limit', () async {
    final ids = [for (var i = 0; i < 8; i++) 'p-$i'];
    final gates = {for (final id in ids) id: Completer<PostSummaryResult?>()};
    final started = <String>[];
    var running = 0;
    var maximumRunning = 0;
    final cache = CalendarCoverPreviewCache(
        maxConcurrent: 3,
        loadPost: (id) async {
          started.add(id);
          running++;
          if (running > maximumRunning) maximumRunning = running;
          try {
            return await gates[id]!.future;
          } finally {
            running--;
          }
        },
        isCurrent: () => true);
    addTearDown(cache.dispose);
    final requests = [
      for (final id in ids) cache.load(_post(id, coverKey: '$id/cover.jpg'))
    ];
    await _settleRequests();
    expect(started, ids.take(3));
    gates[ids.first]!.complete(_post(ids.first, coverUrl: _cover(ids.first)));
    await _settleRequests();
    expect(started, ids.take(4));
    for (final id in ids.skip(1)) {
      gates[id]!.complete(_post(id, coverUrl: _cover(id)));
    }
    expect(await Future.wait(requests), ids.map((id) => _hasCover(_cover(id))));
    expect(maximumRunning, 3);
  });

  test('changing day cancels queued covers and revisit can request them',
      () async {
    final first = Completer<PostSummaryResult?>();
    final started = <String>[];
    final cache = CalendarCoverPreviewCache(
        maxConcurrent: 1,
        loadPost: (id) {
          started.add(id);
          return id == 'one'
              ? first.future
              : Future.value(_post(id, coverUrl: _cover(id)));
        },
        isCurrent: () => true);
    addTearDown(cache.dispose);
    final one = cache.load(_post('one', coverKey: 'one/cover.jpg'));
    final two = cache.load(_post('two', coverKey: 'two/cover.jpg'));
    cache.retain(['one']);
    expect(await two, isNull);
    first.complete(_post('one', coverUrl: _cover('one')));
    expect(await one, _hasCover(_cover('one')));
    await _settleRequests();
    expect(started, ['one']);
    cache.retain(['two']);
    expect(await cache.load(_post('two', coverKey: 'two/cover.jpg')),
        _hasCover(_cover('two')));
    expect(started, ['one', 'two']);
  });

  test('inactive owner drops late covers and does not dispatch queued reads',
      () async {
    var current = true;
    final first = Completer<PostSummaryResult?>();
    final started = <String>[];
    final cache = CalendarCoverPreviewCache(
        maxConcurrent: 1,
        loadPost: (id) {
          started.add(id);
          return id == 'one'
              ? first.future
              : Future.value(_post(id, coverUrl: _cover(id)));
        },
        isCurrent: () => current);
    addTearDown(cache.dispose);
    final one = cache.load(_post('one', coverKey: 'one/cover.jpg'));
    final two = cache.load(_post('two', coverKey: 'two/cover.jpg'));
    current = false;
    first.complete(_post('one', coverUrl: _cover('private-old-owner')));
    expect(await one, isNull);
    expect(await two, isNull);
    expect(started, ['one']);
    current = true;
    expect(await cache.load(_post('two', coverKey: 'two/cover.jpg')),
        _hasCover(_cover('two')));
    expect(started, ['one', 'two']);
  });

  test('inactive or disposed cache never starts another read', () async {
    var current = false;
    var reads = 0;
    final cache = CalendarCoverPreviewCache(
        loadPost: (id) async {
          reads++;
          return _post(id, coverUrl: _cover(id));
        },
        isCurrent: () => current);
    final post = _post('one', coverKey: 'one/cover.jpg');
    expect(await cache.load(post), isNull);
    current = true;
    expect(await cache.load(post), _hasCover(_cover('one')));
    cache.dispose();
    expect(await cache.load(post), isNull);
    expect(reads, 1);
  });

  test('dispose completes pending views and drains no further network work',
      () async {
    final gate = Completer<PostSummaryResult?>();
    final started = <String>[];
    final cache = CalendarCoverPreviewCache(
        maxConcurrent: 1,
        loadPost: (id) {
          started.add(id);
          return gate.future;
        },
        isCurrent: () => true);
    final one = cache.load(_post('one', coverKey: 'one/cover.jpg'));
    final two = cache.load(_post('two', coverKey: 'two/cover.jpg'));
    cache.dispose();
    expect(await Future.wait([one, two]), everyElement(isNull));
    gate.complete(_post('one', coverUrl: _cover('one')));
    await _settleRequests();
    expect(started, ['one']);
  });

  test('a changed cover is reloaded and a late old cover cannot replace it',
      () async {
    final oldCover = Completer<PostSummaryResult?>();
    final newCover = Completer<PostSummaryResult?>();
    var reads = 0;
    final cache = CalendarCoverPreviewCache(
        loadPost: (_) => ++reads == 1 ? oldCover.future : newCover.future,
        isCurrent: () => true);
    addTearDown(cache.dispose);
    final oldRequest = cache.load(_post('one', coverKey: 'one/old-cover.jpg'));
    final replacement = _post('one', coverKey: 'one/new-cover.jpg');
    final newRequest = cache.load(replacement);
    newCover.complete(_post('one', coverUrl: _cover('new')));
    expect(await newRequest, _hasCover(_cover('new')));
    oldCover.complete(_post('one', coverUrl: _cover('old')));
    expect(await oldRequest, isNull);
    expect(await cache.load(replacement), _hasCover(_cover('new')));
    expect(reads, 2);
  });

  for (final url in [
    'javascript:alert(1)',
    'file:///cover.jpg',
    '/relative-cover.jpg',
    'https://user:password@private-media.test/cover.jpg',
  ]) {
    test('unsafe cover $url is never used or replaced with a video', () async {
      var reads = 0;
      final cache = CalendarCoverPreviewCache(
          loadPost: (id) async {
            reads++;
            return _post(id,
                coverUrl: Uri.parse(url),
                videoUrl: Uri.https('private-media.test', '/video.mp4'));
          },
          isCurrent: () => true);
      addTearDown(cache.dispose);
      expect(
          await cache
              .load(_post('one', coverUrl: Uri.parse(url), videoKey: '')),
          isNull);
      expect(reads, 0);
      final keyed = _post('one', coverKey: 'one/cover.jpg');
      expect(await cache.load(keyed), isNull);
      expect(await cache.load(keyed), isNull);
      expect(reads, 1);
    });
  }

  for (final response in ['missing', 'no-cover', 'wrong-id', 'throws']) {
    test('$response returns a stable placeholder without retry loops',
        () async {
      var reads = 0;
      final cache = CalendarCoverPreviewCache(
          loadPost: (id) async {
            reads++;
            return switch (response) {
              'missing' => null,
              'no-cover' => _post(id,
                  videoUrl: Uri.https('private-media.test', '/video.mp4')),
              'wrong-id' => _post('other-post', coverUrl: _cover('other')),
              _ => throw StateError('Offline'),
            };
          },
          isCurrent: () => true);
      addTearDown(cache.dispose);
      final post = _post('one', coverKey: 'one/cover.jpg');
      expect(await cache.load(post), isNull);
      expect(await cache.load(post), isNull);
      expect(reads, 1);
    });
  }
}
