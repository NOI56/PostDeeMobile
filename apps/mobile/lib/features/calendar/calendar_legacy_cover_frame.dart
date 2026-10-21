import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/log_redirection_strategy.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import 'calendar_cover_video_proxy.dart';

class CalendarLegacyCoverFrameTask {
  const CalendarLegacyCoverFrameTask({
    required this.result,
    required this.cancel,
  });

  final Future<bool> result;
  final Future<void> Function() cancel;
}

typedef CalendarLegacyCoverFrameRunner = Future<CalendarLegacyCoverFrameTask>
    Function(List<String> arguments);
typedef CalendarCoverVideoProxyOpener = Future<CalendarCoverVideoProxy>
    Function(Uri videoUrl, {bool Function()? isCurrent});

/// Recovers a selected video frame for older posts without a stored cover image.
/// The remote clip is read by FFmpeg; only a small temporary JPEG is written.
class FfmpegCalendarLegacyCoverFrame {
  const FfmpegCalendarLegacyCoverFrame({
    this.runCommand,
    this.openVideoProxy,
    this.createWorkingDirectory,
    this.timeout = const Duration(seconds: 8),
    this.cancelTimeout = const Duration(seconds: 1),
    this.ownerCheckInterval = const Duration(milliseconds: 50),
  });

  static const maxImageBytes = 512 * 1024;

  final CalendarLegacyCoverFrameRunner? runCommand;
  final CalendarCoverVideoProxyOpener? openVideoProxy;
  final Future<Directory> Function()? createWorkingDirectory;
  final Duration timeout;
  final Duration cancelTimeout;
  final Duration ownerCheckInterval;

  Future<Uint8List?> call(
    Uri videoUrl, {
    int frameTimeMs = 0,
    bool Function()? isCurrent,
  }) async {
    bool current() {
      try {
        return isCurrent?.call() ?? true;
      } catch (_) {
        return false;
      }
    }

    if (!_safeUrl(videoUrl) || !current()) return null;
    Directory? directory;
    CalendarLegacyCoverFrameTask? task;
    CalendarCoverVideoProxy? proxy;
    var expired = false;
    final cancelledTasks = <CalendarLegacyCoverFrameTask>{};
    final invalidated = Completer<Uint8List?>();

    Future<void> cancel(CalendarLegacyCoverFrameTask started) async {
      if (!cancelledTasks.add(started)) return;
      // A late native error must remain observed after this request is gone.
      unawaited(started.result
          .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      try {
        await started.cancel().timeout(cancelTimeout);
      } catch (_) {
        // Cancellation is best effort and always belongs to this session only.
      }
    }

    final ownerTimer = isCurrent == null
        ? null
        : Timer.periodic(ownerCheckInterval, (_) {
            if (!current()) {
              expired = true;
              if (!invalidated.isCompleted) invalidated.complete(null);
            }
          });

    final operation = () async {
      final working = await (createWorkingDirectory?.call() ??
          Directory.systemTemp.createTemp('postdee-calendar-cover-'));
      directory = working;
      try {
        if (expired || !current()) return null;
        // The existing video build has HTTP but no TLS. Dart keeps the owned
        // upstream encrypted and exposes only a short-lived loopback resource.
        if (runCommand == null || openVideoProxy != null) {
          proxy = await (openVideoProxy ?? CalendarCoverVideoProxy.open)(
            videoUrl,
            isCurrent: () => !expired && current(),
          );
          if (expired || !current()) return null;
        }
        final output =
            File('${working.path}${Platform.pathSeparator}selected-frame.jpg');
        final arguments = <String>[
          '-y',
          '-nostdin',
          '-loglevel',
          'error',
          '-protocol_whitelist',
          'http,https,tcp,tls',
          '-rw_timeout',
          '5000000',
          // Input seeking avoids decoding the entire prefix of a long clip.
          '-ss',
          (frameTimeMs.clamp(0, 86400000) / 1000).toStringAsFixed(3),
          '-threads',
          '1',
          '-i',
          (proxy?.url ?? videoUrl).toString(),
          '-map',
          '0:v:0',
          '-frames:v',
          '1',
          '-vf',
          'scale=144:256:force_original_aspect_ratio=increase,crop=144:256',
          '-an',
          '-sn',
          '-dn',
          '-threads',
          '1',
          '-q:v',
          '5',
          output.path,
        ];
        final started = await (runCommand ?? _runNative)(arguments);
        task = started;
        if (expired || !current()) {
          await cancel(started);
          return null;
        }
        final succeeded = await started.result;
        if (!succeeded || expired || !current() || !await output.exists()) {
          return null;
        }
        final size = await output.length();
        if (size < 1 || size > maxImageBytes || expired || !current()) {
          return null;
        }
        final bytes = await output.readAsBytes();
        return !expired &&
                current() &&
                bytes.isNotEmpty &&
                bytes.length <= maxImageBytes
            ? bytes
            : null;
      } finally {
        // This also handles a directory or task that starts after the timeout.
        if (expired) {
          await proxy?.close();
          await _cleanup(working);
        }
      }
    }();

    try {
      final bytes = await Future.any<Uint8List?>([
        operation,
        invalidated.future,
      ]).timeout(timeout);
      if (expired || !current()) {
        expired = true;
        if (task != null) await cancel(task!);
        return null;
      }
      return bytes;
    } on TimeoutException {
      expired = true;
      if (task != null) await cancel(task!);
      return null;
    } catch (_) {
      // Native errors can contain private media URLs; expose no diagnostic text.
      return null;
    } finally {
      expired = true;
      ownerTimer?.cancel();
      await proxy?.close();
      final working = directory;
      if (working != null) await _cleanup(working);
    }
  }

  static bool _safeUrl(Uri url) =>
      (url.scheme == 'https' || url.scheme == 'http') &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;

  static Future<CalendarLegacyCoverFrameTask> _runNative(
      List<String> arguments) async {
    final session = await FFmpegSession.create(
      arguments,
      null,
      (_) {},
      null,
      LogRedirectionStrategy.neverPrintLogs,
    );
    final sessionId = session.getSessionId();
    if (sessionId == null) throw StateError('Missing native thumbnail session');
    final result = () async {
      // Await this engine's method result instead of global completion events.
      await FFmpegKitConfig.ffmpegExecute(session);
      return ReturnCode.isSuccess(await session.getReturnCode());
    }();
    return CalendarLegacyCoverFrameTask(
      result: result,
      cancel: () => FFmpegKit.cancel(sessionId),
    );
  }

  static Future<void> _cleanup(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A failed cleanup must not block the calendar or leak a private path.
    }
  }
}
