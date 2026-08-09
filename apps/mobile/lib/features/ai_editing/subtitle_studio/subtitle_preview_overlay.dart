import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../subtitle_burn_video_processor.dart';
import 'subtitle_project.dart';

class ResolvedSubtitleCanvasLayout {
  const ResolvedSubtitleCanvasLayout({
    required this.fontSize,
    required this.normalizedPosition,
    required this.minNormalizedX,
    required this.maxNormalizedX,
    required this.minNormalizedY,
    required this.maxNormalizedY,
    required this.fitsSingleLine,
  });

  final double fontSize;
  final Offset normalizedPosition;
  final double minNormalizedX;
  final double maxNormalizedX;
  final double minNormalizedY;
  final double maxNormalizedY;
  final bool fitsSingleLine;
}

/// Resolves the one font size and safe anchor used by both the live preview
/// and the ASS export. System text scaling is intentionally excluded because
/// subtitles are video content, not application chrome.
ResolvedSubtitleCanvasLayout resolveSubtitleCanvasLayout({
  required Iterable<String> texts,
  required SubtitleStyle style,
  Size canvasSize = const Size(304, 540),
  double minimumFontSize = 6,
}) {
  final canvasWidth = canvasSize.width;
  final canvasHeight = canvasSize.height;
  if (!canvasWidth.isFinite ||
      !canvasHeight.isFinite ||
      canvasWidth <= 0 ||
      canvasHeight <= 0) {
    throw ArgumentError.value(canvasSize, 'canvasSize', 'must be positive');
  }

  final normalizedTexts = texts
      .map((text) => text.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  final requestedFontSize = style.fontSize.isFinite && style.fontSize > 0
      ? style.fontSize
      : SubtitleStyle.defaults.fontSize;
  final minimum = minimumFontSize.clamp(1.0, requestedFontSize).toDouble();
  final horizontalMargin = 24 * canvasWidth / postDeeSubtitleAssCanvasWidth;
  final verticalMargin = 28 * canvasHeight / postDeeSubtitleAssCanvasHeight;
  final safeWidth = (canvasWidth - horizontalMargin * 2).clamp(
    1.0,
    double.infinity,
  );
  final safeHeight = (canvasHeight - verticalMargin * 2).clamp(
    1.0,
    double.infinity,
  );
  final effectInset = (style.outlineWidth * 2) + style.shadowDepth.abs();
  final effectScale =
      style.animation.trim().toLowerCase() == 'pop' ? 1.03 : 1.0;
  final baseStyle = TextStyle(
    fontFamily: style.fontId,
    fontWeight: FontWeight.values.firstWhere(
      (weight) => weight.value == style.fontWeight,
      orElse: () => FontWeight.w700,
    ),
    fontSize: requestedFontSize,
    height: 1.2,
  );

  Size measureAt(double fontSize) {
    var maximumWidth = 0.0;
    var maximumHeight = 0.0;
    for (final text in normalizedTexts) {
      final painter = TextPainter(
        text:
            TextSpan(text: text, style: baseStyle.copyWith(fontSize: fontSize)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      maximumWidth = math.max(maximumWidth, painter.width);
      maximumHeight = math.max(maximumHeight, painter.height);
    }
    return Size(maximumWidth, maximumHeight);
  }

  bool fits(Size measured) =>
      ((measured.width + effectInset * 2) * effectScale) <= safeWidth &&
      ((measured.height + effectInset * 2) * effectScale) <= safeHeight;

  var fontSize = requestedFontSize;
  var measured = measureAt(fontSize);
  while (fontSize > minimum && !fits(measured)) {
    fontSize = math.max(minimum, fontSize - 1);
    measured = measureAt(fontSize);
  }

  final contentWidth =
      ((measured.width + effectInset * 2) * effectScale).clamp(1.0, safeWidth);
  final contentHeight = ((measured.height + effectInset * 2) * effectScale)
      .clamp(1.0, safeHeight);
  final minX =
      ((horizontalMargin + contentWidth / 2) / canvasWidth).clamp(0.0, 0.5);
  final maxX = (1 - minX).clamp(0.5, 1.0);
  final minY =
      ((verticalMargin + contentHeight / 2) / canvasHeight).clamp(0.0, 0.5);
  final maxY = (1 - minY).clamp(0.5, 1.0);
  final normalizedX = _safeNormalized(style.normalizedX, fallback: 0.5);
  final normalizedY = _safeNormalized(style.normalizedY, fallback: 0.88);

  return ResolvedSubtitleCanvasLayout(
    fontSize: fontSize,
    normalizedPosition: Offset(
      normalizedX.clamp(minX, maxX),
      normalizedY.clamp(minY, maxY),
    ),
    minNormalizedX: minX,
    maxNormalizedX: maxX,
    minNormalizedY: minY,
    maxNormalizedY: maxY,
    fitsSingleLine: fits(measured),
  );
}

class SubtitlePreviewOverlay extends StatelessWidget {
  const SubtitlePreviewOverlay({
    super.key,
    required this.text,
    required this.style,
    this.layoutTexts = const <String>[],
    this.onPositionChanged,
    this.currentPlaybackTimeMs,
    this.cueStartMs,
    this.cueEndMs,
    this.words = const [],
  });

  final String text;
  final SubtitleStyle style;
  final List<String> layoutTexts;
  final ValueChanged<Offset>? onPositionChanged;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth;
        final frameHeight = constraints.maxHeight;
        final canvasSize = subtitleAssCanvasSizeForDisplay(
          Size(frameWidth, frameHeight),
        );
        final layout = resolveSubtitleCanvasLayout(
          texts: <String>{...layoutTexts, displayText},
          style: style,
          canvasSize: canvasSize,
        );
        final horizontalScale = frameWidth / canvasSize.width;
        final verticalScale = frameHeight / canvasSize.height;
        final horizontalMargin =
            24 * canvasSize.width / postDeeSubtitleAssCanvasWidth;
        final verticalMargin =
            28 * canvasSize.height / postDeeSubtitleAssCanvasHeight;
        final safePadding = EdgeInsets.symmetric(
          horizontal: horizontalMargin * horizontalScale,
          vertical: verticalMargin * verticalScale,
        );
        final scaledOutlineWidth = style.outlineWidth * verticalScale;
        final scaledShadowDepth = style.shadowDepth * verticalScale;
        final baseStyle = TextStyle(
          fontFamily: style.fontId,
          fontWeight: FontWeight.values.firstWhere(
            (weight) => weight.value == style.fontWeight,
            orElse: () => FontWeight.w700,
          ),
          fontSize: layout.fontSize * verticalScale,
          height: 1.2,
          color: subtitleColor(style.textColor),
          shadows: style.shadowDepth <= 0
              ? null
              : [
                  Shadow(
                    color: subtitleColor(style.shadowColor),
                    offset: Offset(scaledShadowDepth, scaledShadowDepth),
                    blurRadius: scaledShadowDepth,
                  ),
                ],
        );
        final safeWidth = (frameWidth - safePadding.horizontal).clamp(
          1.0,
          double.infinity,
        );
        final fittedStyle = baseStyle;
        final textPainter = TextPainter(
          text: TextSpan(text: displayText, style: fittedStyle),
          textAlign: TextAlign.center,
          textDirection: Directionality.of(context),
          textScaler: TextScaler.noScaling,
          maxLines: 1,
        )..layout(maxWidth: safeWidth);
        final effectPadding =
            (scaledOutlineWidth * 2) + scaledShadowDepth.abs();
        final contentWidth = (textPainter.width + effectPadding * 2).clamp(
          1.0,
          safeWidth,
        );
        final safeHeight = (frameHeight - safePadding.vertical).clamp(
          1.0,
          double.infinity,
        );
        final contentHeight = (textPainter.height + effectPadding * 2).clamp(
          1.0,
          safeHeight,
        );
        final minX = layout.minNormalizedX;
        final maxX = layout.maxNormalizedX;
        final minY = layout.minNormalizedY;
        final maxY = layout.maxNormalizedY;
        final position = layout.normalizedPosition;

        final subtitle = Stack(
          alignment: Alignment.center,
          children: [
            if (scaledOutlineWidth > 0)
              Text(
                displayText,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.clip,
                style: fittedStyle.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = scaledOutlineWidth * 2
                    ..strokeJoin = StrokeJoin.round
                    ..color = subtitleColor(style.outlineColor),
                  color: null,
                ),
              ),
            if (timedWords == null)
              Text(
                displayText,
                textScaler: TextScaler.noScaling,
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
                                color: subtitleColor(style.activeWordColor),
                              )
                            : null,
                      ),
                      if (timedWords.parts[index].separator.isNotEmpty)
                        TextSpan(text: timedWords.parts[index].separator),
                    ],
                  ],
                ),
                textAlign: TextAlign.center,
                textDirection: Directionality.of(context),
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
          ],
        );
        final positionedContent = SizedBox(
          key: const ValueKey('subtitle-preview-positioned-content'),
          width: contentWidth,
          height: contentHeight,
          child: Center(
            child: _applySubtitleEffect(
              animation: style.animation,
              currentPlaybackTimeMs: currentPlaybackTimeMs,
              cueStartMs: cueStartMs,
              cueEndMs: cueEndMs,
              child: subtitle,
            ),
          ),
        );
        final draggable = _SubtitleDragTarget(
          position: position,
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          frameSize: Size(frameWidth, frameHeight),
          onPositionChanged: onPositionChanged,
          child: positionedContent,
        );

        return Padding(
          padding: safePadding,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                key: const ValueKey('subtitle-preview-position'),
                left: position.dx * frameWidth -
                    safePadding.left -
                    contentWidth / 2,
                top: position.dy * frameHeight -
                    safePadding.top -
                    contentHeight / 2,
                child: draggable,
              ),
            ],
          ),
        );
      },
    );
  }
}

