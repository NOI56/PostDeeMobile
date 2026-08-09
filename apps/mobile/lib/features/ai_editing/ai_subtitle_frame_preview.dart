import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'review_video_timeline.dart';

const Duration subtitleFrameEndMargin = Duration(milliseconds: 100);

/// Converts the encoded stream size to the size users actually see after the
/// video player's rotation correction has been applied.
///
/// The returned size is the coordinate space for subtitle preview overlays.
/// Callers must not use the surrounding widget or letterbox as that space.
Size displayOrientedFrameSize(Size encodedSize, int rotationDegrees) {
  if (!encodedSize.width.isFinite ||
      !encodedSize.height.isFinite ||
      encodedSize.width <= 0 ||
      encodedSize.height <= 0) {
    return Size.zero;
  }

  final normalizedRotation = ((rotationDegrees % 360) + 360) % 360;
  if (normalizedRotation == 90 || normalizedRotation == 270) {
    return Size(encodedSize.height, encodedSize.width);
  }
  return encodedSize;
}

Duration maxSelectableSubtitleFramePosition(Duration duration) {
  final durationMs = duration.inMilliseconds;
  if (durationMs <= subtitleFrameEndMargin.inMilliseconds) {
    return Duration.zero;
  }
  return Duration(
    milliseconds: durationMs - subtitleFrameEndMargin.inMilliseconds,
  );
}

Duration clampSubtitleFramePosition(
  Duration position, {
  required Duration duration,
}) {
  final maximum = maxSelectableSubtitleFramePosition(duration).inMilliseconds;
  return Duration(
    milliseconds: position.inMilliseconds.clamp(0, maximum),
  );
}

Duration midpointSubtitleFramePosition(Duration duration) =>
    clampSubtitleFramePosition(
      Duration(milliseconds: duration.inMilliseconds ~/ 2),
      duration: duration,
    );

/// Local-only frame selection. It intentionally remembers only the current
/// source and must never be serialized into a preset, draft, recipe, or API
/// request.
class AiSubtitleFramePreviewSession {
  String? _sourceKey;
  Duration? _position;

  Duration? positionForSource(String sourceKey) =>
      sourceKey == _sourceKey ? _position : null;

  void beginSource(String sourceKey) {
    if (_sourceKey == sourceKey) return;
    _sourceKey = sourceKey;
    _position = null;
  }

  void remember(String sourceKey, Duration position) {
    beginSource(sourceKey);
    _position = position;
  }

  void clear() {
    _sourceKey = null;
    _position = null;
  }
}

/// Small surface around video_player that keeps widget tests independent from
/// the native plugin. [encodedSize] is the unrotated stream size and
/// [rotationCorrectionDegrees] is the clockwise display correction.
abstract interface class AiSubtitleFrameController {
  Future<void> initialize();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> dispose();

  Duration get duration;
  Size get encodedSize;
  int get rotationCorrectionDegrees;
  Widget buildView();
}

typedef AiSubtitleFrameControllerFactory = AiSubtitleFrameController Function(
  File sourceFile,
);

typedef AiSubtitleFrameOverlayBuilder = Widget Function(
  BuildContext context,
  Size displayOrientedSize,
  Duration position,
);

class AiSubtitleFramePreview extends StatefulWidget {
  const AiSubtitleFramePreview({
    super.key,
    required this.sourceFile,
    this.sourceFingerprint,
    this.controllerFactory,
    this.session,
    this.displaySizeHint,
    this.onPositionChanged,
    this.overlayBuilder,
    this.placeholder,
    this.seekThrottle = const Duration(milliseconds: 110),
    this.maxPreviewWidth = 240,
    this.maxPreviewHeight = 320,
    this.showTimeline = true,
  })  : assert(maxPreviewWidth > 0),
        assert(maxPreviewHeight > 0);

  final File sourceFile;

  /// A source fingerprint is preferred when the same local path can be
  /// overwritten. It is local state only and is never sent to AI providers.
  final String? sourceFingerprint;
  final AiSubtitleFrameControllerFactory? controllerFactory;
  final AiSubtitleFramePreviewSession? session;

