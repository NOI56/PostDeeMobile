import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../ai_editing/review_video_timeline.dart';
import '../ai_editing/video_duration_probe.dart';
import '../platforms/social_platform.dart';
import 'cover_image_processor.dart';

class CoverEditorRequest {
  const CoverEditorRequest({
    required this.videoFile,
    required this.videoName,
    required this.platforms,
    this.initialResult,
  });

  final File videoFile;
  final String videoName;
  final List<SocialPlatform> platforms;
  final CoverEditorResult? initialResult;
}

typedef UploaderCoverEditorLauncher = Future<CoverEditorResult?> Function(
  BuildContext context,
  CoverEditorRequest request,
);

class CoverEditorScreen extends StatefulWidget {
  const CoverEditorScreen({
    super.key,
    required this.videoFile,
    required this.videoName,
    required this.platforms,
    this.initialResult,
    this.processCover,
    this.probeDuration,
    this.onSaved,
  });

  final File videoFile;
  final String videoName;
  final List<SocialPlatform> platforms;
  final CoverEditorResult? initialResult;
  final CoverImageProcessor? processCover;
  final VideoDurationProbe? probeDuration;
  final ValueChanged<CoverEditorResult>? onSaved;

  @override
  State<CoverEditorScreen> createState() => _CoverEditorScreenState();
}

class _CoverEditorScreenState extends State<CoverEditorScreen> {
  final _textController = TextEditingController();
  VideoPlayerController? _videoController;
  Timer? _seekTimer;
  Duration? _pendingSeek;
  int _durationMs = 0;
  bool _videoReady = false;
  bool _isSaving = false;
  String? _errorMessage;
  late CoverDesign _design;

  static const _fontSizes = [40.0, 52.0, 64.0];
  static const _fontWeights = [400, 600, 700, 900];
  static const _textColors = [
    Color(0xFFFFFFFF),
    Color(0xFF111111),
    Color(0xFFFFEB3B),
    Color(0xFF00E2A0),
  ];
  static const _backgroundColors = [
    Color(0x00000000),
    Color(0xB3000000),
    Color(0xD900A77A),
    Color(0xD9FFFFFF),
  ];

  int get _maximumFrameTimeMs => maxSelectableCoverFrameTimeMs(_durationMs);