double _safeNormalized(double value, {required double fallback}) =>
    value.isFinite ? value.clamp(0.0, 1.0) : fallback;

class _SubtitleDragTarget extends StatefulWidget {
  const _SubtitleDragTarget({
    required this.position,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.frameSize,
    required this.onPositionChanged,
    required this.child,
  });

  final Offset position;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final Size frameSize;
  final ValueChanged<Offset>? onPositionChanged;
  final Widget child;

  @override
  State<_SubtitleDragTarget> createState() => _SubtitleDragTargetState();
}

class _SubtitleDragTargetState extends State<_SubtitleDragTarget> {
  late Offset _dragPosition = widget.position;
  Offset? _dragStartGlobal;
  Offset? _dragStartPosition;

  @override
  void didUpdateWidget(covariant _SubtitleDragTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _dragPosition = widget.position;
    }
  }

  void _handlePanDown(DragDownDetails details) {
    _dragStartGlobal = details.globalPosition;
    _dragStartPosition = _dragPosition;
  }

  void _handlePanStart(DragStartDetails details) {
    _dragStartGlobal ??= details.globalPosition;
    _dragStartPosition ??= _dragPosition;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final width = widget.frameSize.width;
    final height = widget.frameSize.height;
    if (width <= 0 || height <= 0) return;
    final startGlobal = _dragStartGlobal ?? details.globalPosition;
    final startPosition = _dragStartPosition ?? _dragPosition;
    final totalDelta = details.globalPosition - startGlobal;
    _dragPosition = Offset(
      (startPosition.dx + totalDelta.dx / width)
          .clamp(widget.minX, widget.maxX),
      (startPosition.dy + totalDelta.dy / height)
          .clamp(widget.minY, widget.maxY),
    );
    widget.onPositionChanged?.call(_dragPosition);
  }

  void _handlePanEnd(DragEndDetails details) {
    _dragStartGlobal = null;
    _dragStartPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final child = Semantics(
      label: 'ตำแหน่งซับ ลากเพื่อขยับ',
      value:
          '${(_dragPosition.dx * 100).round()}%, ${(_dragPosition.dy * 100).round()}%',
      child: widget.child,
    );
    if (widget.onPositionChanged == null) {
      return IgnorePointer(child: child);
    }
    return GestureDetector(
      key: const ValueKey('subtitle-preview-draggable'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanDown: _handlePanDown,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      onPanCancel: () {
        _dragStartGlobal = null;
        _dragStartPosition = null;
      },
      child: child,
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
    if (text.isEmpty) continue;
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

Color subtitleColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16) ?? 0xFFFFFF;
  return Color(0xFF000000 | value);
}
