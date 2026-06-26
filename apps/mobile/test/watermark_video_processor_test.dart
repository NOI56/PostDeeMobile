import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/watermark_video_processor.dart';

void main() {
  test('creates a processor without invoking native FFmpeg', () {
    expect(
        FfmpegWatermarkVideoProcessor(), isA<FfmpegWatermarkVideoProcessor>());
  });
}
