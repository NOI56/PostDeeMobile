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

class _PostDeePressFeedbackState extends State<PostDeePressFeedback> {
  int? _pointer;
  bool _pressed = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _pointer = null;
      _pressed = false;
    }
  }

  @override
  void didUpdateWidget(covariant PostDeePressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pointer = null;
      _pressed = false;
    }
  }

  void _release(int pointer) {
    if (!mounted || _pointer != pointer) return;
    setState(() {
      _pointer = null;
      _pressed = false;
    });
  }

  @override
  void dispose() {
    // Pointer release events can outlive a control removed while held.
    _pointer = null;
    _pressed = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (!widget.enabled || _reduceMotion || _pointer != null) return;
          setState(() {
            _pointer = event.pointer;
            _pressed = true;
          });
        },
        onPointerUp: (event) => _release(event.pointer),
        onPointerCancel: (event) => _release(event.pointer),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: _pressed ? .97 : 1),
          duration: _reduceMotion
              ? Duration.zero
              : Duration(milliseconds: _pressed ? 110 : 160),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(
            key: const ValueKey('postdee-press-transform'),
            scale: scale,
            transformHitTests: false,
            child: child,
          ),
          child: widget.child,
        ),
      );
}
