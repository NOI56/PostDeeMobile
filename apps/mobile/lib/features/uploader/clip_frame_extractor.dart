import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';

import '../ai_editing/video_duration_probe.dart';

/// Extracts a few still frames from a local clip. Used for Pro AI captioning
/// where Gemini also "looks at" selected frames. Injectable so the uploader can
/// be tested without the native FFmpeg plugin.
typedef UploaderClipFrameExtractor = Future<List<File>> Function(
  File videoFile, {
  int maxFrames,
});

typedef ClipFrameFfmpegRunner = Future<bool> Function(List<String> arguments);

class FfmpegClipFrameExtractor {
  FfmpegClipFrameExtractor({
    VideoDurationProbe? probeDuration,
    ClipFrameFfmpegRunner? runFfmpeg,
  })  : probeDuration = probeDuration ?? const FfprobeVideoDurationProbe().call,
        runFfmpeg = runFfmpeg ?? _runNativeFfmpeg;

  final VideoDurationProbe probeDuration;
  final ClipFrameFfmpegRunner runFfmpeg;

  Future<List<File>> call(File videoFile, {int maxFrames = 3}) async {
    if (maxFrames < 1 || !await videoFile.exists()) {
      return const [];
    }

    final directory = await Directory.systemTemp.createTemp('postdee-frames-');
    final duration = await probeDuration(videoFile);
    final timestamps = _frameTimestamps(duration, maxFrames);
    final frames = <File>[];

    for (var index = 0; index < timestamps.length; index += 1) {
      final output = File(
        '${directory.path}${Platform.pathSeparator}frame_${index + 1}.jpg',
      );
      // Fast-seek before input, grab a single frame as a JPEG. 720 px wide
      // keeps each frame well under the API's 1 MiB AI caption frame limit.
      // Separate arguments keep paths with quotes or spaces intact.
      final succeeded = await runFfmpeg([
        '-y',
        '-ss',
        timestamps[index].toStringAsFixed(2),
        '-i',
        videoFile.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=720:-2',
        '-q:v',
        '3',
        output.path,
      ]);

      if (succeeded && await output.exists()) {
        frames.add(output);
      }
    }

    return frames;
  }

  // Evenly spaced sample points across the clip, avoiding the very first and
  // last frame. Falls back to a single frame at the start if duration is unknown.
  List<double> _frameTimestamps(double? duration, int maxFrames) {
    if (duration == null || duration <= 0) {
      return const [0];
    }

    return [
      for (var index = 1; index <= maxFrames; index += 1)
        duration * index / (maxFrames + 1),
    ];
  }
}

Future<bool> _runNativeFfmpeg(List<String> arguments) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  return ReturnCode.isSuccess(await session.getReturnCode());
}
