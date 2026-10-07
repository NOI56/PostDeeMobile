import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/link_in_bio_appearance.dart';

typedef BioMotionBuilder = Widget Function(double phase, double entrance,
    bool paused, VoidCallback togglePause, bool reducedMotion);

class BioMotionSurface extends StatefulWidget {
  const BioMotionSurface(
      {super.key, required this.effects, required this.builder});
  final LinkInBioEffects effects;
  final BioMotionBuilder builder;
  @override
  State<BioMotionSurface> createState() => _BioMotionSurfaceState();
}

class _BioMotionSurfaceState extends State<BioMotionSurface>
    with TickerProviderStateMixin {
  late final _ambient =
      AnimationController(vsync: this, duration: const Duration(seconds: 18));
  late final _entrance = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500), value: 1);
  late final _animation = Listenable.merge([_ambient, _entrance]);
  bool _paused = false;
  bool _reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant BioMotionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effects != widget.effects) {
      _paused = false;
      _configure();
    }
  }

  void _configure() {
    _reduced = MediaQuery.disableAnimationsOf(context);
    final active =
        !_reduced && !_paused && TickerMode.valuesOf(context).enabled;
    if (active &&
        (widget.effects.background ||
            widget.effects.featured ||
            widget.effects.stickers != 'none')) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient.stop();
    }
    if (active && widget.effects.entrance) {
      _entrance.forward(from: 0);
    } else {
      _entrance.stop();
      _entrance.value = 1;
    }
  }

  void _togglePause() => setState(() {
        _paused = !_paused;
        _configure();
      });
  @override
  void dispose() {
    _ambient.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => widget.builder(_reduced ? 0 : _ambient.value,
          _entrance.value, _paused, _togglePause, _reduced));
}

class BioDecorations extends StatelessWidget {
  const BioDecorations({super.key, required this.kind, required this.phase});
  final String kind;
  final double phase;
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: ExcludeSemantics(
          child: CustomPaint(painter: _BioDecorationPainter(kind, phase))));
}

class _BioDecorationPainter extends CustomPainter {
  _BioDecorationPainter(this.kind, this.phase);
  final String kind;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    if (kind == 'none') return;
    final points = [
      Offset(size.width * .04, size.height * .05),
      Offset(size.width * .9, size.height * .07),
      Offset(size.width * .05, size.height * .87),
      Offset(size.width * .9, size.height * .88)
    ];
    for (var index = 0; index < points.length; index++) {
      canvas.save();
      canvas.translate(
          points[index].dx,
          points[index].dy -
              5 +
              math.cos(phase * math.pi * 4 + index * 1.4) * 5);
      canvas.scale(index == 1 || index == 2 ? .55 : .7);
      final paint = Paint()
        ..color = (kind == 'flowers'
                ? const Color(0xfff5dce6)
                : kind == 'hearts'
                    ? const Color(0xffed9dbb)
                    : const Color(0xffb89bdb))
            .withValues(alpha: .68);
      if (kind == 'flowers') {
        for (var petal = 0; petal < 5; petal++) {
          canvas.save();
          canvas.translate(20, 20);
          canvas.rotate(petal * math.pi * 2 / 5);
          canvas.drawOval(const Rect.fromLTWH(-7, -20, 14, 20), paint);
          canvas.restore();
        }
        canvas.drawCircle(
            const Offset(20, 20), 5, Paint()..color = const Color(0xffe9bd58));
      } else if (kind == 'sparkles') {
        canvas.drawPath(
            Path()
              ..moveTo(20, 2)
              ..lineTo(25, 14)
              ..lineTo(38, 20)
              ..lineTo(25, 25)
              ..lineTo(20, 38)
              ..lineTo(14, 25)
              ..lineTo(2, 20)
              ..lineTo(14, 14)
              ..close(),
            paint);
      } else {
        canvas.drawPath(
            Path()
              ..moveTo(20, 35)
              ..cubicTo(-4, 20, 4, 2, 15, 7)
              ..lineTo(20, 12)
              ..lineTo(25, 7)
              ..cubicTo(36, 2, 44, 20, 20, 35)
              ..close(),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BioDecorationPainter oldDelegate) =>
      kind != oldDelegate.kind || phase != oldDelegate.phase;
}

Widget bioMotionBackground(
    {required Widget child,
    required LinkInBioEffects effects,
    required double phase,
    required bool reduced}) {
  if (!effects.background || reduced) return child;
  return Transform.scale(
      scale: 1.04,
      child: Transform.translate(
          offset: Offset(math.sin(phase * math.pi * 2) * 4,
              math.cos(phase * math.pi * 2) * 3),
          child: child));
}

Widget bioMotionLink(
    {required Widget child,
    required LinkInBioEffects effects,
    required double phase,
    required double entrance,
    required bool featured}) {
  final progress = Curves.easeOut.transform(entrance);
  final lift = effects.featured && featured
      ? math.pow(math.max(0, math.sin(phase * math.pi * 7.2)), 12).toDouble() *
          -3
      : 0.0;
  return Opacity(
      opacity: progress,
      child: Transform.translate(
          offset: Offset(0, (1 - progress) * 10 + lift), child: child));
}
