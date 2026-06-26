import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Renders a sticker (emoji) to a PNG file on device. Injectable so the editor
/// can be tested without the real rasterizer.
typedef StickerRasterizer = Future<File> Function(String sticker);

/// Default [StickerRasterizer] that paints the emoji with the platform's own
/// color-emoji font (so we don't have to bundle a multi-MB emoji font), then
/// writes a transparent PNG ready for FFmpeg's `overlay` filter.
class FlutterEmojiStickerRasterizer {
  const FlutterEmojiStickerRasterizer({this.sizePx = 96});

  /// Square canvas size for each rendered sticker, in pixels.
  final int sizePx;

  Future<File> call(String sticker) async {
    final bytes = await _renderPng(sticker);
    final directory =
        await Directory.systemTemp.createTemp('postdee-sticker-');
    final file =
        File('${directory.path}${Platform.pathSeparator}sticker.png');
    await file.writeAsBytes(bytes);

    return file;
  }

  Future<Uint8List> _renderPng(String sticker) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      text: TextSpan(
        text: sticker,
        style: TextStyle(fontSize: sizePx * 0.78),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    painter.paint(
      canvas,
      Offset((sizePx - painter.width) / 2, (sizePx - painter.height) / 2),
    );

    final image = await recorder.endRecording().toImage(sizePx, sizePx);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    if (data == null) {
      throw StateError('Failed to rasterize sticker "$sticker"');
    }

    return data.buffer.asUint8List();
  }
}