  /// Already display-oriented dimensions, normally from PickedVideoFile.
  final Size? displaySizeHint;
  final ValueChanged<Duration>? onPositionChanged;
  final AiSubtitleFrameOverlayBuilder? overlayBuilder;
  final Widget? placeholder;
  final Duration seekThrottle;
  final double maxPreviewWidth;
  final double maxPreviewHeight;
  final bool showTimeline;

  String get sourceKey {
    final fingerprint = sourceFingerprint?.trim() ?? '';
    return fingerprint.isNotEmpty ? fingerprint : sourceFile.path;
  }

  @override
  State<AiSubtitleFramePreview> createState() => _AiSubtitleFramePreviewState();
}

class _AiSubtitleFramePreviewState extends State<AiSubtitleFramePreview> {
  AiSubtitleFramePreviewSession? _ownedSession;
  AiSubtitleFrameController? _controller;
  AiSubtitleFrameController? _initializingController;
  final Map<AiSubtitleFrameController, Future<void>> _controllerDisposals =
      Map<AiSubtitleFrameController, Future<void>>.identity();

  Timer? _liveSeekTimer;
  Future<void>? _activeSeek;
  Future<void>? _activeInitialization;
  Future<void> _sourceTransition = Future<void>.value();
  Duration? _pendingSeekPosition;
  bool _pendingSeekIsExact = false;
  int _sourceGeneration = 0;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Size _displaySize = Size.zero;
  bool _ready = false;
  bool _failed = false;

  AiSubtitleFramePreviewSession get _session =>
      widget.session ?? (_ownedSession ??= AiSubtitleFramePreviewSession());

  @override
  void initState() {
    super.initState();
    _session.beginSource(widget.sourceKey);
    _startSource();
  }

  @override
  void didUpdateWidget(covariant AiSubtitleFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.sourceFile.path != widget.sourceFile.path;
    if (sourceChanged) {
      _session.beginSource(widget.sourceKey);
      _startSource();
    }
  }

  @override
  void dispose() {
    _sourceGeneration += 1;
    final activeSeek = _activeSeek;
    final activeInitialization = _activeInitialization;
    final controller = _controller;
    final initializingController = _initializingController;
    _cancelSeekQueue();
    _activeInitialization = null;
    _controller = null;
    _initializingController = null;
    _sourceTransition = _cleanupControllersAfterTransition(
      previousTransition: _sourceTransition,
      activeSeek: activeSeek,
      activeInitialization: activeInitialization,
      controllers: [
        if (controller != null) controller,
        if (initializingController != null) initializingController,
      ],
    );
    unawaited(_sourceTransition);
    super.dispose();
  }

  void _startSource() {
    final generation = ++_sourceGeneration;
    final activeSeek = _activeSeek;
    final activeInitialization = _activeInitialization;
    final previousController = _controller;
    final previousInitializingController = _initializingController;
    _cancelSeekQueue();
    _activeInitialization = null;
    _controller = null;
    _initializingController = null;

    _ready = false;
    _failed = false;
    _duration = Duration.zero;
    _position = Duration.zero;
    _displaySize = _validDisplaySize(widget.displaySizeHint) ?? Size.zero;

    final transition = _cleanupControllersAfterTransition(
      previousTransition: _sourceTransition,
      activeSeek: activeSeek,
      activeInitialization: activeInitialization,
      controllers: [
        if (previousController != null) previousController,
        if (previousInitializingController != null)
          previousInitializingController,
      ],
    );
    _sourceTransition = transition;
    unawaited(_startControllerAfterTransition(generation, transition));
  }

  Future<void> _startControllerAfterTransition(
    int generation,
    Future<void> transition,
  ) async {
    await transition;
    if (!mounted || generation != _sourceGeneration) return;

    AiSubtitleFrameController controller;
    try {
      final factory = widget.controllerFactory ?? _createNativeController;
      controller = factory(widget.sourceFile);
    } catch (_) {
      if (mounted && generation == _sourceGeneration) {
        setState(() => _failed = true);
      }
      return;
    }
    _initializingController = controller;
    final initialization = _initializeController(controller, generation);
    _activeInitialization = initialization;
    unawaited(
      initialization.then<void>((_) {
        if (identical(_activeInitialization, initialization)) {
          _activeInitialization = null;
        }
      }),
    );
  }

