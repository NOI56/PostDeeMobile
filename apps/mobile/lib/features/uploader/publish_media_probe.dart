import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_session.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import 'platform_publish_preflight.dart';
import 'video_picker_service.dart';

typedef PublishMediaProbe = Future<PublishMediaMetadata> Function(File file);
typedef PublishMediaProbeRunner = Future<PublishMediaProbeTask> Function(
    String path);

class PublishMediaProbeException implements Exception {
  const PublishMediaProbeException([
    this.message =
        'ตรวจสอบข้อมูลคลิปไม่สำเร็จ กรุณาลองอีกครั้งหรือเลือกคลิปใหม่',
  ]);
  final String message;
  @override
  String toString() => message;
}

class PublishMediaProbeTask {
  const PublishMediaProbeTask({required this.result, required this.cancel});
  final Future<Map<dynamic, dynamic>> result;
  final Future<void> Function() cancel;
}

double? _positiveNumber(Object? value) {
  final parsed = double.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
}

int? _positiveInteger(Object? value) {
  final parsed = int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _frameRate(Object? value) {
  final parts = '$value'.split('/');
  if (parts.length > 2) return null;
  final numerator = _positiveNumber(parts.first);
  final denominator = parts.length == 1 ? 1.0 : _positiveNumber(parts.last);
  if (numerator == null || denominator == null) return null;
  final rate = numerator / denominator;
  return rate.isFinite && rate > 0 ? rate : null;
}

String? _metadataString(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 128 ? value : null;

PublishMediaMetadata readPublishMediaMetadata(Map<dynamic, dynamic> properties,
    {required int sizeBytes}) {
  final streams = properties['streams'];
  final entries = streams is List ? streams.whereType<Map>() : <Map>[];
  final videos = entries.where((stream) {
    final disposition = stream['disposition'];
    return stream['codec_type'] == 'video' &&
        !(disposition is Map && '${disposition['attached_pic']}' == '1');
  });
  final audios = entries.where((stream) => stream['codec_type'] == 'audio');
  final video = videos.firstOrNull;
  final audio = audios.firstOrNull;
  final format = properties['format'];
  final duration = _positiveNumber(video?['duration']) ??
      _positiveNumber(format is Map ? format['duration'] : null);
  final width = _positiveInteger(video?['width']);
  final height = _positiveInteger(video?['height']);
  final dimensions = width == null || height == null
      ? null
      : displayOrientedVideoDimensions(
          width: width,
          height: height,
          streamProperties: video,
          durationSeconds: duration);
  return PublishMediaMetadata(
    durationSeconds: duration,
    width: dimensions?.width,
    height: dimensions?.height,
    sizeBytes: sizeBytes,
    hasVideo: video != null,
    hasAudio: audio != null,
    videoCodec: _metadataString(video?['codec_name']),
    audioCodec: _metadataString(audio?['codec_name']),
    fps: _frameRate(video?['avg_frame_rate']) ??
        _frameRate(video?['r_frame_rate']),
    sampleRate: _positiveInteger(audio?['sample_rate']),
    channels: _positiveInteger(audio?['channels']),
    container: _metadataString(format is Map ? format['format_name'] : null),
  );
}

Future<PublishMediaProbeTask> _nativeProbe(String path) async {
  final session = await FFprobeSession.create([
    '-v',
    'error',
    '-print_format',
    'json',
    '-show_entries',
    'format=duration,format_name:stream=codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,duration,sample_rate,channels:stream_tags=rotate:stream_side_data=rotation:stream_disposition=attached_pic',
    '-i',
    path,
  ]);
  final sessionId = session.getSessionId();
  if (sessionId == null) throw const PublishMediaProbeException();
  final result = () async {
    // This awaits this session's MethodChannel completion, rather than global
    // plugin events that might be delivered to a different Flutter engine.
    await FFmpegKitConfig.ffprobeExecute(session);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw const PublishMediaProbeException();
    }
    final output = await session.getOutput();
    if (output == null || output.length > 131072) {
      throw const PublishMediaProbeException();
    }
    final decoded = jsonDecode(output);
    if (decoded is! Map) throw const PublishMediaProbeException();
    return decoded;
  }();
  return PublishMediaProbeTask(
      result: result, cancel: () => FFmpegKit.cancel(sessionId));
}

class FfmpegPublishMediaProbe {
  const FfmpegPublishMediaProbe({
    this.runProbe,
    this.timeout = const Duration(seconds: 15),
    this.cancelTimeout = const Duration(seconds: 2),
  });
  final PublishMediaProbeRunner? runProbe;
  final Duration timeout;
  final Duration cancelTimeout;

  Future<void> _cancel(PublishMediaProbeTask task) async {
    // A late-created native result may still finish with an error after this
    // caller has timed out. Observe it even when no caller can await it now.
    unawaited(
        task.result.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      await task.cancel().timeout(cancelTimeout);
    } catch (_) {
      // Cancellation is best effort and is always scoped to this session ID.
    }
  }

  Future<PublishMediaMetadata> call(File file) async {
    PublishMediaProbeTask? task;
    var expired = false;
    try {
      final sizeBytes = await file.length();
      if (sizeBytes <= 0) throw const PublishMediaProbeException();
      final operation = () async {
        final started = await (runProbe ?? _nativeProbe)(file.path);
        if (expired) {
          await _cancel(started);
          throw const PublishMediaProbeException();
        }
        task = started;
        return await started.result;
      }();
      final properties = await operation.timeout(timeout);
      return readPublishMediaMetadata(properties, sizeBytes: sizeBytes);
    } on TimeoutException {
      expired = true;
      if (task != null) await _cancel(task!);
      throw const PublishMediaProbeException();
    } catch (_) {
      throw const PublishMediaProbeException();
    }
  }
}
