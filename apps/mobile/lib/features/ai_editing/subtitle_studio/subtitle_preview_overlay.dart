import 'package:flutter/material.dart';

import 'subtitle_project.dart';

class SubtitlePreviewOverlay extends StatelessWidget {
  const SubtitlePreviewOverlay({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.expand();
    final alignment = switch (style.alignment) {
      SubtitleAlignment.top => Alignment.topCenter,
      SubtitleAlignment.middle => Alignment.center,
      SubtitleAlignment.bottom => Alignment.bottomCenter,
    };
    final baseStyle = TextStyle(
      fontFamily: style.fontId,
      fontWeight: FontWeight.values.firstWhere(
        (weight) => weight.value == style.fontWeight,
        orElse: () => FontWeight.w700,
      ),
      fontSize: style.fontSize,
      height: 1.2,
      color: subtitleColor(style.textColor),
      shadows: style.shadowDepth <= 0
          ? null
          : [
              Shadow(
                color: subtitleColor(style.shadowColor),
                offset: Offset(style.shadowDepth, style.shadowDepth),
                blurRadius: style.shadowDepth,
              ),
            ],
    );

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Align(
          key: const ValueKey('subtitle-preview-position'),
          alignment: alignment,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fittedFontSize = _fitSubtitleFontSize(
                context: context,
                text: text,
                style: baseStyle,
                maxLines: style.maxLines,
                maxWidth: constraints.maxWidth,
              );
              final fittedStyle = baseStyle.copyWith(fontSize: fittedFontSize);

              return Stack(
                alignment: Alignment.center,
                children: [
                  if (style.outlineWidth > 0)
                    Text(
                      text,
                      maxLines: style.maxLines,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.clip,
                      style: fittedStyle.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = style.outlineWidth * 2
                          ..strokeJoin = StrokeJoin.round
                          ..color = subtitleColor(style.outlineColor),
                        color: null,
                      ),
                    ),
                  Text(
                    text,
                    maxLines: style.maxLines,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.clip,
                    style: fittedStyle,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

double _fitSubtitleFontSize({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
}) {
  final requested = style.fontSize ?? 22;
  final minimum = requested < 10 ? requested : 10.0;
  final safeWidth = maxWidth.isFinite && maxWidth > 0
      ? maxWidth
      : MediaQuery.sizeOf(context).width;

  for (var candidate = requested; candidate >= minimum; candidate -= 1) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: candidate)),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: safeWidth);
    if (!painter.didExceedMaxLines) {
      return candidate;
    }
  }

  return minimum;
}

Color subtitleColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}
