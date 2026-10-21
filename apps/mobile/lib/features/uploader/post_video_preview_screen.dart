import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';

/// Plays a local clip or a temporary owned-post URL without uploading media.
class PostVideoPreviewScreen extends StatefulWidget {
  const PostVideoPreviewScreen({
    super.key,
    required this.videoFile,
    required this.videoName,
    this.controllerFactory,
  })  : assert(videoFile != null),
        videoUrl = null,
        networkControllerFactory = null;

  /// The caller obtains this temporary URL through an authenticated owned-post
  /// read. Network playback is revoked when that sign-in lifetime ends.
  const PostVideoPreviewScreen.network({
    super.key,
    required this.videoUrl,
    required this.videoName,
    this.networkControllerFactory,
  })  : assert(videoUrl != null),
        videoFile = null,
        controllerFactory = null;

  final File? videoFile;
  final Uri? videoUrl;
  final String videoName;
  final VideoPlayerController Function(File)? controllerFactory;
  final VideoPlayerController Function(Uri)? networkControllerFactory;

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
  AuthSessionBinding? _ownerBinding;
  bool _accessRevoked = false;
  final _sessions = PostDeeAuthSessionStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (widget.videoUrl != null) {
      _ownerBinding = _sessions.captureSession();
      _sessions.addListener(_onSessionChanged);
      _accessRevoked = !_sessions.session.isSignedIn ||
          _sessions.session.stableUserId == null;
    }
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(PostVideoPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != null && widget.videoUrl == null) {
      _sessions.removeListener(_onSessionChanged);
      _ownerBinding = null;
    }
    if (oldWidget.videoUrl == null && widget.videoUrl != null) {
      _ownerBinding = _sessions.captureSession();
      _sessions.addListener(_onSessionChanged);
      _accessRevoked = _accessRevoked ||
          !_sessions.session.isSignedIn ||
          _sessions.session.stableUserId == null;
    }
    if (oldWidget.videoFile?.path != widget.videoFile?.path ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.controllerFactory != widget.controllerFactory ||
        oldWidget.networkControllerFactory != widget.networkControllerFactory) {
      _restartInitialization();
    }
  }

  void _onSessionChanged() {
    if (_ownerBinding?.isCurrent != false || _accessRevoked || !mounted) return;
    _accessRevoked = true;
    _initializationVersion++;
    _cancelInitialization();
    final controller = _controller;
    _controller = null;
    if (controller != null) _releaseController(controller);
    setState(() {
      _loading = false;
      _errorMessage = 'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่';
    });
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
      if (_accessRevoked || _ownerBinding?.isCurrent == false) {
        throw StateError('Preview access ended');
      }
      final videoUrl = widget.videoUrl;
      if (videoUrl != null) {
        if (!const {'http', 'https'}.contains(videoUrl.scheme) ||
            videoUrl.host.isEmpty ||
            videoUrl.userInfo.isNotEmpty) {
          throw StateError('Preview URL is unavailable');
        }
        controller = widget.networkControllerFactory?.call(videoUrl) ??
            VideoPlayerController.networkUrl(videoUrl,
                videoPlayerOptions:
                    VideoPlayerOptions(allowBackgroundPlayback: true));
      } else {
        final videoFile = widget.videoFile;
        if (videoFile == null) {
          throw StateError('Preview source is unavailable');
        }
        controller = widget.controllerFactory?.call(videoFile) ??
            VideoPlayerController.file(
              videoFile,
              // This screen owns lifecycle pausing, so returning to the app
              // cannot trigger the plugin's automatic playback resume.
              videoPlayerOptions: VideoPlayerOptions(
                allowBackgroundPlayback: true,
              ),
            );
      }
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
    if (_accessRevoked || _ownerBinding?.isCurrent == false) return;
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
    _sessions.removeListener(_onSessionChanged);
    _initializationVersion++;
    _cancelInitialization();
    final controller = _controller;
    _controller = null;
    if (controller != null) _releaseController(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accessRevoked) {
      return Scaffold(
          appBar: AppBar(title: const Text('ดูคลิป')),
          body: const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่',
                      textAlign: TextAlign.center))));
    }
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
              Text(
                widget.videoUrl != null
                    ? 'กลับไปตรวจสถานะเพื่อเปิดตัวอย่างล่าสุด'
                    : 'ลองเปิดอีกครั้ง หรือกลับไปเลือกคลิปอื่น',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (!_accessRevoked)
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
      final animate = _foreground &&
          TickerMode.valuesOf(context).enabled &&
          !MediaQuery.disableAnimationsOf(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: animate
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.hourglass_empty, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('กำลังเปิดคลิป…'),
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
