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

/// Returned frames are disposable outputs; the selected source clip is retained.
Future<void> cleanupExtractedCaptionFrames(
    List<File> frames, File source) async {
  final parents = <String>{};
  for (final frame in frames) {
    try {
      if (!frame.existsSync() ||
          FileSystemEntity.identicalSync(frame.path, source.path)) {
        continue;
      }
      parents.add(frame.parent.path);
      frame.deleteSync();
    } catch (_) {
      // A cleanup failure must not replace a caption or upload result.
    }
  }
  for (final path in parents) {
    final directory = Directory(path);
    final name = path.replaceAll('\\', '/').split('/').last;
    if (!name.startsWith('postdee-frames-') ||
        directory.parent.absolute.path != Directory.systemTemp.absolute.path) {
      continue;
    }
    try {
      directory.deleteSync();
    } catch (_) {/* Keep non-empty directories. */}
  }
}

class FfmpegClipFrameExtractor {
  FfmpegClipFrameExtractor({VideoDurationProbe? probeDuration})
      : probeDuration = probeDuration ?? const FfprobeVideoDurationProbe().call;

  final VideoDurationProbe probeDuration;

  Future<List<File>> call(File videoFile, {int maxFrames = 3}) async {
    if (maxFrames < 1 || !await videoFile.exists()) {
      return const [];
    }

    final directory = await Directory.systemTemp.createTemp('postdee-frames-');
    var succeeded = false;
    try {
      final duration = await probeDuration(videoFile);
      final timestamps = _frameTimestamps(duration, maxFrames);
      final frames = <File>[];

      for (var index = 0; index < timestamps.length; index += 1) {
        final output = File(
          '${directory.path}${Platform.pathSeparator}frame_${index + 1}.jpg',
        );
        // Fast-seek before input, grab a single frame as a JPEG.
        final command = "-y -ss ${timestamps[index].toStringAsFixed(2)} "
            "-i '${videoFile.path}' -frames:v 1 -q:v 3 '${output.path}'";
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode) && await output.exists()) {
          frames.add(output);
        } else if (await output.exists()) {
          await output.delete();
        }
      }

      succeeded = frames.isNotEmpty;
      return frames;
    } finally {
      if (!succeeded) await directory.delete(recursive: true);
    }
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
