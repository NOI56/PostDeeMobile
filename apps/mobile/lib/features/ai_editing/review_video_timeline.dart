import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum ReviewVideoSource { original, ai }

String formatReviewVideoClock(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String formatReviewVideoComparison({
  required Duration? originalDuration,
  required Duration? aiDuration,
}) {
  final original = originalDuration;
  final ai = aiDuration;
  if (original == null ||
      original <= Duration.zero ||
      ai == null ||
      ai <= Duration.zero) {
    return 'ต้นฉบับ --:-- → ผล AI --:-- · กำลังอ่านความยาวคลิป';
  }

  final differenceMilliseconds = ai.inMilliseconds - original.inMilliseconds;
  final absoluteDifference = differenceMilliseconds.abs();
  final differenceLabel = absoluteDifference == 0
      ? 'ความยาวเท่าเดิม'
      : differenceMilliseconds < 0
          ? 'สั้นลง${_formatReviewDurationDifference(absoluteDifference)}'
          : 'ยาวขึ้น${_formatReviewDurationDifference(absoluteDifference)}';

  return 'ต้นฉบับ ${formatReviewVideoClock(original)} '
      '→ ผล AI ${formatReviewVideoClock(ai)} · $differenceLabel';
}

String _formatReviewDurationDifference(int milliseconds) {
  if (milliseconds < Duration.millisecondsPerSecond) {
    return 'น้อยกว่า 1 วิ';
  }
  final seconds = milliseconds / Duration.millisecondsPerSecond;
  final rounded = seconds.roundToDouble() == seconds
      ? seconds.round().toString()
      : seconds.toStringAsFixed(1);
  return ' $rounded วิ';
}

String _reviewVideoComparisonSemantics({
  required Duration? originalDuration,
  required Duration? aiDuration,
}) {
  if (originalDuration == null ||
      originalDuration <= Duration.zero ||
      aiDuration == null ||
      aiDuration <= Duration.zero) {
    return 'กำลังอ่านความยาววิดีโอต้นฉบับและผล AI';
  }

  final differenceMilliseconds =
      aiDuration.inMilliseconds - originalDuration.inMilliseconds;
  final absoluteDifference = differenceMilliseconds.abs();
  final differenceLabel = absoluteDifference == 0
      ? 'ความยาวเท่าเดิม'
      : differenceMilliseconds < 0
          ? 'สั้นลง${_formatReviewDurationDifference(absoluteDifference)}'
          : 'ยาวขึ้น${_formatReviewDurationDifference(absoluteDifference)}';
  return 'ต้นฉบับ ${originalDuration.inSeconds} วินาที '
      'ผล AI ${aiDuration.inSeconds} วินาที $differenceLabel';
}

class ReviewVideoCompareHeader extends StatelessWidget {
  const ReviewVideoCompareHeader({
    super.key,
    required this.selectedSource,
    required this.originalDuration,
    required this.aiDuration,
    required this.enabled,
    required this.onSourceSelected,
  });

  final ReviewVideoSource selectedSource;
  final Duration? originalDuration;
  final Duration? aiDuration;
  final bool enabled;
  final ValueChanged<ReviewVideoSource> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    final comparisonLabel = formatReviewVideoComparison(
      originalDuration: originalDuration,
      aiDuration: aiDuration,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.glassDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSoft),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ReviewVideoSourceButton(
                  key: const ValueKey('ai-review-source-original'),
                  label: 'ต้นฉบับ',
                  selected: selectedSource == ReviewVideoSource.original,
                  enabled: enabled,
                  onTap: () => onSourceSelected(ReviewVideoSource.original),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ReviewVideoSourceButton(
                  key: const ValueKey('ai-review-source-ai'),
                  label: 'ผล AI',
                  selected: selectedSource == ReviewVideoSource.ai,
                  enabled: enabled,
                  onTap: () => onSourceSelected(ReviewVideoSource.ai),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: _reviewVideoComparisonSemantics(
            originalDuration: originalDuration,
            aiDuration: aiDuration,
          ),
          child: ExcludeSemantics(
            child: Text(
              comparisonLabel,
              key: const ValueKey('ai-review-duration-comparison'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentCyanInk,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewVideoSourceButton extends StatelessWidget {
  const _ReviewVideoSourceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final action = enabled ? onTap : null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      onTap: action,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: action,
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int reviewVideoRemainingSeconds({
  required Duration position,
  required Duration duration,
}) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final elapsedSeconds = position.inSeconds.clamp(0, totalSeconds);
  final remainingSeconds = totalSeconds - elapsedSeconds;
  if (remainingSeconds > 0) {
    return remainingSeconds;
  }
  return position < duration ? 1 : 0;
}

class ReviewVideoTimeline extends StatelessWidget {
  const ReviewVideoTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onSeekStart;
  final ValueChanged<Duration> onSeekChanged;
  final ValueChanged<Duration> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds =
        duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;
    final positionMilliseconds = position.inMilliseconds.clamp(
      0,
      durationMilliseconds,
    );
    final canSeek = enabled && durationMilliseconds > 0;
    final remainingSeconds = reviewVideoRemainingSeconds(
      position: position,
      duration: duration,
    );
    final elapsedLabel = formatReviewVideoClock(
      Duration(milliseconds: positionMilliseconds),
    );
    final durationLabel = formatReviewVideoClock(duration);

    Duration readSeekDuration(double value) => Duration(
          milliseconds: value.round().clamp(0, durationMilliseconds),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'ตำแหน่งวิดีโอ',
          value:
              '$elapsedLabel จาก $durationLabel เหลือ $remainingSeconds วินาที',
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.borderSoft,
              thumbColor: AppTheme.accent,
              overlayColor: AppTheme.accent.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              key: const ValueKey('ai-review-seek-slider'),
              value: positionMilliseconds.toDouble(),
              min: 0,
              max: durationMilliseconds > 0
                  ? durationMilliseconds.toDouble()
                  : 1,
              onChangeStart: canSeek
                  ? (value) => onSeekStart(readSeekDuration(value))
                  : null,
              onChanged: canSeek
                  ? (value) => onSeekChanged(readSeekDuration(value))
                  : null,
              onChangeEnd: canSeek
                  ? (value) => onSeekEnd(readSeekDuration(value))
                  : null,
              semanticFormatterCallback: (value) {
                final semanticPosition = readSeekDuration(value);
                final semanticElapsedLabel =
                    formatReviewVideoClock(semanticPosition);
                final semanticRemainingSeconds = reviewVideoRemainingSeconds(
                  position: semanticPosition,
                  duration: duration,
                );
                return '$semanticElapsedLabel จาก $durationLabel '
                    'เหลือ $semanticRemainingSeconds วินาที';
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$elapsedLabel / $durationLabel',
                  key: const ValueKey('ai-review-time-elapsed-total'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'เหลือ $remainingSeconds วิ',
                key: const ValueKey('ai-review-time-remaining'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
