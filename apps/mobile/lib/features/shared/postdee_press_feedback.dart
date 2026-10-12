import 'package:flutter/material.dart';

/// Adds a small visual response without replacing a control's gesture,
/// keyboard, semantics, layout, or hit target.
class PostDeePressFeedback extends StatefulWidget {
  const PostDeePressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<PostDeePressFeedback> createState() => _PostDeePressFeedbackState();
}

class _PostDeePressFeedbackState extends State<PostDeePressFeedback>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  int? _pointer;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _resumed = true;

  bool get _motionAllowed =>
      widget.enabled && _tickerEnabled && !_reduceMotion && _resumed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: .97,
      upperBound: 1,
      value: 1,
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant PostDeePressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (!_motionAllowed) {
      _pointer = null;
      // A muted ticker alone would retain a partial press and replay it on
      // resume. Finish the visual immediately, including mid-release.
      _controller.stop();
      _controller.value = 1;
    }
  }

  void _animateScale(double target, int milliseconds) {
    if (!_motionAllowed) {
      _syncMotion();
      return;
    }
    _controller.animateTo(target,
        duration: Duration(milliseconds: milliseconds),
        curve: Curves.easeOutCubic);
  }

  void _release(int pointer) {
    if (!mounted || _pointer != pointer) return;
    _pointer = null;
    _animateScale(1, 160);
  }

  @override
  void dispose() {
    // Pointer release events can outlive a control removed while held.
    _pointer = null;
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (!mounted || !_motionAllowed || _pointer != null) return;
          _pointer = event.pointer;
          _animateScale(.97, 110);
        },
        onPointerUp: (event) => _release(event.pointer),
        onPointerCancel: (event) => _release(event.pointer),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.scale(
            key: const ValueKey('postdee-press-transform'),
            scale: _controller.value,
            transformHitTests: false,
            child: child,
          ),
          child: widget.child,
        ),
      );
}
