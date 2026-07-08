import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/video_picker_service.dart';
import 'capcut_editor_screen.dart';
import 'edit_styles.dart';
import 'subtitle_burn_video_processor.dart';

typedef EditorVideoPicker = Future<PickedVideoFile?> Function();
typedef EditorUploadCreator = Future<UploadResult> Function(
    CreateUploadRequest request);
typedef EditorVideoUploader = Future<void> Function(
  UploadResult upload,
  File videoFile,
);

/// Editing tab entry. Picks a real clip then opens the unified editor, which
/// mixes manual tools (trim/split/speed/volume/text/sticker/filter/adjust) with
/// AI helpers (auto caption + silence cut) — the user chooses per tool.
class AiEditingScreen extends StatefulWidget {
  const AiEditingScreen({
    super.key,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.transcribeClip,
  });

  final EditorVideoPicker? pickVideo;
  final EditorUploadCreator? createUpload;
  final EditorVideoUploader? uploadVideoFile;
  final CapCutTranscriptLoader? transcribeClip;

  @override
  State<AiEditingScreen> createState() => _AiEditingScreenState();
}

class _AiEditingScreenState extends State<AiEditingScreen> {
  final _apiClient = PostDeeApiClient();

  String _readFileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final fileName = parts.isEmpty ? path : parts.last;

    return fileName.trim();
  }

  Future<void> _pickAndOpen({EditStyleSelection? style}) async {
    final picker = widget.pickVideo ?? GalleryVideoPicker().pickVideo;

    PickedVideoFile? picked;
    try {
      picked = await picker();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลือกวิดีโอไม่สำเร็จ')),
        );
      }
      return;
    }

    if (picked == null || !mounted) {
      return;
    }

    final file = File(picked.path);
    final fileName = picked.name.trim().isNotEmpty
        ? picked.name.trim()
        : _readFileNameFromPath(picked.path);

    try {
      if (!file.existsSync()) {
        throw const ApiException('ไม่พบไฟล์วิดีโอในเครื่อง');
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final upload = await createUpload(
        CreateUploadRequest(
          fileName: fileName,
          contentType: 'video/mp4',
          sizeBytes:
              picked.sizeBytes > 0 ? picked.sizeBytes : file.lengthSync(),
          width: picked.width,
          height: picked.height,
        ),
      );
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      await uploadVideoFile(upload, file);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CapCutEditorScreen(
            videoName: fileName,
            videoS3Key: upload.videoS3Key,
            videoFile: file,
            transcribeClip: widget.transcribeClip,
            requestEditPlan: _apiClient.requestAiEditPlan,
            initialStyle: style,
            onExported: _openPostFlow,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดวิดีโอก่อนตัดต่อไม่สำเร็จ')),
        );
      }
    }
  }

  /// Opens the posting flow pre-filled with the editor's rendered clip so the
  /// edited video reaches TikTok/Shorts/Reels without re-picking from gallery.
  Future<void> _openPostFlow(BurnedSubtitleResult result) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'โพสต์คลิปที่ตัดแล้ว',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: DecoratedBox(
            decoration: AppTheme.screenBackground,
            child: UploaderScreen(
              initialVideoPath: result.file.path,
              initialVideoName: result.fileName,
              initialVideoSizeBytes: result.sizeBytes,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, AppTheme.navOverlap),
      children: [
        Text(
          'ตัดต่อด้วย AI',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'เลือกสไตล์ แล้วเลือกคลิป เดี๋ยว AI ตั้งค่าตัดต่อให้อัตโนมัติ',
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _AddVideoCard(onTap: _pickAndOpen),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(Icons.auto_fix_high, size: 19, color: AppTheme.accentCyanInk),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'ให้ AI จัดการให้',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'เลือกสไตล์การตัดต่อที่เข้ากับคลิปของคุณ',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 12),
        for (final group in const [
          EditStyleGroup.hardSell,
          EditStyleGroup.storytelling,
          EditStyleGroup.engagement,
          EditStyleGroup.custom,
        ]) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text(
              group == EditStyleGroup.hardSell
                  ? '🔥 ${group.label}'
                  : group.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.48,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          for (final style in editStyles.where((s) => s.group == group))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _StyleExampleCard(
                style: style,
                onTap: () =>
                    _pickAndOpen(style: EditStyleSelection(style: style)),
              ),
            ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _AddVideoCard extends StatelessWidget {
  const _AddVideoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'เพิ่มวิดีโอ',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        key: const ValueKey('ai-add-video'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedRRectBorderPainter(
            color: AppTheme.accent.withValues(alpha: 0.5),
            radius: 18,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.mint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.video_call_outlined,
                    size: 29,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'เพิ่มวิดีโอ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'แตะเพื่อเลือกคลิปแนวตั้ง 9:16 ที่จะให้ AI ตัดต่อ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1.5;

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _StyleExampleCard extends StatelessWidget {
  const _StyleExampleCard({required this.style, required this.onTap});

  final EditStyle style;
  final VoidCallback onTap;

  // Per-style accent colors from the design handoff's styleDefs.
  static const _styleColors = {
    'fast_review': Color(0xFFF59E0B),
    'flash_sale': Color(0xFF0E9F6E),
    'before_after': Color(0xFF6366F1),
    'vlog': Color(0xFF10B981),
    'tutorial': Color(0xFF8B5CF6),
    'qa': Color(0xFF0EA5B7),
    'comedy': Color(0xFFF472B6),
    'asmr': Color(0xFFA855F7),
    'aesthetic': Color(0xFFD97706),
  };

  @override
  Widget build(BuildContext context) {
    final color = _styleColors[style.id] ?? AppTheme.accent;
    final comingSoon = style.plan.comingSoon;

    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: comingSoon ? 0.6 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF122018).withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      style.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              style.name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (comingSoon)
                            _MiniBadge(
                              label: 'เร็วๆ นี้',
                              background: AppTheme.glassDeep,
                              foreground: AppTheme.textMuted,
                            )
                          else if (style.plan.requiresAi)
                            _MiniBadge(
                              label: 'ใช้ AI',
                              background: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.13),
                              foreground: const Color(0xFF6366F1),
                            ),
                          if (style.plan.isCustomPrompt)
                            _MiniBadge(
                              label: 'Pro',
                              background: AppTheme.mint,
                              foreground: AppTheme.accentCyanInk,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        style.editingNote,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'เหมาะกับ: ${style.suitableFor}',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppTheme.spaceSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
