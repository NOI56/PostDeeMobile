import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

const tikTokVideoPreparationPolicy = 'tiktok-cfr30-h264-aac-v2';

class TikTokVideoPreparationException implements Exception {
  const TikTokVideoPreparationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TikTokVideoPreparationRequest {
  const TikTokVideoPreparationRequest({
    required this.inputFile,
    required this.fileName,
    this.isCancelled,
    this.maxDurationSeconds,
  });
  final File inputFile;
  final String fileName;
  final bool Function()? isCancelled;
  final int? maxDurationSeconds;
}

class TikTokPreparedVideoResult {
  const TikTokPreparedVideoResult({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.width,
    required this.height,
    this.videoPreparationPolicy = tikTokVideoPreparationPolicy,
    this.workingDirectory,
    this.cleanup,
    this.durationSeconds,
  });
  final File file;
  final String fileName;
  final int sizeBytes;
  final int width;
  final int height;
  final String videoPreparationPolicy;
  final Directory? workingDirectory;
  final Future<void> Function()? cleanup;

  /// Verified from the rendered stream; absent on historical/injected receipts.
  final double? durationSeconds;

  Future<void> cleanupTemporaryFiles() async {
    if (cleanup != null) {
      await cleanup!();
    } else if (workingDirectory != null) {
      await _deleteTemporaryDirectory(workingDirectory!);
    }
  }
}

typedef UploaderTikTokVideoPreparer = Future<TikTokPreparedVideoResult>
    Function(TikTokVideoPreparationRequest request);
typedef TikTokTemporaryDirectoryCreator = Future<Directory> Function(
    String prefix);
typedef TikTokVideoRunner = Future<TikTokVideoTask<bool>> Function(
    List<String> arguments);
typedef TikTokVideoProbe = Future<TikTokVideoTask<TikTokVideoMetadata?>>
    Function(String path);

/// A single native session. Cancellation never affects another editor or probe.
class TikTokVideoTask<T> {
  const TikTokVideoTask({required this.result, required this.cancel});
  final Future<T> result;
  final Future<void> Function() cancel;
}

class TikTokVideoMetadata {
  const TikTokVideoMetadata({
    required this.videoCodec,
    required this.averageFrameRate,
    required this.realFrameRate,
    required this.width,
    required this.height,
    required this.durationSeconds,
    this.hasAudio = false,
    this.audioCodec,
    this.decodedPrefixFrameCount,
  });
  final String videoCodec;
  final double? averageFrameRate;
  final double? realFrameRate;
  final int width;
  final int height;
  final double durationSeconds;
  final bool hasAudio;
  final String? audioCodec;

