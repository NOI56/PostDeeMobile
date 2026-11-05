import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import 'platform_publish_preflight.dart';
import 'publish_media_probe.dart';

const _clipTicksPerSecond = 1000000;

/// An explicit source interval. Different channel plans may overlap.
class ClipSegmentRange {
  const ClipSegmentRange({
    required this.index,
    required this.startSeconds,
    required this.endSeconds,
    required this.minimumDurationSeconds,
    required this.maximumDurationSeconds,
  });
  final int index;
  final double startSeconds;
  final double endSeconds;
  final double minimumDurationSeconds;
  final double maximumDurationSeconds;
  int get _durationTicks =>
      (endSeconds * _clipTicksPerSecond).round() -
      (startSeconds * _clipTicksPerSecond).round();

  // Match the planner and FFmpeg's six-decimal source intervals. Subtracting
  // their binary doubles directly can make an exact 90 seconds appear longer.
  double get durationSeconds => _durationTicks / _clipTicksPerSecond;
}

class ClipSegmentRequest {
  const ClipSegmentRequest({
    required this.inputFile,
    required this.fileName,
    required this.ranges,
    this.isCancelled,
    this.onProgress,
  });
  final File inputFile;
  final String fileName;
  final List<ClipSegmentRange> ranges;
  final bool Function()? isCancelled;
  final void Function(int completed, int total)? onProgress;
}

class ClipSegmentResult {
  const ClipSegmentResult({
    required this.file,
    required this.fileName,
    required this.index,
    required this.startSeconds,
    required this.endSeconds,
    required this.metadata,
  });
  final File file;
  final String fileName;
  final int index;
  final double startSeconds;
  final double endSeconds;
  final PublishMediaMetadata metadata;
}

class ClipSegmentBatchResult {
  ClipSegmentBatchResult({
    required this.parts,
    this.workingDirectory,
    this.cleanup,
  });
  final List<ClipSegmentResult> parts;
  final Directory? workingDirectory;
  final Future<void> Function()? cleanup;
  Future<void>? _cleanupFuture;

  Future<void> cleanupTemporaryFiles() => _cleanupFuture ??= cleanup != null
      ? cleanup!()
      : workingDirectory == null
          ? Future.value()
          : _deleteDirectory(workingDirectory!);
}

class ClipSegmentException implements Exception {
  const ClipSegmentException(this.message, {this.isCancelled = false});
  final String message;
  final bool isCancelled;
  @override
  String toString() => message;
}

typedef UploaderClipSegmenter = Future<ClipSegmentBatchResult> Function(
    ClipSegmentRequest request);
typedef ClipSegmentRunner = Future<ClipSegmentTask<bool>> Function(
    List<String> arguments);
typedef ClipSegmentProbe = Future<ClipSegmentTask<ClipSegmentProbeResult?>>
    Function(String path);
typedef ClipSegmentDirectoryCreator = Future<Directory> Function(String prefix);

/// One native session: cancellation must never target unrelated FFmpeg work.
class ClipSegmentTask<T> {
  const ClipSegmentTask({required this.result, required this.cancel});
  final Future<T> result;
  final Future<void> Function() cancel;
}

class ClipSegmentProbeResult {
  const ClipSegmentProbeResult({
    required this.metadata,
    this.decodedPrefixFrameCount,
  });
  final PublishMediaMetadata metadata;
  final int? decodedPrefixFrameCount;
}

Future<ClipSegmentTask<bool>> _nativeRender(List<String> arguments) async {
  final session = await FFmpegSession.create(arguments);
  final id = session.getSessionId();
  if (id == null) throw StateError('Missing clip segmentation session');
  final result = () async {
    // Await this session's MethodChannel completion, not global engine events.
    await FFmpegKitConfig.ffmpegExecute(session);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }();
  return ClipSegmentTask(result: result, cancel: () => FFmpegKit.cancel(id));
}

