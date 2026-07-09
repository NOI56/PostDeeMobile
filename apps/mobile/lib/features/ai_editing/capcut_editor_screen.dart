import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'custom_prompt_interpreter.dart';
import 'edit_style_gallery.dart';
import 'edit_styles.dart';
import 'sticker_overlay.dart';
import 'style_options.dart';
import 'style_options_sheet.dart';
import 'subtitle_burn_video_processor.dart';
import 'video_duration_probe.dart';

typedef CapCutTranscriptLoader = Future<ClipTranscriptResult> Function(
    String videoS3Key);
typedef EditPlanLoader = Future<AiEditPlanResult> Function(
    AiEditPlanRequest request);

/// Manual CapCut-style video editor (UI scaffold). The preview reflects the
/// chosen settings, but applying edits to the real video file needs FFmpeg and
/// is deferred. Familiar layout: preview on top, a timeline, and a bottom tool
/// bar that opens a control panel per tool.
enum _Tool {
  caption,
  silence,
  trim,
  split,
  speed,
  volume,
  text,
  sticker,
  filter,
  adjust,
}

/// A draggable overlay position: [dx]/[dy] are normalized 0..1 of the frame.
class _TextOverlay {
  _TextOverlay(this.text);
  final String text;
  double dx = 0.5;
  double dy = 0.18;
}

class _StickerItem {
  _StickerItem(this.emoji, {this.dx = 0.8, this.dy = 0.14});
  final String emoji;
  double dx;
  double dy;
}