  Future<void> _cleanupControllersAfterTransition({
    required Future<void> previousTransition,
    required Future<void>? activeSeek,
    required Future<void>? activeInitialization,
    required List<AiSubtitleFrameController> controllers,
  }) async {
    await _awaitBestEffort(previousTransition);
    await _awaitBestEffort(activeSeek);
    await _awaitBestEffort(activeInitialization);

    final uniqueControllers = Set<AiSubtitleFrameController>.identity()
      ..addAll(controllers);
    for (final controller in uniqueControllers) {
      await _disposeOnce(controller);
    }
  }

  Future<void> _awaitBestEffort(Future<void>? operation) async {
    if (operation == null) return;
    try {
      await operation;
    } catch (_) {
      // A failed native operation still has to release its controller before
      // the replacement player can claim decoder and texture resources.
    }
  }

  Future<void> _initializeController(
    AiSubtitleFrameController controller,
    int generation,
  ) async {
    try {
      await controller.initialize();
      if (!_isCurrentInitializing(controller, generation)) {
        await _disposeOnce(controller);
        return;
      }

      await controller.pause();
      if (!_isCurrentInitializing(controller, generation)) {
        await _disposeOnce(controller);
        return;
      }

      final duration = controller.duration;
      if (duration <= Duration.zero) {
        throw StateError('Video duration is unavailable.');
      }
      final restored = _session.positionForSource(widget.sourceKey);
      final initialPosition = restored == null
          ? midpointSubtitleFramePosition(duration)
          : clampSubtitleFramePosition(restored, duration: duration);
      await controller.seekTo(initialPosition);
      if (!_isCurrentInitializing(controller, generation)) {
        await _disposeOnce(controller);
        return;
      }

      final orientedSize = displayOrientedFrameSize(
        controller.encodedSize,
        controller.rotationCorrectionDegrees,
      );
      _initializingController = null;
      _controller = controller;
      _duration = duration;
      _position = initialPosition;
      _displaySize = _validDisplaySize(orientedSize) ??
          _validDisplaySize(widget.displaySizeHint) ??
          const Size(9, 16);
      _ready = true;
      _failed = false;
      _session.remember(widget.sourceKey, initialPosition);
      if (mounted) {
        setState(() {});
        widget.onPositionChanged?.call(initialPosition);
      }
    } catch (_) {
      if (_isCurrentInitializing(controller, generation)) {
        _initializingController = null;
        _ready = false;
        _failed = true;
        if (mounted) setState(() {});
      }
      await _disposeOnce(controller);
    }
  }

  bool _isCurrentInitializing(
    AiSubtitleFrameController controller,
    int generation,
  ) =>
      mounted &&
      generation == _sourceGeneration &&
      identical(_initializingController, controller);

  Future<void> _disposeOnce(AiSubtitleFrameController controller) async {
    final existing = _controllerDisposals[controller];
    if (existing != null) return existing;

    final completer = Completer<void>();
    _controllerDisposals[controller] = completer.future;
    unawaited(
      () async {
        try {
          await controller.dispose();
        } catch (_) {
          // Preview cleanup is best effort and must never block the editor.
        } finally {
          completer.complete();
        }
      }(),
    );
    return completer.future;
  }

  void _handleSeekStart(Duration position) {
    final controller = _controller;
    if (!_ready || controller == null) return;
    unawaited(controller.pause());
    _rememberPosition(position);
  }

  void _handleSeekChanged(Duration position) {
    if (!_ready || _controller == null) return;
    final clamped = _rememberPosition(position);
    _pendingSeekPosition = clamped;
    _pendingSeekIsExact = false;
    if (_activeSeek == null && _liveSeekTimer == null) {
      _scheduleLiveSeek();
    }
  }

  void _handleSeekEnd(Duration position) {
    if (!_ready || _controller == null) return;
    final clamped = _rememberPosition(position);
    _pendingSeekPosition = clamped;
    _pendingSeekIsExact = true;
    _liveSeekTimer?.cancel();
    _liveSeekTimer = null;
    if (_activeSeek == null) {
      _startPendingSeek();
    }
  }

