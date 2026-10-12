import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

import '../shared/postdee_press_feedback.dart';

/// Finite editor feedback is independent of effects on the shared public page.
class BioUiMotionScope extends StatefulWidget {
  const BioUiMotionScope({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<BioUiMotionScope> createState() => _BioUiMotionScopeState();
}

class _BioUiMotionScopeState extends State<BioUiMotionScope>
    with WidgetsBindingObserver {
  late bool _resumed;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (mounted && resumed != _resumed) {
      setState(() => _resumed = resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final active =
        widget.enabled && _resumed && TickerMode.valuesOf(context).enabled;
    final allowed = active && !media.disableAnimations;
    return TickerMode(
        // Keep active native disclosure controls able to finish their state
        // changes. New feedback uses the reduced-motion flag independently.
        enabled: active,
        child: MediaQuery(
            data: media.copyWith(disableAnimations: !allowed),
            child: widget.child));
  }
}

bool bioUiMotionAllowed(BuildContext context) =>
    TickerMode.valuesOf(context).enabled &&
    !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

/// Drag overlays listen to their origin without rebuilding across subtrees
/// during the origin's own build. Always consume the latest notifier value.
class BioUiOriginScope extends StatefulWidget {
  const BioUiOriginScope(
      {super.key, required this.originTicker, required this.child});

  final ValueListenable<TickerModeData> originTicker;
  final Widget child;

  @override
  State<BioUiOriginScope> createState() => _BioUiOriginScopeState();
}

class _BioUiOriginScopeState extends State<BioUiOriginScope> {
  late bool _originEnabled;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    _originEnabled = widget.originTicker.value.enabled;
    widget.originTicker.addListener(_handleOriginChanged);
  }

  @override
  void didUpdateWidget(covariant BioUiOriginScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originTicker != widget.originTicker) {
      oldWidget.originTicker.removeListener(_handleOriginChanged);
      _originEnabled = widget.originTicker.value.enabled;
      widget.originTicker.addListener(_handleOriginChanged);
    }
  }

  void _refreshFromOrigin() {
    if (!mounted) return;
    final enabled = widget.originTicker.value.enabled;
    if (enabled != _originEnabled) {
      setState(() => _originEnabled = enabled);
    }
  }

  void _handleOriginChanged() {
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_refreshQueued) return;
      _refreshQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshQueued = false;
        _refreshFromOrigin();
      });
    } else {
      _refreshFromOrigin();
    }
  }

  @override
  void dispose() {
    widget.originTicker.removeListener(_handleOriginChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BioUiMotionScope(enabled: _originEnabled, child: widget.child);
}

/// Keep the child's native callback, semantics, layout and hit region.
class BioUiPress extends StatelessWidget {
  const BioUiPress({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final allowed = enabled && bioUiMotionAllowed(context);
    final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return MediaQuery(
        data: media.copyWith(disableAnimations: !allowed),
        child: PostDeePressFeedback(enabled: allowed, child: child));
  }
}

/// Key each section/category so only its current controls remain mounted.
class BioUiEntrance extends StatefulWidget {
  const BioUiEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<BioUiEntrance> createState() => _BioUiEntranceState();
}

class _BioUiEntranceState extends State<BioUiEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220), value: 1);
    _progress = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
  }

  void _syncMotion() {
    final allowed = bioUiMotionAllowed(context);
    if (!_entered) {
      _entered = true;
      if (allowed) _controller.forward(from: 0);
    }
    if (!allowed) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant BioUiEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) => Opacity(
          opacity: _progress.value,
          child: Transform.translate(
              offset: Offset(0, 6 * (1 - _progress.value)),
              transformHitTests: false,
              child: child)));
}
