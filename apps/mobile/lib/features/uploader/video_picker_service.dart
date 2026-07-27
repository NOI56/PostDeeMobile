import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

typedef UploaderVideoPicker = Future<PickedVideoFile?> Function();
typedef VideoMetadataReader = Future<VideoDimensions?> Function(
  String videoPath,
);

const _videoMetadataReadAttempts = 2;
const _defaultVideoMetadataRetryDelay = Duration(milliseconds: 200);

class VideoDimensions {
  const VideoDimensions({
    required this.width,
    required this.height,
    this.durationSeconds,
  });

  final int width;
  final int height;
  final double? durationSeconds;
}

class VideoMetadataException implements Exception {
  const VideoMetadataException([this.message = 'อ่านขนาดวิดีโอไม่ได้']);

  final String message;

  @override
  String toString() => message;
}

class FfmpegVideoMetadataReader {
  const FfmpegVideoMetadataReader();

  Future<VideoDimensions?> call(String videoPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final mediaInformation = session.getMediaInformation();

      if (mediaInformation == null) {
        return null;
      }

      final rawDuration = mediaInformation.getDuration();
      final parsedDuration =
          rawDuration == null ? null : double.tryParse(rawDuration);
      final durationSeconds =
          parsedDuration != null && parsedDuration > 0 ? parsedDuration : null;

      for (final stream in mediaInformation.getStreams()) {
        if (stream.getType() != 'video') {
          continue;
        }

        final width = stream.getWidth();
        final height = stream.getHeight();

        if (width == null || height == null || width < 1 || height < 1) {
          continue;
        }

        return VideoDimensions(
          width: width,
          height: height,
          durationSeconds: durationSeconds,
        );
      }

      return null;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Video metadata probe failed: ${error.runtimeType}: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      throw const VideoMetadataException();
    }
  }
}

class PickedVideoFile {
  const PickedVideoFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final int? width;
  final int? height;
  final double? durationSeconds;
}

class GalleryVideoPicker {
  GalleryVideoPicker({
    ImagePicker? imagePicker,
    VideoMetadataReader? readVideoDimensions,
    Duration metadataRetryDelay = _defaultVideoMetadataRetryDelay,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _readVideoDimensions =
            readVideoDimensions ?? const FfmpegVideoMetadataReader().call,
        _metadataRetryDelay = metadataRetryDelay;

  final ImagePicker _imagePicker;
  final VideoMetadataReader _readVideoDimensions;
  final Duration _metadataRetryDelay;

  Future<PickedVideoFile?> pickVideo() async {
    final video = await _imagePicker.pickVideo(source: ImageSource.gallery);

    if (video == null) {
      return null;
    }

    final dimensions = await _readMetadataWithRetry(video.path);

    return PickedVideoFile(
      name: video.name,
      path: video.path,
      sizeBytes: await video.length(),
      width: dimensions?.width,
      height: dimensions?.height,
      durationSeconds: dimensions?.durationSeconds,
    );
  }

  Future<VideoDimensions?> _readMetadataWithRetry(String videoPath) async {
    VideoDimensions? partialDimensions;
    for (var attempt = 1; attempt <= _videoMetadataReadAttempts; attempt += 1) {
      try {
        final dimensions = await _readVideoDimensions(videoPath);
        if (dimensions != null &&
            _hasUsableDuration(dimensions.durationSeconds)) {
          return dimensions;
        }
        partialDimensions ??= dimensions;
      } on VideoMetadataException {
        // A native FFprobe session can fail briefly after the gallery resumes.
      }

      if (attempt < _videoMetadataReadAttempts &&
          _metadataRetryDelay != Duration.zero) {
        await Future<void>.delayed(_metadataRetryDelay);
      }
    }
    return partialDimensions;
  }
}

bool _hasUsableDuration(double? durationSeconds) =>
    durationSeconds != null && durationSeconds.isFinite && durationSeconds > 0;
