import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'clip_split_localizations.dart';
import 'clip_split_plan.dart';

/// A visual overview of the actual source ranges. The editable, accessible
/// ranges remain in the list below; this strip never handles input.
class ClipSplitTimeline extends StatelessWidget {
  const ClipSplitTimeline({
    super.key,
    required this.sourceDurationSeconds,
    required this.segments,
  });

  final double sourceDurationSeconds;
  final List<ClipSplitSegment> segments;

  @override
  Widget build(BuildContext context) {
    final motion =
        !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    final rangeKey = Object.hashAll(segments
        .expand((segment) => [segment.startSeconds, segment.endSeconds]));
    return ExcludeSemantics(
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.tileRadius),
          child: TweenAnimationBuilder<double>(
            key: ValueKey((sourceDurationSeconds, rangeKey)),
            tween: Tween(begin: 0, end: 1),
            duration:
                motion ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              size: const Size(double.infinity, AppTheme.spaceXl * 2),
              painter: _SplitTimelinePainter(
                duration: sourceDurationSeconds,
                segments: segments,
                progress: motion ? progress : 1,
                track: AppTheme.glassDeep,
                colors: [AppTheme.accentCyanInk, AppTheme.accent],
                labelStyle: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: AppTheme.onDarkPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                textScaler: MediaQuery.textScalerOf(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        SizedBox(
            width: double.infinity,
            child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceXs,
                children: [
                  Text(formatClipSplitTime(0),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppTheme.textSecondary)),
                  Text(formatClipSplitTime(sourceDurationSeconds),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppTheme.textSecondary)),
                ])),
      ]),
    );
  }
}

class _SplitTimelinePainter extends CustomPainter {
  const _SplitTimelinePainter({
    required this.duration,
    required this.segments,
    required this.progress,
    required this.track,
    required this.colors,
    required this.labelStyle,
    required this.textScaler,
  });

  final double duration;
  final List<ClipSplitSegment> segments;
  final double progress;
  final Color track;
  final List<Color> colors;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (!duration.isFinite || duration <= 0) return;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final left = size.width * segment.startSeconds / duration;
      final width = size.width * segment.durationSeconds / duration;
      final gap = math.min(AppTheme.spaceXs, width / 4);
      final rect = Rect.fromLTWH(
          left + gap / 2, 0, math.max(0, width - gap), size.height);
      final fill = colors[index % colors.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(AppTheme.spaceSm)),
        Paint()..color = fill.withValues(alpha: progress),
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          // Either foreground stays legible on the light/dark brand palettes.
          style: labelStyle.copyWith(
              color:
                  (fill.computeLuminance() > .179 ? Colors.black : Colors.white)
                      .withValues(alpha: progress)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      // Dense 64-part plans retain accurate cuts without cramped numbers.
      if (label.width + AppTheme.spaceMd <= rect.width &&
          label.height <= rect.height) {
        canvas.save();
        canvas.clipRect(rect);
        label.paint(
            canvas, rect.center - Offset(label.width / 2, label.height / 2));
        canvas.restore();
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _SplitTimelinePainter oldDelegate) =>
      duration != oldDelegate.duration ||
      segments != oldDelegate.segments ||
      progress != oldDelegate.progress ||
      track != oldDelegate.track ||
      colors[0] != oldDelegate.colors[0] ||
      colors[1] != oldDelegate.colors[1] ||
      labelStyle != oldDelegate.labelStyle ||
      textScaler != oldDelegate.textScaler;
}
