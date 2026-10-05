import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'normalizer resizes detailed source to a bounded PNG without full-size upload',
      () async {
    const width = 1800, height = 900;
    final rgba = Uint8List(width * height * 4);
    var random = 12345;
    for (var pixel = 0; pixel < width * height; pixel++) {
      for (var channel = 0; channel < 3; channel++) {
        random = (random * 1664525 + 1013904223) & 0xffffffff;
        rgba[pixel * 4 + channel] = random >> 24;
      }
      rgba[pixel * 4 + 3] = 255;
    }
    final pending = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        rgba, width, height, ui.PixelFormat.rgba8888, pending.complete);
    final image = await pending.future;
    final source = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    final png = await normalizeLinkInBioImage(source);
    expect(png.length, lessThanOrEqualTo(512 * 1024));
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(png);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, lessThanOrEqualTo(1280));
    expect(descriptor.height, lessThanOrEqualTo(1280));
    expect(descriptor.width / descriptor.height, closeTo(2, .01));
    descriptor.dispose();
    buffer.dispose();
  });
  test('source cap is enforced before image decoding', () async {
    expect(normalizeLinkInBioImage(Uint8List(20 * 1024 * 1024 + 1)),
        throwsFormatException);
  });
}
