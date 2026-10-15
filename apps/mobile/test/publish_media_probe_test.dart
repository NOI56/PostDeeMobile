import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/publish_media_probe.dart';

Map<String, Object?> _properties() => {
      'format': {'duration': '10.5', 'format_name': 'mov,mp4,m4a,3gp,3g2,mj2'},
      'streams': [
        {
          'codec_type': 'video',
          'codec_name': 'h264',
          'width': 1920,
          'height': 1080,
          'avg_frame_rate': '30000/1001',
          'side_data_list': [
            {'rotation': -90}
          ]
        },
        {
          'codec_type': 'audio',
          'codec_name': 'aac',
          'sample_rate': '48000',
          'channels': 2
        },
      ],
    };

void main() {
  test('probe parser reads actual streams, rotation and rational frame rate',
      () {
    final value = readPublishMediaMetadata(_properties(), sizeBytes: 4096);
    expect(value.hasVideo, isTrue);
    expect(value.hasAudio, isTrue);
    expect(value.width, 1080);
    expect(value.height, 1920);
    expect(value.durationSeconds, 10.5);
    expect(value.videoCodec, 'h264');
    expect(value.audioCodec, 'aac');
    expect(value.sampleRate, 48000);
    expect(value.channels, 2);
    expect(value.fps, closeTo(29.97003, .0001));
    expect(value.sizeBytes, 4096);
    expect(value.container, contains('mp4'));
  });

  test(
      'probe parser leaves missing metadata unknown and ignores attached pictures',
      () {
    final value = readPublishMediaMetadata({
      'streams': [
        {
          'codec_type': 'video',
          'width': 200,
          'height': 200,
          'disposition': {'attached_pic': 1}
        },
        {'codec_type': 'audio', 'codec_name': 'aac'},
      ],
    }, sizeBytes: 1);
    expect(value.hasVideo, isFalse);
    expect(value.durationSeconds, isNull);
    expect(value.width, isNull);
    expect(value.hasAudio, isTrue);
    expect(value.sampleRate, isNull);
  });

  test('probe parser rejects unusable duration/frame rates as unknown', () {
    final properties = _properties();
    properties['format'] = {'duration': 'NaN'};
    (properties['streams'] as List).first['avg_frame_rate'] = '1/0';
    final value = readPublishMediaMetadata(properties, sizeBytes: 1);
    expect(value.durationSeconds, isNull);
    expect(value.fps, isNull);
  });

  test('probe timeout cancels only its own session and reports safe retry',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('publish-probe-test-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes([1]);
    var cancelled = 0;
    try {
      final probe = FfmpegPublishMediaProbe(
        timeout: const Duration(milliseconds: 5),
        runProbe: (_) async => PublishMediaProbeTask(
          result: Completer<Map<dynamic, dynamic>>().future,
          cancel: () async {
            cancelled++;
          },
        ),
      );
      await expectLater(
          probe(file), throwsA(isA<PublishMediaProbeException>()));
      expect(cancelled, 1);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('probe cancels a late starting native session after its deadline',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('publish-probe-test-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes([1]);
    final started = Completer<PublishMediaProbeTask>();
    final result = Completer<Map<dynamic, dynamic>>();
    var cancelled = 0;
    try {
      final probe = FfmpegPublishMediaProbe(
        timeout: const Duration(milliseconds: 5),
        runProbe: (_) => started.future,
      );
      await expectLater(
          probe(file), throwsA(isA<PublishMediaProbeException>()));
      started.complete(PublishMediaProbeTask(
          result: result.future,
          cancel: () async {
            cancelled++;
          }));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      result.completeError(StateError('cancelled-native-operation'));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, 1);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('probe reads actual size and sanitizes parser/native errors', () async {
    final directory =
        await Directory.systemTemp.createTemp('publish-probe-test-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes([1, 2, 3]);
    try {
      final probe = FfmpegPublishMediaProbe(
          runProbe: (_) async => PublishMediaProbeTask(
              result: Future.value(_properties()), cancel: () async {}));
      expect((await probe(file)).sizeBytes, 3);
      final failed = FfmpegPublishMediaProbe(
          runProbe: (_) async => throw StateError('private-file-path'));
      await expectLater(
          failed(file),
          throwsA(isA<PublishMediaProbeException>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('private-file-path')))));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
