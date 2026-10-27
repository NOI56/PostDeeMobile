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
  group('videoDimensionsForDisplay', () {
    test('swaps encoded dimensions for a 90-degree tag rotation', () {
      final dimensions = videoDimensionsForDisplay(
        width: 1920,
        height: 1080,
        metadata: const {
          'tags': {'rotate': '90'},
        },
      );

      expect(dimensions.width, 1080);
      expect(dimensions.height, 1920);
    });

    test('swaps encoded dimensions for a 270-degree side-data rotation', () {
      final dimensions = videoDimensionsForDisplay(
        width: 1920,
        height: 1080,
        metadata: const {
          'side_data_list': [
            {'rotation': -90},
          ],
        },
      );

      expect(dimensions.width, 1080);
      expect(dimensions.height, 1920);
    });

    test('keeps dimensions for a 180-degree rotation', () {
      final dimensions = videoDimensionsForDisplay(
        width: 1080,
        height: 1920,
        metadata: const {
          'tags': {'rotate': '180'},
        },
      );

      expect(dimensions.width, 1080);
      expect(dimensions.height, 1920);
    });
  });

  group('resolveVideoDimensionsForDisplay', () {
    test('uses player display size when Android FFprobe drops rotation',
        () async {
      var fallbackCalls = 0;
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'zz-postdee-rotation90.mp4',
        width: 960,
        height: 540,
        // This mirrors the Android ffmpeg-kit map for the rotated fixture:
        // encoded dimensions survive, but side_data_list is missing.
        metadata: const {
          'codec_type': 'video',
          'width': 960,
          'height': 540,
          'display_aspect_ratio': '16:9',
          'tags': {
            'handler_name': 'VideoHandler',
            'language': 'und',
          },
        },
        readDisplayDimensions: (path) async {
          fallbackCalls += 1;
          expect(path, 'zz-postdee-rotation90.mp4');
          return const VideoDimensions(width: 540, height: 960);
        },
      );

      expect(fallbackCalls, 1);
      expect(dimensions.width, 540);
      expect(dimensions.height, 960);
    });

    test('keeps a true landscape display size from the fallback', () async {
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'landscape.mp4',
        width: 960,
        height: 540,
        metadata: const {'codec_type': 'video'},
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
        metadata: const {'codec_type': 'video'},
        readDisplayDimensions: (_) async =>
            throw StateError('player initialization failed'),
      );

      expect(dimensions.width, 960);
      expect(dimensions.height, 540);
    });

    test('does not use fallback when FFprobe includes rotation', () async {
      var fallbackCalls = 0;
      final dimensions = await resolveVideoDimensionsForDisplay(
        videoPath: 'tagged-rotation.mp4',
        width: 960,
        height: 540,
        metadata: const {
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
        return const VideoDimensions(width: 1080, height: 1920);
      },
    );

    final pickedVideo = await picker.pickVideo();

    expect(
        pickedVideo?.name, videoFile.path.split(Platform.pathSeparator).last);
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
    expect(pickedVideo?.width, 1080);
    expect(pickedVideo?.height, 1920);
  });

  test('still returns the picked video when metadata reading fails', () async {
    final videoFile = File('test/uploader_screen_test.dart').absolute;
    final picker = GalleryVideoPicker(
      imagePicker: _FakeImagePicker(
        XFile(videoFile.path, name: 'unknown-demo.mp4'),
      ),
      readVideoDimensions: (_) async => throw const VideoMetadataException(),
    );

    final pickedVideo = await picker.pickVideo();

    expect(
        pickedVideo?.name, videoFile.path.split(Platform.pathSeparator).last);
    expect(pickedVideo?.path, videoFile.path);
    expect(pickedVideo?.sizeBytes, videoFile.lengthSync());
    expect(pickedVideo?.width, isNull);
    expect(pickedVideo?.height, isNull);
  });
}
