import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';

typedef HomeDraftThumbnailControllerFactory = VideoPlayerController Function(
  File videoFile,
);

/// Displays the owner's saved cover or a paused local video frame. This does
/// not autoplay, fetch a network URL, or write an image back into the draft.
class HomeDraftThumbnail extends StatefulWidget {
  const HomeDraftThumbnail({
    super.key,
    required this.videoPath,
    this.coverPath,
    this.isActive = true,
    this.createController,
  });

  final String videoPath;
  final String? coverPath;
  final bool isActive;
  final HomeDraftThumbnailControllerFactory? createController;

  @override
  State<HomeDraftThumbnail> createState() => _HomeDraftThumbnailState();
}

class _HomeDraftThumbnailState extends State<HomeDraftThumbnail>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int _generation = 0;
  bool _ready = false;
  bool _coverFailed = false;
  bool _foreground = true;

  bool get _hasCover =>
      !_coverFailed && (widget.coverPath?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _startController();
  }

  @override
  void didUpdateWidget(covariant HomeDraftThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.coverPath != widget.coverPath ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.createController != widget.createController) {
      _stopController();
      _coverFailed = false;
      _startController();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextForeground = state == AppLifecycleState.resumed;
    if (_foreground == nextForeground) return;
    _foreground = nextForeground;
    _stopController();
    if (_foreground) _startController();
    if (mounted) setState(() {});
  }

  bool _isCurrent(VideoPlayerController controller, int generation) =>
      mounted &&
      widget.isActive &&
      _foreground &&
      generation == _generation &&
      identical(controller, _controller);

  void _startController() {
    if (_hasCover ||
        !widget.isActive ||
        !_foreground ||
        widget.videoPath.isEmpty) {
      return;
    }
    try {
      final file = File(widget.videoPath);
      final controller = widget.createController?.call(file) ??
          VideoPlayerController.file(file,
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      _controller = controller;
      controller.addListener(_onControllerChanged);
      unawaited(_initialize(controller, ++_generation));
    } catch (_) {
      _stopController();
    }
  }

  Future<void> _prepareFrame(
      VideoPlayerController controller, int generation) async {
    await controller.initialize();
    if (!_isCurrent(controller, generation)) return;
    await controller.setVolume(0);
    if (!_isCurrent(controller, generation)) return;
    await controller.pause();
    if (!_isCurrent(controller, generation)) return;
    await controller.seekTo(Duration.zero);
  }

  Future<void> _initialize(
      VideoPlayerController controller, int generation) async {
    try {
      await _prepareFrame(controller, generation)
          .timeout(const Duration(seconds: 5));
      if (_isCurrent(controller, generation)) setState(() => _ready = true);
    } catch (_) {
      if (_isCurrent(controller, generation)) {
        _stopController();
        setState(() {});
      }
    }
  }

  void _onControllerChanged() {
    if (_controller?.value.hasError != true) return;
    _stopController();
    if (mounted) setState(() {});
  }

  void _stopController() {
    _generation++;
    final previous = _controller;
    _controller = null;
    _ready = false;
    if (previous != null) {
      previous.removeListener(_onControllerChanged);
      unawaited(_disposeController(previous));
    }
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // A failed native decoder must not interrupt the rest of the Home page.
    }
  }

  Widget _placeholder() => ColoredBox(
        key: const ValueKey('home-draft-thumbnail-placeholder'),
        color: AppTheme.glassDeep,
        child: Center(
          child: Icon(Icons.video_file_outlined,
              size: 38, color: AppTheme.accentCyanInk),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_hasCover) {
      final generation = _generation;
      return Image.file(
        File(widget.coverPath!),
        key: const ValueKey('home-draft-cover'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stack) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _generation || _coverFailed) return;
            setState(() => _coverFailed = true);
            _startController();
          });
          return _placeholder();
        },
      );
    }
    final controller = _controller;
    final size = controller?.value.size ?? Size.zero;
    if (!_ready ||
        controller == null ||
        !controller.value.isInitialized ||
        size.width <= 0 ||
        size.height <= 0) {
      return _placeholder();
    }
    return SizedBox.expand(
      key: const ValueKey('home-draft-video-frame'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopController();
    super.dispose();
  }
}
