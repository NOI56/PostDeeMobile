import 'dart:async';

import 'package:flutter/material.dart';

/// Wraps the app so a branded splash shows briefly at cold start, then fades to
/// [child]. The splash continues seamlessly from the white Android system splash
/// (same white background + brand mark) and adds a light band sweeping across
/// the mark from left to right while the app warms up.
class PostDeeSplashGate extends StatefulWidget {
  const PostDeeSplashGate({
    required this.child,
    super.key,
    this.minimumDuration = const Duration(milliseconds: 1800),
  });

  final Widget child;
  final Duration minimumDuration;

  @override
  State<PostDeeSplashGate> createState() => _PostDeeSplashGateState();
}

class _PostDeeSplashGateState extends State<PostDeeSplashGate> {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minimumDuration, () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _showSplash
          ? const _SplashScreen(key: ValueKey('postdee-splash'))
          : KeyedSubtree(
              key: const ValueKey('postdee-app'),
              child: widget.child,
            ),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen({super.key});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Match the white Android system splash and its colored brand mark for a
    // seamless hand-off regardless of the app's light/dark theme.
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: SizedBox(
          width: 176,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    // Slight diagonal so the streak reads like a glint of light.
                    begin: const Alignment(-1, -0.6),
                    end: const Alignment(1, 0.6),
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 1),
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.40, 0.5, 0.60, 1.0],
                    transform: _SweepTransform(_controller.value),
                  ).createShader(bounds);
                },
                child: child,
              );
            },
            child: Image.asset(
              'assets/images/brand/postdee_mark.png',
              key: const ValueKey('postdee-splash-mark'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides the highlight band from off the left edge to off the right edge as
/// [progress] goes 0 -> 1, so the sweep enters and exits cleanly each loop.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.progress);

  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}