  @override
  void initState() {
    super.initState();
    final initialResult = widget.initialResult;
    _design = initialResult?.design ?? const CoverDesign();
    _textController.text = _design.text;
    unawaited(_loadDuration());
    unawaited(_initializeVideo());
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    _textController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadDuration() async {
    final probe =
        widget.probeDuration ?? const FfprobeVideoDurationProbe().call;
    final seconds = await probe(widget.videoFile);
    if (!mounted || seconds == null || seconds <= 0) return;

    setState(() {
      _durationMs = (seconds * 1000).round();
      _design = _design.copyWith(
        coverFrameTimeMs: clampCoverFrameTimeMs(
          _design.coverFrameTimeMs,
          durationMs: _durationMs,
        ),
      );
    });
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.file(widget.videoFile);
    _videoController = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      final controllerDurationMs = controller.value.duration.inMilliseconds;
      final effectiveDurationMs =
          controllerDurationMs > 0 ? controllerDurationMs : _durationMs;
      final frameTimeMs = clampCoverFrameTimeMs(
        _design.coverFrameTimeMs,
        durationMs: effectiveDurationMs,
      );
      if (frameTimeMs > 0) {
        await controller.seekTo(
          Duration(milliseconds: frameTimeMs),
        );
      }
      if (!mounted || !identical(_videoController, controller)) return;
      setState(() {
        _videoReady = true;
        if (controller.value.duration > Duration.zero) {
          _durationMs = controllerDurationMs;
        }
        _design = _design.copyWith(coverFrameTimeMs: frameTimeMs);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'ยังเปิดภาพเคลื่อนไหวไม่ได้ แต่ยังเลือกเวลาและสร้างหน้าปกได้';
        });
      }
    }
  }

  void _selectFrame(Duration position) {
    final milliseconds = clampCoverFrameTimeMs(
      position.inMilliseconds,
      durationMs: _durationMs,
    );
    setState(() {
      _design = _design.copyWith(coverFrameTimeMs: milliseconds);
    });
    _pendingSeek = Duration(milliseconds: milliseconds);
    _seekTimer ??= Timer(const Duration(milliseconds: 100), _runPendingSeek);
  }

  void _runPendingSeek() {
    _seekTimer = null;
    final controller = _videoController;
    final target = _pendingSeek;
    _pendingSeek = null;
    if (controller != null &&
        controller.value.isInitialized &&
        target != null) {
      unawaited(controller.seekTo(target));
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final design = _design.copyWith(
      coverFrameTimeMs: clampCoverFrameTimeMs(
        _design.coverFrameTimeMs,
        durationMs: _durationMs,
      ),
      text: _textController.text.trim(),
    );
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final processor = widget.processCover ?? FfmpegCoverImageProcessor().call;
      final result = await processor(
        CoverImageRequest(
          videoFile: widget.videoFile,
          fileName: widget.videoName,
          design: design,
          durationMs: _durationMs > 0 ? _durationMs : null,
        ),
      );
      if (!mounted) {
        await result.cleanupTemporaryFiles();
        return;
      }
      widget.onSaved?.call(result);
      final didPop = await Navigator.of(context).maybePop(result);
      if (!didPop && widget.onSaved == null) {
        await result.cleanupTemporaryFiles();
      }
    } on CoverImageException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'สร้างหน้าปกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แต่งหน้าปก',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 116),
            children: [
              _sectionLabel('เลือกเฟรมหน้าปกจากคลิป'),
              const SizedBox(height: 12),
              _buildPreview(),
              const SizedBox(height: 12),
              Text(
                'เลื่อนเลือกภาพจากคลิป',
                key: const ValueKey('cover-frame-instruction'),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'ภาพตัวอย่างจะเปลี่ยนตามตำแหน่งเวลา แล้วใช้ภาพนั้นเป็นหน้าปก',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              ReviewVideoTimeline(
                sliderKey: const ValueKey('cover-frame-slider'),
                position: Duration(milliseconds: _design.coverFrameTimeMs),
                duration: Duration(milliseconds: _durationMs),
                maxPosition: Duration(milliseconds: _maximumFrameTimeMs),
                enabled: _durationMs > 0 && !_isSaving,
                onSeekStart: (position) {
                  unawaited(_videoController?.pause());
                  _selectFrame(position);
                },
                onSeekChanged: _selectFrame,
                onSeekEnd: (position) {
                  _selectFrame(position);
                  _runPendingSeek();
                },
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('cover-text-field'),
                controller: _textController,
                maxLength: 48,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'ข้อความบนหน้าปก (ไม่ใส่ก็ได้)',
                  hintText: 'เช่น ลดวันนี้เท่านั้น',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                onChanged: (value) => setState(() {
                  _design = _design.copyWith(text: value);
                }),
              ),
              const SizedBox(height: 10),
              _sectionLabel('ฟอนต์'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _choiceChip(
                    key: const ValueKey('cover-font-prompt'),
                    label: 'Prompt',
                    selected: _design.fontFamily == CoverFontFamily.prompt,
                    onSelected: () => setState(() {
                      _design = _design.copyWith(
                        fontFamily: CoverFontFamily.prompt,
                      );
                    }),
                  ),
                  _choiceChip(
                    key: const ValueKey('cover-font-anuphan'),
                    label: 'Anuphan',
                    selected: _design.fontFamily == CoverFontFamily.anuphan,
                    onSelected: () => setState(() {
                      _design = _design.copyWith(
                        fontFamily: CoverFontFamily.anuphan,
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionLabel('ความหนาและขนาด'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final weight in _fontWeights)
                    _choiceChip(
                      key: ValueKey('cover-weight-$weight'),
                      label: _weightLabel(weight),
                      selected: _design.fontWeight == weight,
                      onSelected: () => setState(() {
                        _design = _design.copyWith(fontWeight: weight);
                      }),
                    ),
                  for (final size in _fontSizes)
                    _choiceChip(
                      key: ValueKey('cover-size-${size.round()}'),
                      label: '${size.round()} px',
                      selected: _design.fontSize == size,
                      onSelected: () => setState(() {
                        _design = _design.copyWith(fontSize: size);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionLabel('สีข้อความ'),
              const SizedBox(height: 8),
              _colorChoices(
                colors: _textColors,
                selected: _design.textColor,
                keyPrefix: 'cover-text-color',
                onSelected: (color) => setState(() {
                  _design = _design.copyWith(textColor: color);
                }),
              ),
              const SizedBox(height: 14),
              _sectionLabel('พื้นหลังข้อความ'),
              const SizedBox(height: 8),
              _colorChoices(
                colors: _backgroundColors,
                selected: _design.backgroundColor,
                keyPrefix: 'cover-background-color',
                onSelected: (color) => setState(() {
                  _design = _design.copyWith(backgroundColor: color);
                }),
              ),
              const SizedBox(height: 14),
              _sectionLabel('ตำแหน่งข้อความ'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _positionChip('บน', 'top', 0.22),
                  _positionChip('กลาง', 'center', 0.5),
                  _positionChip('ล่าง', 'bottom', 0.78),
                ],
              ),
              const SizedBox(height: 16),
              CoverPlatformCapabilityNotice(platforms: widget.platforms),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCC80)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFF8A4B08),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('cover-save-button'),
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _isSaving ? 'กำลังสร้างหน้าปก...' : 'ใช้หน้าปกนี้',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _videoController;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: const Color(0xFF07120D),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_videoReady && controller != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
                        )
                      else
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF27483A), Color(0xFF07120D)],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.video_file_outlined,
                              size: 44,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      if (_design.text.trim().isNotEmpty)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment(
                              (_design.dx * 2) - 1,
                              (_design.dy * 2) - 1,
                            ),
                            child: GestureDetector(
                              key: const ValueKey('cover-draggable-text'),
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) {
                                setState(() {
                                  _design = _design.copyWith(
                                    dx: (_design.dx + details.delta.dx / width)
                                        .clamp(0.1, 0.9),
                                    dy: (_design.dy + details.delta.dy / height)
                                        .clamp(0.1, 0.9),
                                  );
                                });
                              },
                              child: Container(
                                constraints:
                                    BoxConstraints(maxWidth: width * 0.9),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _design.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  formatCoverTextForExport(
                                    _design.text,
                                    fontSize: _design.fontSize,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: _design.fontFamily ==
                                            CoverFontFamily.prompt
                                        ? 'Prompt'
                                        : 'Anuphan',
                                    fontWeight: _fontWeight(_design.fontWeight),
                                    fontSize: _design.fontSize * 0.28,
                                    color: _design.textColor,
                                    height: 1.15,
                                    shadows: const [
                                      Shadow(
                                        blurRadius: 3,
                                        color: Color(0x80000000),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            child: Text(
                              formatReviewVideoClock(
                                Duration(
                                  milliseconds: _design.coverFrameTimeMs,
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _choiceChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: _isSaving ? null : (_) => onSelected(),
    );
  }

  Widget _positionChip(String label, String keySuffix, double dy) =>
      _choiceChip(
        key: ValueKey('cover-position-$keySuffix'),
        label: label,
        selected: (_design.dy - dy).abs() < 0.01,
        onSelected: () => setState(() {
          _design = _design.copyWith(dx: 0.5, dy: dy);
        }),
      );

  Widget _colorChoices({
    required List<Color> colors,
    required Color selected,
    required String keyPrefix,
    required ValueChanged<Color> onSelected,
  }) {
    return Wrap(
      spacing: 10,
      children: [
        for (var index = 0; index < colors.length; index += 1)
          InkWell(
            key: ValueKey('$keyPrefix-$index'),
            borderRadius: BorderRadius.circular(999),
            onTap: _isSaving ? null : () => onSelected(colors[index]),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors[index],
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors[index] == selected
                      ? AppTheme.accent
                      : AppTheme.border,
                  width: colors[index] == selected ? 3 : 1,
                ),
              ),
              child: colors[index].a == 0
                  ? Icon(Icons.block, size: 20, color: AppTheme.textMuted)
                  : colors[index] == selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: colors[index].computeLuminance() > 0.55
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
            ),
          ),
      ],
    );
  }

  String _weightLabel(int weight) => switch (weight) {
        400 => 'ปกติ',
        600 => 'กึ่งหนา',
        700 => 'หนา',
        _ => 'หนาพิเศษ',
      };

  FontWeight _fontWeight(int weight) => switch (weight) {
        <= 400 => FontWeight.w400,
        <= 600 => FontWeight.w600,
        <= 700 => FontWeight.w700,
        <= 800 => FontWeight.w800,
        _ => FontWeight.w900,
      };
}

class CoverPlatformCapabilityNotice extends StatelessWidget {
  const CoverPlatformCapabilityNotice({
    super.key,
    required this.platforms,
    this.compact = false,
  });

  final List<SocialPlatform> platforms;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visiblePlatforms = platforms.isEmpty
        ? const [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
            SocialPlatform.instagramReels,
            SocialPlatform.facebookReels,
          ]
        : platforms;
    final messages = <String>[
      if (visiblePlatforms.contains(SocialPlatform.instagramReels))
        'Instagram Reels: ใช้ภาพปกที่แต่งได้',
      if (visiblePlatforms.contains(SocialPlatform.facebookReels))
        'Facebook Video: ส่งภาพปกแบบพยายามให้ดีที่สุด',
      if (visiblePlatforms.contains(SocialPlatform.tiktok))
        'TikTok: ใช้เฉพาะเฟรมที่เลือก ไม่ส่งข้อความแต่งปก',
      if (visiblePlatforms.contains(SocialPlatform.youtubeShorts))
        'YouTube Shorts: แต่งต่อในแอป YouTube',
    ];

    return Container(
      key: const ValueKey('cover-platform-capability-notice'),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB9DCCB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppTheme.accentCyanInk,
              ),
              const SizedBox(width: 7),
              Text(
                'การรองรับหน้าปก',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '• $message',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: compact ? 10.5 : 11.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
