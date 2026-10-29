import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';
import 'publish_post_preview.dart';
import 'video_preview_localizations.dart';

/// Plays a local clip or a temporary owned-post URL without uploading media.
class PostVideoPreviewScreen extends StatefulWidget {
  const PostVideoPreviewScreen({
    super.key,
    required this.videoFile,
    required this.videoName,
    this.controllerFactory,
    this.postPreview,
    this.ownerSession,
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
        controllerFactory = null,
        postPreview = null,
        ownerSession = null;

  final File? videoFile;
  final Uri? videoUrl;
  final String videoName;
  final PublishPostPreviewData? postPreview;
  // Capture at the caller before navigation so a delayed route cannot bind
  // an old account's caption and clip to a new sign-in lifetime.
  final AuthSessionBinding? ownerSession;
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
  int _playbackVersion = 0;
  bool _loading = true;
  bool _foreground = true;
  bool _commandPending = false;
  double? _dragPositionMs;
  double? _dragVolume;
  double _previewVolume = 1;
  double _lastAudibleVolume = 1;
  bool _volumePanelOpen = false;
  String? _errorMessage;
  String? _playbackMessage;
  AuthSessionBinding? _ownerBinding;
  bool _accessRevoked = false;
  final _sessions = PostDeeAuthSessionStore.instance;

  bool get _requiresOwnerBinding =>
      widget.videoUrl != null ||
      widget.postPreview != null ||
      widget.ownerSession != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_requiresOwnerBinding) {
      _ownerBinding = widget.ownerSession ?? _sessions.captureSession();
      _sessions.addListener(_onSessionChanged);
      _accessRevoked = !_ownerBinding!.isCurrent ||
          (widget.videoUrl != null &&
              (!_sessions.session.isSignedIn ||
                  _sessions.session.stableUserId == null));
    }
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(PostVideoPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previouslyBound = oldWidget.videoUrl != null ||
        oldWidget.postPreview != null ||
        oldWidget.ownerSession != null;
    if (previouslyBound && !_requiresOwnerBinding) {
      _sessions.removeListener(_onSessionChanged);
      _ownerBinding = null;
    }
    if (!previouslyBound && _requiresOwnerBinding) {
      _ownerBinding = widget.ownerSession ?? _sessions.captureSession();
      _sessions.addListener(_onSessionChanged);
    }
    if (_requiresOwnerBinding &&
        (_ownerBinding?.isCurrent == false ||
            widget.ownerSession?.isCurrent == false ||
            (widget.videoUrl != null &&
                (!_sessions.session.isSignedIn ||
                    _sessions.session.stableUserId == null)))) {
      _revokeAccess();
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
    _revokeAccess();
  }

  void _revokeAccess() {
    if (_accessRevoked || !mounted) return;
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
    if (!_foreground) {
      _dragVolume = null;
      _volumePanelOpen = false;
      _pauseCurrent();
    }
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
      if (_previewVolume != 1) {
        await controller.setVolume(_previewVolume).timeout(_commandTimeout);
        if (!_isCurrent(controller, version)) {
          _releaseController(controller);
          return;
        }
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
      _dragVolume = null;
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
    // A pending play continuation stays cancelled even if the app resumes
    // before its native volume/seek request completes.
    _playbackVersion++;
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

  Future<bool> _runCommand(
    Future<void> Function(
            VideoPlayerController controller, bool Function() isActive)
        command, {
    String failureMessage = 'ยังเล่นคลิปไม่ได้ ลองอีกครั้ง',
  }) async {
    final controller = _controller;
    final version = _initializationVersion;
    final playbackVersion = _playbackVersion;
    if (controller == null || _loading || _commandPending || !_foreground) {
      return false;
    }
    setState(() {
      _commandPending = true;
      _playbackMessage = null;
    });
    var active = true;
    bool isActive() =>
        active &&
        playbackVersion == _playbackVersion &&
        _foreground &&
        _isCurrent(controller, version);
    try {
      await command(controller, isActive).timeout(_commandTimeout);
      if (!isActive()) {
        await _pauseSafely(controller);
      }
      return _isCurrent(controller, version);
    } catch (_) {
      // Future.timeout does not cancel the native command. Invalidate its
      // continuation before pausing so a late result cannot start playback.
      active = false;
      if (_isCurrent(controller, version)) {
        await _pauseSafely(controller);
      }
      if (_isCurrent(controller, version)) {
        setState(() {
          _playbackMessage = failureMessage;
        });
      }
      return false;
    } finally {
      active = false;
      if (_isCurrent(controller, version)) {
        setState(() {
          _commandPending = false;
          _dragPositionMs = null;
          _dragVolume = null;
        });
      }
    }
  }

  void _togglePlayback() {
    unawaited(_runCommand((controller, isActive) async {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        if (isActive()) {
          // A failed native volume request may have changed the plugin's
          // optimistic value. Reapply the confirmed level before playback.
          if (controller.value.volume != _previewVolume) {
            await controller.setVolume(_previewVolume);
          }
        }
        if (isActive()) {
          await controller.play();
        }
      }
    }));
  }

  Future<void> _setPreviewVolume(double requestedVolume) async {
    final controller = _controller;
    final version = _initializationVersion;
    final volume = requestedVolume.clamp(0.0, 1.0);
    final applied = await _runCommand(
      (controller, _) => controller.setVolume(volume),
      failureMessage: 'ยังปรับเสียงไม่ได้ ลองอีกครั้ง',
    );
    if (!applied || controller == null || !_isCurrent(controller, version)) {
      return;
    }
    setState(() {
      _previewVolume = volume;
      if (volume > 0) _lastAudibleVolume = volume;
    });
  }

  void _seek(double positionMs) {
    unawaited(_runCommand((controller, isActive) async {
      await controller.pause();
      if (!isActive()) return;
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
    final postPreview = widget.postPreview;
    final title = postPreview == null ? 'ดูคลิป' : 'พรีวิว';
    if (_accessRevoked) {
      return Scaffold(
          appBar: AppBar(title: VideoPreviewText(title)),
          body: const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: VideoPreviewText(
                      'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดคลิปใหม่',
                      textAlign: TextAlign.center))));
    }
    final controller = _controller;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _pauseCurrent();
      },
      child: postPreview != null
          ? Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Colors.white,
                  surface: Color(0xFF202020),
                ),
                textTheme: Theme.of(context).textTheme.apply(
                      bodyColor: Colors.white,
                      displayColor: Colors.white,
                    ),
              ),
              child: _buildImmersivePreview(postPreview, controller),
            )
          : Scaffold(
              appBar: AppBar(title: VideoPreviewText(title)),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (postPreview == null) ...[
                        Text(
                          widget.videoName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(child: _buildVideo(controller)),
                      if (!_loading &&
                          controller != null &&
                          _errorMessage == null)
                        _buildControls(controller),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildImmersivePreview(
      PublishPostPreviewData preview, VideoPlayerController? controller) {
    final ready = !_loading && controller != null && _errorMessage == null;
    final enabled = ready && !_commandPending && _foreground;
    final playing = controller?.value.isPlaying ?? false;
    // Staging's outer banner uses the app theme above this dark preview route.
    final lightStagingBar =
        const bool.fromEnvironment('POSTDEE_STAGING_BUILD') &&
            Theme.of(context).brightness == Brightness.light;
    final systemBars = lightStagingBar
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBars.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          key: const ValueKey('post-video-preview-immersive'),
          fit: StackFit.expand,
          children: [
            Tooltip(
              message: localizeVideoPreviewMessage(
                  context, playing ? 'หยุดคลิป' : 'เล่นคลิป'),
              child: Semantics(
                button: true,
                enabled: enabled,
                label: localizeVideoPreviewMessage(
                    context, playing ? 'หยุดคลิป' : 'เล่นคลิป'),
                child: GestureDetector(
                  key: const ValueKey('post-video-preview-play'),
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled
                      ? () {
                          if (_volumePanelOpen) {
                            setState(() => _volumePanelOpen = false);
                          } else {
                            _togglePlayback();
                          }
                        }
                      : null,
                  child: PublishPostPreviewPane(
                    immersive: true,
                    data: preview,
                    video: Stack(fit: StackFit.expand, children: [
                      _buildVideo(controller, edgeToEdge: true),
                      if (ready && !playing)
                        const Center(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Icon(Icons.play_arrow_rounded,
                                  size: 76, color: Colors.white70),
                            ),
                          ),
                        ),
                    ]),
                    hasStartedPlayback: controller != null &&
                        (playing || controller.value.position > Duration.zero),
                    isPlaying: playing,
                    onShowCover: _pauseCurrent,
                    onShowInformation: _pauseCurrent,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: SafeArea(
                bottom: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(children: [
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          color: Colors.white,
                          icon: const Icon(Icons.arrow_back_ios_new, size: 26),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const Expanded(
                          child: VideoPreviewText('พรีวิว',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          key: const ValueKey(
                              'post-video-preview-volume-toggle'),
                          tooltip: localizeVideoPreviewMessage(
                              context, 'ปรับเสียงพรีวิว'),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          onPressed: enabled
                              ? () => setState(
                                  () => _volumePanelOpen = !_volumePanelOpen)
                              : null,
                          icon: Icon(_previewVolume == 0
                              ? Icons.volume_off_outlined
                              : Icons.volume_up_outlined),
                        ),
                      ])),
                  if (_volumePanelOpen && ready)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _buildImmersiveVolume(),
                      ),
                    ),
                ]),
              ),
            ),
            if (_playbackMessage != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: Material(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: VideoPreviewText(_playbackMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveVolume() {
    final enabled = !_commandPending && _foreground;
    final displayedVolume = _dragVolume ?? _previewVolume;
    return Material(
      key: const ValueKey('post-video-preview-volume-panel'),
      color: const Color(0xEE202020),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 24).clamp(0.0, 300.0),
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(children: [
            IconButton(
              key: const ValueKey('post-video-preview-mute'),
              tooltip: localizeVideoPreviewMessage(context,
                  _previewVolume == 0 ? 'เปิดเสียงพรีวิว' : 'ปิดเสียงพรีวิว'),
              color: Colors.white,
              onPressed: enabled
                  ? () => unawaited(_setPreviewVolume(
                      _previewVolume == 0 ? _lastAudibleVolume : 0))
                  : null,
              icon: Icon(_previewVolume == 0
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined),
            ),
            Expanded(
              child: Semantics(
                label: localizeVideoPreviewMessage(context, 'ระดับเสียงพรีวิว'),
                child: Slider(
                  key: const ValueKey('post-video-preview-volume'),
                  value: displayedVolume,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  semanticFormatterCallback: (value) =>
                      localizeVideoPreviewMessage(
                          context, '${(value * 100).round()} เปอร์เซ็นต์'),
                  onChanged: enabled
                      ? (value) => setState(() => _dragVolume = value)
                      : null,
                  onChangeEnd: enabled
                      ? (value) => unawaited(_setPreviewVolume(value))
                      : null,
                ),
              ),
            ),
            Text('${(displayedVolume * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _buildVideo(VideoPlayerController? controller,
      {bool edgeToEdge = false}) {
    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined,
                  size: 48,
                  color: edgeToEdge
                      ? Colors.white70
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              VideoPreviewText(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              VideoPreviewText(
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
                  label: const VideoPreviewText('ลองเปิดคลิปอีกครั้ง'),
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
            const VideoPreviewText('กำลังเปิดคลิป…'),
          ],
        ),
      );
    }
    final aspectRatio = controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(edgeToEdge ? 0 : AppTheme.cardRadius),
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
          label: localizeVideoPreviewMessage(context, 'เลื่อนเวลาคลิป'),
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
              tooltip: localizeVideoPreviewMessage(
                  context, value.isPlaying ? 'หยุดคลิป' : 'เล่นคลิป'),
              onPressed: controlsEnabled ? _togglePlayback : null,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: localizeVideoPreviewMessage(context, 'เริ่มคลิปใหม่'),
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
        Row(
          children: [
            IconButton(
              key: const ValueKey('post-video-preview-mute'),
              tooltip: localizeVideoPreviewMessage(context,
                  _previewVolume == 0 ? 'เปิดเสียงพรีวิว' : 'ปิดเสียงพรีวิว'),
              onPressed: controlsEnabled
                  ? () => unawaited(_setPreviewVolume(
                      _previewVolume == 0 ? _lastAudibleVolume : 0))
                  : null,
              icon: Icon(_previewVolume == 0
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined),
            ),
            Expanded(
              child: Semantics(
                label: localizeVideoPreviewMessage(context, 'ระดับเสียงพรีวิว'),
                child: Slider(
                  key: const ValueKey('post-video-preview-volume'),
                  value: _dragVolume ?? _previewVolume,
                  activeColor: AppTheme.accent,
                  label: '${((_dragVolume ?? _previewVolume) * 100).round()}%',
                  semanticFormatterCallback: (value) =>
                      localizeVideoPreviewMessage(
                          context, '${(value * 100).round()} เปอร์เซ็นต์'),
                  onChanged: controlsEnabled
                      ? (value) => setState(() => _dragVolume = value)
                      : null,
                  onChangeEnd: controlsEnabled
                      ? (value) => unawaited(_setPreviewVolume(value))
                      : null,
                ),
              ),
            ),
            Text(
              '${((_dragVolume ?? _previewVolume) * 100).round()}%',
              maxLines: 1,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        if (_playbackMessage != null) ...[
          const SizedBox(height: 8),
          VideoPreviewText(_playbackMessage!, textAlign: TextAlign.center),
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