  Duration _rememberPosition(Duration position) {
    final clamped = clampSubtitleFramePosition(
      position,
      duration: _duration,
    );
    _position = clamped;
    _session.remember(widget.sourceKey, clamped);
    if (mounted) {
      setState(() {});
      widget.onPositionChanged?.call(clamped);
    }
    return clamped;
  }

  void _scheduleLiveSeek() {
    _liveSeekTimer?.cancel();
    _liveSeekTimer = Timer(widget.seekThrottle, () {
      _liveSeekTimer = null;
      _startPendingSeek();
    });
  }

  void _startPendingSeek() {
    final controller = _controller;
    final position = _pendingSeekPosition;
    if (!_ready ||
        controller == null ||
        position == null ||
        _activeSeek != null) {
      return;
    }

    final generation = _sourceGeneration;
    _pendingSeekPosition = null;
    _pendingSeekIsExact = false;
    late final Future<void> operation;
    operation = () async {
      try {
        await controller.seekTo(position);
      } catch (_) {
        // Keep the last valid frame. A later exact seek can still recover.
      }
    }();
    _activeSeek = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_activeSeek, operation)) {
          _activeSeek = null;
        }
        if (!mounted ||
            generation != _sourceGeneration ||
            !identical(_controller, controller) ||
            _pendingSeekPosition == null) {
          return;
        }
        if (_pendingSeekIsExact) {
          _startPendingSeek();
        } else if (_liveSeekTimer == null) {
          _scheduleLiveSeek();
        }
      }),
    );
  }

  void _cancelSeekQueue() {
    _liveSeekTimer?.cancel();
    _liveSeekTimer = null;
    _pendingSeekPosition = null;
    _pendingSeekIsExact = false;
    _activeSeek = null;
  }

  Size get _effectiveDisplaySize =>
      _validDisplaySize(_displaySize) ??
      _validDisplaySize(widget.displaySizeHint) ??
      const Size(9, 16);

  @override
  Widget build(BuildContext context) {
    final displaySize = _effectiveDisplaySize;
    final aspectRatio = displaySize.width / displaySize.height;
    final controller = _controller;
    final frame = _ready && controller != null
        ? KeyedSubtree(
            key: const ValueKey('ai-subtitle-frame-video'),
            child: controller.buildView(),
          )
        : widget.placeholder ?? _buildDefaultPlaceholder();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.maxPreviewWidth,
              maxHeight: widget.maxPreviewHeight,
            ),
            child: AspectRatio(
              key: const ValueKey('ai-subtitle-frame-content'),
              aspectRatio: aspectRatio,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    frame,
                    if (widget.overlayBuilder != null)
                      widget.overlayBuilder!(
                        context,
                        displaySize,
                        _position,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.showTimeline) ...[
          const SizedBox(height: 8),
          ReviewVideoTimeline(
            sliderKey: const ValueKey('ai-subtitle-frame-slider'),
            position: _position,
            duration: _duration,
            maxPosition: maxSelectableSubtitleFramePosition(_duration),
            enabled: _ready,
            onSeekStart: _handleSeekStart,
            onSeekChanged: _handleSeekChanged,
            onSeekEnd: _handleSeekEnd,
          ),
        ],
      ],
    );
  }

  Widget _buildDefaultPlaceholder() => ColoredBox(
        key: ValueKey(
          _failed ? 'ai-subtitle-frame-error' : 'ai-subtitle-frame-loading',
        ),
        color: const Color(0xFF07120D),
        child: Center(
          child: Icon(
            _failed ? Icons.broken_image_outlined : Icons.video_file_outlined,
            color: Colors.white54,
            size: 36,
          ),
        ),
      );
}

Size? _validDisplaySize(Size? size) {
  if (size == null ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return null;
  }
  return size;
}

AiSubtitleFrameController _createNativeController(File sourceFile) =>
    _NativeAiSubtitleFrameController(
      VideoPlayerController.file(sourceFile),
    );

class _NativeAiSubtitleFrameController implements AiSubtitleFrameController {
  _NativeAiSubtitleFrameController(this._controller);

  final VideoPlayerController _controller;

  @override
  Duration get duration => _controller.value.duration;

  @override
  Size get encodedSize => _controller.value.size;

  @override
  int get rotationCorrectionDegrees => _controller.value.rotationCorrection;

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> dispose() => _controller.dispose();
}