  /// Actual decoded frames in at most the first two seconds, not nb_frames
  /// declared by an MP4 header. Only the prepared output requires this count.
  final int? decodedPrefixFrameCount;
}

double? readVideoFrameRate(Object? value) {
  final parts = value?.toString().split('/');
  if (parts == null || parts.isEmpty || parts.length > 2) return null;
  final numerator = double.tryParse(parts.first);
  final denominator = parts.length == 2 ? double.tryParse(parts.last) : 1.0;
  if (numerator == null || denominator == null || denominator <= 0) return null;
  final rate = numerator / denominator;
  return rate.isFinite && rate > 0 ? rate : null;
}

({int width, int height})? _tikTokPreparedDimensions(
    TikTokVideoMetadata source) {
  final width = source.width;
  final height = source.height;
  if (width < 2 || height < 2) return null;
  final shortest = width < height ? width : height;
  final longest = width > height ? width : height;
  final numerator = shortest < 360 ? 360 : (longest > 4096 ? 4096 : 1);
  final denominator =
      shortest < 360 ? shortest : (longest > 4096 ? longest : 1);
  // Scale uniformly, allowing only the existing rounding to even pixels. An
  // extreme aspect ratio cannot meet both limits without cropping or padding.
  final preparedWidth = width * numerator ~/ denominator ~/ 2 * 2;
  final preparedHeight = height * numerator ~/ denominator ~/ 2 * 2;
  if (preparedWidth < 360 ||
      preparedHeight < 360 ||
      preparedWidth > 4096 ||
      preparedHeight > 4096) {
    return null;
  }
  return (width: preparedWidth, height: preparedHeight);
}

bool isCompatibleTikTokPreparedVideo(
  TikTokVideoMetadata output, {
  required TikTokVideoMetadata source,
}) {
  final dimensions = _tikTokPreparedDimensions(source);
  if (dimensions == null ||
      !output.durationSeconds.isFinite ||
      output.durationSeconds <= 0) {
    return false;
  }
  final expectedFrames = (output.durationSeconds.clamp(0.0, 2.0) * 30).round();
  final decodedFrames = output.decodedPrefixFrameCount;
  final minimumFrames = (expectedFrames - 2).clamp(1, 60);
  bool isThirty(double? rate) => rate != null && (rate - 30).abs() < .001;
  return output.videoCodec == 'h264' &&
      isThirty(output.averageFrameRate) &&
      isThirty(output.realFrameRate) &&
      output.width == dimensions.width &&
      output.height == dimensions.height &&
      decodedFrames != null &&
      decodedFrames >= minimumFrames &&
      decodedFrames <= expectedFrames + 2 &&
      (output.durationSeconds - source.durationSeconds).abs() <= .25 &&
      (!source.hasAudio || output.hasAudio) &&
      (!output.hasAudio || output.audioCodec == 'aac');
}

/// Reads the actual stream, including phone rotation, rather than trusting the
/// requested encoder or the container's successful return code.
TikTokVideoMetadata? readTikTokVideoMetadata(Map<dynamic, dynamic> properties) {
  final streams = properties['streams'];
  if (streams is! List) return null;
  final videos =
      streams.whereType<Map>().where((s) => s['codec_type'] == 'video');
  if (videos.isEmpty) return null;
  final video = videos.first;
  final audios =
      streams.whereType<Map>().where((s) => s['codec_type'] == 'audio');
  final format = properties['format'];
  final duration = double.tryParse(
      '${video['duration'] ?? (format is Map ? format['duration'] : null)}');
  var width = int.tryParse('${video['width']}');
  var height = int.tryParse('${video['height']}');
  if (width == null ||
      height == null ||
      width < 2 ||
      height < 2 ||
      duration == null ||
      !duration.isFinite ||
      duration <= 0) {
    return null;
  }
  final tags = video['tags'];
  var rotation = double.tryParse('${tags is Map ? tags['rotate'] : null}') ?? 0;
  final sideData = video['side_data_list'];
  if (sideData is List) {
    for (final item in sideData.whereType<Map>()) {
      rotation = double.tryParse('${item['rotation']}') ?? rotation;
    }
  }
  if (rotation.isFinite && (rotation.abs() % 180 - 90).abs() < .01) {
    final originalWidth = width;
    width = height;
    height = originalWidth;
  }
  return TikTokVideoMetadata(
    videoCodec: '${video['codec_name']}',
    averageFrameRate: readVideoFrameRate(video['avg_frame_rate']),
    realFrameRate: readVideoFrameRate(video['r_frame_rate']),
    width: width,
    height: height,
    durationSeconds: duration,
    hasAudio: audios.isNotEmpty,
    audioCodec: audios.isEmpty ? null : '${audios.first['codec_name']}',
    decodedPrefixFrameCount: int.tryParse('${video['nb_read_frames']}'),
  );
}

Future<TikTokVideoTask<bool>> _runTikTokVideo(List<String> arguments) async {
  final session = await FFmpegSession.create(arguments);
  final sessionId = session.getSessionId();
  if (sessionId == null) throw StateError('Missing native preparation session');
  // These execute methods run on Android/iOS native workers and resolve the
  // caller's MethodChannel result. Global completion events can instead belong
  // to another Flutter engine without a listener. Expose this session's cancel
  // handle immediately, while its native execution is still pending.
  final result = () async {
    await FFmpegKitConfig.ffmpegExecute(session);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }();
  return TikTokVideoTask(
    result: result,
    cancel: () => _cancelNativeSession(sessionId),
  );
}

Future<TikTokVideoTask<TikTokVideoMetadata?>> probeTikTokVideo(String path,
    {bool countDecodedFrames = false}) async {
  final session = await FFprobeSession.create([
    '-v',
    'error',
    '-print_format',
    'json',
    '-show_format',
    '-show_streams',
    if (countDecodedFrames) ...[
      '-count_frames',
      '-read_intervals',
      '0%+2',
    ],
    '-i',
    path,
  ]);
  final sessionId = session.getSessionId();
  if (sessionId == null) throw StateError('Missing native preparation session');
  final result = () async {
    await FFmpegKitConfig.ffprobeExecute(session);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      return null;
    }
    final decoded = jsonDecode(await session.getOutput() ?? '{}');
    return decoded is Map ? readTikTokVideoMetadata(decoded) : null;
  }();
  return TikTokVideoTask(
    result: result,
    cancel: () => _cancelNativeSession(sessionId),
  );
}

