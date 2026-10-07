import 'package:flutter/material.dart';

/// Raster artwork supplies the accepted paper/photo/leaf details. All text,
/// logos, links and page geometry remain native widgets.
Widget bioCompositionArt(String name,
        {double? height, BoxFit fit = BoxFit.cover}) =>
    Image.asset('assets/images/profile_decorations/$name.png',
        height: height,
        width: double.infinity,
        fit: fit,
        excludeFromSemantics: true,
        errorBuilder: (_, error, stack) => SizedBox(height: height));

class BioCompositionClipper extends CustomClipper<Path> {
  const BioCompositionClipper(this.kind);
  final String kind;
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (kind == 'tag') {
      const cut = 24.0;
      return path
        ..moveTo(cut, 0)
        ..lineTo(w - cut, 0)
        ..lineTo(w, cut)
        ..lineTo(w, h - cut)
        ..lineTo(w - cut, h)
        ..lineTo(cut, h)
        ..lineTo(0, h - cut)
        ..lineTo(0, cut)
        ..close();
    }
    if (kind == 'arch') {
      return path
        ..moveTo(0, h)
        ..lineTo(0, w / 2)
        ..quadraticBezierTo(0, 0, w / 2, 0)
        ..quadraticBezierTo(w, 0, w, w / 2)
        ..lineTo(w, h)
        ..close();
    }
    if (kind == 'torn') {
      path
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h - 7);
      for (var x = w; x > 0; x -= 12) {
        path.lineTo(x - 6, h - ((x ~/ 12).isEven ? 1 : 5));
        path.lineTo(x - 12, h - 8);
      }
      return path
        ..lineTo(0, 0)
        ..close();
    }
    if (kind == 'ticket') {
      const r = 12.0;
      return path
        ..moveTo(r, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w - r, r, w, r)
        ..lineTo(w, h / 2 - r)
        ..quadraticBezierTo(w - 24, h / 2, w, h / 2 + r)
        ..lineTo(w, h - r)
        ..quadraticBezierTo(w - r, h - r, w - r, h)
        ..lineTo(r, h)
        ..quadraticBezierTo(r, h - r, 0, h - r)
        ..lineTo(0, h / 2 + r)
        ..quadraticBezierTo(24, h / 2, 0, h / 2 - r)
        ..lineTo(0, r)
        ..quadraticBezierTo(r, r, r, 0)
        ..close();
    }
    if (kind == 'scallop') {
      const edge = 8.0;
      path.moveTo(edge, edge);
      for (var x = edge; x < w - edge; x += 24) {
        path.quadraticBezierTo(
            x + 12, -5, (x + 24).clamp(edge, w - edge), edge);
      }
      for (var y = edge; y < h - edge; y += 24) {
        path.quadraticBezierTo(
            w + 5, y + 12, w - edge, (y + 24).clamp(edge, h - edge));
      }
      for (var x = w - edge; x > edge; x -= 24) {
        path.quadraticBezierTo(
            x - 12, h + 5, (x - 24).clamp(edge, w - edge), h - edge);
      }
      for (var y = h - edge; y > edge; y -= 24) {
        path.quadraticBezierTo(
            -5, y - 12, edge, (y - 24).clamp(edge, h - edge));
      }
      return path..close();
    }
    return path..addRect(Offset.zero & size);
  }

  @override
  bool shouldReclip(covariant BioCompositionClipper oldClipper) =>
      oldClipper.kind != kind;
}

class BioCompositionPattern extends CustomPainter {
  const BioCompositionPattern(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = 1;
    if (kind == 'window') {
      paint.color = color.withValues(alpha: .47);
      const cell = 24.0;
      paint.style = PaintingStyle.fill;
      for (var y = 0.0; y < size.height; y += cell) {
        for (var x = 0.0; x < size.width; x += cell) {
          if (((x / cell + y / cell).round()).isEven) {
            canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
          }
        }
      }
    } else if (kind == 'notebook') {
      for (var y = 28.0; y < size.height; y += 28) {
        canvas.drawLine(Offset(22, y), Offset(size.width, y), paint);
      }
      paint.color = color.withValues(alpha: .45);
      canvas.drawLine(const Offset(18, 0), Offset(18, size.height), paint);
      for (var y = 20.0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(6, y), 3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BioCompositionPattern oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
