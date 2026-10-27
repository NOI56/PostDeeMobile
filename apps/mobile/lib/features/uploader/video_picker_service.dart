import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

typedef UploaderVideoPicker = Future<PickedVideoFile?> Function();
typedef VideoMetadataReader = Future<VideoDimensions?> Function(
  String videoPath,
);

class VideoDimensions {
  const VideoDimensions({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

bool isVerticalNineBySixteen({
  required int width,
  required int height,
}) {
  if (width < 1 || height < 1 || height <= width) {
    return false;
  }

  final expectedHeight = width * 16 / 9;
  final tolerance = expectedHeight * 0.02;
  return (height - expectedHeight).abs() <= tolerance;
}

/// Returns the dimensions as viewers see the clip after applying its rotation
/// metadata. Phones commonly encode a portrait clip as landscape pixels plus
/// a 90/270-degree display rotation.
VideoDimensions videoDimensionsForDisplay({
  required int width,
  required int height,
  Map<dynamic, dynamic>? metadata,
}) {
  final rotation = _readVideoRotation(metadata);
  final normalizedRotation =
      rotation == null ? 0 : ((rotation % 360) + 360) % 360;

  if (normalizedRotation == 90 || normalizedRotation == 270) {
    return VideoDimensions(width: height, height: width);
  }

  return VideoDimensions(width: width, height: height);
}

/// Resolves the displayed dimensions when FFprobe cannot expose an MP4 display
/// matrix on a native build. Only encoded landscape clips are ambiguous: a
/// physically portrait clip needs no fallback, while a landscape stream may be
/// either truly landscape or a phone recording rotated by metadata.
Future<VideoDimensions> resolveVideoDimensionsForDisplay({
  required String videoPath,
  required int width,
  required int height,
  required Map<dynamic, dynamic>? metadata,
  required VideoMetadataReader readDisplayDimensions,
}) async {
  final ffprobeDimensions = videoDimensionsForDisplay(
    width: width,
    height: height,
    metadata: metadata,
  );
  if (_readVideoRotation(metadata) != null || width <= height) {
    return ffprobeDimensions;
  }

  try {
    final displayDimensions = await readDisplayDimensions(videoPath);
    if (displayDimensions != null &&
        displayDimensions.width > 0 &&
        displayDimensions.height > 0) {
      return displayDimensions;
    }
  } catch (_) {
    // FFprobe dimensions remain useful when the player cannot initialize.
  }

  return ffprobeDimensions;
}

int? _readVideoRotation(Map<dynamic, dynamic>? metadata) {
  if (metadata == null) {
    return null;
  }

  final directRotation = _parseRotation(
    metadata['rotation'] ?? metadata['rotation_angle'],
  );
  if (directRotation != null) {
    return directRotation;
  }

  final tags = metadata['tags'];
  if (tags is Map) {
    final tagRotation = _parseRotation(tags['rotate'] ?? tags['rotation']);
    if (tagRotation != null) {
      return tagRotation;
    }
  }

  final sideData = metadata['side_data_list'];
  if (sideData is Iterable) {
    for (final entry in sideData) {
      if (entry is! Map) {
        continue;
      }

      final sideDataRotation = _parseRotation(
        entry['rotation'] ?? entry['rotation_angle'],
      );
      if (sideDataRotation != null) {
        return sideDataRotation;
      }
    }
  }

  return null;
}

int? _parseRotation(dynamic value) {
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return double.tryParse(value.trim())?.round();
  }
  return null;
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
      if (width < 1 || height < 1) {
        return null;
      }

      // video_player_android obtains this from Media3 VideoSize, whose width
      // and height already account for the stream's display rotation.
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
          metadata: stream.getAllProperties(),
          readDisplayDimensions: readDisplayDimensions ??
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
  });

  final String name;
  final String path;
  final int sizeBytes;
  final int? width;
  final int? height;
}

class GalleryVideoPicker {
  GalleryVideoPicker({
    ImagePicker? imagePicker,
    VideoMetadataReader? readVideoDimensions,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _readVideoDimensions =
            readVideoDimensions ?? const FfmpegVideoMetadataReader().call;

  final ImagePicker _imagePicker;
  final VideoMetadataReader _readVideoDimensions;

  Future<PickedVideoFile?> pickVideo() async {
    final video = await _imagePicker.pickVideo(source: ImageSource.gallery);

    if (video == null) {
      return null;
    }

    VideoDimensions? dimensions;

    try {
      dimensions = await _readVideoDimensions(video.path);
    } on VideoMetadataException {
      dimensions = null;
    }

    return PickedVideoFile(
      name: video.name,
      path: video.path,
      sizeBytes: await video.length(),
      width: dimensions?.width,
      height: dimensions?.height,
    );
  }
}
