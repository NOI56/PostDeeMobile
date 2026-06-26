import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A shimmering placeholder block shown while real content loads. Reuse for any
/// loading state instead of a bare spinner so the layout settles in place.
class PostDeeSkeleton extends StatefulWidget {
  const PostDeeSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<PostDeeSkeleton> createState() => _PostDeeSkeletonState();
}

class _PostDeeSkeletonState extends State<PostDeeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.textMuted.withValues(alpha: 0.16);
    final highlight = AppTheme.textMuted.withValues(alpha: 0.32);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, highlight, base],
                stops: const [0.25, 0.5, 0.75],
                transform: _SkeletonSweep(_controller.value),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonSweep extends GradientTransform {
  const _SkeletonSweep(this.progress);

  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}
