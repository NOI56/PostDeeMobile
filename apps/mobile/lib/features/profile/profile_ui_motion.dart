import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

import '../shared/postdee_press_feedback.dart';

/// Account feedback runs only while its tab and the app are visible.
class AccountUiMotionScope extends StatefulWidget {
  const AccountUiMotionScope(
      {super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<AccountUiMotionScope> createState() => _AccountUiMotionScopeState();
}

class _AccountUiMotionScopeState extends State<AccountUiMotionScope>
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
        // Reduced feedback must not prevent native disclosures from finishing.
        enabled: active,
        child: MediaQuery(
            data: media.copyWith(disableAnimations: !allowed),
            child: widget.child));
  }
}

bool accountUiMotionAllowed(BuildContext context) =>
    TickerMode.valuesOf(context).enabled &&
    !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

/// Navigator overlays observe the account tab's ticker without updating across
/// subtrees during build. Deferred refreshes always consume the latest value.
class AccountUiOriginScope extends StatefulWidget {
  const AccountUiOriginScope(
      {super.key, required this.originTicker, required this.child});

  final ValueListenable<TickerModeData> originTicker;
  final Widget child;

  @override
  State<AccountUiOriginScope> createState() => _AccountUiOriginScopeState();
}

class _AccountUiOriginScopeState extends State<AccountUiOriginScope> {
  late bool _originEnabled;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    _originEnabled = widget.originTicker.value.enabled;
    widget.originTicker.addListener(_handleOriginChanged);
  }

  @override
  void didUpdateWidget(covariant AccountUiOriginScope oldWidget) {
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
      AccountUiMotionScope(enabled: _originEnabled, child: widget.child);
}

/// Preserve the native control's callback, semantics, layout and hit region.
class AccountUiPress extends StatelessWidget {
  const AccountUiPress({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final allowed = enabled && accountUiMotionAllowed(context);
    final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return MediaQuery(
        data: media.copyWith(disableAnimations: !allowed),
        child: PostDeePressFeedback(enabled: allowed, child: child));
  }
}

/// A tab activation starts one finite entrance without remounting its child.
/// Data rebuilds and re-enabling motion after an interruption do not replay it.
class AccountUiEntrance extends StatefulWidget {
  const AccountUiEntrance(
      {super.key, required this.child, this.isActive = true});

  final Widget child;
  final bool isActive;

  @override
  State<AccountUiEntrance> createState() => _AccountUiEntranceState();
}

class _AccountUiEntranceState extends State<AccountUiEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220), value: 1);
    _progress = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
  }

  void _syncMotion() {
    final becameActive = widget.isActive && !_wasActive;
    _wasActive = widget.isActive;
    final allowed = widget.isActive && accountUiMotionAllowed(context);
    if (!allowed) {
      _controller.stop();
      _controller.value = 1;
    } else if (becameActive) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant AccountUiEntrance oldWidget) {
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