Future<ClipSegmentTask<ClipSegmentProbeResult?>> _nativeProbe(String path,
    {bool countDecodedFrames = false}) async {
  final session = await FFprobeSession.create([
    '-v',
    'error',
    '-print_format',
    'json',
    '-show_format',
    '-show_streams',
    if (countDecodedFrames) ...['-count_frames', '-read_intervals', '0%+2'],
    '-i',
    path,
  ]);
  final id = session.getSessionId();
  if (id == null) throw StateError('Missing clip probe session');
  final result = () async {
    await FFmpegKitConfig.ffprobeExecute(session);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
    final output = await session.getOutput();
    if (output == null || output.length > 131072) return null;
    final properties = jsonDecode(output);
    if (properties is! Map) return null;
    final streams = properties['streams'];
    final video = streams is List
        ? streams.whereType<Map>().where((stream) {
            final disposition = stream['disposition'];
            return stream['codec_type'] == 'video' &&
                !(disposition is Map &&
                    '${disposition['attached_pic']}' == '1');
          }).firstOrNull
        : null;
    return ClipSegmentProbeResult(
      metadata: readPublishMediaMetadata(properties,
          sizeBytes: await File(path).length()),
      decodedPrefixFrameCount: int.tryParse('${video?['nb_read_frames']}'),
    );
  }();
  return ClipSegmentTask(result: result, cancel: () => FFmpegKit.cancel(id));
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

const _cancelled = ClipSegmentException('หยุดแบ่งคลิปแล้ว', isCancelled: true);
const _failed = ClipSegmentException('แบ่งคลิปไม่สำเร็จ กรุณาลองอีกครั้ง');

/// Creates local publish copies only. It never uploads, posts, or spends quota.
class FfmpegClipSegmenter {
  FfmpegClipSegmenter({
    bool? isAndroid,
    bool? isIOS,
    ClipSegmentDirectoryCreator? createTemporaryDirectory,
    ClipSegmentRunner? run,
    ClipSegmentProbe? probe,
    this.renderTimeout = const Duration(minutes: 10),
    this.probeTimeout = const Duration(seconds: 30),
    this.cancelTimeout = const Duration(seconds: 2),
    this.cancellationPollInterval = const Duration(milliseconds: 100),
  })  : isAndroid = isAndroid ?? Platform.isAndroid,
        isIOS = isIOS ?? Platform.isIOS,
        _createTemporaryDirectory =
            createTemporaryDirectory ?? Directory.systemTemp.createTemp,
        _run = run ?? _nativeRender,
        _probe = probe ?? _nativeProbe,
        _probeOutput =
            probe ?? ((path) => _nativeProbe(path, countDecodedFrames: true));

  final bool isAndroid;
  final bool isIOS;
  final ClipSegmentDirectoryCreator _createTemporaryDirectory;
  final ClipSegmentRunner _run;
  final ClipSegmentProbe _probe;
  final ClipSegmentProbe _probeOutput;
  final Duration renderTimeout;
  final Duration probeTimeout;
  final Duration cancelTimeout;
  final Duration cancellationPollInterval;

  void _checkCancelled(ClipSegmentRequest request) {
    if (request.isCancelled?.call() ?? false) throw _cancelled;
  }

  Future<void> _cancel<T>(
      ClipSegmentTask<T> task, Future<void> Function() discard) async {
    // Observe and clean up a late native result even after the bounded wait.
    unawaited(task.result
        .then<void>((_) => discard(),
            onError: (Object _, StackTrace __) => discard())
        .catchError((_) {}));
    try {
      await task.cancel().timeout(cancelTimeout);
    } catch (_) {/* Session cancellation is best effort. */}
    try {
      await task.result.timeout(cancelTimeout);
    } catch (_) {/* An unresponsive session cannot become a ready result. */}
  }

  Future<T> _bounded<T>(
      Future<ClipSegmentTask<T>> Function() start,
      Duration timeout,
      ClipSegmentRequest request,
      Future<void> Function() discard) async {
    _checkCancelled(request);
    ClipSegmentTask<T>? task;
    var expired = false;
    final cancelled = Completer<T>();
    final timer = Timer.periodic(cancellationPollInterval, (_) {
      if ((request.isCancelled?.call() ?? false) && !cancelled.isCompleted) {
        cancelled.completeError(_cancelled);
      }
    });
    final operation = () async {
      final started = await start();
      if (expired) {
        await _cancel(started, discard);
        await discard();
        throw _failed;
      }
      task = started;
      return started.result;
    }();
    try {
      final result =
          await Future.any([operation, cancelled.future]).timeout(timeout);
      _checkCancelled(request);
      return result;
    } catch (_) {
      expired = true;
      if (task != null) await _cancel(task!, discard);
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  bool _validMetadata(PublishMediaMetadata media) =>
      media.hasVideo &&
      media.sizeBytes > 0 &&
      media.width != null &&
      media.width! >= 2 &&
      media.height != null &&
      media.height! >= 2 &&
      media.durationSeconds != null &&
      media.durationSeconds!.isFinite &&
      media.durationSeconds! > 0;

  void _validateRanges(List<ClipSegmentRange> ranges, double sourceDuration) {
    if (ranges.isEmpty || ranges.length > 64) throw _failed;
    final indices = <int>{};
    for (final range in ranges) {
      if (range.index < 0 ||
          !indices.add(range.index) ||
          !range.startSeconds.isFinite ||
          !range.endSeconds.isFinite ||
          !range.minimumDurationSeconds.isFinite ||
          !range.maximumDurationSeconds.isFinite ||
          range.startSeconds < 0 ||
          range.endSeconds <= range.startSeconds ||
          range.endSeconds > sourceDuration + .001 ||
          range.minimumDurationSeconds < 0 ||
          range.maximumDurationSeconds <= 0 ||
          range.minimumDurationSeconds > range.maximumDurationSeconds) {
        throw const ClipSegmentException(
            'ช่วงเวลาที่แบ่งคลิปไม่ถูกต้อง กรุณาเลือกใหม่');
      }
      if (range._durationTicks <= 0 ||
          range._durationTicks <
              (range.minimumDurationSeconds * _clipTicksPerSecond).round() ||
          range._durationTicks >
              (range.maximumDurationSeconds * _clipTicksPerSecond).round()) {
        throw const ClipSegmentException(
            'ช่วงเวลาที่แบ่งคลิปไม่ถูกต้อง กรุณาเลือกใหม่');
      }
    }
  }

  Future<void> _checkSource(File input, FileStat original) async {
    final current = await input.stat();
    if (current.type != FileSystemEntityType.file ||
        current.size != original.size ||
        current.modified != original.modified) {
      throw const ClipSegmentException(
          'คลิปต้นฉบับเปลี่ยนแล้ว กรุณาเลือกคลิปใหม่');
    }
  }

  bool _validOutput(ClipSegmentProbeResult probe, PublishMediaMetadata source,
      ClipSegmentRange range, int sizeBytes) {
    final media = probe.metadata;
    if (!_validMetadata(media)) return false;
    final duration = media.durationSeconds!;
    final expectedFrames = (duration.clamp(0, 2) * 30).round();
    final decoded = probe.decodedPrefixFrameCount;
    final container = media.container?.split(',');
    return media.sizeBytes == sizeBytes &&
        media.videoCodec == 'h264' &&
        media.fps != null &&
        (media.fps! - 30).abs() < .001 &&
        media.width == source.width! ~/ 2 * 2 &&
        media.height == source.height! ~/ 2 * 2 &&
        container != null &&
        container.contains('mp4') &&
        media.hasAudio == source.hasAudio &&
        (!media.hasAudio || media.audioCodec == 'aac') &&
        decoded != null &&
        decoded >= (expectedFrames - 2).clamp(1, 60) &&
        decoded <= expectedFrames + 2 &&
        (duration - range.durationSeconds).abs() <= 1 / 30 + .025 &&
        duration >= range.minimumDurationSeconds &&
        duration <= range.maximumDurationSeconds;
  }

  Future<ClipSegmentBatchResult> call(ClipSegmentRequest request) async {
    Directory? ownedDirectory;
    Future<void> discard() async {
      final directory = ownedDirectory;
      if (directory != null) await _deleteDirectory(directory);
    }

    try {
      _checkCancelled(request);
      final ranges = List<ClipSegmentRange>.of(request.ranges);
      if ((!isAndroid && !isIOS) || ranges.isEmpty || ranges.length > 64) {
        throw _failed;
      }
      final original = await request.inputFile.stat();
      if (original.type != FileSystemEntityType.file || original.size <= 0) {
        throw _failed;
      }
      final sourceProbe = await _bounded(
          () => _probe(request.inputFile.path), probeTimeout, request, discard);
      if (sourceProbe == null || !_validMetadata(sourceProbe.metadata)) {
        throw const ClipSegmentException(
            'ตรวจสอบคลิปต้นฉบับไม่สำเร็จ กรุณาเลือกคลิปใหม่');
      }
      final source = sourceProbe.metadata;
      _validateRanges(ranges, source.durationSeconds!);
      await _checkSource(request.inputFile, original);
      _checkCancelled(request);
      final directory = await _createTemporaryDirectory('postdee-clip-parts-');
      // Do not assume ownership of an injected, nonempty, or source directory.
      final directoryPath = await directory.resolveSymbolicLinks();
      final sourcePath = await request.inputFile.resolveSymbolicLinks();
      final separator = Platform.pathSeparator;
      if (sourcePath
              .toLowerCase()
              .startsWith('${directoryPath.toLowerCase()}$separator') ||
          await directory.list(followLinks: false).isEmpty == false) {
        throw _failed;
      }
      ownedDirectory = directory;
      final parts = <ClipSegmentResult>[];
      final sourceName = request.fileName.replaceAll('\\', '/').split('/').last;
      final baseName = sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
      for (var position = 0; position < ranges.length; position++) {
        _checkCancelled(request);
        await _checkSource(request.inputFile, original);
        final range = ranges[position];
        final output = File(
            '${directory.path}${separator}part_${position.toString().padLeft(4, '0')}.mp4');
        final succeeded = await _bounded(
            () => _run([
                  '-y',
                  '-i',
                  request.inputFile.path,
                  '-ss',
                  range.startSeconds.toStringAsFixed(6),
                  '-t',
                  range.durationSeconds.toStringAsFixed(6),
                  '-map',
                  '0:v:0',
                  '-map',
                  '0:a?',
                  '-vf',
                  'fps=30,scale=${source.width! ~/ 2 * 2}:${source.height! ~/ 2 * 2}',
                  '-c:v',
                  isAndroid ? 'h264_mediacodec' : 'h264_videotoolbox',
                  if (isAndroid) ...[
                    '-flags:v',
                    '-global_header',
                    '-bsf:v',
                    'extract_extradata'
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
            request,
            discard);
        if (!succeeded ||
            !await output.exists() ||
            await output.length() <= 0) {
          throw _failed;
        }
        final verified = await _bounded(
            () => _probeOutput(output.path), probeTimeout, request, discard);
        if (verified == null ||
            !_validOutput(verified, source, range, await output.length())) {
          throw const ClipSegmentException(
              'คลิปที่แบ่งยังไม่ผ่านการตรวจสอบ กรุณาลองอีกครั้ง');
        }
        await _checkSource(request.inputFile, original);
        _checkCancelled(request);
        parts.add(ClipSegmentResult(
          file: output,
          fileName:
              '${baseName.isEmpty ? 'video' : baseName}_part_${position + 1}.mp4',
          index: range.index,
          startSeconds: range.startSeconds,
          endSeconds: range.endSeconds,
          metadata: verified.metadata,
        ));
        request.onProgress?.call(position + 1, ranges.length);
      }
      _checkCancelled(request);
      return ClipSegmentBatchResult(
          parts: List.unmodifiable(parts), workingDirectory: directory);
    } catch (error) {
      try {
        await discard();
      } catch (_) {/* Preserve the failure and allow late-session cleanup. */}
      if (error is ClipSegmentException) rethrow;
      throw _failed;
    }
  }
}
