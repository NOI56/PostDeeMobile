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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Align(
          key: const ValueKey('subtitle-preview-position'),
          alignment: alignment,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (style.outlineWidth > 0)
                Text(
                  text,
                  maxLines: style.maxLines,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle.copyWith(
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
                overflow: TextOverflow.ellipsis,
                style: baseStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color subtitleColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}