Future<void> _cancelNativeSession(int? sessionId) async {
  // The plugin's session.cancel() falls back to global cancellation for a
  // missing ID. Never let this uploader cancel a separate editor or probe.
  if (sessionId == null) throw StateError('Missing native preparation session');
  await FFmpegKit.cancel(sessionId);
}

Future<void> _deleteTemporaryDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

class FfmpegTikTokVideoPreparer {
  FfmpegTikTokVideoPreparer({
    bool? isAndroid,
    bool? isIOS,
    TikTokTemporaryDirectoryCreator? createTemporaryDirectory,
    TikTokVideoRunner? run,
    TikTokVideoProbe? probe,
    this.renderTimeout = const Duration(minutes: 10),
    this.probeTimeout = const Duration(seconds: 30),
    this.cancelTimeout = const Duration(seconds: 5),
    this.cancellationPollInterval = const Duration(milliseconds: 100),
  })  : isAndroid = isAndroid ?? Platform.isAndroid,
        isIOS = isIOS ?? Platform.isIOS,
        _createTemporaryDirectory =
            createTemporaryDirectory ?? Directory.systemTemp.createTemp,
        _run = run ?? _runTikTokVideo,
        _probe = probe ?? probeTikTokVideo,
        _probeOutput = probe ??
            ((path) => probeTikTokVideo(path, countDecodedFrames: true));

  final bool isAndroid;
  final bool isIOS;
  final TikTokTemporaryDirectoryCreator _createTemporaryDirectory;
  final TikTokVideoRunner _run;
  final TikTokVideoProbe _probe;
  final TikTokVideoProbe _probeOutput;
  final Duration renderTimeout;
  final Duration probeTimeout;
  final Duration cancelTimeout;
  final Duration cancellationPollInterval;

  Future<void> _cancel<T>(TikTokVideoTask<T> task) async {
    try {
      await task.cancel().timeout(cancelTimeout);
    } catch (_) {/* Fail closed. */}
    try {
      await task.result.timeout(cancelTimeout);
    } catch (_) {/* Already stopped or unresponsive. */}
  }

