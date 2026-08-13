import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

typedef UploaderVideoPicker = Future<PickedVideoFile?> Function();
typedef VideoMetadataReader =
    Future<VideoDimensions?> Function(String videoPath);

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

bool isVerticalNineBySixteen({required int width, required int height}) {
  if (width < 1 || height < 1 || height <= width) return false;

  final expectedHeight = width * 16 / 9;
  final tolerance = expectedHeight * 0.02;
  return (height - expectedHeight).abs() <= tolerance;
}

VideoDimensions displayOrientedVideoDimensions({
  required int width,
  required int height,
  Map<dynamic, dynamic>? streamProperties,
  double? durationSeconds,
}) {
  final rotation = _readVideoRotationDegrees(streamProperties);
  final normalizedRotation = ((rotation.round() % 360) + 360) % 360;
  final swapsDimensions = normalizedRotation == 90 || normalizedRotation == 270;

  return VideoDimensions(
    width: swapsDimensions ? height : width,
    height: swapsDimensions ? width : height,
    durationSeconds: durationSeconds,
  );
}

/// Resolves the dimensions viewers see when FFprobe omits an MP4 display
/// matrix. Android's video player reports a display-oriented size, while the
/// encoded stream may still look landscape for a portrait phone recording.
Future<VideoDimensions> resolveVideoDimensionsForDisplay({
  required String videoPath,
  required int width,
  required int height,
  required Map<dynamic, dynamic>? streamProperties,
  required VideoMetadataReader readDisplayDimensions,
  double? durationSeconds,
}) async {
  final ffprobeDimensions = displayOrientedVideoDimensions(
    width: width,
    height: height,
    streamProperties: streamProperties,
    durationSeconds: durationSeconds,
  );

  if (_readVideoRotationDegreesOrNull(streamProperties) != null ||
      width <= height) {
    return ffprobeDimensions;
  }

  try {
    final displayDimensions = await readDisplayDimensions(videoPath);
    if (displayDimensions != null &&
        displayDimensions.width > 0 &&
        displayDimensions.height > 0) {
      return VideoDimensions(
        width: displayDimensions.width,
        height: displayDimensions.height,
        durationSeconds: durationSeconds,
      );
    }
  } catch (_) {
    // FFprobe dimensions remain useful when the player cannot initialize.
  }

  return ffprobeDimensions;
}

double _readVideoRotationDegrees(Map<dynamic, dynamic>? streamProperties) {
  return _readVideoRotationDegreesOrNull(streamProperties) ?? 0;
}

double? _readVideoRotationDegreesOrNull(
  Map<dynamic, dynamic>? streamProperties,
) {
  if (streamProperties == null) return null;

  final directRotation = _readRotationNumber(
    streamProperties['rotation'] ?? streamProperties['rotation_angle'],
  );
  if (directRotation != null) return directRotation;

  final sideData = streamProperties['side_data_list'];
  if (sideData is List) {
    for (final entry in sideData) {
      if (entry is Map) {
        final rotation = _readRotationNumber(
          entry['rotation'] ?? entry['rotation_angle'],
        );
        if (rotation != null) {
          return rotation;
        }
      }
    }
  }

  final tags = streamProperties['tags'];
  if (tags is Map) {
    return _readRotationNumber(tags['rotate'] ?? tags['rotation']);
  }
  return null;
}

double? _readRotationNumber(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return value is String ? double.tryParse(value.trim()) : null;
}

class VideoMetadataException implements Exception {
  const VideoMetadataException([this.message = 'อ่านขนาดวิดีโอไม่ได้']);

  final String message;

  @override
  String toString() => message;
}

class VideoPlayerDisplayDimensionsReader {
  const VideoPlayerDisplayDimensionsReader();

  Future<VideoDimensions?> call(String videoPath) async {
    final controller = VideoPlayerController.file(File(videoPath));
    try {
      await controller.initialize();
      final size = controller.value.size;
      final width = size.width.round();
      final height = size.height.round();
      if (width < 1 || height < 1) return null;

      return VideoDimensions(width: width, height: height);
    } finally {
      await controller.dispose();
    }
  }
}

class FfmpegVideoMetadataReader {
  const FfmpegVideoMetadataReader({this.readDisplayDimensions});

  final VideoMetadataReader? readDisplayDimensions;

  Future<VideoDimensions?> call(String videoPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final mediaInformation = session.getMediaInformation();

      if (mediaInformation == null) {
        return null;
      }

      final rawDuration = mediaInformation.getDuration();
      final parsedDuration = rawDuration == null
          ? null
          : double.tryParse(rawDuration);
      final durationSeconds = parsedDuration != null && parsedDuration > 0
          ? parsedDuration
          : null;

      for (final stream in mediaInformation.getStreams()) {
        if (stream.getType() != 'video') {
          continue;
        }

        final width = stream.getWidth();
        final height = stream.getHeight();

        if (width == null || height == null || width < 1 || height < 1) {
          continue;
        }

        return resolveVideoDimensionsForDisplay(
          videoPath: videoPath,
          width: width,
          height: height,
          streamProperties: stream.getAllProperties(),
          durationSeconds: durationSeconds,
          readDisplayDimensions:
              readDisplayDimensions ??
              const VideoPlayerDisplayDimensionsReader().call,
        );
      }

      return null;
    } catch (_) {
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
  }) : _imagePicker = imagePicker ?? ImagePicker(),
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
        // A native FFprobe session can fail briefly after gallery selection.
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
