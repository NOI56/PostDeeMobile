import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:postdee_mobile/features/uploader/video_picker_service.dart';

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.video);

  final XFile? video;

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    expect(source, ImageSource.gallery);
    return video;
  }
}

void main() {
  test('adds real video dimensions from the metadata reader', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'vertical-demo.mp4'),
      ),
      readVideoDimensions: (path) async {
        expect(path, videoFile.path);
        return const VideoDimensions(
          width: 1080,
          height: 1920,
          durationSeconds: 150.5,
        );
      },
    );

    final pickedVideo = await picker.pickVideo();

    expect(
        pickedVideo?.name, videoFile.path.split(Platform.pathSeparator).last);
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
    expect(pickedVideo?.width, 1080);
    expect(pickedVideo?.height, 1920);
    expect(pickedVideo?.durationSeconds, 150.5);
  });

  test('retries a transient metadata exception once', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var metadataCalls = 0;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'retry-demo.mp4'),
      ),
      readVideoDimensions: (_) async {
        metadataCalls += 1;
        if (metadataCalls == 1) {
          throw const VideoMetadataException();
        }
        return const VideoDimensions(
          width: 1080,
          height: 1920,
          durationSeconds: 150.5,
        );
      },
      metadataRetryDelay: Duration.zero,
    );

    final pickedVideo = await picker.pickVideo();

    expect(metadataCalls, 2);
    expect(pickedVideo?.width, 1080);
    expect(pickedVideo?.height, 1920);
    expect(pickedVideo?.durationSeconds, 150.5);
  });

  test('retries missing metadata once', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var metadataCalls = 0;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'retry-null-demo.mp4'),
      ),
      readVideoDimensions: (_) async {
        metadataCalls += 1;
        if (metadataCalls == 1) {
          return null;
        }
        return const VideoDimensions(
          width: 1080,
          height: 1920,
          durationSeconds: 150.5,
        );
      },
      metadataRetryDelay: Duration.zero,
    );

    final pickedVideo = await picker.pickVideo();

    expect(metadataCalls, 2);
    expect(pickedVideo?.durationSeconds, 150.5);
  });

  test('retries metadata when the duration is missing', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var metadataCalls = 0;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'retry-duration-demo.mp4'),
      ),
      readVideoDimensions: (_) async {
        metadataCalls += 1;
        if (metadataCalls == 1) {
          return const VideoDimensions(
            width: 1080,
            height: 1920,
          );
        }
        return const VideoDimensions(
          width: 1080,
          height: 1920,
          durationSeconds: 150.5,
        );
      },
      metadataRetryDelay: Duration.zero,
    );

    final pickedVideo = await picker.pickVideo();

    expect(metadataCalls, 2);
    expect(pickedVideo?.width, 1080);
    expect(pickedVideo?.height, 1920);
    expect(pickedVideo?.durationSeconds, 150.5);
  });

  test('still returns the picked video when metadata reading fails', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var metadataCalls = 0;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'unknown-demo.mp4'),
      ),
      readVideoDimensions: (_) async {
        metadataCalls += 1;
        throw const VideoMetadataException();
      },
      metadataRetryDelay: Duration.zero,
    );

    final pickedVideo = await picker.pickVideo();

    expect(
        pickedVideo?.name, videoFile.path.split(Platform.pathSeparator).last);
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
    expect(pickedVideo?.width, isNull);
    expect(pickedVideo?.height, isNull);
    expect(pickedVideo?.durationSeconds, isNull);
    expect(metadataCalls, 2);
  });
}