String _fmtClock(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

class _SilenceSeg {
  _SilenceSeg(this.start, this.end, this.cut);
  final double start;
  final double end;
  bool cut;

  double get seconds => end - start;
  String get label => '${_fmtClock(start)} – ${_fmtClock(end)}';
}

/// A clip segment expressed as timeline fractions (0..1). Splitting cuts a
/// segment in two at the playhead; toggling [keep] drops it from the export.
class _Segment {
  _Segment(this.start, this.end, {this.keep = true});
  final double start;
  final double end;
  bool keep;

  double get span => end - start;
}

class CapCutEditorScreen extends StatefulWidget {
  const CapCutEditorScreen({
    super.key,
    this.videoName,
    this.videoS3Key,
    this.videoFile,
    this.transcribeClip,
    this.burnVideo,
    this.probeDuration,
    this.onExported,
    this.rasterizeSticker,
    this.requestEditPlan,
    this.initialStyle,
    this.cancelRender,
  });

  final String? videoName;
  final String? videoS3Key;
  final File? videoFile;
  final CapCutTranscriptLoader? transcribeClip;
  final SubtitleBurnVideoProcessor? burnVideo;
  final VideoDurationProbe? probeDuration;

  /// Invoked when the user chooses to take a freshly rendered clip into the
  /// posting flow. When null, export just reports success.
  final ValueChanged<BurnedSubtitleResult>? onExported;

  /// Renders an emoji sticker to a PNG for burn-in. Defaults to the on-device
  /// Flutter rasterizer; injectable for tests.
  final StickerRasterizer? rasterizeSticker;

  /// Server-side AI edit planner (`POST /ai-edits/plan`). When provided, AI
  /// styles and custom prompts ask it for cut decisions, falling back to the
  /// on-device heuristics if it errors. Null = local heuristics only.
  final EditPlanLoader? requestEditPlan;

  /// A style chosen on the editing entry screen, applied as soon as the editor
  /// opens (custom prompt opens the style sheet so the user can type).
  final EditStyleSelection? initialStyle;

  /// Cancels the in-flight render. Defaults to cancelling all FFmpeg sessions;
  /// injectable for tests.
  final Future<void> Function()? cancelRender;

  @override
  State<CapCutEditorScreen> createState() => _CapCutEditorScreenState();
}

class _CapCutEditorScreenState extends State<CapCutEditorScreen> {
  double _trimStart = 0;
  double _trimEnd = 1;
  final List<_Segment> _segments = [_Segment(0, 1)];
  double _speed = 1;
  double _volume = 1;
  final List<_TextOverlay> _texts = [];
  final List<_StickerItem> _stickers = [];
  int _filterIndex = 0;
  double _brightness = 0;
  double _contrast = 0;
  double _playhead = 0.35;
  _Tool? _tool;

  // AI-assist state. The editor mixes manual tools with optional AI helpers so
  // the user can let AI cut/caption, or do it by hand with trim/split.
  final _apiClient = PostDeeApiClient();
  bool _captionOn = false;
  bool _captionBusy = false;
  String _captionText = 'สวัสดีค่ะ มีของดีมาแนะนำ';
  List<ClipTranscriptSegment> _transcriptSegments = const [];
  double _durationSeconds = 0;
  bool _silenceFound = false;
  final List<_SilenceSeg> _silence = [];

  // Auto-edit style state. A style is a starting preset; the user can keep
  // tweaking afterwards. Style cut ranges ride the same export pipeline as
  // silence cuts.
  EditStyle? _appliedStyle;
  List<SilenceCutRange> _styleCutRanges = const [];
  // Post-style fine-tuning (target length / subtitle line length / pacing).
  EditStyleOptions _options = const EditStyleOptions();

  final _textController = TextEditingController();

  // Real-frame preview. Falls back to the gradient placeholder when the video
  // cannot be loaded (e.g. native plugin missing under widget tests).
  VideoPlayerController? _videoController;
  bool _videoReady = false;

  // Render progress (0..1) shown in the export dialog.
  final ValueNotifier<double> _renderProgress = ValueNotifier<double>(0);

  static const _filters = ['ปกติ', 'สดใส', 'วินเทจ', 'ขาวดำ', 'อบอุ่น', 'เย็น'];
  static const _filterTints = [
    Colors.transparent,
    Color(0x14FFFFFF),
    Color(0x33A1662F),
    Color(0x66000000),
    Color(0x33FF8A3D),
    Color(0x3340A9FF),
  ];
  static const _stickerChoices = ['😍', '🔥', '💯', '🛒', '✨', '👍', '🎉', '❤️'];

  @override
  void initState() {
    super.initState();
    _loadDuration();
    _initVideo();

    final initialStyle = widget.initialStyle;
    if (initialStyle != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // Custom prompt needs the user's words, so open the sheet; otherwise
        // apply the chosen style straight away.
        if (initialStyle.style.plan.isCustomPrompt) {
          _openStyleGallery();
        } else {
          _applyStyle(initialStyle);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _videoController?.dispose();
    _renderProgress.dispose();
    super.dispose();
  }

  /// Loads the picked clip into a real video preview. Any failure (unsupported
  /// file, or the plugin being unavailable in tests) leaves the placeholder up.
  Future<void> _initVideo() async {
    final file = widget.videoFile;

    if (file == null) {
      return;
    }

    final controller = VideoPlayerController.file(file);
    _videoController = controller;

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await _syncPlayback();

      if (!mounted) {
        return;
      }

      setState(() => _videoReady = true);
    } catch (_) {
      // Keep the gradient placeholder; preview is non-critical.
    }
  }

  /// Mirrors the editor's speed/volume onto the preview player. Volume tops out
  /// at 1.0 on the player even though the editor allows boosting up to 2.0.
  Future<void> _syncPlayback() async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await controller.setPlaybackSpeed(_speed);
    await controller.setVolume(_volume.clamp(0.0, 1.0));
  }

  void _togglePlayback() {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  /// Reads the real clip duration up front so manual trim works without first
  /// running AI captions (the transcript is no longer the only duration source).
  Future<void> _loadDuration() async {
    final file = widget.videoFile;

    if (file == null) {
      return;
    }

    final probe = widget.probeDuration ?? const FfprobeVideoDurationProbe().call;
    final seconds = await probe(file);

    if (!mounted || seconds == null || seconds <= 0) {
      return;
    }

    setState(() => _durationSeconds = seconds);
  }

  void _selectTool(_Tool tool) {
    setState(() => _tool = _tool == tool ? null : tool);
  }

  Future<void> _openStyleGallery() async {
    final selection = await showEditStyleGallery(context);

    if (selection == null || !mounted) {
      return;
    }

    await _applyStyle(selection);
  }

  /// Transcribes the clip just to get timed segments (no subtitle burn). Returns
  /// false when there's no uploaded clip to analyze.
  Future<bool> _ensureTranscriptForStyle() async {
    if (_transcriptSegments.isNotEmpty) {
      return true;
    }

    final videoS3Key = (widget.videoS3Key ?? '').trim();
    if (videoS3Key.isEmpty) {
      return false;
    }

    try {
      final transcribe = widget.transcribeClip ?? _apiClient.transcribeClip;
      final transcript = await transcribe(videoS3Key);

      if (!mounted) {
        return false;
      }

      setState(() {
        _transcriptSegments = transcript.segments;
        if (transcript.durationSeconds > 0) {
          _durationSeconds = transcript.durationSeconds;
        }
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyStyle(EditStyleSelection selection) async {
    final style = selection.style;
    final plan = style.plan;
    final messenger = ScaffoldMessenger.of(context);

    // Honesty: styles that truly need non-speech audio / visual analysis can't
    // work yet, so don't pretend to apply them — say so clearly.
    if (plan.comingSoon) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('สไตล์ "${style.name}" ต้องวิเคราะห์เสียง/ภาพจริง '
              '· กำลังพัฒนา เร็วๆ นี้'),
        ),
      );
      return;
    }

    // Custom Prompt: a client-side interpreter handles the reliable parts
    // (target length + "cut the swear words") now; richer NLU comes with AI.
    if (plan.isCustomPrompt) {
      await _applyCustomPrompt(style, selection.prompt ?? '');
      return;
    }

    final needsTranscript = plan.keepKeywords.isNotEmpty ||
        plan.silenceMinGapSec != null ||
        (plan.requiresAi && widget.requestEditPlan != null);
    var hasTranscript = _transcriptSegments.isNotEmpty;

    if (needsTranscript && !hasTranscript) {
      hasTranscript = await _ensureTranscriptForStyle();
      if (!mounted) {
        return;
      }
      if (!hasTranscript) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('อัปโหลดคลิปจริงก่อน เพื่อให้สไตล์นี้วิเคราะห์เนื้อหาได้ '
                '· ตอนนี้ปรับจังหวะให้ก่อน'),
          ),
        );
      }
    }

    final styleCuts = await _resolveStyleCuts(style, plan, hasTranscript);
    if (!mounted) {
      return;
    }

    setState(() {
      _appliedStyle = style;
      _styleCutRanges = styleCuts;
      _speed = plan.speed;
      _filterIndex = plan.filterIndex;
      _volume = plan.volume;

      final gap = _options.silenceMinGapSec ?? plan.silenceMinGapSec;
      if (gap != null && hasTranscript) {
        final ranges = detectSilenceRanges(
          [
            for (final segment in _transcriptSegments)
              SubtitleSegment(
                text: segment.text,
                start: segment.start,
                end: segment.end,
              ),
          ],
          minGapSec: gap,
        );
        _silence
          ..clear()
          ..addAll([
            for (final range in ranges) _SilenceSeg(range.start, range.end, true),
          ]);
        _silenceFound = true;
      }
    });

    await _syncPlayback();
    if (!mounted) {
      return;
    }

    // Be honest when a speech-based style couldn't actually cut anything (no
    // matching speech, or real transcription isn't enabled) — otherwise the
    // user sees "applied" but nothing changed.
    final producedCuts = styleCuts.isNotEmpty || _silence.any((s) => s.cut);
    if (plan.needsSpeech && !producedCuts) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('ใช้สไตล์ "${style.name}" แล้ว แต่ยังไม่พบช่วงที่จะตัด '
              '· สไตล์นี้ต้องมีเสียงพูดในคลิป (และเปิดถอดเสียงจริง)'),
        ),
      );
    }
  }

  /// AI styles ask the server planner (with the on-device heuristic as a
  /// fallback); plain styles stay fully local to avoid a needless round-trip.
  Future<List<SilenceCutRange>> _resolveStyleCuts(
    EditStyle style,
    EditStylePlan plan,
    bool hasTranscript,
  ) async {
    if (!hasTranscript) {
      return const [];
    }

    final loader = widget.requestEditPlan;
    if (loader != null && plan.requiresAi) {
      try {
        final result = await loader(
          AiEditPlanRequest(
            segments: _transcriptSegments,
            durationSeconds: _durationSeconds,
            styleId: style.id,
          ),
        );
        return [
          for (final cut in result.cuts)
            SilenceCutRange(start: cut.start, end: cut.end),
        ];
      } catch (_) {
        // Fall back to the local heuristic below.
      }
    }

    return buildStyleCutRanges(
      segments: _transcriptSegments,
      durationSeconds: _durationSeconds,
      plan: plan,
    );
  }

  Future<void> _applyCustomPrompt(EditStyle style, String rawPrompt) async {
    final messenger = ScaffoldMessenger.of(context);
    final prompt = rawPrompt.trim();

    if (prompt.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('พิมพ์คำสั่งให้ AI ก่อน')),
      );
      return;
    }

    // Prefer the server planner; fall back to the on-device interpreter if it
    // is unavailable or errors.
    final loader = widget.requestEditPlan;
    if (loader != null) {
      try {
        if (_transcriptSegments.isEmpty) {
          await _ensureTranscriptForStyle();
          if (!mounted) {
            return;
          }
        }

        final result = await loader(
          AiEditPlanRequest(
            segments: _transcriptSegments,
            durationSeconds: _durationSeconds,
            prompt: prompt,
          ),
        );
        if (!mounted) {
          return;
        }

        setState(() {
          _appliedStyle = style;
          _styleCutRanges = [
            for (final cut in result.cuts)
              SilenceCutRange(start: cut.start, end: cut.end),
          ];
        });
        await _syncPlayback();

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.cuts.isEmpty
                  ? 'อ่านคำสั่งแล้ว: ${result.summary}'
                  : 'ตัดตามคำสั่งให้แล้ว · ${result.summary}'),
            ),
          );
        }
        return;
      } catch (_) {
        // Fall through to the local interpreter.
      }
    }

    final instruction = parseCustomPrompt(prompt);

    if (instruction.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ยังตีความคำสั่งนี้ไม่ได้ · ตอนนี้รองรับกำหนดเวลา '
              '(เช่น "เหลือ 45 วิ") และ "ตัดคำหยาบ" · จะเข้าใจซับซ้อนขึ้นด้วย AI'),
        ),
      );
      return;
    }

    // Profanity removal needs the transcript text; a duration target needs the
    // clip length (probe usually has it, transcript is the fallback).
    if (instruction.removeProfanity ||
        (instruction.targetSeconds != null && _durationSeconds <= 0)) {
      if (_transcriptSegments.isEmpty) {
        await _ensureTranscriptForStyle();
        if (!mounted) {
          return;
        }
      }
    }

    final cuts = buildCustomPromptCutRanges(
      segments: _transcriptSegments,
      durationSeconds: _durationSeconds,
      instruction: instruction,
    );

    setState(() {
      _appliedStyle = style;
      _styleCutRanges = cuts;
    });
    await _syncPlayback();

    if (!mounted) {
      return;
    }

    if (cuts.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('อ่านคำสั่งแล้วแต่ยังไม่มีอะไรต้องตัด '
              '(อัปโหลดคลิปจริงเพื่อให้ตัดคำหยาบได้)'),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('ตัดตามคำสั่งให้แล้ว · คำสั่งซับซ้อนขึ้น '
            '(เช่นเลือกฉากจากภาพ) กำลังมาด้วย AI'),
      ),
    );
  }

  void _clearStyle() {
    setState(() {
      _appliedStyle = null;
      _styleCutRanges = const [];
      _options = const EditStyleOptions();
      _speed = 1;
      _filterIndex = 0;
      _volume = 1;
    });
    _syncPlayback();
  }

  /// The trim window in absolute seconds, with null on a side that is not
  /// trimmed (start at 0 / end at the clip end). Shared by the export call and
  /// the length estimate so both agree on the kept window.
  ({double? start, double? end}) _trimWindowSeconds() {
    final start = (_durationSeconds > 0 && _trimStart > 0)
        ? _trimStart * _durationSeconds
        : null;
    final end = (_durationSeconds > 0 && _trimEnd < 1)
        ? _trimEnd * _durationSeconds
        : null;

    return (start: start, end: end);
  }

  /// All cut ranges that will be removed on export: manual silence toggles,
  /// removed split segments, style cuts, then a target-length tail cut.
  List<SilenceCutRange> _activeCutRanges() {
    final segmentCuts = <SilenceCutRange>[
      if (_durationSeconds > 0)
        for (final segment in _segments)
          if (!segment.keep)
            SilenceCutRange(
              start: segment.start * _durationSeconds,
              end: segment.end * _durationSeconds,
            ),
    ];
    var cuts = <SilenceCutRange>[
      for (final segment in _silence)
        if (segment.cut)
          SilenceCutRange(start: segment.start, end: segment.end),
      ...segmentCuts,
      ..._styleCutRanges,
    ];

    final target = _options.targetSeconds;
    if (target != null && _durationSeconds > 0) {
      cuts = withTargetLength(cuts, _durationSeconds, target.toDouble());
    }

    return cuts;
  }

  /// Subtitle segments for the burn, re-chunked to the chosen line length.
  List<SubtitleSegment> _subtitleSegmentsForExport() {
    final base = [
      for (final segment in _transcriptSegments)
        SubtitleSegment(
          text: segment.text,
          start: segment.start,
          end: segment.end,
        ),
    ];
    final maxChars = _options.subtitleMaxChars;

    return maxChars != null
        ? rechunkSubtitleByMaxChars(base, maxChars)
        : base;
  }

  void _redetectSilence(double minGapSec) {
    final ranges = detectSilenceRanges(
      [
        for (final segment in _transcriptSegments)
          SubtitleSegment(
            text: segment.text,
            start: segment.start,
            end: segment.end,
          ),
      ],
      minGapSec: minGapSec,
    );

    setState(() {
      _silence
        ..clear()
        ..addAll([
          for (final range in ranges) _SilenceSeg(range.start, range.end, true),
        ]);
      _silenceFound = true;
    });
  }

  Future<void> _openStyleOptions() async {
    final result = await showStyleOptionsSheet(
      context,
      _options.copyWith(
        speed: _speed,
        filterIndex: _filterIndex,
        brightness: _brightness,
        contrast: _contrast,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _options = result;
      if (result.speed != null) {
        _speed = result.speed!;
      }
      if (result.filterIndex != null) {
        _filterIndex = result.filterIndex!;
      }
      if (result.brightness != null) {
        _brightness = result.brightness!;
      }
      if (result.contrast != null) {
        _contrast = result.contrast!;
      }
    });

    // Re-run silence detection with the new pacing when we have a transcript.
    final gap = _options.silenceMinGapSec ?? _appliedStyle?.plan.silenceMinGapSec;
    if (gap != null && _transcriptSegments.isNotEmpty) {
      _redetectSilence(gap);
    }

    await _syncPlayback();
  }

  Widget _buildStyleBanner() {
    final style = _appliedStyle!;
    final trim = _trimWindowSeconds();
    final estimate = _durationSeconds > 0
        ? estimateResultSeconds(
            durationSeconds: _durationSeconds,
            cutRanges: _activeCutRanges(),
            speed: _speed,
            trimStartSec: trim.start,
            trimEndSec: trim.end,
          )
        : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLg, vertical: AppTheme.spaceXs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceMd, vertical: AppTheme.spaceSm),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(style.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Text(
              estimate != null
                  ? 'สไตล์: ${style.name} · จะเหลือ ~${estimate.round()} วิ'
                  : 'สไตล์: ${style.name}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          TextButton.icon(
            onPressed: _openStyleOptions,
            icon: const Icon(Icons.tune, size: 16),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            label: const Text('ปรับแต่ง'),
          ),
          TextButton(
            onPressed: _clearStyle,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('ล้าง'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final file = widget.videoFile;
    final trim = _trimWindowSeconds();
    final trimStartSec = trim.start;
    final trimEndSec = trim.end;
    // Manual silence + removed split segments + style cuts + target-length
    // trim, all riding the same FFmpeg select() pipeline.
    final silenceRanges = _activeCutRanges();
    final hasEdits = _captionOn ||
        silenceRanges.isNotEmpty ||
        _filterIndex != 0 ||
        _brightness != 0 ||
        _contrast != 0 ||
        _texts.isNotEmpty ||
        _stickers.isNotEmpty ||
        _speed != 1.0 ||
        _volume != 1.0 ||
        trimStartSec != null ||
        trimEndSec != null;

    final messenger = ScaffoldMessenger.of(context);

    if (file == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('เลือกคลิปจริงก่อนส่งออกวิดีโอ')),
      );
      return;
    }

    if (!hasEdits) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ปรับแก้คลิปอย่างน้อยหนึ่งอย่างก่อนส่งออก')),
      );
      return;
    }

    final processor =
        widget.burnVideo ?? const FfmpegSubtitleBurnVideoProcessor().call;

    _renderProgress.value = 0;
    final estimate = _durationSeconds > 0
        ? estimateResultSeconds(
            durationSeconds: _durationSeconds,
            cutRanges: silenceRanges,
            speed: _speed,
            trimStartSec: trimStartSec,
            trimEndSec: trimEndSec,
          )
        : null;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('กำลังเรนเดอร์วิดีโอในเครื่อง...'),
            const SizedBox(height: AppTheme.spaceMd),
            ValueListenableBuilder<double>(
              valueListenable: _renderProgress,
              builder: (context, value, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: value > 0 ? value : null,
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.glass,
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    value > 0 ? '${(value * 100).round()}%' : 'กำลังเริ่ม...',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => (widget.cancelRender ?? FFmpegKit.cancel)(),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );

    try {
      final (stickerImagePaths, stickerPositions) = await _rasterizeStickers();
      final result = await processor(
        BurnSubtitleRequest(
          inputFile: file,
          fileName: widget.videoName ?? 'clip.mp4',
          segments: _captionOn ? _subtitleSegmentsForExport() : const [],
          subtitleFontSize: _options.subtitleFontSize ?? 18,
          subtitleAtBottom: _options.subtitleAtBottom ?? true,
          speed: _speed,
          volume: _volume,
          trimStartSec: trimStartSec,
          trimEndSec: trimEndSec,
          silenceRanges: silenceRanges,
          filterIndex: _filterIndex,
          brightness: _brightness,
          contrast: _contrast,
          textOverlays: [
            for (final overlay in _texts)
              TextOverlaySpec(overlay.text, dx: overlay.dx, dy: overlay.dy),
          ],
          stickerImagePaths: stickerImagePaths,
          stickerPositions: stickerPositions,
          outputDurationSeconds: estimate,
          onProgress: (fraction) {
            if (mounted) {
              _renderProgress.value = fraction;
            }
          },
        ),
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showExportSuccess(result);
    } on SubtitleBurnException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('ส่งออกวิดีโอไม่สำเร็จ')),
      );
    }
  }

  /// Renders the chosen emoji stickers to PNGs for burn-in. Best-effort: a
  /// sticker that fails to rasterize is simply skipped.
  Future<(List<String>, List<(double, double)>)> _rasterizeStickers() async {
    if (_stickers.isEmpty) {
      return (const <String>[], const <(double, double)>[]);
    }

    final rasterize =
        widget.rasterizeSticker ?? const FlutterEmojiStickerRasterizer().call;
    final paths = <String>[];
    final positions = <(double, double)>[];

    for (final sticker in _stickers) {
      try {
        final file = await rasterize(sticker.emoji);
        paths.add(file.path);
        positions.add((sticker.dx, sticker.dy));
      } catch (_) {
        // Skip stickers that fail to render.
      }
    }

    return (paths, positions);
  }

  void _showExportSuccess(BurnedSubtitleResult result) {
    // Small renders would show as "0.0 MB", so switch to KB below 1 MB.
    final sizeLabel = result.sizeBytes >= 1024 * 1024
        ? '${(result.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(result.sizeBytes / 1024).toStringAsFixed(0)} KB';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.charcoal,
        title: const Text('ส่งออกวิดีโอสำเร็จ'),
        content: Text(
          'เรนเดอร์คลิปที่ตัดแล้ว: ${result.fileName} ($sizeLabel)\n'
          'นำไปโพสต์หรือตั้งเวลาต่อได้เลย',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          if (widget.onExported != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onExported!(result);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('นำไปโพสต์'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ตัดต่อด้วยมือ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'สไตล์อัตโนมัติ',
            onPressed: _openStyleGallery,
            icon: Icon(Icons.movie_filter, color: AppTheme.accentCyanInk),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
            child: FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('ส่งออก'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: AppTheme.screenBackground,
          child: Column(
            children: [
              Expanded(child: _buildPreview()),
              if (_appliedStyle != null) _buildStyleBanner(),
              _buildTimeline(),
              if (_tool != null) _buildToolPanel(),
              _buildToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  /// A draggable overlay anchored at normalized ([dx],[dy]) within a [w]x[h]
  /// area. [centerY] centers vertically (stickers) vs anchoring the top (text).
  Widget _draggableOverlay({
    required double dx,
    required double dy,
    required double w,
    required double h,
    required bool centerY,
    required void Function(double dx, double dy) onMove,
    required Widget child,
  }) {
    return Positioned(
      left: dx * w,
      top: dy * h,
      child: FractionalTranslation(
        translation: Offset(-0.5, centerY ? -0.5 : 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            if (w <= 0 || h <= 0) {
              return;
            }
            onMove(
              (dx + details.delta.dx / w).clamp(0.05, 0.95),
              (dy + details.delta.dy / h).clamp(0.05, 0.95),
            );
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _videoController;
    final isPlaying =
        _videoReady && controller != null && controller.value.isPlaying;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: GestureDetector(
              onTap: _togglePlayback,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: ColoredBox(
                  color: const Color(0xFF11131B),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base layer: real video frame, or the gradient fallback.
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
                              colors: [
                                Color(0xFF263755),
                                Color(0xFF11131B),
                                Color(0xFF050507),
                              ],
                            ),
                          ),
                        ),
                      // Filter tint + brightness/contrast preview overlays.
                      ColoredBox(color: _filterTints[_filterIndex]),
                      if (_brightness != 0)
                        ColoredBox(
                          color:
                              (_brightness > 0 ? Colors.white : Colors.black)
                                  .withValues(alpha: (_brightness.abs()) * 0.4),
                        ),
                      if (_contrast != 0)
                        ColoredBox(
                          color: Colors.black
                              .withValues(alpha: _contrast.abs() * 0.18),
                        ),
                      // Play affordance, hidden while the clip is playing.
                      if (!isPlaying)
                        const Center(
                          child: Icon(Icons.play_circle_outline,
                              color: Colors.white54, size: 44),
                        ),
                      // Draggable stickers + text overlays (positions are
                      // normalized so they map straight to the export filters).
                      if (_stickers.isNotEmpty || _texts.isNotEmpty)
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final h = constraints.maxHeight;
                              return Stack(
                                children: [
                                  for (final s in _stickers)
                                    _draggableOverlay(
                                      dx: s.dx,
                                      dy: s.dy,
                                      w: w,
                                      h: h,
                                      centerY: true,
                                      onMove: (nx, ny) => setState(() {
                                        s
                                          ..dx = nx
                                          ..dy = ny;
                                      }),
                                      child: Text(s.emoji,
                                          style: const TextStyle(fontSize: 28)),
                                    ),
                                  for (final t in _texts)
                                    _draggableOverlay(
                                      dx: t.dx,
                                      dy: t.dy,
                                      w: w,
                                      h: h,
                                      centerY: false,
                                      onMove: (nx, ny) => setState(() {
                                        t
                                          ..dx = nx
                                          ..dy = ny;
                                      }),
                                      child: Text(
                                        t.text,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          shadows: [
                                            Shadow(
                                                blurRadius: 6,
                                                color: Colors.black),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (_captionOn)
                        Positioned(
                          left: 8,
                          right: 8,
                          top: (_options.subtitleAtBottom ?? true) ? null : 18,
                          bottom: (_options.subtitleAtBottom ?? true) ? 18 : null,
                          child: Text(
                            _captionText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              // Scale the burn font size (14/18/24) into the
                              // smaller preview so it matches what's exported.
                              fontSize: (_options.subtitleFontSize ?? 18) * 0.83,
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      if (_speed != 1)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _Badge(label: '${_speed}x'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLg, vertical: AppTheme.spaceSm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _movePlayhead(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _movePlayhead(details.localPosition.dx, width),
            child: SizedBox(
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Thumbnail blocks.
                  Row(
                    children: [
                      for (var i = 0; i < 6; i += 1)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.glass,
                              border: Border.all(color: AppTheme.borderSoft),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(Icons.image_outlined,
                                color: AppTheme.textMuted, size: 16),
                          ),
                        ),
                    ],
                  ),
                  // Removed (dropped) segments masked out.
                  for (final segment in _segments)
                    if (!segment.keep)
                      Positioned(
                        left: segment.start * width,
                        width: segment.span * width,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.accentPinkInk.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Icon(Icons.block,
                                color: Colors.white70, size: 16),
                          ),
                        ),
                      ),
                  // Split boundaries between segments.
                  for (var i = 1; i < _segments.length; i += 1)
                    Positioned(
                      left: (_segments[i].start * width).clamp(0, width - 2),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: AppTheme.accentPinkInk),
                    ),
                  // Trim region overlay edges.
                  _trimHandle(width, isStart: true),
                  _trimHandle(width, isStart: false),
                  // Playhead.
                  Positioned(
                    left: (_playhead * width).clamp(0, width - 2),
                    top: -4,
                    bottom: -4,
                    child: Container(width: 2, color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _trimHandle(double width, {required bool isStart}) {
    final value = isStart ? _trimStart : _trimEnd;
    return Positioned(
      left: (value * width).clamp(0.0, width - 14),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            final delta = details.delta.dx / width;
            if (isStart) {
              _trimStart = (_trimStart + delta).clamp(0.0, _trimEnd - 0.08);
            } else {
              _trimEnd = (_trimEnd + delta).clamp(_trimStart + 0.08, 1.0);
            }
          });
        },
        child: Container(
          width: 14,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.drag_indicator,
              color: Colors.white, size: 14),
        ),
      ),
    );
  }

  Widget _buildToolPanel() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceLg, AppTheme.spaceMd, AppTheme.spaceLg, AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: AppTheme.charcoal,
        border: Border(top: BorderSide(color: AppTheme.borderSoft)),
      ),
      child: switch (_tool!) {
        _Tool.caption => _captionPanel(),
        _Tool.silence => _silencePanel(),
        _Tool.trim => _hint('ลากที่จับสีเขียวสองข้างบนไทม์ไลน์ เพื่อตัดต้น-ท้ายคลิป'),
        _Tool.split => _splitPanel(),
        _Tool.speed => _speedPanel(),
        _Tool.volume => _volumePanel(),
        _Tool.text => _textPanel(),
        _Tool.sticker => _stickerPanel(),
        _Tool.filter => _filterPanel(),
        _Tool.adjust => _adjustPanel(),
      },
    );
  }

  Widget _hint(String text) => Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Text(text,
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      );

  Future<void> _runCaption() async {
    setState(() => _captionBusy = true);

    try {
      final videoS3Key = (widget.videoS3Key ?? '').trim();

      if (videoS3Key.isEmpty) {
        throw const ApiException(
          'อัปโหลดคลิปจริงก่อนใช้ซับ AI ในหน้าแก้ไข',
        );
      }

      final transcribeClip = widget.transcribeClip ?? _apiClient.transcribeClip;
      final transcript = await transcribeClip(videoS3Key);

      if (!mounted) return;

      setState(() {
        _transcriptSegments = transcript.segments;
        _durationSeconds = transcript.durationSeconds;
        _captionText = transcript.segments.isNotEmpty
            ? transcript.segments.first.text
            : (transcript.text.isEmpty ? _captionText : transcript.text);
        _captionOn = true;
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ถอดเสียงไม่สำเร็จ ลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _captionBusy = false);
      }
    }
  }

  Widget _captionPanel() {
    if (_captionBusy) {
      return _hint('AI กำลังถอดเสียงไทยและใส่ซับ...');
    }
    if (!_captionOn) {
      return Row(
        children: [
          Expanded(child: _hint('ให้ AI ถอดเสียงไทยแล้วใส่ซับให้อัตโนมัติ')),
          const SizedBox(width: AppTheme.spaceSm),
          FilledButton.icon(
            onPressed: _runCaption,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('ใส่ซับ AI'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.check_circle, color: AppTheme.successInk, size: 18),
        const SizedBox(width: AppTheme.spaceSm),
        const Expanded(
          child: Text('ใส่ซับ AI แล้ว · ปรับคำ/สไตล์เพิ่มได้ที่ "ข้อความ"'),
        ),
        TextButton(
          onPressed: () => setState(() => _captionOn = false),
          child: const Text('เอาออก'),
        ),
      ],
    );
  }

  void _detectSilence() {
    if (_transcriptSegments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ให้ AI ใส่ซับ (ถอดเสียง) ก่อน แล้วจะหาช่วงเงียบให้'),
        ),
      );
      return;
    }

    final ranges = detectSilenceRanges([
      for (final segment in _transcriptSegments)
        SubtitleSegment(
          text: segment.text,
          start: segment.start,
          end: segment.end,
        ),
    ]);

    setState(() {
      _silence
        ..clear()
        ..addAll([
          for (final range in ranges) _SilenceSeg(range.start, range.end, true),
        ]);
      _silenceFound = true;
    });
  }

  Widget _silencePanel() {
    if (!_silenceFound) {
      return Row(
        children: [
          Expanded(
            child: _hint('ให้ AI หาช่วงเงียบให้ หรือใช้ "ตัด/แบ่ง" ตัดเอง'),
          ),
          const SizedBox(width: AppTheme.spaceSm),
          FilledButton.icon(
            onPressed: _detectSilence,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('หาช่วงเงียบ'),
          ),
        ],
      );
    }
    if (_silence.isEmpty) {
      return _hint('ไม่พบช่วงเงียบที่ชัดเจน · ใช้ "ตัด/แบ่ง" ตัดเองได้');
    }
    final saved = _silence
        .where((s) => s.cut)
        .fold<double>(0, (sum, s) => sum + s.seconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _silence.length; i += 1)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_silence[i].label}  ·  ${_silence[i].seconds.toStringAsFixed(1)} วิ',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SizedBox(
                height: 28,
                child: Switch(
                  value: _silence[i].cut,
                  onChanged: (v) => setState(() => _silence[i].cut = v),
                ),
              ),
            ],
          ),
        Text(
          'ตัดออกรวม ~${saved.toStringAsFixed(1)} วินาที',
          style: TextStyle(
            color: AppTheme.accentCyanInk,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  void _movePlayhead(double dx, double width) {
    if (width <= 0) return;
    setState(() => _playhead = (dx / width).clamp(0.0, 1.0));
  }

  void _splitAtPlayhead() {
    for (var i = 0; i < _segments.length; i += 1) {
      final seg = _segments[i];
      if (_playhead > seg.start + 0.02 && _playhead < seg.end - 0.02) {
        setState(() {
          _segments
            ..removeAt(i)
            ..insert(i, _Segment(_playhead, seg.end, keep: seg.keep))
            ..insert(i, _Segment(seg.start, _playhead, keep: seg.keep));
        });
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เลื่อนหัวอ่านให้ห่างจากรอยแบ่งเดิมก่อนแบ่ง')),
    );
  }

  String _segmentLabel(_Segment segment) {
    if (_durationSeconds > 0) {
      return '${_fmtClock(segment.start * _durationSeconds)} – '
          '${_fmtClock(segment.end * _durationSeconds)}';
    }

    return '${(segment.start * 100).round()}% – ${(segment.end * 100).round()}%';
  }

  Widget _splitPanel() {
    final removed = _segments.where((s) => !s.keep).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _hint('แตะไทม์ไลน์เลื่อนหัวอ่าน (เส้นขาว) แล้วกดแบ่ง '
                  'จากนั้นปิดท่อนที่ไม่เอาออกได้'),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            FilledButton.icon(
              onPressed: _splitAtPlayhead,
              icon: const Icon(Icons.call_split, size: 18),
              label: const Text('แบ่งตรงนี้'),
            ),
          ],
        ),
        if (_segments.length > 1) ...[
          const SizedBox(height: AppTheme.spaceSm),
          for (var i = 0; i < _segments.length; i += 1)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ท่อน ${i + 1} · ${_segmentLabel(_segments[i])}',
                    style: TextStyle(
                      fontSize: 13,
                      color: _segments[i].keep
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      decoration: _segments[i].keep
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: _segments[i].keep,
                    onChanged: (v) => setState(() => _segments[i].keep = v),
                  ),
                ),
              ],
            ),
          if (removed > 0)
            Text(
              'จะตัด $removed ท่อนออกตอนส่งออก',
              style: TextStyle(
                color: AppTheme.accentCyanInk,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ],
    );
  }

  Widget _speedPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ความเร็ว', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceSm,
            children: [
              for (final s in [0.5, 1.0, 1.5, 2.0])
                ChoiceChip(
                  label: Text('${s}x'),
                  selected: _speed == s,
                  onSelected: (_) {
                    setState(() => _speed = s);
                    _syncPlayback();
                  },
                ),
            ],
          ),
        ],
      );

  Widget _volumePanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('เสียง · ${(_volume * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Slider(
            value: _volume,
            max: 2,
            divisions: 20,
            label: '${(_volume * 100).round()}%',
            onChanged: (v) {
              setState(() => _volume = v);
              _syncPlayback();
            },
          ),
        ],
      );

  Widget _textPanel() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'ข้อความ',
                hintText: 'พิมพ์ข้อความที่จะใส่ในคลิป',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spaceSm),
          FilledButton(
            onPressed: () {
              final text = _textController.text.trim();
              if (text.isEmpty) return;
              setState(() {
                _texts.add(_TextOverlay(text));
                _textController.clear();
              });
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      );

  Widget _stickerPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _hint('แตะเพื่อเพิ่มสติกเกอร์ · ลากย้ายตำแหน่งบนตัวอย่างได้'),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceMd,
            runSpacing: AppTheme.spaceSm,
            children: [
              for (final s in _stickerChoices)
                GestureDetector(
                  onTap: () => setState(() => _stickers.add(
                        _StickerItem(
                          s,
                          dx: 0.5,
                          dy: 0.2 + (_stickers.length % 4) * 0.12,
                        ),
                      )),
                  child: Text(s, style: const TextStyle(fontSize: 28)),
                ),
            ],
          ),
        ],
      );

  Widget _filterPanel() => SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spaceSm),
          itemBuilder: (context, i) {
            final selected = _filterIndex == i;
            return GestureDetector(
              onTap: () => setState(() => _filterIndex = i),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2230),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ColoredBox(color: _filterTints[i]),
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(_filters[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      )),
                ],
              ),
            );
          },
        ),
      );

  Widget _adjustPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ความสว่าง ${(_brightness * 100).round()}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Slider(
            value: _brightness,
            min: -1,
            max: 1,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          Text('คอนทราสต์ ${(_contrast * 100).round()}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Slider(
            value: _contrast,
            min: -1,
            max: 1,
            onChanged: (v) => setState(() => _contrast = v),
          ),
        ],
      );

  Widget _buildToolbar() {
    const tools = [
      (_Tool.caption, Icons.closed_caption_outlined, 'ซับ AI'),
      (_Tool.silence, Icons.auto_fix_high, 'ตัดเงียบ'),
      (_Tool.trim, Icons.content_cut, 'ตัด'),
      (_Tool.split, Icons.call_split, 'แบ่ง'),
      (_Tool.speed, Icons.speed, 'ความเร็ว'),
      (_Tool.volume, Icons.volume_up_outlined, 'เสียง'),
      (_Tool.text, Icons.text_fields, 'ข้อความ'),
      (_Tool.sticker, Icons.emoji_emotions_outlined, 'สติกเกอร์'),
      (_Tool.filter, Icons.auto_awesome_outlined, 'ฟิลเตอร์'),
      (_Tool.adjust, Icons.tune, 'ปรับ'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.navSurface,
        border: Border(top: BorderSide(color: AppTheme.navBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
            itemCount: tools.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spaceXl),
            itemBuilder: (context, i) {
              final (tool, icon, label) = tools[i];
              final selected = _tool == tool;
              final color =
                  selected ? AppTheme.accent : AppTheme.navInactive;
              return InkWell(
                onTap: () => _selectTool(tool),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}
