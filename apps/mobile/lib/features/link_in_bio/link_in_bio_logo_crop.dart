import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'link_in_bio_image_picker.dart';

/// The same source rectangle drives the circular preview and saved PNG.
Rect linkInBioLogoCropRect(Size imageSize, {double zoom = 1, Offset? center}) {
  final side = imageSize.shortestSide / zoom.clamp(1.0, 4.0);
  final half = side / 2;
  final focus = center ?? imageSize.center(Offset.zero);
  return Rect.fromLTWH(focus.dx.clamp(half, imageSize.width - half) - half,
      focus.dy.clamp(half, imageSize.height - half) - half, side, side);
}

Future<Uint8List> cropLinkInBioLogo(ui.Image image, Rect source) async {
  final dimension = math.min(512, source.width.round()).clamp(1, 512);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, dimension.toDouble(), dimension.toDouble()),
      Paint()..filterQuality = FilterQuality.high);
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(dimension, dimension);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const FormatException('บันทึกโลโก้ไม่สำเร็จ');
    return normalizeLinkInBioImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } finally {
    output?.dispose();
    picture.dispose();
  }
}

class LinkInBioLogoCropDialog extends StatefulWidget {
  const LinkInBioLogoCropDialog(
      {super.key, required this.bytes, this.exportImage});

  final Uint8List bytes;
  final Future<Uint8List> Function(ui.Image image, Rect source)? exportImage;

  @override
  State<LinkInBioLogoCropDialog> createState() =>
      _LinkInBioLogoCropDialogState();
}

class _LinkInBioLogoCropDialogState extends State<LinkInBioLogoCropDialog> {
  ui.Image? _image;
  Offset _center = Offset.zero;
  double _zoom = 1;
  double _startZoom = 1;
  Offset _gestureAnchor = Offset.zero;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Size get _imageSize =>
      Size(_image!.width.toDouble(), _image!.height.toDouble());
  Rect get _crop =>
      linkInBioLogoCropRect(_imageSize, zoom: _zoom, center: _center);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.bytes);
      final image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _center = _imageSize.center(Offset.zero);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'เปิดรูปนี้ไม่ได้ กรุณาเลือกรูปอื่น';
        });
      }
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _updateCrop(double zoom, Offset center) {
    setState(() {
      _zoom = zoom.clamp(1.0, 4.0);
      _center =
          linkInBioLogoCropRect(_imageSize, zoom: _zoom, center: center).center;
    });
  }

  Future<void> _confirm() async {
    if (_image == null || _saving) return;
    setState(() => _saving = true);
    final route = ModalRoute.of(context);
    // Keep export alive if the owned dialog is dismissed during encoding.
    final image = _image!.clone();
    try {
      final bytes =
          await (widget.exportImage ?? cropLinkInBioLogo)(image, _crop);
      if (mounted && route?.isCurrent == true) {
        Navigator.of(context).pop(bytes);
      }
    } catch (_) {
      if (mounted && route?.isCurrent == true) {
        setState(() {
          _saving = false;
          _error = 'บันทึกโลโก้ไม่สำเร็จ กรุณาลองใหม่';
        });
      }
    } finally {
      image.dispose();
    }
  }

  Widget _preview(double diameter) => Semantics(
      label: 'ลากรูปเพื่อเลือกตำแหน่งโลโก้ในวงกลม',
      child: GestureDetector(
          key: const ValueKey('link-in-bio-logo-crop-preview'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: _saving
              ? null
              : (details) {
                  _startZoom = _zoom;
                  _gestureAnchor = _crop.center +
                      (details.localFocalPoint -
                              Offset(diameter / 2, diameter / 2)) *
                          (_crop.width / diameter);
                },
          onScaleUpdate: _saving
              ? null
              : (details) {
                  final zoom = (_startZoom * details.scale).clamp(1.0, 4.0);
                  final side = _imageSize.shortestSide / zoom;
                  _updateCrop(
                      zoom,
                      _gestureAnchor -
                          (details.localFocalPoint -
                                  Offset(diameter / 2, diameter / 2)) *
                              (side / diameter));
                },
          child: Container(
              width: diameter,
              height: diameter,
              foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 2)),
              child: ClipOval(
                  child: ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: CustomPaint(
                          painter: _LogoCropPainter(_image!, _crop)))))));

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('ปรับตำแหน่งโลโก้'),
          content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('ลากรูปเพื่อจัดตำแหน่ง จีบหรือเลื่อนแถบเพื่อซูม',
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (_loading) const CircularProgressIndicator(),
                if (_image != null) ...[
                  LayoutBuilder(
                      builder: (context, constraints) => Center(
                          child:
                              _preview(math.min(260, constraints.maxWidth)))),
                  const SizedBox(height: 16),
                  Text('ซูม ${_zoom.toStringAsFixed(1)} เท่า'),
                  Slider(
                      key: const ValueKey('link-in-bio-logo-crop-zoom'),
                      min: 1,
                      max: 4,
                      value: _zoom,
                      label: '${_zoom.toStringAsFixed(1)} เท่า',
                      onChanged: _saving
                          ? null
                          : (value) => _updateCrop(value, _center)),
                  TextButton.icon(
                      key: const ValueKey('link-in-bio-logo-crop-reset'),
                      onPressed: _saving
                          ? null
                          : () =>
                              _updateCrop(1, _imageSize.center(Offset.zero)),
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('กลับตรงกลาง')),
                ],
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                key: const ValueKey('link-in-bio-logo-crop-cancel'),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('ยกเลิก')),
            FilledButton(
                key: const ValueKey('link-in-bio-logo-crop-confirm'),
                onPressed: _image == null || _saving ? null : _confirm,
                child: Text(_saving ? 'กำลังบันทึก…' : 'ใช้โลโก้นี้')),
          ]);
}

class _LogoCropPainter extends CustomPainter {
  const _LogoCropPainter(this.image, this.source);
  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(image, source,
      Offset.zero & size, Paint()..filterQuality = FilterQuality.high);

  @override
  bool shouldRepaint(_LogoCropPainter oldDelegate) =>
      image != oldDelegate.image || source != oldDelegate.source;
}
