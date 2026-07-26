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
    final displayText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (displayText.isEmpty) return const SizedBox.expand();
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
                text: displayText,
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
                      displayText,
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
                    displayText,
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

bool subtitleTextFitsSingleLine({
  required Iterable<String> texts,
  required TextStyle style,
  required double fontSize,
  required double maxWidth,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return true;
  }

  for (final rawText in texts) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      continue;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    if (painter.didExceedMaxLines) {
      return false;
    }
  }

  return true;
}

double fitSubtitleFontSizeForSingleLine({
  required Iterable<String> texts,
  required TextStyle style,
  required double maxWidth,
  double minimumFontSize = 6,
}) {
  final requested = style.fontSize ?? 22;
  final minimum = minimumFontSize.clamp(1.0, requested).toDouble();

  for (var candidate = requested; candidate >= minimum; candidate -= 1) {
    if (subtitleTextFitsSingleLine(
      texts: texts,
      style: style,
      fontSize: candidate,
      maxWidth: maxWidth,
    )) {
      return candidate;
    }
  }

  return minimum;
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
