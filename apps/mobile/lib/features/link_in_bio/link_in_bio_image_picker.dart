import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

/// Uploads use PNG so the editor and public page render the same pixels.
Future<Uint8List?> pickLinkInBioImage() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('เลือกรูปที่มีขนาดไม่เกิน 20 MB');
  }
  return normalizeLinkInBioImage(await file.readAsBytes());
}

Future<Uint8List> normalizeLinkInBioImage(Uint8List bytes) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('เลือกรูปที่มีขนาดไม่เกิน 20 MB');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final largest = math.max(descriptor.width, descriptor.height);
    var scale = math.min(1.0, 1280 / largest);
    // Target dimensions keep large source files from being decoded at full size.
    for (var attempt = 0; attempt < 10; attempt++) {
      final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()));
      ui.Image? image;
      try {
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null && data.lengthInBytes <= 512 * 1024) {
          return data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
        }
      } finally {
        image?.dispose();
        codec.dispose();
      }
      scale *= 0.75;
    }
    throw const FormatException(
        'รูปนี้มีรายละเอียดมากเกินไป กรุณาเลือกรูปอื่น');
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
