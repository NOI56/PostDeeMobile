import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import 'post_delivery_outcome.dart';

/// Missing provider results are different from an explicitly pending delivery.
String postPlatformDeliveryLabel(
  PostPlatformResult? result, {
  String languageCode = 'th',
}) {
  final isThai = languageCode == 'th';
  if (result == null) return isThai ? 'รอผล' : 'Awaiting result';
  return switch (result.status.trim().toUpperCase()) {
    'FAILED' => isThai ? 'ส่งไม่สำเร็จ' : 'Failed',
    'PUBLISHING' => isThai ? 'กำลังส่ง' : 'Sending',
    'PENDING' => isThai ? 'รอส่ง' : 'Pending',
    'PUBLISHED' => postDeliveryOutcomeLabel(result.deliveryOutcome,
            languageCode: languageCode) ??
        (isThai ? 'เผยแพร่แล้ว' : 'Published'),
    _ => isThai ? 'ผลยังไม่ยืนยัน' : 'Delivery unconfirmed',
  };
}

/// One clock for a post's sending badge, channel icons and indeterminate light.
/// This is activity feedback, never an estimate of upload/publishing progress.
class PostDeePublishingMotion extends StatefulWidget {
  const PostDeePublishingMotion({
    super.key,
    required this.sending,
    required this.child,
    this.animate = true,
  });

  final bool sending;
  final bool animate;
  final Widget child;

  @override
  State<PostDeePublishingMotion> createState() =>
      _PostDeePublishingMotionState();
}

class _PostDeePublishingMotionState extends State<PostDeePublishingMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _resumed = true;
  bool _transitionsAllowed = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PostDeePublishingMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
    if (mounted) setState(() {});
  }

  void _sync() {
    _transitionsAllowed = widget.animate &&
        _resumed &&
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (widget.sending && _transitionsAllowed) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PublishingMotionScope(
        turns: _controller,
        transitionsAllowed: _transitionsAllowed,
        child: widget.child,
      );
}

class _PublishingMotionScope extends InheritedWidget {
  const _PublishingMotionScope({
    required this.turns,
    required this.transitionsAllowed,
    required super.child,
  });

  final Animation<double> turns;
  final bool transitionsAllowed;

  static _PublishingMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PublishingMotionScope>();

  @override
  bool updateShouldNotify(_PublishingMotionScope oldWidget) =>
      oldWidget.turns != turns ||
      oldWidget.transitionsAllowed != transitionsAllowed;
}

class PostDeePublishingIcon extends StatelessWidget {
  const PostDeePublishingIcon({
    super.key,
    this.icon = Icons.sync_rounded,
    this.sending = true,
    this.color,
    this.size = 14,
  });

  final IconData icon;
  final bool sending;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, size: size, color: color);
    final motion = _PublishingMotionScope.maybeOf(context);
    return ExcludeSemantics(
      child: sending && motion != null
          ? RotationTransition(turns: motion.turns, child: child)
          : child,
    );
  }
}

class PostDeePublishingBadge extends StatelessWidget {
  const PostDeePublishingBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.sending = false,
    this.icon,
    this.fontSize = 11,
    this.wrapLabel = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool sending;
  final IconData? icon;
  final double fontSize;
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final motion = _PublishingMotionScope.maybeOf(context);
    final status = Row(
      key: ValueKey('$sending-$label'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sending || icon != null) ...[
          PostDeePublishingIcon(
            icon: sending ? Icons.sync_rounded : icon!,
            sending: sending,
            color: foreground,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(label,
              maxLines: wrapLabel ? null : 1,
              overflow: wrapLabel ? null : TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: foreground)),
        ),
      ],
    );
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: wrapLabel ? double.infinity : 190),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: motion?.transitionsAllowed == true
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: status,
                  )
                : status,
          ),
        ),
      ),
    );
  }
}

/// A sweeping light with no percentage or determinate progress semantics.
class PostDeePublishingRail extends StatelessWidget {
  const PostDeePublishingRail({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final motion = _PublishingMotionScope.maybeOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('postdee-publishing-rail'),
        width: double.infinity,
        height: 3,
        child: ClipRect(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _PublishingLightPainter(
                motion?.turns ?? const AlwaysStoppedAnimation(.5),
                color ?? AppTheme.accentCyanInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishingLightPainter extends CustomPainter {
  _PublishingLightPainter(this.phase, this.color) : super(repaint: phase);

  final Animation<double> phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = color.withValues(alpha: .05));
    final left = size.width * (phase.value * 1.4 - .4);
    final light = Rect.fromLTWH(left, 0, size.width * .4, size.height);
    canvas.drawRect(
      light,
      Paint()
        ..shader = LinearGradient(colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: .42),
          color.withValues(alpha: 0),
        ]).createShader(light),
    );
  }

  @override
  bool shouldRepaint(_PublishingLightPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

class PostDeePlatformDeliveryRow extends StatelessWidget {
  const PostDeePlatformDeliveryRow({
    super.key,
    required this.platforms,
    required this.results,
    this.languageCode = 'th',
  });

  final List<String> platforms;
  final List<PostPlatformResult> results;
  final String languageCode;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final platform in platforms.toSet()) _channel(context, platform),
        ],
      );

  Widget _channel(BuildContext context, String platformValue) {
    final result =
        results.where((value) => value.platform == platformValue).firstOrNull;
    final status = result?.status.trim().toUpperCase();
    final label = postPlatformDeliveryLabel(result, languageCode: languageCode);
    final platform = SocialPlatform.values
        .where((value) => value.apiValue == platformValue)
        .firstOrNull;
    final text = '${platform?.shortLabel ?? platformValue} · $label';
    final sending = status == 'PUBLISHING';
    final confirmed = status == 'PUBLISHED' &&
        (result?.deliveryOutcome == null ||
            isKnownDeliveryOutcome(result?.deliveryOutcome));
    final color = status == 'FAILED'
        ? Theme.of(context).colorScheme.error
        : sending || confirmed
            ? AppTheme.accentCyanInk
            : AppTheme.textMuted;
    final icon = sending
        ? Icons.sync_rounded
        : status == 'FAILED'
            ? Icons.error_outline_rounded
            : confirmed
                ? Icons.check_circle_outline_rounded
                : Icons.hourglass_empty_rounded;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PostDeePublishingIcon(
              icon: icon, sending: sending, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
