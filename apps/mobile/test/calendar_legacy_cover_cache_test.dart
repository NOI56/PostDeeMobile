import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/calendar/calendar_cover_preview_cache.dart';

PostSummaryResult _post(String id,
        {int? frame, String? coverKey, String? videoKey, Uri? videoUrl}) =>
    PostSummaryResult(
      id: id,
      caption: 'Selected legacy frame',
      videoS3Key: videoKey ?? 'uploads/owner/$id/video.mp4',
      coverImageS3Key: coverKey,
      coverFrameTimeMs: frame,
      videoUrl: videoUrl,
      platforms: const ['TIKTOK'],
      status: 'PUBLISHED',
      createdAt: DateTime(2026, 10, 21),
    );

Uri get _video => Uri.https('private-media.test', '/owned-video.mp4');

void main() {
  test('selected legacy frame is read once through the exact owned post',
      () async {
    var reads = 0;
    var extracts = 0;
    final bytes = Uint8List.fromList([1, 2, 3]);
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async {
        reads++;
        expect(id, 'legacy');
        return _post(id, frame: 1350, videoUrl: _video);
      },
      extractFrame: (url, {required frameTimeMs, required isCurrent}) async {
        extracts++;
        expect(url, _video);
        expect(frameTimeMs, 1350);
        expect(isCurrent(), isTrue);
        return bytes;
      },
      isCurrent: () => true,
    );
    addTearDown(cache.dispose);
    final post = _post('legacy', frame: 1350);
    final first = cache.load(post);
    expect(cache.load(post), same(first));
    final result = await first;
    expect(result?.imageUrl, isNull);
    expect(result?.frameBytes, same(bytes));
    expect((await cache.load(post))?.frameBytes, same(bytes));
    expect(reads, 1);
    expect(extracts, 1);
  });

  test(
      'legacy clips without a saved frame use the first frame and preserve explicit zero',
      () async {
    var reads = 0;
    var extracts = 0;
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async {
        reads++;
        return _post(id, frame: 0, videoUrl: _video);
      },
      extractFrame: (url, {required frameTimeMs, required isCurrent}) async {
        extracts++;
        expect(frameTimeMs, 0);
        return Uint8List.fromList([1]);
      },
      isCurrent: () => true,
    );
    addTearDown(cache.dispose);
    expect(
        (await cache.load(_post('not-selected', videoUrl: _video)))?.frameBytes,
        isNotNull);
    expect((await cache.load(_post('zero', frame: 0)))?.frameBytes, isNotNull);
    expect(reads, 2);
    expect(extracts, 2);
  });

  test('an uploaded cover is never replaced with a sampled frame on failure',
      () async {
    var extracts = 0;
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async => _post(id, frame: 0, videoUrl: _video),
      extractFrame: (url, {required frameTimeMs, required isCurrent}) async {
        extracts++;
        return Uint8List.fromList([1]);
      },
      isCurrent: () => true,
    );
    addTearDown(cache.dispose);
    expect(await cache.load(_post('saved', frame: 0, coverKey: 'cover.jpg')),
        isNull);
    expect(extracts, 0);
  });

  test('owner changes discard late frame bytes and cancel their current guard',
      () async {
    var current = true;
    final gate = Completer<Uint8List?>();
    late bool Function() frameIsCurrent;
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async => _post(id, frame: 0, videoUrl: _video),
      extractFrame: (url, {required frameTimeMs, required isCurrent}) {
        frameIsCurrent = isCurrent;
        return gate.future;
      },
      isCurrent: () => current,
    );
    addTearDown(cache.dispose);
    final pending = cache.load(_post('legacy', frame: 0));
    await Future<void>.delayed(Duration.zero);
    current = false;
    expect(frameIsCurrent(), isFalse);
    gate.complete(Uint8List.fromList([1]));
    expect(await pending, isNull);
  });

  test('changing the saved frame or video cannot reuse an old sample',
      () async {
    var extracts = 0;
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async => _post(id, frame: 0, videoUrl: _video),
      extractFrame: (url, {required frameTimeMs, required isCurrent}) async =>
          Uint8List.fromList([++extracts]),
      isCurrent: () => true,
    );
    addTearDown(cache.dispose);
    expect((await cache.load(_post('same', frame: 0)))?.frameBytes, [1]);
    expect((await cache.load(_post('same', frame: 1000)))?.frameBytes, [2]);
    expect(
        (await cache.load(_post('same', frame: 1000, videoKey: 'another.mp4')))
            ?.frameBytes,
        [3]);
  });

  test('frame extraction shares the three-work limit with cover reads',
      () async {
    final gates = [for (var i = 0; i < 5; i++) Completer<Uint8List?>()];
    var started = 0;
    final cache = CalendarCoverPreviewCache(
      loadPost: (id) async => _post(id, frame: 0, videoUrl: _video),
      extractFrame: (url, {required frameTimeMs, required isCurrent}) =>
          gates[started++].future,
      isCurrent: () => true,
    );
    addTearDown(cache.dispose);
    final pending = [
      for (var i = 0; i < 5; i++) cache.load(_post('p$i', frame: 0))
    ];
    await Future<void>.delayed(Duration.zero);
    expect(started, 3);
    gates.first.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(started, 4);
    for (final gate in gates.skip(1)) {
      gate.complete(Uint8List.fromList([1]));
    }
    expect(await Future.wait(pending), everyElement(isNotNull));
  });
}
