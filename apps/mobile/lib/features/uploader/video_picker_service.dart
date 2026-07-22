import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:image_picker/image_picker.dart';

typedef UploaderVideoPicker = Future<PickedVideoFile?> Function();
typedef VideoMetadataReader = Future<VideoDimensions?> Function(
  String videoPath,
);

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
      durationSeconds: dimensions?.durationSeconds,
    );
  }
}