  Future<T> _bounded<T>(Future<TikTokVideoTask<T>> Function() start,
      Duration timeout, TikTokVideoPreparationRequest request) async {
    if (request.isCancelled?.call() ?? false) {
      throw const TikTokVideoPreparationException(
          'หยุดเตรียมวิดีโอ เพราะบัญชีหรือร่างเปลี่ยนแล้ว');
    }
    TikTokVideoTask<T>? task;
    var stopped = false;
    final cancelled = Completer<T>();
    final timer = Timer.periodic(cancellationPollInterval, (_) {
      if ((request.isCancelled?.call() ?? false) && !cancelled.isCompleted) {
        cancelled.completeError(const TikTokVideoPreparationException(
            'หยุดเตรียมวิดีโอ เพราะบัญชีหรือร่างเปลี่ยนแล้ว'));
      }
    });
    final operation = () async {
      final started = await start();
      task = started;
      if (stopped) {
        await _cancel(started);
        throw const TikTokVideoPreparationException('หยุดเตรียมวิดีโอแล้ว');
      }
      return started.result;
    }();
    try {
      final result =
          await Future.any([operation, cancelled.future]).timeout(timeout);
      if (request.isCancelled?.call() ?? false) {
        throw const TikTokVideoPreparationException(
            'หยุดเตรียมวิดีโอ เพราะบัญชีหรือร่างเปลี่ยนแล้ว');
      }
      return result;
    } catch (_) {
      stopped = true;
      if (task != null) await _cancel(task!);
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  Future<TikTokPreparedVideoResult> call(
      TikTokVideoPreparationRequest request) async {
    Directory? workingDirectory;
    try {
      if ((!isAndroid && !isIOS) ||
          !await request.inputFile.exists() ||
          await request.inputFile.length() <= 0) {
        throw const TikTokVideoPreparationException(
            'อุปกรณ์นี้ยังเตรียมวิดีโอสำหรับ TikTok ไม่ได้ กรุณาใช้ไฟล์ H.264 30 FPS บนอุปกรณ์ที่รองรับ');
      }
      final source = await _bounded(
          () => _probe(request.inputFile.path), probeTimeout, request);
      if (source == null) {
        throw const TikTokVideoPreparationException(
            'ตรวจวิดีโอต้นฉบับไม่ได้ กรุณาเลือกไฟล์วิดีโอใหม่');
      }
      final durationLimit = request.maxDurationSeconds;
      if (durationLimit != null &&
          (durationLimit <= 0 || source.durationSeconds > durationLimit)) {
        throw const TikTokVideoPreparationException(
            'วิดีโอยาวเกินระยะเวลาที่บัญชี TikTok นี้อนุญาต กรุณาเลือกคลิปที่สั้นลง');
      }
      final dimensions = _tikTokPreparedDimensions(source);
      if (dimensions == null) {
        throw const TikTokVideoPreparationException(
            'วิดีโอมีสัดส่วนกว้างหรือสูงเกินไป จึงปรับขนาดให้ TikTok รับไม่ได้ กรุณาเลือกวิดีโอใหม่');
      }
      workingDirectory = await _createTemporaryDirectory('postdee-tiktok-');
      final baseName = request.fileName
          .split(RegExp(r'[/\\]'))
          .last
          .trim()
          .replaceFirst(RegExp(r'\.[^.]+$'), '');
      final fileName = '${baseName.isEmpty ? 'video' : baseName}_tiktok.mp4';
      final output =
          File('${workingDirectory.path}${Platform.pathSeparator}$fileName');
      final succeeded = await _bounded(
          () => _run([
                '-y',
                '-i',
                request.inputFile.path,
                '-map',
                '0:v:0',
                '-map',
                '0:a?',
                '-vf',
                'fps=30,scale=${dimensions.width}:${dimensions.height}',
                '-c:v',
                isAndroid ? 'h264_mediacodec' : 'h264_videotoolbox',
                if (isAndroid) ...[
                  // MediaCodec encoder flush is undefined. FFmpeg's MP4
                  // global-header setup sends a dummy frame/EOS then flushes,
                  // which can return success with no video frames. Keep SPS/PPS
                  // in packet extradata without that initialization flush.
                  '-flags:v', '-global_header',
                  '-bsf:v', 'extract_extradata',
                ],
                '-b:v',
                '6M',
                '-pix_fmt',
                'yuv420p',
                '-r',
                '30',
                '-fps_mode',
                'cfr',
                '-c:a',
                'aac',
                '-b:a',
                '192k',
                '-movflags',
                '+faststart',
                output.path,
              ]),
          renderTimeout,
          request);
      if (!succeeded || !await output.exists() || await output.length() <= 0) {
        throw const TikTokVideoPreparationException(
            'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่บนอุปกรณ์ที่รองรับ');
      }
      final metadata = await _bounded(
          () => _probeOutput(output.path), probeTimeout, request);
      if (metadata == null ||
          !isCompatibleTikTokPreparedVideo(metadata, source: source) ||
          (durationLimit != null && metadata.durationSeconds > durationLimit)) {
        throw const TikTokVideoPreparationException(
            'วิดีโอที่แปลงยังไม่ผ่านการตรวจภาพ เสียง หรือ 30 FPS จึงหยุดก่อนอัปโหลด กรุณาเลือกวิดีโอใหม่หรือลองบนอุปกรณ์ที่รองรับ');
      }
      return TikTokPreparedVideoResult(
        file: output,
        fileName: fileName,
        sizeBytes: await output.length(),
        width: metadata.width,
        height: metadata.height,
        durationSeconds: metadata.durationSeconds,
        workingDirectory: workingDirectory,
      );
    } catch (error) {
      if (workingDirectory != null) {
        try {
          await _deleteTemporaryDirectory(workingDirectory);
        } catch (_) {/* Preserve the preparation failure. */}
      }
      if (error is TikTokVideoPreparationException) rethrow;
      throw const TikTokVideoPreparationException(
          'เตรียมวิดีโอสำหรับ TikTok ไม่สำเร็จ ยังไม่ได้อัปโหลด กรุณาลองใหม่');
    }
  }
}
