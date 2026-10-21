import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Bounded, private bridge for FFmpeg builds without an HTTPS protocol.
/// Signed source URLs stay in Dart; only a random loopback path reaches FFmpeg.
class CalendarCoverVideoProxy {
  CalendarCoverVideoProxy._(HttpServer server, this._client, this._upstream,
      String path, this._maxBytes, this._maxRequests, this._isCurrent)
      : _server = server,
        _path = path,
        url = Uri.http('127.0.0.1:${server.port}', path);

  final HttpServer _server;
  final HttpClient _client;
  final Uri _upstream;
  final String _path;
  final int _maxBytes;
  final int _maxRequests;
  final bool Function()? _isCurrent;
  int _active = 0;
  int _requests = 0;
  int _bytesForwarded = 0;
  bool _closed = false;
  Future<void>? _closing;

  final Uri url;
  int get bytesForwarded => _bytesForwarded;

  static Future<CalendarCoverVideoProxy> open(Uri upstream,
      {HttpClient? client,
      int maxBytes = 8 * 1024 * 1024,
      int maxRequests = 24,
      bool Function()? isCurrent}) async {
    if (!{'https', 'http'}.contains(upstream.scheme) ||
        upstream.host.isEmpty ||
        upstream.userInfo.isNotEmpty ||
        maxBytes < 1 ||
        maxRequests < 1) {
      throw ArgumentError('Invalid thumbnail source or limits');
    }
    final http = client ?? HttpClient();
    http
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 5)
      ..maxConnectionsPerHost = 3;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final random = Random.secure();
      final token = base64Url
          .encode(List<int>.generate(24, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final proxy = CalendarCoverVideoProxy._(server, http, upstream,
          '/$token/video', maxBytes, maxRequests, isCurrent);
      server.listen((request) => unawaited(proxy._serve(request)),
          onError: (Object _) => unawaited(proxy.close()));
      return proxy;
    } catch (_) {
      http.close(force: true);
      throw StateError('Thumbnail bridge is unavailable');
    }
  }

  bool get _current {
    try {
      return !_closed && (_isCurrent?.call() ?? true);
    } catch (_) {
      return false;
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _client.close(force: true);
    return _closing = _server.close(force: true).then<void>((_) {});
  }

  Future<void> _serve(HttpRequest request) async {
    var acquired = false;
    var started = false;
    HttpClientRequest? outbound;
    var upstreamCompleted = false;
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.uri.path != _path || request.uri.hasQuery) {
        await _empty(request.response, HttpStatus.notFound);
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _empty(request.response, HttpStatus.methodNotAllowed);
        return;
      }
      final ranges = request.headers[HttpHeaders.rangeHeader];
      final range = ranges?.join(',');
      if (range != null && !_validRange(range)) {
        await _empty(request.response, HttpStatus.badRequest);
        return;
      }
      if (!_current ||
          _active >= 3 ||
          _requests >= _maxRequests ||
          _bytesForwarded >= _maxBytes) {
        await _empty(request.response, HttpStatus.badGateway);
        return;
      }
      _active++;
      _requests++;
      acquired = true;
      // R2 signatures bind the HTTP method. Obtain HEAD metadata with a tiny
      // GET range rather than changing a signed GET into an upstream HEAD.
      outbound = await _client.getUrl(_upstream);
      if (!_current) {
        await _empty(request.response, HttpStatus.badGateway);
        return;
      }
      outbound.followRedirects = false;
      outbound.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (request.method == 'HEAD') {
        outbound.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      } else if (range != null) {
        outbound.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstream = await outbound.close();
      final encoding =
          upstream.headers.value(HttpHeaders.contentEncodingHeader);
      if (!_current ||
          !{HttpStatus.ok, HttpStatus.partialContent}
              .contains(upstream.statusCode) ||
          (encoding != null && encoding.toLowerCase() != 'identity')) {
        await upstream.listen(null).cancel();
        upstreamCompleted = true;
        await _empty(request.response, HttpStatus.badGateway);
        return;
      }
      final response = request.response;
      response.bufferOutput = false;
      final contentType = upstream.headers.value(HttpHeaders.contentTypeHeader);
      if (contentType != null) {
        response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (request.method == 'HEAD') {
        final rangeMetadata =
            upstream.headers.value(HttpHeaders.contentRangeHeader);
        final total = upstream.statusCode == HttpStatus.partialContent
            ? int.tryParse(RegExp(r'^bytes \d+-\d+/(\d+)$')
                    .firstMatch(rangeMetadata ?? '')
                    ?.group(1) ??
                '')
            : upstream.contentLength;
        await upstream.listen(null).cancel();
        upstreamCompleted = true;
        if (total == null || total < 0 || !_current) {
          await _empty(response, HttpStatus.badGateway);
          return;
        }
        response.statusCode = HttpStatus.ok;
        response.contentLength = total;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        await response.close();
        return;
      }
      response.statusCode = upstream.statusCode;
      if (upstream.contentLength >= 0) {
        response.contentLength = upstream.contentLength;
      }
      for (final name in [
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader
      ]) {
        final value = upstream.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      started = true;
      await for (final chunk in upstream) {
        if (!_current) {
          unawaited(close());
          return;
        }
        final remaining = _maxBytes - _bytesForwarded;
        if (chunk.length > remaining) {
          if (remaining > 0) {
            _bytesForwarded += remaining;
            response.add(chunk.sublist(0, remaining));
            await response.flush();
          }
          // Closing also cancels every in-flight HTTPS request for this frame.
          unawaited(close());
          return;
        }
        _bytesForwarded += chunk.length;
        response.add(chunk);
        await response.flush();
      }
      upstreamCompleted = true;
      await response.close();
    } catch (_) {
      // Network errors may contain signed URLs; never return or log details.
      try {
        if (started) {
          await request.response.close();
        } else {
          await _empty(request.response, HttpStatus.badGateway);
        }
      } catch (_) {}
    } finally {
      if (!upstreamCompleted) outbound?.abort();
      if (acquired) _active--;
    }
  }

  static bool _validRange(String value) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (match.group(1)!.isNotEmpty && start == null ||
        match.group(2)!.isNotEmpty && end == null) {
      return false;
    }
    if (start == null) return end != null && end > 0;
    return end == null || end >= start;
  }

  static Future<void> _empty(HttpResponse response, int status) async {
    response.statusCode = status;
    response.contentLength = 0;
    await response.close();
  }
}
