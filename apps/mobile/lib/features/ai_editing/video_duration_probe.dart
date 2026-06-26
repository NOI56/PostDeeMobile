import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';

/// Reads the duration (in seconds) of a local video file. Returns null when the
/// duration cannot be determined. Injectable so the editor can be tested without
/// the native FFprobe plugin.
typedef VideoDurationProbe = Future<double?> Function(File videoFile);

/// Default [VideoDurationProbe] backed by FFprobe media information, mirroring
/// the dimension reader used by the gallery picker.
class FfprobeVideoDurationProbe {
  const FfprobeVideoDurationProbe();

  Future<double?> call(File videoFile) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoFile.path);
      final mediaInformation = session.getMediaInformation();
      final rawDuration = mediaInformation?.getDuration();

      if (rawDuration == null) {
        return null;
      }

      final seconds = double.tryParse(rawDuration);

      if (seconds == null || seconds <= 0) {
        return null;
      }

      return seconds;
    } catch (_) {
      return null;
    }
  }
}
