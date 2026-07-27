import 'package:flutter/material.dart';

import 'subtitle_project.dart';

class SubtitlePreviewOverlay extends StatelessWidget {
  const SubtitlePreviewOverlay({
    super.key,
    required this.text,
    required this.style,
    this.currentPlaybackTimeMs,
    this.cueStartMs,
    this.cueEndMs,
    this.words = const [],
  });

  final String text;
  final SubtitleStyle style;
  final int? currentPlaybackTimeMs;
  final int? cueStartMs;
  final int? cueEndMs;
  final List<SubtitleWord> words;

  @override
  Widget build(BuildContext context) {
    final displayText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (displayText.isEmpty) return const SizedBox.expand();
    final timedWords = _safeTimedWords(
      displayText: displayText,
      words: words,
      currentPlaybackTimeMs: currentPlaybackTimeMs,
    );
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
                maxLines: 1,
                maxWidth: subtitleSafeWidthForEffect(
                  maxWidth: constraints.maxWidth,
                  animation: style.animation,
                ),
              );
              final fittedStyle = baseStyle.copyWith(fontSize: fittedFontSize);

              final subtitle = Stack(
                alignment: Alignment.center,
                children: [
                  if (style.outlineWidth > 0)
                    Text(
                      displayText,
                      maxLines: 1,
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
                  if (timedWords == null)
                    Text(
                      displayText,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.clip,
                      style: fittedStyle,
                    )
                  else
                    RichText(
                      key: const ValueKey('subtitle-preview-active-words'),
                      text: TextSpan(
                        style: fittedStyle,
                        children: [
                          for (var index = 0;
                              index < timedWords.parts.length;
                              index += 1) ...[
                            TextSpan(
                              text: timedWords.parts[index].word,
                              style: index == timedWords.activeWordIndex
                                  ? TextStyle(
                                      color:
                                          subtitleColor(style.activeWordColor),
                                    )
                                  : null,
                            ),
                            if (timedWords.parts[index].separator.isNotEmpty)
                              TextSpan(
                                text: timedWords.parts[index].separator,
                              ),
                          ],
                        ],
                      ),
                      textAlign: TextAlign.center,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                ],
              );
              return _applySubtitleEffect(
                animation: style.animation,
                currentPlaybackTimeMs: currentPlaybackTimeMs,
                cueStartMs: cueStartMs,
                cueEndMs: cueEndMs,
                child: subtitle,
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget _applySubtitleEffect({
  required String animation,
  required int? currentPlaybackTimeMs,
  required int? cueStartMs,
  required int? cueEndMs,
  required Widget child,
}) {
  if (currentPlaybackTimeMs == null ||
      cueStartMs == null ||
      cueEndMs == null ||
      cueStartMs < 0 ||
      cueEndMs <= cueStartMs ||
      currentPlaybackTimeMs < cueStartMs ||
      currentPlaybackTimeMs > cueEndMs) {
    return child;
  }

  final cueDurationMs = cueEndMs - cueStartMs;
  final elapsedMs = currentPlaybackTimeMs - cueStartMs;
  final remainingMs = cueEndMs - currentPlaybackTimeMs;

  return switch (animation) {
    'pop' => Transform.scale(
        key: const ValueKey('subtitle-preview-effect-pop'),
        scale: _popScale(elapsedMs, cueDurationMs),
        child: child,
      ),
    'fade' => Opacity(
        key: const ValueKey('subtitle-preview-effect-fade'),
        opacity: _fadeOpacity(
          elapsedMs: elapsedMs,
          remainingMs: remainingMs,
          cueDurationMs: cueDurationMs,
        ),
        child: child,
      ),
    _ => child,
  };
}

double _popScale(int elapsedMs, int cueDurationMs) {
  final entryDurationMs = cueDurationMs.clamp(1, 220).toDouble();
  if (elapsedMs >= entryDurationMs) return 1;
  final peakAtMs = entryDurationMs * (120 / 220);
  if (elapsedMs <= peakAtMs) {
    final progress = (elapsedMs / peakAtMs).clamp(0.0, 1.0).toDouble();
    return 0.78 + ((1.03 - 0.78) * progress);
  }
  final progress = ((elapsedMs - peakAtMs) / (entryDurationMs - peakAtMs))
      .clamp(0.0, 1.0)
      .toDouble();
  return 1.03 + ((1 - 1.03) * progress);
}

double subtitleSafeWidthForEffect({
  required double maxWidth,
  required String animation,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return maxWidth;
  return animation.trim().toLowerCase() == 'pop' ? maxWidth / 1.03 : maxWidth;
}

double _fadeOpacity({
  required int elapsedMs,
  required int remainingMs,
  required int cueDurationMs,
}) {
  final edgeDurationMs = (cueDurationMs / 2).clamp(1.0, 180.0);
  final entering = (elapsedMs / edgeDurationMs).clamp(0.0, 1.0);
  final leaving = (remainingMs / edgeDurationMs).clamp(0.0, 1.0);
  return entering < leaving ? entering : leaving;
}

_TimedSubtitleWords? _safeTimedWords({
  required String displayText,
  required List<SubtitleWord> words,
  required int? currentPlaybackTimeMs,
}) {
  if (words.isEmpty ||
      currentPlaybackTimeMs == null ||
      currentPlaybackTimeMs < 0) {
    return null;
  }

  final parts = <_TimedSubtitleWordPart>[];
  var previousEndMs = -1;
  int? activeWordIndex;
  for (var index = 0; index < words.length; index += 1) {
    final word = words[index];
    final wordText = word.text.trim();
    if (wordText.isEmpty ||
        wordText != word.text ||
        RegExp(r'\s').hasMatch(wordText) ||
        word.sourceStartMs < 0 ||
        word.sourceEndMs <= word.sourceStartMs ||
        word.sourceStartMs < previousEndMs) {
      return null;
    }

    final separator = word.separatorAfter.replaceAll(RegExp(r'\s+'), ' ');
    parts.add(_TimedSubtitleWordPart(word: wordText, separator: separator));
    previousEndMs = word.sourceEndMs;
    if (currentPlaybackTimeMs >= word.sourceStartMs &&
        currentPlaybackTimeMs < word.sourceEndMs) {
      if (activeWordIndex != null) {
        return null;
      }
      activeWordIndex = index;
    }
  }

  if (parts.isNotEmpty) {
    final last = parts.last;
    parts[parts.length - 1] = _TimedSubtitleWordPart(
      word: last.word,
      separator: last.separator.trimRight(),
    );
  }
  final reconstructed =
      parts.map((part) => '${part.word}${part.separator}').join();
  if (reconstructed != displayText || activeWordIndex == null) {
    return null;
  }

  return _TimedSubtitleWords(
    parts: parts,
    activeWordIndex: activeWordIndex,
  );
}

class _TimedSubtitleWords {
  const _TimedSubtitleWords({
    required this.parts,
    required this.activeWordIndex,
  });

  final List<_TimedSubtitleWordPart> parts;
  final int activeWordIndex;
}

class _TimedSubtitleWordPart {
  const _TimedSubtitleWordPart({
    required this.word,
    required this.separator,
  });

  final String word;
  final String separator;
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
  final minimum = requested < 6 ? requested : 6.0;
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
