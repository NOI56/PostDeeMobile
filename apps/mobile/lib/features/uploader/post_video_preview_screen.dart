import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';

/// Plays the selected local clip without changing or uploading the source file.
class PostVideoPreviewScreen extends StatefulWidget {
  const PostVideoPreviewScreen({
    super.key,
    required this.videoFile,
    required this.videoName,
    this.controllerFactory,
  });

  final File videoFile;
  final String videoName;
  final VideoPlayerController Function(File)? controllerFactory;

  @override
  State<PostVideoPreviewScreen> createState() => _PostVideoPreviewScreenState();
}

class _PostVideoPreviewScreenState extends State<PostVideoPreviewScreen>
    with WidgetsBindingObserver {
  static const _initializationTimeout = Duration(seconds: 15);
  static const _commandTimeout = Duration(seconds: 5);
  final _releasedControllers = Set<VideoPlayerController>.identity();
  VideoPlayerController? _controller;
  Completer<void>? _initializationGate;
  Timer? _initializationTimer;
  int _initializationVersion = 0;
  bool _loading = true;
  bool _foreground = true;
  bool _commandPending = false;
  double? _dragPositionMs;
  String? _errorMessage;
  String? _playbackMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(PostVideoPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoFile.path != widget.videoFile.path ||
        oldWidget.controllerFactory != widget.controllerFactory) {
      _restartInitialization();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _pauseCurrent();
    if (mounted) setState(() {});
  }

  bool _isCurrent(VideoPlayerController controller, int version) =>
      mounted &&
      version == _initializationVersion &&
      identical(_controller, controller);

  Future<void> _initialize() async {
    final version = ++_initializationVersion;
    VideoPlayerController? controller;
    try {
      controller = widget.controllerFactory?.call(widget.videoFile) ??
          VideoPlayerController.file(
            widget.videoFile,
            // This screen owns lifecycle pausing, so returning to the app
            // cannot trigger the plugin's automatic playback resume.
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          );
      _controller = controller;
      final initializationGate = Completer<void>();
      _initializationGate = initializationGate;
      final initializationTimer = Timer(_initializationTimeout, () {
        if (!initializationGate.isCompleted) {
          initializationGate
              .completeError(TimeoutException('Video open timed out'));
        }
      });
      _initializationTimer = initializationTimer;
      unawaited(controller.initialize().then((_) {
        if (!initializationGate.isCompleted) initializationGate.complete();
      }, onError: (Object error, StackTrace stack) {
        if (!initializationGate.isCompleted) {
          initializationGate.completeError(error, stack);
        }
      }));
      try {
        await initializationGate.future;
      } finally {
        initializationTimer.cancel();
        if (identical(_initializationGate, initializationGate)) {
          _initializationGate = null;
          _initializationTimer = null;
        }
      }
      if (!_isCurrent(controller, version)) {
        _releaseController(controller);
        return;
      }
      if (controller.value.hasError || !controller.value.isInitialized) {
        throw StateError('The local clip could not be initialized');
      }
      controller.addListener(_onVideoChanged);
      setState(() => _loading = false);
    } catch (_) {
      if (version == _initializationVersion) _cancelInitialization();
      if (controller != null && !_isCurrent(controller, version)) {
        _releaseController(controller);
        return;
      }
      if (mounted && version == _initializationVersion) {
        _controller = null;
        setState(() {
          _loading = false;
          _errorMessage = 'ยังเปิดคลิปไม่ได้';
        });
      }
      if (controller != null) _releaseController(controller);
    }
  }

  void _onVideoChanged() {
    final controller = _controller;
    if (!mounted || controller == null || _loading) return;
    if (controller.value.hasError) {
      _initializationVersion++;
      _controller = null;
      _releaseController(controller);
      setState(() {
        _commandPending = false;
        _dragPositionMs = null;
        _errorMessage = 'ยังเปิดคลิปไม่ได้';
      });
      return;
    }
    setState(() {});
  }

  void _restartInitialization() {
    _initializationVersion++;
    _cancelInitialization();
    final previous = _controller;
    _controller = null;
    if (previous != null) _releaseController(previous);
    setState(() {
      _loading = true;
      _errorMessage = null;
      _playbackMessage = null;
      _commandPending = false;
      _dragPositionMs = null;
    });
    unawaited(_initialize());
  }

  void _cancelInitialization() {
    _initializationTimer?.cancel();
    _initializationTimer = null;
    final gate = _initializationGate;
    _initializationGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _pauseSafely(VideoPlayerController controller) async {
    try {
      if (controller.value.isInitialized) {
        await controller.pause().timeout(_commandTimeout);
      }
    } catch (_) {
      // Exiting or backgrounding must still release an unresponsive player.
    }
  }

  void _pauseCurrent() {
    final controller = _controller;
    if (controller != null) unawaited(_pauseSafely(controller));
  }

  void _releaseController(VideoPlayerController controller) {
    if (!_releasedControllers.add(controller)) return;
    controller.removeListener(_onVideoChanged);
    unawaited(() async {
      await _pauseSafely(controller);
      try {
        await controller.dispose();
      } catch (_) {
        // Native resources may already be gone after a decoder failure.
      }
    }());
  }

  Future<void> _runCommand(
    Future<void> Function(VideoPlayerController controller) command,
  ) async {
    final controller = _controller;
    final version = _initializationVersion;
    if (controller == null || _loading || _commandPending || !_foreground) {
      return;
    }
    setState(() {
      _commandPending = true;
      _playbackMessage = null;
    });
    try {
      await command(controller).timeout(_commandTimeout);
      if (!_foreground || !_isCurrent(controller, version)) {
        await _pauseSafely(controller);
      }
    } catch (_) {
      if (_isCurrent(controller, version)) {
        await _pauseSafely(controller);
      }
      if (_isCurrent(controller, version)) {
        setState(() {
          _playbackMessage = 'ยังเล่นคลิปไม่ได้ ลองอีกครั้ง';
        });
      }
    } finally {
      if (_isCurrent(controller, version)) {
        setState(() {
          _commandPending = false;
          _dragPositionMs = null;
        });
      }
    }
  }

  void _togglePlayback() {
    unawaited(_runCommand((controller) async {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        if (_foreground && identical(_controller, controller)) {
          await controller.play();
        }
      }
    }));
  }

  void _seek(double positionMs) {
    unawaited(_runCommand((controller) async {
      await controller.pause();
      final maximumMs = controller.value.duration.inMilliseconds;
      await controller.seekTo(Duration(
        milliseconds: positionMs.round().clamp(0, maximumMs),
      ));
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationVersion++;
    _cancelInitialization();
    final controller = _controller;
    _controller = null;
    if (controller != null) _releaseController(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _pauseCurrent();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ดูคลิป')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.videoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildVideo(controller)),
                if (!_loading && controller != null && _errorMessage == null)
                  _buildControls(controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(VideoPlayerController? controller) {
    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'ลองเปิดอีกครั้ง หรือกลับไปเลือกคลิปอื่น',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('post-video-preview-retry'),
                onPressed: _restartInitialization,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองเปิดคลิปอีกครั้ง'),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading || controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('กำลังเปิดคลิป…'),
          ],
        ),
      );
    }
    final aspectRatio = controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio:
                aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 9 / 16,
            child: VideoPlayer(
              controller,
              key: const ValueKey('post-video-preview-player'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerController controller) {
    final value = controller.value;
    final maximumMs = value.duration.inMilliseconds.toDouble();
    final positionMs =
        (_dragPositionMs ?? value.position.inMilliseconds.toDouble())
            .clamp(0.0, maximumMs);
    final controlsEnabled = !_commandPending && _foreground;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Semantics(
          label: 'เลื่อนเวลาคลิป',
          child: Slider(
            key: const ValueKey('post-video-preview-seek'),
            value: positionMs,
            max: maximumMs > 0 ? maximumMs : 1,
            activeColor: AppTheme.accent,
            semanticFormatterCallback: (position) =>
                _formatTime(Duration(milliseconds: position.round())),
            onChangeStart: controlsEnabled && maximumMs > 0
                ? (_) => _pauseCurrent()
                : null,
            onChanged: controlsEnabled && maximumMs > 0
                ? (position) => setState(() => _dragPositionMs = position)
                : null,
            onChangeEnd: controlsEnabled && maximumMs > 0 ? _seek : null,
          ),
        ),
        Row(
          children: [
            IconButton.filled(
              key: const ValueKey('post-video-preview-play'),
              tooltip: value.isPlaying ? 'หยุดคลิป' : 'เล่นคลิป',
              onPressed: controlsEnabled ? _togglePlayback : null,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'เริ่มคลิปใหม่',
              onPressed: controlsEnabled ? () => _seek(0) : null,
              icon: const Icon(Icons.replay),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_formatTime(Duration(milliseconds: positionMs.round()))} / '
                '${_formatTime(value.duration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (_playbackMessage != null) ...[
          const SizedBox(height: 8),
          Text(_playbackMessage!, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}
