import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../core/network/postdee_api_client.dart';
import 'calendar_legacy_cover_frame.dart';

typedef _CoverKey = ({
  String postId,
  String coverKey,
  String videoKey,
  int? frameTimeMs,
});

typedef CalendarLegacyCoverFrameLoader = Future<Uint8List?> Function(
  Uri videoUrl, {
  required int frameTimeMs,
  required bool Function() isCurrent,
});

class CalendarCoverPreview {
  const CalendarCoverPreview.image(this.imageUrl) : frameBytes = null;
  const CalendarCoverPreview.frame(this.frameBytes) : imageUrl = null;

  final Uri? imageUrl;
  final Uint8List? frameBytes;
}

/// Keeps selected covers and legacy saved-frame images for this view/session.
/// Legacy sampling shares the read limit and never creates a video player.
class CalendarCoverPreviewCache {
  CalendarCoverPreviewCache({
    required Future<PostSummaryResult?> Function(String) loadPost,
    required bool Function() isCurrent,
    CalendarLegacyCoverFrameLoader? extractFrame,
    int maxConcurrent = 3,
  })  : _loadPost = loadPost,
        _isCurrent = isCurrent,
        _extractFrame = extractFrame ?? FfmpegCalendarLegacyCoverFrame().call,
        _maxConcurrent = maxConcurrent {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
          maxConcurrent, 'maxConcurrent', 'Must be positive');
    }
  }

  final Future<PostSummaryResult?> Function(String) _loadPost;
  final bool Function() _isCurrent;
  final CalendarLegacyCoverFrameLoader _extractFrame;
  final int _maxConcurrent;
  final _entries = <_CoverKey, _CoverEntry>{};
  final _pending = Queue<_CoverEntry>();
  int _running = 0;
  bool _disposed = false;
  bool _drainScheduled = false;

  bool get _canLoad => !_disposed && _isCurrent();

  Future<CalendarCoverPreview?> load(PostSummaryResult post) {
    if (!_canLoad) {
      _discardAll();
      return Future.value();
    }
    if (post.id.trim().isEmpty) {
      return Future.value();
    }

    final key = (
      postId: post.id,
      coverKey: post.coverImageS3Key?.trim() ?? '',
      videoKey: post.videoS3Key,
      frameTimeMs: post.coverFrameTimeMs,
    );
    for (final entry in _entries.values.toList()) {
      if (entry.key.postId == key.postId && entry.key != key) {
        _discard(entry);
      }
    }

    final providedUrl = _safeCover(post.coverImageUrl);
    final existing = _entries[key];
    if (providedUrl != null) {
      if (existing != null && existing.providedUrl == providedUrl) {
        return existing.result.future;
      }
      if (existing != null) {
        _discard(existing);
      }
      final entry = _CoverEntry(key, providedUrl: providedUrl);
      _entries[key] = entry;
      entry.complete(CalendarCoverPreview.image(providedUrl));
      return entry.result.future;
    }

    // Older posts may have no cover metadata; use their owned clip's first frame.
    if (key.coverKey.isEmpty && key.videoKey.trim().isEmpty) {
      if (existing != null) {
        _discard(existing);
      }
      return Future.value();
    }
    if (existing != null) {
      return existing.result.future;
    }

    final entry = _CoverEntry(key);
    _entries[key] = entry;
    _pending.add(entry);
    _drain();
    return entry.result.future;
  }

  /// Evicted rows may load again when revisited. Queued work is not dispatched.
  void retain(Iterable<String> postIds) {
    if (!_canLoad) {
      _discardAll();
      return;
    }
    final retained = postIds.toSet();
    for (final entry in _entries.values.toList()) {
      if (!retained.contains(entry.key.postId)) {
        _discard(entry);
      }
    }
    _pending.removeWhere((entry) => entry.cancelled);
    _drain();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _discardAll();
  }

  void _discard(_CoverEntry entry) {
    entry.cancelled = true;
    if (identical(_entries[entry.key], entry)) {
      _entries.remove(entry.key);
    }
    entry.complete(null);
  }

  void _discardAll() {
    for (final entry in _entries.values.toList()) {
      _discard(entry);
    }
    _pending.clear();
  }

  bool _ownsEntry(_CoverEntry entry) =>
      !entry.cancelled && identical(_entries[entry.key], entry);

  void _drain() {
    if (!_canLoad) {
      _discardAll();
      return;
    }
    while (_running < _maxConcurrent && _pending.isNotEmpty) {
      if (!_canLoad) {
        _discardAll();
        return;
      }
      final entry = _pending.removeFirst();
      if (!_ownsEntry(entry)) {
        continue;
      }
      _running++;
      unawaited(_read(entry));
    }
  }

  Future<void> _read(_CoverEntry entry) async {
    try {
      final post = await _loadPost(entry.key.postId);
      if (!_canLoad || !_ownsEntry(entry)) {
        _discard(entry);
        return;
      }
      if (post == null || post.id != entry.key.postId) {
        entry.complete(null);
        return;
      }
      final imageUrl = _safeCover(post.coverImageUrl);
      if (imageUrl != null) {
        entry.complete(CalendarCoverPreview.image(imageUrl));
        return;
      }
      final videoUrl = _safeCover(post.videoUrl);
      final frame = entry.key.frameTimeMs ?? 0;
      if (entry.key.coverKey.isNotEmpty ||
          (post.coverImageS3Key?.trim().isNotEmpty ?? false) ||
          videoUrl == null) {
        entry.complete(null);
        return;
      }
      final bytes = await _extractFrame(
        videoUrl,
        frameTimeMs: post.coverFrameTimeMs ?? frame,
        isCurrent: () => _canLoad && _ownsEntry(entry),
      );
      if (!_canLoad || !_ownsEntry(entry)) {
        _discard(entry);
        return;
      }
      entry.complete(bytes == null || bytes.isEmpty
          ? null
          : CalendarCoverPreview.frame(bytes));
    } catch (_) {
      // Remember failures until explicit refresh or eviction, avoiding rebuild
      // retry loops. A cancelled owner/view never gets even the failed entry.
      if (_canLoad && _ownsEntry(entry)) {
        entry.complete(null);
      } else {
        _discard(entry);
      }
    } finally {
      _running--;
      if (!_canLoad) {
        _discardAll();
      } else if (!_drainScheduled) {
        _drainScheduled = true;
        scheduleMicrotask(() {
          _drainScheduled = false;
          _drain();
        });
      }
    }
  }

  static Uri? _safeCover(Uri? url) => url != null &&
          (url.scheme == 'https' || url.scheme == 'http') &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty
      ? url
      : null;
}

class _CoverEntry {
  _CoverEntry(this.key, {this.providedUrl});

  final _CoverKey key;
  final Uri? providedUrl;
  final result = Completer<CalendarCoverPreview?>();
  bool cancelled = false;

  void complete(CalendarCoverPreview? value) {
    if (!result.isCompleted) {
      result.complete(value);
    }
  }
}
