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
  test('uses display-oriented dimensions for rotated portrait video', () {
    final dimensions = displayOrientedVideoDimensions(
      width: 1920,
      height: 1080,
      streamProperties: const {
        'tags': {'rotate': '90'},
      },
    );

    expect(dimensions.width, 1080);
    expect(dimensions.height, 1920);
  });

  test('reads negative rotation from display-matrix side data', () {
    final dimensions = displayOrientedVideoDimensions(
      width: 1920,
      height: 1080,
      streamProperties: const {
        'side_data_list': [
          {'rotation': -90},
        ],
      },
    );

    expect(dimensions.width, 1080);
    expect(dimensions.height, 1920);
  });

  test('reads rotation from direct stream metadata', () {
    final dimensions = displayOrientedVideoDimensions(
      width: 1920,
      height: 1080,
      streamProperties: const {'rotation_angle': '270'},
    );

    expect(dimensions.width, 1080);
    expect(dimensions.height, 1920);
  });

  group('resolveVideoDimensionsForDisplay', () {
    test(
      'uses player display size when Android FFprobe drops rotation',
      () async {
        var fallbackCalls = 0;
        final dimensions = await resolveVideoDimensionsForDisplay(
          videoPath: 'rotation-90.mp4',
          width: 960,
          height: 540,
          streamProperties: const {
            'codec_type': 'video',
            'width': 960,
            'height': 540,
            'display_aspect_ratio': '16:9',
          },
          durationSeconds: 12.5,
          readDisplayDimensions: (path) async {
            fallbackCalls += 1;
            expect(path, 'rotation-90.mp4');
            return const VideoDimensions(width: 540, height: 960);
          },
        );

        expect(fallbackCalls, 1);
        expect(dimensions.width, 540);
        expect(dimensions.height, 960);
        expect(dimensions.durationSeconds, 12.5);
      },
    );

    test('keeps true landscape dimensions returned by the player', () async {
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'landscape.mp4',
        width: 960,
        height: 540,
        streamProperties: const {'codec_type': 'video'},
        readDisplayDimensions: (_) async =>
            const VideoDimensions(width: 960, height: 540),
      );

      expect(dimensions.width, 960);
      expect(dimensions.height, 540);
    });

    test('retains FFprobe dimensions when the player fallback fails', () async {
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'broken-preview.mp4',
        width: 960,
        height: 540,
        streamProperties: const {'codec_type': 'video'},
        durationSeconds: 8,
        readDisplayDimensions: (_) async =>
            throw StateError('player initialization failed'),
      );

      expect(dimensions.width, 960);
      expect(dimensions.height, 540);
      expect(dimensions.durationSeconds, 8);
    });

    test('does not call fallback when FFprobe includes rotation', () async {
      var fallbackCalls = 0;
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'tagged-rotation.mp4',
        width: 960,
        height: 540,
        streamProperties: const {
          'side_data_list': [
            {'rotation': 90},
          ],
        },
        readDisplayDimensions: (_) async {
          fallbackCalls += 1;
          return null;
        },
      );

      expect(fallbackCalls, 0);
      expect(dimensions.width, 540);
      expect(dimensions.height, 960);
    });
  });

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
      pickedVideo?.name,
      videoFile.path.split(Platform.pathSeparator).last,
    );
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
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
      pickedVideo?.name,
      videoFile.path.split(Platform.pathSeparator).last,
    );
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
    expect(pickedVideo?.width, isNull);
    expect(pickedVideo?.height, isNull);
    expect(pickedVideo?.durationSeconds, isNull);
    expect(metadataCalls, 2);
  });

  test('retries missing duration metadata once', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    var metadataCalls = 0;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(XFile(videoFile.path)),
      readVideoDimensions: (_) async {
        metadataCalls += 1;
        return VideoDimensions(
          width: 1080,
          height: 1920,
          durationSeconds: metadataCalls == 1 ? null : 150.5,
        );
      },
      metadataRetryDelay: Duration.zero,
    );

    final pickedVideo = await picker.pickVideo();

    expect(metadataCalls, 2);
    expect(pickedVideo?.durationSeconds, 150.5);
  });
}
